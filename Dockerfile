# ---- Build Stage ----
FROM node:20-slim AS builder

WORKDIR /app/backend

# System-Dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Corepack aktivieren für Yarn 4
RUN corepack enable

# Dependencies
COPY backend/package.json backend/yarn.lock ./
COPY backend/.yarnrc.yml ./
RUN yarn install --network-timeout 300000

# Source kopieren & build
COPY backend/ ./
RUN yarn medusa build


# ---- Production Stage ----
FROM node:20-slim AS production

WORKDIR /app/backend

RUN apt-get update && apt-get install -y \
    python3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable

# Nur das Nötigste rüberziehen
COPY --from=builder /app/backend/package.json ./
COPY --from=builder /app/backend/yarn.lock ./
COPY --from=builder /app/backend/.yarnrc.yml ./
COPY --from=builder /app/backend/node_modules ./node_modules
COPY --from=builder /app/backend/.medusa ./.medusa
COPY --from=builder /app/backend/medusa-config.* ./
COPY --from=builder /app/backend/tsconfig.json ./tsconfig.json

ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=2048"

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1

CMD ["yarn", "medusa", "start"]
