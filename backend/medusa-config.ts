import { QUOTE_MODULE } from "./src/modules/quote"
import { APPROVAL_MODULE } from "./src/modules/approval"
import { COMPANY_MODULE } from "./src/modules/company"
import { loadEnv, defineConfig, Modules } from "@medusajs/framework/utils"

loadEnv(process.env.NODE_ENV!, process.cwd())

export default defineConfig({
  projectConfig: {
    databaseUrl: process.env.DATABASE_URL!,
    http: {
      storeCors: process.env.STORE_CORS?.split(",") ?? ["*"],
      adminCors: process.env.ADMIN_CORS?.split(",") ?? ["*"],
      authCors: process.env.AUTH_CORS?.split(",") ?? ["*"],
      jwtSecret: process.env.JWT_SECRET ?? "supersecret",
      cookieSecret: process.env.COOKIE_SECRET ?? "supersecret",
    },
  },
  modules: {
    [COMPANY_MODULE]: {
      resolve: "./src/modules/company",
    },
    [QUOTE_MODULE]: {
      resolve: "./src/modules/quote",
    },
    [APPROVAL_MODULE]: {
      resolve: "./src/modules/approval",
    },
    [Modules.CACHE]: {
      resolve: "@medusajs/medusa/cache-inmemory",
      options: {
        ttl: 300, // optional: 5 Min Cache-Lifetime
      },
    },
    [Modules.WORKFLOW_ENGINE]: {
      resolve: "@medusajs/medusa/workflow-engine-inmemory",
    },
  },
})
