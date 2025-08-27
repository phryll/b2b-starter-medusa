import { QUOTE_MODULE } from "./src/modules/quote";
import { APPROVAL_MODULE } from "./src/modules/approval";
import { COMPANY_MODULE } from "./src/modules/company";
import { loadEnv, defineConfig, Modules } from "@medusajs/framework/utils";

loadEnv(process.env.NODE_ENV!, process.cwd());

// Force SSL disable in database URL
const getDatabaseUrl = () => {
  let url = process.env.DATABASE_URL || "";
  
  // Parse URL and force sslmode=disable
  try {
    const dbUrl = new URL(url);
    dbUrl.searchParams.set("sslmode", "disable");
    return dbUrl.toString();
  } catch {
    // Fallback: append sslmode if URL parsing fails
    const separator = url.includes("?") ? "&" : "?";
    return `${url}${separator}sslmode=disable`;
  }
};

module.exports = defineConfig({
  projectConfig: {
    databaseUrl: getDatabaseUrl(),
    redisUrl: process.env.REDIS_URL,
    workerMode: process.env.WORKER_MODE as "shared" | "worker" | "server",
    http: {
      storeCors: process.env.STORE_CORS!,
      adminCors: process.env.ADMIN_CORS!,
      authCors: process.env.AUTH_CORS!,
      jwtSecret: process.env.JWT_SECRET || "4870377b462a73ce988c2d52b713b08b",
      cookieSecret: process.env.COOKIE_SECRET || "supersecret",
    },
    databaseExtra: {
      ssl: false,
      rejectUnauthorized: false,
    },
  },
  modules: {
    [COMPANY_MODULE]: {
      resolve: "./modules/company",
    },
    [QUOTE_MODULE]: {
      resolve: "./modules/quote",
    },
    [APPROVAL_MODULE]: {
      resolve: "./modules/approval",
    },
    [Modules.CACHE]: {
      resolve: "@medusajs/medusa/cache-inmemory",
    },
    [Modules.WORKFLOW_ENGINE]: {
      resolve: "@medusajs/medusa/workflow-engine-inmemory",
    },
  },
});