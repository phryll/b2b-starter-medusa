// storefront/src/app/[countryCode]/(main)/products/[handle]/page.tsx

import { sdk } from "@/lib/config"
import { getAuthHeaders } from "@/lib/data/cookies"
import { getProductByHandle } from "@/lib/data/products"
import { getRegion, listRegions } from "@/lib/data/regions"
import ProductTemplate from "@/modules/products/templates"
import { Metadata } from "next"
import { notFound } from "next/navigation"

export const dynamicParams = true

type Props = {
  params: Promise<{ countryCode: string; handle: string }>
}

// Safe wrapper for build-time API calls that handles publishable key issues
async function safeBuildApiCall<T>(
  apiCall: () => Promise<T>,
  fallback: T,
  operationName: string
): Promise<T> {
  try {
    // Check if we have a publishable key available
    const publishableKey = process.env.NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY
    
    if (!publishableKey) {
      console.warn(`[BUILD] No publishable key available for ${operationName}, using fallback`)
      return fallback
    }

    // Attempt the API call with timeout
    const timeoutPromise = new Promise<never>((_, reject) => {
      setTimeout(() => reject(new Error('API call timeout')), 10000) // 10s timeout
    })

    const result = await Promise.race([
      apiCall(),
      timeoutPromise
    ])

    console.log(`[BUILD] Successfully completed ${operationName}`)
    return result

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error'
    
    // Log specific error types for debugging
    if (errorMessage.includes('publishable key')) {
      console.warn(`[BUILD] Publishable key validation failed for ${operationName}:`, errorMessage)
    } else if (errorMessage.includes('timeout')) {
      console.warn(`[BUILD] API timeout for ${operationName}, backend may not be ready`)
    } else if (errorMessage.includes('ECONNREFUSED') || errorMessage.includes('fetch failed')) {
      console.warn(`[BUILD] Backend connection failed for ${operationName}, backend may not be running`)
    } else {
      console.warn(`[BUILD] API call failed for ${operationName}:`, errorMessage)
    }
    
    console.warn(`[BUILD] Using fallback for ${operationName}`)
    return fallback
  }
}

export async function generateStaticParams() {
  try {
    console.log('[BUILD] Starting static params generation for product pages')
    
    // Step 1: Get country codes from regions
    let countryCodes: string[] = []
    
    try {
      const regions = await listRegions()
      if (!regions || regions.length === 0) {
        console.warn('[BUILD] No regions found, using fallback country codes')
        // Fallback to common country codes if regions API fails
        countryCodes = ['us', 'ca', 'gb', 'de', 'fr'] 
      } else {
        const extractedCodes = regions
          ?.map((r) => r.countries?.map((c) => c.iso_2))
          .flat()
          .filter(Boolean) as string[]
        
        if (!extractedCodes || extractedCodes.length === 0) {
          console.warn('[BUILD] No country codes extracted from regions, using fallback')
          countryCodes = ['us', 'ca', 'gb', 'de', 'fr']
        } else {
          countryCodes = extractedCodes
          console.log(`[BUILD] Found ${countryCodes.length} country codes:`, countryCodes)
        }
      }
    } catch (regionError) {
      console.error('[BUILD] Failed to fetch regions:', regionError)
      // Use fallback country codes
      countryCodes = ['us', 'ca', 'gb', 'de', 'fr']
      console.log('[BUILD] Using fallback country codes:', countryCodes)
    }

    // Step 2: Get products from store API with safe wrapper
    const { products } = await safeBuildApiCall(
      async () => {
        const authHeaders = await getAuthHeaders()
        return sdk.store.product.list(
          { fields: "handle" },
          { 
            next: { tags: ["products"] }, 
            ...authHeaders 
          }
        )
      },
      { products: [] }, // Fallback to empty products array
      'product list fetch'
    )

    // Step 3: Generate static params
    if (!products || products.length === 0) {
      console.warn('[BUILD] No products available, returning empty static params')
      console.warn('[BUILD] This means product pages will be generated dynamically at request time')
      return []
    }

    const staticParams = countryCodes
      .map((countryCode) =>
        products
          .filter((product) => product.handle) // Ensure handle exists
          .map((product) => ({
            countryCode,
            handle: product.handle,
          }))
      )
      .flat()

    console.log(`[BUILD] Generated ${staticParams.length} static params for product pages`)
    console.log(`[BUILD] Products: ${products.length}, Countries: ${countryCodes.length}`)
    
    // Log first few params for debugging
    if (staticParams.length > 0) {
      console.log('[BUILD] Sample static params:', staticParams.slice(0, 3))
    }

    return staticParams

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "Unknown error"
    console.error(`[BUILD] Failed to generate static paths for product pages: ${errorMessage}`)
    
    // Log the full error in development for debugging
    if (process.env.NODE_ENV === 'development') {
      console.error('[BUILD] Full error details:', error)
    }
    
    // Return empty array to allow build to continue
    // This means all product pages will be generated on-demand
    console.warn('[BUILD] Returning empty static params - pages will be generated dynamically')
    return []
  }
}

export async function generateMetadata(props: Props): Promise<Metadata> {
  try {
    const params = await props.params
    const { handle } = params
    
    // Get region with error handling
    const region = await getRegion(params.countryCode).catch((error) => {
      console.error(`[METADATA] Failed to get region for ${params.countryCode}:`, error)
      return null
    })

    if (!region) {
      console.warn(`[METADATA] No region found for ${params.countryCode}, using notFound`)
      notFound()
    }

    // Get product with error handling
    const product = await getProductByHandle(handle, region.id).catch((error) => {
      console.error(`[METADATA] Failed to get product ${handle}:`, error)
      return null
    })

    if (!product) {
      console.warn(`[METADATA] No product found for handle ${handle}, using notFound`)
      notFound()
    }

    // Generate metadata with fallbacks
    const title = product.title || handle
    const description = product.description || product.title || `Product: ${handle}`

    return {
      title: `${title} | Medusa Store`,
      description: description,
      openGraph: {
        title: `${title} | Medusa Store`,
        description: description,
        images: product.thumbnail ? [product.thumbnail] : [],
      },
    }
  } catch (error) {
    console.error('[METADATA] Metadata generation failed:', error)
    
    // Return basic metadata as fallback
    return {
      title: "Product | Medusa Store",
      description: "Product from Medusa Store",
    }
  }
}

export default async function ProductPage(props: Props) {
  try {
    const params = await props.params
    
    // Get region with error handling
    const region = await getRegion(params.countryCode).catch((error) => {
      console.error(`[PAGE] Failed to get region for ${params.countryCode}:`, error)
      return null
    })

    if (!region) {
      console.warn(`[PAGE] No region found for ${params.countryCode}`)
      notFound()
    }

    // Get product with error handling
    const pricedProduct = await getProductByHandle(params.handle, region.id).catch((error) => {
      console.error(`[PAGE] Failed to get product ${params.handle}:`, error)
      return null
    })

    if (!pricedProduct) {
      console.warn(`[PAGE] No product found for handle ${params.handle}`)
      notFound()
    }

    return (
      <ProductTemplate
        product={pricedProduct}
        region={region}
        countryCode={params.countryCode}
      />
    )
  } catch (error) {
    console.error('[PAGE] Product page rendering failed:', error)
    
    // In case of unexpected errors, show not found
    // This prevents the entire application from crashing
    notFound()
  }
}