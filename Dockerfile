# ---- Production Stage ----
FROM node:20-slim AS production
WORKDIR /app/backend

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare yarn@4.4.0 --activate

# Artefakte aus Builder kopieren
COPY --from=builder /app/backend/package.json ./
COPY --from=builder /app/backend/yarn.lock ./
COPY --from=builder /app/backend/.yarnrc.yml ./
COPY --from=builder /app/backend/node_modules ./node_modules
COPY --from=builder /app/backend/.medusa ./.medusa
COPY --from=builder /app/backend/medusa-config.* ./

# Server-Dependencies installieren
RUN yarn --cwd .medusa/server install --network-timeout 300000 --production

ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=2048"
EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

# Migrationen ausführen, dann starten
CMD sh -c "yarn medusa db:migrate && yarn --cwd .medusa/server start"
