# Build Arguments
ARG NODE_ENV=production

# Stage 1: Dependencies
FROM node:23-alpine AS deps
WORKDIR /app

ARG NODE_ENV
ENV NODE_TLS_REJECT_UNAUTHORIZED=0

RUN apk add --no-cache python3 make g++ postgresql-client git
RUN corepack enable && corepack prepare yarn@4.4.0 --activate

COPY backend/package.json backend/yarn.lock backend/.yarnrc.yml ./
RUN yarn install --network-timeout 300000

# Stage 2: Builder
FROM node:23-alpine AS builder
WORKDIR /app

ARG NODE_ENV
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
ENV PGSSLMODE=disable

RUN apk add --no-cache python3 make g++ git
RUN corepack enable && corepack prepare yarn@4.4.0 --activate

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/.yarn ./.yarn
COPY backend/package.json backend/yarn.lock backend/.yarnrc.yml ./
COPY backend/ ./

# Ensure health endpoint exists before build
RUN mkdir -p /app/src/api/health && \
    cat > /app/src/api/health/route.ts << 'EOF'
import type { MedusaRequest, MedusaResponse } from "@medusajs/framework/http";

export async function GET(req: MedusaRequest, res: MedusaResponse): Promise<void> {
  res.json({
    status: "healthy",
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || "development",
  });
}
EOF

RUN yarn medusa build

# Stage 3: Production
FROM node:23-alpine AS production
WORKDIR /app

ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}
ENV PGSSLMODE=disable
ENV PGSSL=0
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
ENV MIKRO_ORM_SSL=false
ENV MIKRO_ORM_REJECT_UNAUTHORIZED=false

RUN apk add --no-cache \
    postgresql-client \
    redis \
    curl \
    wget \
    netcat-openbsd \
    bash \
    tini && \
    corepack enable && \
    corepack prepare yarn@4.4.0 --activate

RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

COPY --from=builder --chown=nodejs:nodejs /app ./

RUN mkdir -p /app/uploads /app/logs /app/.medusa && \
    chown -R nodejs:nodejs /app

COPY --chown=nodejs:nodejs startup.sh /app/startup.sh
RUN chmod +x /app/startup.sh

# Create healthcheck script
RUN cat > /app/healthcheck.sh << 'EOF'
#!/bin/sh
# Wait for port to be open
timeout 10 sh -c 'until nc -z localhost 9000; do sleep 1; done'
# Check health endpoint
wget --no-verbose --tries=1 --spider --timeout=10 http://localhost:9000/health || exit 1
EOF
RUN chmod +x /app/healthcheck.sh && chown nodejs:nodejs /app/healthcheck.sh

USER nodejs
EXPOSE 9000

HEALTHCHECK --interval=30s \
            --timeout=30s \
            --start-period=600s \
            --retries=20 \
            CMD /app/healthcheck.sh

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/startup.sh"]