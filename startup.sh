#!/bin/bash
set -e

echo "========================================="
echo "  Medusa B2B Starter - Starting Up"
echo "========================================="

# All environment variables come from Coolify runtime

# Set defaults only if not provided
export NODE_ENV=${NODE_ENV:-production}
export PORT=${PORT:-9000}
export WORKER_MODE=${WORKER_MODE:-shared}
export PGSSLMODE=${PGSSLMODE:-disable}
export NODE_TLS_REJECT_UNAUTHORIZED=${NODE_TLS_REJECT_UNAUTHORIZED:-0}

# Fix Redis URL if using SSL
if [ -n "$REDIS_URL" ]; then
    if echo "$REDIS_URL" | grep -q "^rediss://"; then
        echo "Converting Redis SSL URL to non-SSL..."
        export REDIS_URL=$(echo "$REDIS_URL" | sed 's|^rediss://|redis://|' | sed 's|:6380|:6379|g')
        export REDISURL=$REDIS_URL
        export CACHE_REDIS_URL=$REDIS_URL
    fi
fi

# Ensure DATABASE_URL has sslmode=disable
if [ -n "$DATABASE_URL" ]; then
    if ! echo "$DATABASE_URL" | grep -q "sslmode=disable"; then
        if echo "$DATABASE_URL" | grep -q "?"; then
            export DATABASE_URL="${DATABASE_URL}&sslmode=disable"
        else
            export DATABASE_URL="${DATABASE_URL}?sslmode=disable"
        fi
    fi
    export DATABASEURL=$DATABASE_URL
fi

echo "Configuration loaded from environment"
echo "  NODE_ENV: ${NODE_ENV}"
echo "  PORT: ${PORT}"
echo "  WORKER_MODE: ${WORKER_MODE}"
echo ""

# Test database connection
echo "Testing database connection..."
if [ -n "$DATABASE_URL" ]; then
    DB_HOST=$(echo $DATABASE_URL | sed -n 's/.*@\([^:]*\):.*/\1/p')
    DB_PORT=$(echo $DATABASE_URL | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
    
    for i in {1..30}; do
        if pg_isready -h "$DB_HOST" -p "$DB_PORT" 2>/dev/null; then
            echo "✓ Database is ready!"
            break
        fi
        echo "  Waiting for database... attempt $i/30"
        sleep 2
    done
fi

# Run migrations
echo "Running database migrations..."
yarn medusa db:migrate || {
    echo "Migration failed, retrying..."
    sleep 5
    yarn medusa db:migrate || echo "Migration skipped"
}

# Seed data
echo "Seeding database..."
yarn run seed || echo "Seeding skipped"

echo "Starting Medusa server on port ${PORT}..."
exec yarn medusa start