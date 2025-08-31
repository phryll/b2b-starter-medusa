#!/bin/bash
set -e

echo "========================================="
echo "Medusa B2B Starter - Starting Up (NPM)"
echo "========================================="

# SSL environment variables
export PGSSLMODE=disable
export NODE_TLS_REJECT_UNAUTHORIZED=0
export MIKRO_ORM_SSL=false
export MIKRO_ORM_REJECT_UNAUTHORIZED=false

# Set defaults from environment
export NODE_ENV=${NODE_ENV:-production}
export PORT=${PORT:-3000}
export WORKER_MODE=${WORKER_MODE:-shared}

echo "Configuration loaded from environment"
echo "NODE_ENV: ${NODE_ENV}"
echo "PORT: ${PORT}"
echo "WORKER_MODE: ${WORKER_MODE}"
echo ""

# Create a simple health endpoint immediately
echo "Creating immediate health endpoint..."
cat > /tmp/health_response.txt << EOF
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 45
Connection: close

{"status":"starting","stage":"initializing"}
EOF

# Start temporary health server using netcat
start_temp_health_server() {
    while true; do
        cat /tmp/health_response.txt | nc -l -p 3000 -q 1 2>/dev/null || sleep 0.1
    done
}

start_temp_health_server &
TEMP_SERVER_PID=$!

# Function to cleanup temporary server
cleanup_temp_server() {
    if [ ! -z "$TEMP_SERVER_PID" ]; then
        kill $TEMP_SERVER_PID 2>/dev/null || true
        pkill -f "nc -l -p 3000" 2>/dev/null || true
    fi
}

# Ensure cleanup on exit
trap cleanup_temp_server EXIT

# Wait a moment for temp server to start
sleep 2

# Test database connection with better error handling
echo "Testing database connection..."
if [ -n "$DATABASE_URL" ]; then
    DB_HOST=$(echo $DATABASE_URL | sed -n 's/.*@\([^:]*\):.*/\1/p')
    DB_PORT=$(echo $DATABASE_URL | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
    
    echo "Connecting to database at $DB_HOST:$DB_PORT"
    
    for i in {1..60}; do
        if pg_isready -h "$DB_HOST" -p "$DB_PORT" 2>/dev/null; then
            echo "✓ Database is ready!"
            break
        fi
        echo "Waiting for database... attempt $i/60"
        sleep 3
    done
    
    # Test actual connection
    if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" 2>/dev/null; then
        echo "❌ Database connection failed after 3 minutes"
        exit 1
    fi
else
    echo "❌ DATABASE_URL not set"
    exit 1
fi

# Log DATABASE_URL for debugging
echo "DATABASE_URL at startup: $DATABASE_URL"

# Update health response
cat > /tmp/health_response.txt << EOF
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 42
Connection: close

{"status":"starting","stage":"migrating"}
EOF

# Run migrations with retry logic (using npm instead of yarn)
echo "Running database migrations..."
for i in {1..3}; do
    if npx medusa db:migrate; then
        echo "✓ Migrations completed successfully"
        break
    else
        echo "❌ Migration attempt $i failed"
        if [ $i -eq 3 ]; then
            echo "❌ All migration attempts failed"
            exit 1
        fi
        sleep 10
    fi
done

# Update health response
cat > /tmp/health_response.txt << EOF
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 38
Connection: close

{"status":"starting","stage":"seeding"}
EOF

# Seed data if needed (using npm instead of yarn)
echo "Seeding database..."
npm run seed 2>/dev/null || echo "⚠️  Seeding skipped or already done"

# Update health response
cat > /tmp/health_response.txt << EOF
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 37
Connection: close

{"status":"starting","stage":"starting"}
EOF

# Stop temporary server before starting real server
echo "Stopping temporary health server..."
cleanup_temp_server

# Give a moment for port to be released
sleep 2

# Start Medusa server (using npx instead of yarn)
echo "🚀 Starting Medusa server on port ${PORT}..."
exec npx medusa start