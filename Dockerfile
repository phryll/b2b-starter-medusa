# --------------------
# Build Stage
# --------------------
FROM node:23-slim AS builder

WORKDIR /app

# System Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

# Corepack aktivieren
RUN corepack enable

# Copy package files from backend directory
COPY backend/package.json backend/yarn.lock backend/.yarnrc.yml ./

# Install dependencies
RUN yarn install --network-timeout 300000 \
 && yarn cache clean

# Copy backend source code
COPY backend/ ./

# Build Medusa
RUN yarn medusa build

# --------------------
# Production Stage
# --------------------
FROM node:23-slim AS production

WORKDIR /app

# System dependencies
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

RUN corepack enable

# Declare all ARGs
ARG DATABASE_URL
ARG REDIS_URL
ARG WORKER_MODE
ARG COOKIE_SECRET
ARG JWT_SECRET
ARG STORE_CORS
ARG ADMIN_CORS
ARG AUTH_CORS
ARG PORT

# Set environment variables
ENV DATABASE_URL=${DATABASE_URL}
ENV REDIS_URL=${REDIS_URL}
ENV WORKER_MODE=${WORKER_MODE:-server}
ENV COOKIE_SECRET=${COOKIE_SECRET}
ENV JWT_SECRET=${JWT_SECRET}
ENV STORE_CORS=${STORE_CORS}
ENV ADMIN_CORS=${ADMIN_CORS}
ENV AUTH_CORS=${AUTH_CORS}
ENV PORT=${PORT:-9000}

# Copy everything from builder stage
COPY --from=builder /app ./

# Create .env file for compatibility
RUN echo "DATABASE_URL=${DATABASE_URL}" > .env \
 && echo "REDIS_URL=${REDIS_URL}" >> .env \
 && echo "WORKER_MODE=${WORKER_MODE:-server}" >> .env \
 && echo "COOKIE_SECRET=${COOKIE_SECRET}" >> .env \
 && echo "JWT_SECRET=${JWT_SECRET}" >> .env \
 && echo "STORE_CORS=${STORE_CORS}" >> .env \
 && echo "ADMIN_CORS=${ADMIN_CORS}" >> .env \
 && echo "AUTH_CORS=${AUTH_CORS}" >> .env \
 && echo "PORT=${PORT:-9000}" >> .env

EXPOSE 9000

COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

# Health check - check if medusa process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD ps aux | grep 'medusa start' | grep -v grep || exit 1

CMD ["./entrypoint.sh"]
