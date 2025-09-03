import { ExecArgs } from "@medusajs/framework/types";
import { ModuleRegistrationName } from "@medusajs/framework/utils";

export default async function createPublishableKey({ container }: ExecArgs) {
  const logger = container.resolve("logger");
  const apiKeyModuleService = container.resolve(ModuleRegistrationName.API_KEY);

  try {
    // Check if publishable key already exists
    const existingKeys = await apiKeyModuleService.listApiKeys({
      type: "publishable",
    });

    if (existingKeys.length > 0) {
      logger.info(`Publishable key already exists: ${existingKeys[0].token}`);
      console.log(`MEDUSA_PUBLISHABLE_KEY=${existingKeys[0].token}`);
      return;
    }

    // Create new publishable key
    const publishableKey = await apiKeyModuleService.createApiKeys({
      title: "B2B Storefront Key",
      type: "publishable",
    });

    logger.info(`Created publishable key: ${publishableKey.token}`);
    console.log(`MEDUSA_PUBLISHABLE_KEY=${publishableKey.token}`);
    
    return publishableKey;
  } catch (error) {
    logger.error("Failed to create publishable key:", error);
    throw error;
  }
}