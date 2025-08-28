# ===========================================
# Build Arguments (from Coolify build variables)
# ===========================================
ARG NODE_ENV=production

# ===========================================
# Stage 1: Dependencies Installation
# ===========================================
FROM node:23-alpine AS deps
WORKDIR /app

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
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
RUN yarn install --network-timeout 300000

# ===========================================
# Stage 2: Application Build
# ===========================================
FROM node:23-alpine AS builder
WORKDIR /app

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

# CRITICAL: Create health endpoint BEFORE build so it gets compiled
RUN mkdir -p /app/src/api/health && \
    echo 'import type { MedusaRequest, MedusaResponse } from "@medusajs/framework/http";' > /app/src/api/health/route.ts && \
    echo '' >> /app/src/api/health/route.ts && \
    echo 'export const GET = async (req: MedusaRequest, res: MedusaResponse): Promise<void> => {' >> /app/src/api/health/route.ts && \
    echo '  res.json({ status: "healthy", timestamp: new Date().toISOString(), uptime: process.uptime() });' >> /app/src/api/health/route.ts && \
    echo '};' >> /app/src/api/health/route.ts

# Build the application
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
ENV PGSSLMODE=disable
RUN yarn medusa build

# ===========================================
# Stage 3: Production Runtime
# ===========================================
FROM node:23-alpine AS production
WORKDIR /app

ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}

# SSL disable environment variables (already working from your config)
ENV PGSSLMODE=disable
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
ENV MIKRO_ORM_SSL=false
ENV MIKRO_ORM_REJECT_UNAUTHORIZED=false

# Install runtime dependencies
RUN apk add --no-cache \
    postgresql-client \
    redis \
    curl \
    wget \
    bash \
    tini && \
    corepack enable && \
    corepack prepare yarn@4.4.0 --activate

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy built application from builder
COPY --from=builder --chown=nodejs:nodejs /app ./

# Create required directories
RUN mkdir -p /app/uploads /app/logs /app/.medusa && \
    chown -R nodejs:nodejs /app

# Copy startup script
COPY --chown=nodejs:nodejs startup.sh /app/startup.sh
RUN chmod +x /app/startup.sh

# Switch to non-root user
USER nodejs

EXPOSE 9000

# Healthcheck with realistic timing for Medusa startup
HEALTHCHECK --interval=30s \
            --timeout=30s \
            --start-period=120s \
            --retries=20 \
            CMD wget --no-verbose --tries=1 --spider http://localhost:9000/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/startup.sh"]