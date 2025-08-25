# ===========================================
# Build Arguments (from Coolify build variables)
# ===========================================
ARG NODE_ENV=production

# ===========================================
# Stage 1: Dependencies Installation
# ===========================================
FROM node:23-alpine AS deps
WORKDIR /app

# Accept build arguments
ARG NODE_ENV

# Install system dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    postgresql-client \
    git

# Enable Yarn 4
RUN corepack enable && corepack prepare yarn@4.4.0 --activate

# Copy package files
COPY backend/package.json backend/yarn.lock backend/.yarnrc.yml ./

# Install dependencies
RUN yarn install --network-timeout 300000

# ===========================================
# Stage 2: Application Build
# ===========================================
FROM node:23-alpine AS builder
WORKDIR /app

# Accept build arguments
ARG NODE_ENV

# Install build dependencies
RUN apk add --no-cache python3 make g++ git
RUN corepack enable && corepack prepare yarn@4.4.0 --activate

# Copy dependencies from previous stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/.yarn ./.yarn
COPY backend/package.json backend/yarn.lock backend/.yarnrc.yml ./

# Copy application source
COPY backend/ ./

# Build the application
RUN yarn medusa build

# ===========================================
# Stage 3: Production Runtime
# ===========================================
FROM node:23-alpine AS production
WORKDIR /app

# Runtime arguments (these become ENV at runtime)
ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}

# Install runtime dependencies
RUN apk add --no-cache \
    postgresql-client \
    redis \
    curl \
    bash \
    tini && \
    corepack enable && \
    corepack prepare yarn@4.4.0 --activate

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy built application
COPY --from=builder --chown=nodejs:nodejs /app ./

# Create required directories
RUN mkdir -p /app/uploads /app/logs /app/.medusa && \
    chown -R nodejs:nodejs /app

# ===========================================
# Runtime Scripts (no hardcoded values)
# ===========================================
RUN cat > /app/startup.sh << 'EOF'
#!/bin/bash
set -e

echo "========================================="
echo "  Medusa B2B Starter - Starting Up"
echo "========================================="

# All environment variables come from Coolify runtime

# Set defaults only if not provided
export NODE_ENV=${NODE_ENV:-production}
export PORT=${PORT:-9000}
export WORKER_MODE=${WORKER_MODE:-shared}
export PGSSLMODE=${PGSSLMODE:-disable}
export NODE_TLS_REJECT_UNAUTHORIZED=${NODE_TLS_REJECT_UNAUTHORIZED:-0}

# Fix Redis URL if it's using SSL
if [ -n "$REDIS_URL" ]; then
    if echo "$REDIS_URL" | grep -q "^rediss://"; then
        echo "Converting Redis SSL URL to non-SSL..."
        export REDIS_URL=$(echo "$REDIS_URL" | sed 's|^rediss://|redis://|' | sed 's|:6380|:6379|g')
        export REDISURL=$REDIS_URL
        export CACHE_REDIS_URL=$REDIS_URL
    fi
fi

# Ensure DATABASE_URL has sslmode=disable
if [ -n "$DATABASE_URL" ]; then
    if ! echo "$DATABASE_URL" | grep -q "sslmode=disable"; then
        if echo "$DATABASE_URL" | grep -q "?"; then
            export DATABASE_URL="${DATABASE_URL}&sslmode=disable"
        else
            export DATABASE_URL="${DATABASE_URL}?sslmode=disable"
        fi
    fi
    export DATABASEURL=$DATABASE_URL
fi

echo "Configuration loaded from environment"
echo "  NODE_ENV: ${NODE_ENV}"
echo "  PORT: ${PORT}"
echo "  WORKER_MODE: ${WORKER_MODE}"
echo ""

# Test connections
echo "Testing database connection..."
if [ -n "$DATABASE_URL" ]; then
    # Extract host and port from DATABASE_URL
    DB_HOST=$(echo $DATABASE_URL | sed -n 's/.*@\([^:]*\):.*/\1/p')
    DB_PORT=$(echo $DATABASE_URL | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
    
    for i in {1..30}; do
        if pg_isready -h "$DB_HOST" -p "$DB_PORT" 2>/dev/null; then
            echo "✓ Database is ready!"
            break
        fi
        echo "  Waiting for database... attempt $i/30"
        sleep 2
    done
fi

# Run migrations
echo "Running database migrations..."
yarn medusa db:migrate || {
    echo "Migration failed, retrying..."
    sleep 5
    yarn medusa db:migrate || echo "Migration skipped"
}

# Seed data
echo "Seeding database..."
yarn run seed || echo "Seeding skipped"

echo "Starting Medusa server on port ${PORT}..."
exec yarn medusa start
EOF

RUN chmod +x /app/startup.sh

# Health check endpoint
RUN mkdir -p /app/src/api/health && \
    cat > /app/src/api/health/route.ts << 'EOF'
import { MedusaRequest, MedusaResponse } from "@medusajs/framework";

export const GET = async (req: MedusaRequest, res: MedusaResponse) => {
  res.status(200).json({
    status: "healthy",
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || "development"
  });
};
EOF

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s \
            --timeout=15s \
            --start-period=180s \
            --retries=10 \
            CMD curl -f http://localhost:9000/health || exit 1

# Use tini for signal handling
ENTRYPOINT ["/sbin/tini", "--"]

# Start application
CMD ["/app/startup.sh"]