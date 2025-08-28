# ===========================================
# Build Arguments (from Coolify build variables)
# ===========================================
arg NODE_ENV=production

# ===========================================
# Stage 1: Dependencies Installation
# ===========================================
from node:23-alpine AS deps
workdir /app

# Accept build arguments
arg NODE_ENV

# Install system dependencies
run apk add --no-cache \
    python3 \
    make \
    g++ \
    postgresql-client \
    git

# Enable Yarn 4
run corepack enable && corepack prepare yarn@4.4.0 --activate

# Copy package files
copy backend/package.json backend/yarn.lock backend/.yarnrc.yml ./

# Install dependencies
run yarn install --network-timeout 300000

# ===========================================
# Stage 2: Application Build
# ===========================================
from node:23-alpine AS builder
workdir /app

# Accept build arguments
arg NODE_ENV

# Install build dependencies
run apk add --no-cache python3 make g++ git
run corepack enable && corepack prepare yarn@4.4.0 --activate

# Copy dependencies from previous stage
copy --from=deps /app/node_modules ./node_modules
copy --from=deps /app/.yarn ./.yarn
copy backend/package.json backend/yarn.lock backend/.yarnrc.yml ./

# Copy application source
copy backend/ ./

# Build the application
run yarn medusa build

# ===========================================
# Stage 3: Production Runtime
# ===========================================
from node:23-alpine as production
workdir /app

# Runtime arguments
arg NODE_ENV=production
env NODE_ENV=${NODE_ENV}

# Install runtime dependencies
run apk add --no-cache \
    postgresql-client \
    redis \
    curl \
    bash \
    tini && \
    corepack enable && \
    corepack prepare yarn@4.4.0 --activate

# Create non-root user
run addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy built application
copy --from=builder --chown=nodejs:nodejs /app ./

# Create required directories
run mkdir -p /app/uploads /app/logs /app/.medusa && \
    chown -R nodejs:nodejs /app

# Copy startup script from repository
copy --chown=nodejs:nodejs startup.sh /app/startup.sh
run chmod +x /app/startup.sh


# Switch to non-root user
user nodejs

# Expose port
expose 9000

# Health check
healthcheck --interval=30s \
            --timeout=15s \
            --start-period=180s \
            --retries=10 \
            CMD curl -f http://wks0cw4oswsc8ssc4sggs4wo.91.98.72.224.sslip.io:9000/health || exit 1

# Use tini for signal handling
entrypoint ["/sbin/tini", "--"]

# Start application
cmd ["/app/startup.sh"]