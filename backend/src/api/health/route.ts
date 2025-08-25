import type { MedusaRequest, MedusaResponse } from "@medusajs/framework";

export async function GET(req: MedusaRequest, res: MedusaResponse) {
  try {
    // Basic health check - you can add more sophisticated checks here
    // like database connectivity, Redis connectivity, etc.
    res.status(200).json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      service: "medusa",
      version: process.env.npm_package_version || "1.0.0"
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