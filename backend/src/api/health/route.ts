import type { MedusaRequest, MedusaResponse } from "@medusajs/framework";

export async function GET(req: MedusaRequest, res: MedusaResponse) {
  try {
    // Simple health check that responds quickly
    // This should work even if database/Redis are not yet available
    res.status(200).json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      service: "medusa",
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
