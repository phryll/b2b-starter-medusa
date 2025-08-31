# ===========================================
# Backend Dockerfile - NPM Version (Simpler)
# ===========================================
ARG NODE_ENV=production

# ===========================================
# Stage 1: Dependencies Installation
# ===========================================
FROM node:20-alpine AS deps
WORKDIR /app
ARG NODE_ENV

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
    freetype-dev \
    npm

# Copy only package.json (ignore yarn.lock to force npm usage)
COPY package.json ./

# Clean install with correct dependencies
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
RUN rm -rf node_modules package-lock.json && \
    npm install --legacy-peer-deps

# ===========================================
# Stage 2: Application Build
# ===========================================
FROM node:20-alpine AS builder
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
    freetype-dev \
    typescript

# Copy dependencies from previous stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json ./

# Ensure TypeScript is available locally too
RUN npm install typescript @types/node --save-dev --legacy-peer-deps --no-optional

# Copy application source
COPY . ./

# Verify TypeScript is available before building
RUN which tsc && tsc --version

# Create/override health endpoint (AFTER source copy, BEFORE build)
RUN mkdir -p /app/src/api/health && \
    echo 'import type { MedusaRequest, MedusaResponse } from "@medusajs/framework/http";' > /app/src/api/health/route.ts && \
    echo '' >> /app/src/api/health/route.ts && \
    echo 'export const GET = async (req: MedusaRequest, res: MedusaResponse): Promise<void> => {' >> /app/src/api/health/route.ts && \
    echo '  res.status(200).json({ status: "healthy", timestamp: new Date().toISOString(), uptime: process.uptime() });' >> /app/src/api/health/route.ts && \
    echo '};' >> /app/src/api/health/route.ts

# Build the application (with TypeScript now available)
RUN npm run build

RUN ls -la /app/.medusa/server/src/modules/ || echo "Build output missing"
RUN ls -la /app/src/modules/ || echo "Source missing"
RUN ls -la /app/.medusa/server/src/modules/approval/
RUN ls -la /app/.medusa/server/src/links/


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
ENV PORT=3000

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
    freetype \
    npm

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy built application from builder
COPY --from=builder --chown=nodejs:nodejs /app ./

# Create required directories
RUN mkdir -p /app/uploads /app/logs /app/.medusa && \
    chown -R nodejs:nodejs /app

# Copy startup script (modified for npm)
COPY --chown=nodejs:nodejs startup.sh /app/startup.sh
RUN chmod +x /app/startup.sh

# Switch to non-root user
USER nodejs

EXPOSE 3000


# Health check
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=180s \
            --retries=10 \
            CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/startup.sh"]