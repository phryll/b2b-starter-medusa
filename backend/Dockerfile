# ===========================================
# Backend Dockerfile - Simplified Production
# ===========================================

FROM node:20-alpine AS deps
# Use /server as recommended by Medusa team
WORKDIR /server

# Install system dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    postgresql-client \
    git \
    cairo-dev \
    jpeg-dev \
    pango-dev \
    musl-dev \
    giflib-dev \
    pixman-dev \
    pangomm-dev \
    libjpeg-turbo-dev \
    freetype-dev

# Use npm instead of yarn to avoid fetch issues
COPY package.json ./
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
ENV NPM_CONFIG_CACHE=/tmp/.npm-cache
RUN npm install --only=production

FROM node:20-alpine AS build
WORKDIR /server

RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    cairo-dev \
    jpeg-dev \
    pango-dev \
    musl-dev \
    giflib-dev \
    pixman-dev \
    pangomm-dev \
    libjpeg-turbo-dev \
    freetype-dev

COPY --from=deps /server/node_modules ./node_modules
COPY --from=deps /server/package.json ./
COPY . ./

# Build the application
RUN npm run build

FROM node:20-alpine AS production
WORKDIR /server

ENV NODE_ENV=production
ENV PORT=9000
# SSL configurations from official docs
ENV PGSSLMODE=disable
ENV NODE_TLS_REJECT_UNAUTHORIZED=0

RUN apk add --no-cache \
    postgresql-client \
    curl \
    bash \
    tini

RUN addgroup -g 1001 -S medusa && \
    adduser -S medusa -u 1001

COPY --from=build --chown=medusa:medusa /server ./

# Simplified startup script
COPY --chown=medusa:medusa start.sh /server/start.sh
RUN chmod +x /server/start.sh

USER medusa
EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
  CMD curl -f http://localhost:9000/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/server/start.sh"]