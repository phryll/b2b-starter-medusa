FROM node:20-alpine
WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    curl \
    bash \
    netcat-openbsd \
    tini

# Install Yarn Classic
RUN corepack disable && \
    npm uninstall -g yarn || true && \
    npm install -g yarn@1.22.19

# Copy package files and install dependencies (this can be cached)
COPY package.json ./
RUN yarn install --network-timeout 600000

# Copy source code (do NOT build yet)
COPY . ./

RUN chmod +x ./wait-for-backend.sh

# Create user and set permissions
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

USER nodejs
EXPOSE 3001

# Health check (only works after build completes)
HEALTHCHECK --interval=30s --timeout=15s --start-period=180s --retries=10 \
    CMD curl -f http://localhost:${PORT:-3001}/ || exit 1

# Runtime build and start
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-c", "./wait-for-backend.sh && echo 'Building application...' && yarn build && echo 'Starting application...' && yarn start -p ${PORT:-3001}"]