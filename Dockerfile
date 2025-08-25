# Dockerfile für MedusaJS B2B Starter - Optimiert für CPX21 (4GB RAM, 3 vCPU)
# Multi-stage build für optimale Image-Größe

# Build Stage
FROM node:20-slim AS builder

# Arbeitsverzeichnis setzen
WORKDIR /app

# System-Dependencies installieren
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Corepack aktivieren für Yarn 4.4.0
RUN corepack enable

# Package.json und Yarn-Files kopieren
COPY backend/package.json backend/yarn.lock ./backend/
COPY backend/.yarnrc.yml ./backend/

# Working Directory ins backend wechseln
WORKDIR /app/backend

# Dependencies installieren mit Yarn 4 (Lockfile-Updates erlauben)
RUN yarn install --network-timeout 300000

# Source Code kopieren
COPY backend/ ./

# MedusaJS Backend builden
RUN yarn medusa build

# Production Stage
FROM node:20-slim AS production

# Arbeitsverzeichnis setzen
WORKDIR /app/backend

# System-Dependencies für Production installieren
RUN apt-get update && apt-get install -y \
    python3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Corepack aktivieren
RUN corepack enable

# Built application von builder stage kopieren
COPY --from=builder /app/backend/package.json ./
COPY --from=builder /app/backend/yarn.lock ./
COPY --from=builder /app/backend/.yarnrc.yml ./
COPY --from=builder /app/backend/node_modules ./node_modules
COPY --from=builder /app/backend/.medusa ./.medusa
COPY --from=builder /app/backend/src ./src
COPY --from=builder /app/backend/medusa-config.* ./
COPY --from=builder /app/backend/tsconfig.json ./tsconfig.json
COPY --from=builder /app/backend/.medusa ./.medusa
COPY --from=builder /app/backend/src ./src
COPY --from=builder /app/backend/medusa-config.* ./
COPY --from=builder /app/backend/package.json ./
COPY --from=builder /app/backend/yarn.lock ./
COPY --from=builder /app/backend/.yarnrc.yml ./
COPY --from=builder /app/backend/node_modules ./node_modules



# Environment Variables für Production
ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=3200"

ENV REDIS_URL=${REDIS_URL}

# Port 9000 für MedusaJS exposieren
EXPOSE 9000

# Health Check
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1

# MedusaJS starten
CMD ["yarn", "medusa", "start"]