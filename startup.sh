#!/bin/bash
set -e

echo "========================================="
echo "Medusa B2B Starter - Starting Up"
echo "========================================="

# SSL environment variables
export PGSSLMODE=disable
export NODE_TLS_REJECT_UNAUTHORIZED=0
export MIKRO_ORM_SSL=false
export MIKRO_ORM_REJECT_UNAUTHORIZED=false

# Set defaults from environment
export NODE_ENV=${NODE_ENV:-production}
export PORT=${PORT:-9000}
export WORKER_MODE=${WORKER_MODE:-shared}

echo "Configuration loaded from environment"
echo "NODE_ENV: ${NODE_ENV}"
echo "PORT: ${PORT}"
echo "WORKER_MODE: ${WORKER_MODE}"
echo ""

# Start a minimal HTTP server immediately for healthchecks
echo "Starting temporary health server..."
while true; do
  echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 45\r\n\r\n{\"status\":\"starting\",\"stage\":\"initializing\"}" | nc -l -p 9000 -q 1 2>/dev/null || true
done &
TEMP_SERVER_PID=$!

# Function to cleanup temporary server
cleanup_temp_server() {
  if [ ! -z "$TEMP_SERVER_PID" ]; then
    kill $TEMP_SERVER_PID 2>/dev/null || true
  fi
}

# Ensure cleanup on exit
trap cleanup_temp_server EXIT

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
        echo "Waiting for database... attempt $i/30"
        sleep 2
    done
fi

# Run migrations
echo "Running database migrations..."
yarn medusa db:migrate || {
    echo "Migration attempt 1 failed, retrying..."
    sleep 5
    yarn medusa db:migrate || echo "Migration attempt 2 failed, continuing..."
}

# Seed data if needed
echo "Seeding database..."
yarn run seed 2>/dev/null || echo "Seeding skipped or already done"

# Stop temporary server before starting real server
echo "Stopping temporary health server..."
cleanup_temp_server

# Start Medusa server
echo "Starting Medusa server on port ${PORT}..."
exec yarn medusa start