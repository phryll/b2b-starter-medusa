# ---- Production Stage ----
FROM node:20-slim AS production
WORKDIR /app/backend

# nur was wir wirklich brauchen
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Corepack / Yarn 4 pinnen (stabil)
RUN corepack enable && corepack prepare yarn@4.4.0 --activate

# Artefakte aus Builder kopieren
COPY --from=builder /app/backend/package.json ./
COPY --from=builder /app/backend/yarn.lock ./
COPY --from=builder /app/backend/.yarnrc.yml ./
COPY --from=builder /app/backend/node_modules ./node_modules
COPY --from=builder /app/backend/.medusa ./.medusa
COPY --from=builder /app/backend/medusa-config.* ./

# WICHTIG: deps des kompilierten Servers installieren
RUN yarn --cwd .medusa/server install --network-timeout 300000 --production

ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=2048"
EXPOSE 9000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:9000/health || exit 1

# 1) Migrationen  2) Start
# (einfach gehalten – wenn Postgres mal 2-3s noch nicht antwortet, versucht Coolify den Start erneut)
CMD sh -c "yarn medusa db:migrate && yarn --cwd .medusa/server start"
