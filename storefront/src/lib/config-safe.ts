import { Medusa } from "@medusajs/js-sdk"

const BACKEND_URL = process.env.NEXT_PUBLIC_MEDUSA_BACKEND_URL || "http://localhost:9000"
const PUBLISHABLE_KEY = process.env.NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY

// Create SDK with publishable key
export const safeSdk = new Medusa({
  baseUrl: BACKEND_URL,
  debug: process.env.NODE_ENV === "development",
  publishableKey: PUBLISHABLE_KEY,
})

// Safe wrapper for API calls during build with comprehensive error handling
export async function safeBuildRequest<T>(
  request: () => Promise<T>,
  fallback: T,
  description?: string
): Promise<T> {
  // Check if we have a publishable key
  if (!PUBLISHABLE_KEY) {
    console.warn(`[BUILD] No publishable key available for ${description || 'API call'}, using fallback`)
    console.warn(`[BUILD] Set NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY environment variable`)
    return fallback
  }

  try {
    console.log(`[BUILD] Attempting ${description || 'API call'} with key: ${PUBLISHABLE_KEY.substring(0, 20)}...`)
    
    // Add timeout to prevent hanging
    const timeoutPromise = new Promise<never>((_, reject) => {
      setTimeout(() => reject(new Error('API call timeout after 15 seconds')), 15000)
    })

    const result = await Promise.race([
      request(),
      timeoutPromise
    ])

    console.log(`[BUILD] Successfully completed ${description || 'API call'}`)
    return result

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error'
    
    // Log specific error types for debugging
    if (errorMessage.includes('publishable key') || errorMessage.includes('x-publishable-api-key')) {
      console.error(`[BUILD] Publishable key validation failed for ${description || 'API call'}:`, errorMessage)
      console.error(`[BUILD] Key being used: ${PUBLISHABLE_KEY?.substring(0, 20)}...`)
      console.error(`[BUILD] Backend URL: ${BACKEND_URL}`)
    } else if (errorMessage.includes('timeout')) {
      console.warn(`[BUILD] API timeout for ${description || 'API call'}, backend may not be ready`)
    } else if (errorMessage.includes('ECONNREFUSED') || errorMessage.includes('fetch failed')) {
      console.warn(`[BUILD] Backend connection failed for ${description || 'API call'}, backend may not be running`)
    } else {
      console.error(`[BUILD] API call failed for ${description || 'API call'}:`, errorMessage)
    }
    
    console.warn(`[BUILD] Using fallback for ${description || 'API call'}`)
    return fallback
  }
}