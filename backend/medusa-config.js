const { loadEnv, defineConfig, Modules } = require("@medusajs/framework/utils");

const COMPANY_MODULE = "company";
const QUOTE_MODULE = "quote";  
const APPROVAL_MODULE = "approval";

loadEnv(process.env.NODE_ENV || "production", process.cwd());

const isBuilding = process.argv.includes('build') || process.env.MEDUSA_BUILD === 'true';

// Enhanced admin detection with multiple fallbacks
const detectAdminStatus = () => {
  // Check environment variable first
  if (process.env.ADMIN_DISABLED === "true") {
    console.log("Admin disabled via ADMIN_DISABLED environment variable");
    return true;
  }
  
  // Check if admin files exist
  const fs = require('fs');
  const path = require('path');
  const adminPath = path.join(process.cwd(), '.medusa', 'admin', 'index.html');
  
  try {
    if (fs.existsSync(adminPath)) {
      console.log("Admin files found, enabling admin");
      return false;
    } else {
      console.log("Admin files not found, disabling admin");
      return true;
    }
  } catch (error) {
    console.log("Error checking admin files, disabling admin:", error.message);
    return true;
  }
};

const disableAdmin = isBuilding ? false : detectAdminStatus();

console.log("Medusa Configuration:");
console.log("- NODE_ENV:", process.env.NODE_ENV);
console.log("- Admin disabled:", disableAdmin);
console.log("- Is building:", isBuilding);

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
    databaseDriverOptions: {
      connection: {
        ssl: false,  
        rejectUnauthorized: false
      }
    },   
    database_extra: {
      ssl: false,  
      rejectUnauthorized: false
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
    serve: !disableAdmin,          
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