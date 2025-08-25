# Dockerfile für MedusaJS B2B Starter - Optimiert für CPX21 (4GB RAM, 3 vCPU)
# Multi-stage build für optimale Image-Größe

# -------------------------------
# Build Stage
# -------------------------------
FROM node:20-slim AS builder

# Build-Time ARGs definieren
FROM deps AS build
ARG DATABASE_URL
ARG REDIS_URL
ARG WORKER_MODE
ARG COOKIE_SECRET
ARG JWT_SECRET
ARG STORE_CORS
ARG ADMIN_CORS
ARG AUTH_CORS
ARG PORT

# ENV Variablen setzen (für Build und spätere Runtime optional)
ENV DATABASE_URL=${DATABASE_URL}
ENV REDIS_URL=${REDIS_URL}
ENV WORKER_MODE=${WORKER_MODE}
ENV COOKIE_SECRET=${COOKIE_SECRET}
ENV JWT_SECRET=${JWT_SECRET}
ENV STORE_CORS=${STORE_CORS}
ENV ADMIN_CORS=${ADMIN_CORS}
ENV AUTH_CORS=${AUTH_CORS}
ENV PORT=${PORT}

# Arbeitsverzeichnis setzen
WORKDIR /app/backend

# System-Dependencies installieren
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Corepack aktivieren für Yarn 4.4.0
RUN corepack enable

# Package.json und Yarn-Files kopieren
COPY backend/package.json backend/yarn.lock ./ 
COPY backend/.yarnrc.yml ./

# Dependencies installieren
RUN yarn install --network-timeout 300000 && yarn cache clean

# Source Code kopieren
COPY backend/ ./

# Optional: .env für Build-Time erzeugen (falls Medusa Build Variablen braucht)
RUN echo "DATABASE_URL=${DATABASE_URL}" > .env \
    && echo "REDIS_URL=${REDIS_URL}" >> .env \
    && echo "WORKER_MODE=${WORKER_MODE}" >> .env \
    && echo "COOKIE_SECRET=${COOKIE_SECRET}" >> .env \
    && echo "JWT_SECRET=${JWT_SECRET}" >> .env \
    && echo "STORE_CORS=${STORE_CORS}" >> .env \
    && echo "ADMIN_CORS=${ADMIN_CORS}" >> .env \
    && echo "AUTH_CORS=${AUTH_CORS}" >> .env \
    && echo "PORT=${PORT}" >> .env

# Medusa Backend builden
RUN yarn medusa build

# -------------------------------
# Production Stage
# -------------------------------
FROM node:20-slim AS production

# Arbeitsverzeichnis
WORKDIR /app/backend

# System-Dependencies für Production
RUN apt-get update && apt-get install -y curl \
    && rm -rf /var/lib/apt/lists/*

# Corepack aktivieren
RUN corepack enable

# Copy built app vom Builder
COPY --from=builder /app/backend/package.json ./
COPY --from=builder /app/backend/yarn.lock ./
COPY --from=builder /app/backend/.yarnrc.yml ./
COPY --from=builder /app/backend/node_modules ./node_modules
COPY --from=builder /app/backend/.medusa ./.medusa
COPY --from=builder /app/backend/src ./src
COPY --from=builder /app/backend/medusa-config.* ./
COPY --from=builder /app/backend/tsconfig.json ./
COPY --from=builder /app/backend/.env ./  # .env auch in Production

# Environment Variables für Production (falls nicht über .env gesetzt)
ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=3000"

# Port exposen
EXPOSE 9000

# Entrypoint Script
COPY entrypoint.sh /app/backend/entrypoint.sh
RUN chmod +x /app/backend/entrypoint.sh
CMD ["./entrypoint.sh"]

# Health Check
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1
