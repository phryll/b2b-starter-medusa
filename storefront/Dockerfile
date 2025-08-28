# ===========================================
# Storefront Dockerfile - Yarn 4 Compatible
# ===========================================
FROM node:20-alpine AS deps
WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

# Enable Corepack and setup Yarn 4
RUN corepack enable && \
    corepack prepare yarn@4.4.0 --activate

# Copy package files
COPY package.json yarn.lock .yarnrc.yml* ./

# Install dependencies with Yarn 4
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
RUN yarn install --immutable --network-timeout 600000

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

# Enable Corepack and setup Yarn 4
RUN corepack enable && \
    corepack prepare yarn@4.4.0 --activate

# Copy dependencies and config from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/.yarn ./.yarn
COPY --from=deps /app/package.json /app/yarn.lock /app/.yarnrc.yml* ./

# Copy application source
COPY . ./

# Build the application
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

# Enable Corepack for production
RUN corepack enable && \
    corepack prepare yarn@4.4.0 --activate

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copy built application from builder
COPY --from=builder --chown=nodejs:nodejs /app/package.json ./
COPY --from=builder --chown=nodejs:nodejs /app/yarn.lock ./
COPY --from=builder --chown=nodejs:nodejs /app/.yarnrc.yml* ./
COPY --from=builder --chown=nodejs:nodejs /app/.yarn ./.yarn
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/.next ./.next
COPY --from=builder --chown=nodejs:nodejs /app/public ./public

# Create required directories and fix permissions
RUN mkdir -p /app/.next && \
    chown -R nodejs:nodejs /app

# Switch to non-root user
USER nodejs

EXPOSE 3001

# Health check
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=90s \
            --retries=5 \
            CMD curl -f http://localhost:3001/ || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["yarn", "start"]