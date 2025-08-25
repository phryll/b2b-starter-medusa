# === Build Stage ===
FROM node:20-slim AS builder

WORKDIR /app/backend

# System-Dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Corepack für Yarn 4 aktivieren
RUN corepack enable

# Abhängigkeiten kopieren
COPY backend/package.json backend/yarn.lock ./ 
COPY backend/.yarnrc.yml ./

# Install (kein Cache möglich, wenn Datei geändert)
RUN yarn install --immutable --network-timeout 300000

# Projekt-Dateien kopieren
COPY backend/ ./

# TS-Konfiguration kopieren (falls vorhanden)
COPY backend/tsconfig.json ./

# Build
RUN yarn medusa build

# === Production Stage ===
FROM node:20-slim AS production

WORKDIR /app/backend

# Systemtools für Healthcheck
RUN apt-get update && apt-get install -y \
    python3 \
    curl \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable

# Kopieren aus builder
COPY --from=builder /app/backend/package.json ./
COPY --from=builder /app/backend/yarn.lock ./
COPY --from=builder /app/backend/.yarnrc.yml ./
COPY --from=builder /app/backend/tsconfig.json ./
COPY --from=builder /app/backend/node_modules ./node_modules
COPY --from=builder /app/backend/.medusa ./.medusa
COPY --from=builder /app/backend/src ./src
COPY --from=builder /app/backend/medusa-config.* ./

# Environment
ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=2048"

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

CMD ["yarn", "medusa", "start"]
