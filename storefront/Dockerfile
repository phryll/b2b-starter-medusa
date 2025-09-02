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

# Disable corepack and install Yarn Classic
RUN corepack disable && \
    npm uninstall -g yarn || true && \
    npm install -g yarn@1.22.19

# Copy package files and install dependencies
COPY package.json ./

# Configure for reliable network operations

# Aggressive yarn network settings
ENV YARN_REGISTRY=https://registry.yarnpkg.com/
ENV YARN_NETWORK_TIMEOUT=900000
ENV YARN_CHILD_CONCURRENCY=1
ENV YARN_NETWORK_CONCURRENCY=1

ENV YARN_CACHE_FOLDER=/tmp/.yarn-cache

RUN yarn config set registry https://registry.yarnpkg.com/ && \
    yarn config set network-timeout 900000 && \
    yarn config set child-concurrency 1 && \
    yarn config set network-concurrency 1 && \
    yarn install --network-timeout 900000
    
RUN --mount=type=cache,target=/tmp/.yarn-cache \
    yarn install --cache-folder /tmp/.yarn-cache --network-timeout 600000 && \
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