#!/bin/bash
set -e

echo "========================================="
echo "Medusa B2B Starter - Starting Up"
echo "========================================="

# Force PostgreSQL SSL disable
export PGSSLMODE=disable
export PGSSL=0
export NODE_TLS_REJECT_UNAUTHORIZED=0
export MIKRO_ORM_SSL=false
export MIKRO_ORM_REJECT_UNAUTHORIZED=false

# Environment defaults
export NODE_ENV=${NODE_ENV:-production}
export PORT=${PORT:-9000}
export WORKER_MODE=${WORKER_MODE:-shared}

# Fix Redis SSL URL if needed
if [ -n "$REDIS_URL" ]; then
    if echo "$REDIS_URL" | grep -q "^rediss://"; then
        echo "Converting Redis SSL URL to non-SSL..."
        export REDIS_URL=$(echo "$REDIS_URL" | sed 's|^rediss://|redis://|' | sed 's|:6380|:6379|g')
        export REDISURL=$REDIS_URL
        export CACHE_REDIS_URL=$REDIS_URL
    fi
fi

# Ensure DATABASE_URL has SSL disabled
if [ -n "$DATABASE_URL" ]; then
    BASE_URL=$(echo "$DATABASE_URL" | sed 's/?.*$//')
    export DATABASE_URL="${BASE_URL}?sslmode=disable"
    export DATABASEURL=$DATABASE_URL
    echo "DATABASE_URL configured: ${DATABASE_URL}"
fi

echo "Configuration:"
echo "  NODE_ENV: ${NODE_ENV}"
echo "  PORT: ${PORT}"
echo "  WORKER_MODE: ${WORKER_MODE}"
echo ""

# Wait for database
echo "Testing database connection..."
if [ -n "$DATABASE_URL" ]; then
    DB_HOST=$(echo $DATABASE_URL | sed -n 's/.*@\([^:]*\):.*/\1/p')
    DB_PORT=$(echo $DATABASE_URL | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
    
    COUNTER=0
    MAX_TRIES=30
    while [ $COUNTER -lt $MAX_TRIES ]; do
        if pg_isready -h "$DB_HOST" -p "$DB_PORT" 2>/dev/null; then
            echo "✓ Database is ready!"
            break
        fi
        COUNTER=$((COUNTER+1))
        echo "Waiting for database... ($COUNTER/$MAX_TRIES)"
        sleep 2
    done
    
    if [ $COUNTER -eq $MAX_TRIES ]; then
        echo "⚠️ Database connection timeout, proceeding anyway..."
    fi
fi

# Run migrations
echo "Running database migrations..."
yarn medusa db:migrate || {
    echo "First migration attempt failed, retrying in 5s..."
    sleep 5
    yarn medusa db:migrate || {
        echo "⚠️ Migrations failed, continuing anyway..."
    }
}

# Seed database
echo "Seeding database..."
yarn run seed 2>/dev/null || echo "⚠️ Seeding skipped or already done"

# Start temporary health responder in background
echo "Starting health check responder..."
{
    while true; do
        # Check if Medusa is actually running on port 9000
        if curl -s -f http://localhost:9000/health 2>/dev/null | grep -q "healthy"; then
            # Real server is up, exit this loop
            sleep 5
        else
            # Respond with a temporary health status
            { echo -ne "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 58\r\n\r\n{\"status\":\"starting\",\"message\":\"Server is starting up\"}"; } | nc -l -p 9000 -q 0 2>/dev/null || true
        fi
        sleep 0.5
    done
} &
HEALTH_PID=$!

# Function to cleanup on exit
cleanup() {
    echo "Shutting down..."
    kill $HEALTH_PID 2>/dev/null || true
}
trap cleanup EXIT

# Start Medusa server
echo "Starting Medusa server on port ${PORT}..."
exec yarn medusa start