# --------------------
# Build Stage
# --------------------
FROM node:20-slim AS builder

WORKDIR /app

# System Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

# Corepack aktivieren
RUN corepack enable

# Alle ARGs deklarieren
ARG DATABASE_URL
ARG REDIS_URL
ARG WORKER_MODE
ARG COOKIE_SECRET
ARG JWT_SECRET
ARG STORE_CORS
ARG ADMIN_CORS
ARG AUTH_CORS
ARG PORT

# Kopiere nur package.json + yarn.lock + .yarnrc.yml
COPY backend/package.json backend/yarn.lock backend/.yarnrc.yml ./

# .env erstellen mit allen ARGs
RUN echo "DATABASE_URL=${DATABASE_URL}" > .env \
 && echo "REDIS_URL=${REDIS_URL}" >> .env \
 && echo "WORKER_MODE=${WORKER_MODE}" >> .env \
 && echo "COOKIE_SECRET=${COOKIE_SECRET}" >> .env \
 && echo "JWT_SECRET=${JWT_SECRET}" >> .env \
 && echo "STORE_CORS=${STORE_CORS}" >> .env \
 && echo "ADMIN_CORS=${ADMIN_CORS}" >> .env \
 && echo "AUTH_CORS=${AUTH_CORS}" >> .env \
 && echo "PORT=${PORT}" >> .env

# Dependencies installieren
RUN yarn install --network-timeout 300000 \
 && yarn cache clean

# Backend Source kopieren
COPY backend/ ./

# Build Medusa
RUN yarn medusa build

# --------------------
# Production Stage
# --------------------
FROM node:20-slim AS production

WORKDIR /app

# System dependencies
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

RUN corepack enable

# Optional: alle ARGs auch in Production definieren, falls sie gebraucht werden
ARG DATABASE_URL
ARG REDIS_URL
ARG WORKER_MODE
ARG COOKIE_SECRET
ARG JWT_SECRET
ARG STORE_CORS
ARG ADMIN_CORS
ARG AUTH_CORS
ARG PORT

# Alles aus Builder kopieren (inkl. build output und .env)
COPY --from=builder /app ./

# Environment Variables setzen
ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=3000"

EXPOSE 9000

COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh
CMD ["./entrypoint.sh"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1
