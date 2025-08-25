import type { MedusaRequest, MedusaResponse } from "@medusajs/framework";

export async function GET(req: MedusaRequest, res: MedusaResponse) {
  try {
    // Basic health check - just check if the service is responding
    // This should work even if database/Redis are not yet available
    res.status(200).json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      service: "medusa",
      version: process.env.npm_package_version || "1.0.0",
      message: "Service is running"
    });
  } catch (error) {
    res.status(500).json({
      status: "unhealthy",
      timestamp: new Date().toISOString(),
      service: "medusa",
      error: error instanceof Error ? error.message : "Unknown error"
    });
  }
} 