# ===========================================
# Build Arguments
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
    freetype-dev

# Use standard Yarn (more stable with Medusa than Yarn 4)
# Remove Yarn 4 setup and use the default Yarn that comes with Node 20

# Copy package files
COPY backend/package.json backend/yarn.lock* ./

# Install dependencies with longer timeout
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
RUN yarn install --frozen-lockfile --network-timeout 600000

# ===========================================
# Stage 2: Application Build
# ===========================================
FROM node:20-alpine AS builder
WORKDIR /app

ARG NODE_ENV

# Install build dependencies (same as deps stage)
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

# Copy dependencies from previous stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json /app/yarn.lock* ./

# Copy application source
COPY backend/ ./

# Create health endpoint that actually works
RUN mkdir -p /app/src/api/health && \
    echo 'import type { MedusaRequest, MedusaResponse } from "@medusajs/framework/http";' > /app/src/api/health/route.ts && \
    echo '' >> /app/src/api/health/route.ts && \
    echo 'export const GET = async (req: MedusaRequest, res: MedusaResponse): Promise<void> => {' >> /app/src/api/health/route.ts && \
    echo '  res.status(200).json({ status: "healthy", timestamp: new Date().toISOString(), uptime: process.uptime() });' >> /app/src/api/health/route.ts && \
    echo '};' >> /app/src/api/health/route.ts

# Build the application
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
ENV PGSSLMODE=disable
RUN yarn build

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
    freetype

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

EXPOSE 3000

# More realistic health check for Medusa startup
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=180s \
            --retries=10 \
            CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/startup.sh"]