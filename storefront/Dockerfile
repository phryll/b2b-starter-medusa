# ===========================================
# Storefront Dockerfile - Place in storefront/ directory
# ===========================================
FROM node:20-alpine AS deps
WORKDIR /app

# Install build dependencies for potential native modules
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

# Copy package files (we're IN the storefront directory)
COPY package.json yarn.lock* ./

# Install dependencies
RUN yarn install --frozen-lockfile --network-timeout 600000

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

# Copy dependencies from previous stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json /app/yarn.lock* ./

# Copy application source (everything in storefront/)
COPY . ./

# Build the Next.js application
RUN yarn build

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
COPY --from=builder --chown=nodejs:nodejs /app ./

# Create required directories
RUN mkdir -p /app/.next && \
    chown -R nodejs:nodejs /app

# Switch to non-root user
USER nodejs

EXPOSE 3001

# Health check for Next.js
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=60s \
            --retries=5 \
            CMD curl -f http://localhost:3001/ || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["yarn", "start"]