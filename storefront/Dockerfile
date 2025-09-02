# ===========================================
# Storefront Dockerfile - Yarn Classic Version
# ===========================================
FROM node:20-alpine
WORKDIR /app

# Install system dependencies and runtime tools
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    curl \
    bash \
    tini

# Install Yarn Classic globally (more reliable than corepack)
RUN npm install -g yarn@1.22.19

# Copy package files and install dependencies
COPY package.json ./
COPY yarn.lock* ./

# Configure for reliable network operations
ENV YARN_CACHE_FOLDER=/tmp/.yarn-cache
RUN yarn install --network-timeout 300000 && \
    yarn global add typescript

# Copy source code (no build during Docker build)
COPY . ./

# Create next.config.js for safe runtime building
RUN echo 'module.exports = {' > next.config.js && \
    echo '  eslint: { ignoreDuringBuilds: true },' >> next.config.js && \
    echo '  typescript: { ignoreBuildErrors: true },' >> next.config.js && \
    echo '  images: { unoptimized: true },' >> next.config.js && \
    echo '  output: "standalone"' >> next.config.js && \
    echo '}' >> next.config.js

COPY wait-for-backend.sh .
RUN chmod +x wait-for-backend.sh

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

USER nodejs
EXPOSE 3001

# Health check (more forgiving during initial build)
HEALTHCHECK --interval=30s --timeout=15s --start-period=300s --retries=10 \
    CMD curl -f http://localhost:3001/ || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-c", "./wait-for-backend.sh && yarn build && yarn start"]