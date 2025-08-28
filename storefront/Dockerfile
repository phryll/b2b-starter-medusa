# ===========================================
# Storefront Dockerfile - NPM Version (Simpler)
# ===========================================
FROM node:20-alpine AS deps
WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git

# Copy package.json only (ignore yarn.lock to force npm usage)
COPY package.json ./

# Use npm instead of yarn to avoid version conflicts
RUN npm install --legacy-peer-deps

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

# Copy package.json and install all dependencies (including dev)
COPY package.json ./
RUN npm install --legacy-peer-deps

# Copy application source
COPY . ./

# Build the application with npm
RUN npm run build

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

# Copy only what we need for production
COPY --from=builder --chown=nodejs:nodejs /app/package.json ./
COPY --from=builder --chown=nodejs:nodejs /app/.next ./.next
COPY --from=builder --chown=nodejs:nodejs /app/public ./public

# Install only production dependencies in final stage
RUN npm install --only=production --legacy-peer-deps && \
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
CMD ["npm", "start"]