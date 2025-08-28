# ===========================================
# Storefront Dockerfile - Fixed Version
# ===========================================
FROM node:20-alpine AS deps
WORKDIR /app

# Install build dependencies for potential native modules
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

# Copy package files with better error handling
COPY package.json ./
# Copy yarn.lock only if it exists, otherwise use npm
COPY yarn.lock* ./

# Install dependencies with fallback to npm if yarn fails
RUN set -e; \
    if [ -f yarn.lock ]; then \
        echo "Installing with Yarn..."; \
        yarn install --frozen-lockfile --network-timeout 600000 --verbose || \
        (echo "Yarn failed, trying without frozen lockfile..." && \
         yarn install --network-timeout 600000 --verbose); \
    else \
        echo "No yarn.lock found, using npm..."; \
        npm ci --only=production; \
    fi

# ===========================================
# Stage 2: Application Build
# ===========================================
FROM node:20-alpine AS builder
WORKDIR /app

# Install build dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

# Copy dependencies and package files from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json ./
COPY --from=deps /app/yarn.lock* ./

# Copy application source
COPY . ./

# Build with error handling
RUN set -e; \
    echo "Building Next.js application..."; \
    if [ -f yarn.lock ]; then \
        yarn build; \
    else \
        npm run build; \
    fi

# ===========================================
# Stage 3: Production Runtime
# ===========================================
FROM node:20-alpine AS production
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3001

# Install runtime dependencies
RUN apk add --no-cache \
    curl \
    bash \
    tini

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy built application from builder
COPY --from=builder --chown=nodejs:nodejs /app/package.json ./
COPY --from=builder --chown=nodejs:nodejs /app/yarn.lock* ./
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/.next ./.next
COPY --from=builder --chown=nodejs:nodejs /app/public ./public

# Create required directories
RUN mkdir -p /app/.next && \
    chown -R nodejs:nodejs /app

# Switch to non-root user
USER nodejs

EXPOSE 3001

# Health check for Next.js - more forgiving
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=60s \
            --retries=5 \
            CMD curl -f http://localhost:3001/ || curl -f http://localhost:3001/api/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["yarn", "start"]