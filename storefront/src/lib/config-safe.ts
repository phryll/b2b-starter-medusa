import { Medusa } from "@medusajs/js-sdk"

const BACKEND_URL = process.env.NEXT_PUBLIC_MEDUSA_BACKEND_URL || "http://localhost:9000"
const PUBLISHABLE_KEY = process.env.NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY

// Create SDK with error handling for build time
export const safeSdk = new Medusa({
  baseUrl: BACKEND_URL,
  debug: process.env.NODE_ENV === "development",
  publishableKey: PUBLISHABLE_KEY,
})

// Safe wrapper for API calls during build
export async function safeBuildRequest<T>(
  request: () => Promise<T>,
  fallback: T,
  description?: string
): Promise<T> {
  try {
    if (!PUBLISHABLE_KEY) {
      console.warn(`No publishable key available for ${description || 'API call'}, using fallback`)
      return fallback
    }
    
    return await request()
  } catch (error) {
    console.warn(`Build-time API request failed for ${description || 'unknown'}, using fallback:`, error)
    return fallback
  }
}