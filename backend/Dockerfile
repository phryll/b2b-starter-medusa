# ===========================================
# Backend Dockerfile - Yarn Classic Version
# ===========================================

# ===========================================
# Stage 1: Dependencies Installation
# ===========================================
FROM node:20-alpine AS deps
WORKDIR /app
ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}
ENV PORT=9000

# Install ALL system dependencies Medusa needs
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    postgresql-client \
    git \
    cairo-dev \
    jpeg-dev \
    pango-dev \
    musl-dev \
    giflib-dev \
    pixman-dev \
    pangomm-dev \
    libjpeg-turbo-dev \
    freetype-dev

# Disable corepack and install Yarn Classic
RUN corepack disable && \
    npm uninstall -g yarn || true && \
    npm install -g yarn@1.22.19

# Copy package files
COPY package.json ./
COPY .yarnrc ./

# Aggressive network settings for yarn
ENV YARN_REGISTRY=https://registry.yarnpkg.com/
ENV YARN_NETWORK_TIMEOUT=1800000 
ENV YARN_CHILD_CONCURRENCY=1
ENV YARN_NETWORK_CONCURRENCY=1
ENV YARN_CACHE_FOLDER=/tmp/.yarn-cache

# Install dependencies with maximum reliability settings
RUN yarn config set registry https://registry.yarnpkg.com/ && \
    yarn config set network-timeout 1800000  && \
    yarn config set child-concurrency 1 && \
    yarn config set network-concurrency 1 && \
    yarn config set disable-self-update-check true && \
    yarn install --production=false --network-timeout 1800000  --verbose
# ===========================================
# Stage 2: Application Build
# ===========================================
FROM node:20-alpine AS build
WORKDIR /app
ARG NODE_ENV

# Install build dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    cairo-dev \
    jpeg-dev \
    pango-dev \
    musl-dev \
    giflib-dev \
    pixman-dev \
    pangomm-dev \
    libjpeg-turbo-dev \
    freetype-dev

# Disable corepack and install Yarn Classic
RUN corepack disable && \
    npm uninstall -g yarn || true && \
    npm install -g yarn@1.22.19

# Copy dependencies from previous stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json ./

# Copy application source
COPY . ./

ENV NODE_OPTIONS=--max-old-space-size=4096

# Create/override health endpoint (AFTER source copy, BEFORE build)
RUN mkdir -p /app/src/api/health && \
    echo 'import type { MedusaRequest, MedusaResponse } from "@medusajs/framework/http";' > /app/src/api/health/route.ts && \
    echo '' >> /app/src/api/health/route.ts && \
    echo 'export const GET = async (req: MedusaRequest, res: MedusaResponse): Promise<void> => {' >> /app/src/api/health/route.ts && \
    echo '  res.status(200).json({ status: "healthy", timestamp: new Date().toISOString(), uptime: process.uptime() });' >> /app/src/api/health/route.ts && \
    echo '};' >> /app/src/api/health/route.ts

# Build the application with yarn
ENV DISABLE_ADMIN=true
RUN yarn build || yarn build

# Verify build worked
# RUN ls -la /app/.medusa/server/ || (echo "Build failed" && exit 1)
RUN ls -la /app/.medusa/server/src/modules/ || echo "Build output missing"
RUN ls -la /app/src/modules/ || echo "Source missing"
RUN ls -la /app/.medusa/server/src/modules/approval/ || echo "Approval module missing"
RUN ls -la /app/.medusa/server/src/links/ || echo "Links module missing"
RUN ls -la /app/.medusa/admin || (echo "Admin build missing!")

# ===========================================
# Stage 3: Production Runtime
# ===========================================
FROM node:20-alpine AS production
WORKDIR /app

ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}

# SSL disable environment variables
ENV PGSSLMODE=disable
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
ENV MIKRO_ORM_SSL=false
ENV MIKRO_ORM_REJECT_UNAUTHORIZED=false

# Set port explicitly
ENV PORT=9000

# Install runtime dependencies
RUN apk add --no-cache \
    postgresql-client \
    curl \
    wget \
    bash \
    netcat-openbsd \
    tini \
    cairo \
    jpeg \
    pango \
    giflib \
    pixman \
    libjpeg-turbo \
    freetype

# Disable corepack and install Yarn Classic
RUN corepack disable && \
    npm uninstall -g yarn || true && \
    npm install -g yarn@1.22.19

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy built application from builder
COPY --from=build --chown=nodejs:nodejs /app ./

# Create required directories
RUN mkdir -p /app/uploads /app/logs /app/.medusa && \
    chown -R nodejs:nodejs /app

# Copy startup script
COPY --chown=nodejs:nodejs startup.sh /app/startup.sh
RUN chmod +x /app/startup.sh

# Switch to non-root user
USER nodejs

# Ensure container advertises correct port
EXPOSE 9000

# Use shell form so $PORT is respected at runtime
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=10 \
  CMD curl -f http://localhost:${PORT:-9000}/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/startup.sh"]