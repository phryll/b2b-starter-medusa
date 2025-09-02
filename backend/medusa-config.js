const { loadEnv, defineConfig, Modules } = require("@medusajs/framework/utils");

const COMPANY_MODULE = "company";
const QUOTE_MODULE = "quote";  
const APPROVAL_MODULE = "approval";

loadEnv(process.env.NODE_ENV || "production", process.cwd());

const isBuilding = process.argv.includes('build') || process.env.MEDUSA_BUILD === 'true';
const disableAdmin = process.env.ADMIN_DISABLED === "true" || false;

if (!isBuilding) {
  const requiredEnvVars = [
    'DATABASE_URL',
    'REDIS_URL',
    'JWT_SECRET', 
    'COOKIE_SECRET'
  ];

  for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
      throw new Error(`Missing required environment variable: ${envVar}`);
    }
  }
}

module.exports = defineConfig({
  projectConfig: {
    databaseUrl: process.env.DATABASE_URL || "postgres://dummy:dummy@localhost:5432/dummy?sslmode=disable",
    database_type: "postgres",
    // ADD THIS - Critical SSL configuration from official docs
    databaseDriverOptions: {
      connection: {
        ssl: false,
        rejectUnauthorized: false
      }
    },
    redisUrl: process.env.REDIS_URL || "redis://localhost:6379",
    workerMode: process.env.WORKER_MODE || "shared",
    http: {
      storeCors: process.env.STORE_CORS || "*",
      adminCors: process.env.ADMIN_CORS || "*", 
      authCors: process.env.AUTH_CORS || "*",
      jwtSecret: process.env.JWT_SECRET || "build-time-dummy-secret",
      cookieSecret: process.env.COOKIE_SECRET || "build-time-dummy-secret",
    },
  },
  admin: {
    disable: disableAdmin,
    serve: true,          
    outDir: ".medusa/admin"
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
    },
    [Modules.WORKFLOW_ENGINE]: {
      resolve: "@medusajs/medusa/workflow-engine-inmemory",
    },
  },
});