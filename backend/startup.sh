#!/bin/bash
set -e

echo "========================================="
echo "Medusa B2B Starter - Starting Up (Yarn)"
echo "========================================="

export PGSSLMODE=disable
export NODE_TLS_REJECT_UNAUTHORIZED=0
export MIKRO_ORM_SSL=false
export MIKRO_ORM_REJECT_UNAUTHORIZED=false

export NODE_ENV=${NODE_ENV:-production}
export PORT=${PORT:-9000}
export WORKER_MODE=${WORKER_MODE:-shared}

echo "NODE_ENV: ${NODE_ENV}"
echo "PORT: ${PORT}"
echo "WORKER_MODE: ${WORKER_MODE}"
echo ""

parse_db_url() {
    if [ -z "$DATABASE_URL" ]; then
        echo "❌ DATABASE_URL not set"
        exit 1
    fi
    
    DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*://[^@]*@\([^:]*\):.*|\1|p')
    DB_PORT=$(echo "$DATABASE_URL" | sed -n 's|.*://[^@]*@[^:]*:\([0-9]*\)/.*|\1|p')
    
    if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ]; then
        echo "❌ Failed to parse DATABASE_URL: $DATABASE_URL"
        exit 1
    fi
    
    echo "Parsed database: $DB_HOST:$DB_PORT"
}

parse_redis_url() {
    if [ -z "$REDIS_URL" ]; then
        echo "❌ REDIS_URL not set"
        exit 1
    fi
    
    REDIS_HOST=$(echo "$REDIS_URL" | sed -n 's|redis://\([^:]*\):.*|\1|p')
    REDIS_PORT=$(echo "$REDIS_URL" | sed -n 's|redis://[^:]*:\([0-9]*\).*|\1|p')
    
    if [ -z "$REDIS_HOST" ]; then
        REDIS_HOST=$(echo "$REDIS_URL" | sed -n 's|redis://\([^:]*\)|\1|p')
        REDIS_PORT="6379"
    fi
    
    if [ -z "$REDIS_HOST" ]; then
        echo "❌ Failed to parse REDIS_URL: $REDIS_URL"
        exit 1
    fi
    
    echo "Parsed Redis: $REDIS_HOST:$REDIS_PORT"
}

create_health_endpoint() {
    mkdir -p /tmp/health
    cat > /tmp/health/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Starting</title></head>
<body>
<h1>Medusa Backend Starting</h1>
<p>Status: Initializing...</p>
<script>setTimeout(function(){location.reload()}, 5000);</script>
</body>
</html>
EOF
}

build_admin_if_needed() {
    if [ ! -d ".medusa/admin" ] || [ -z "$(ls -A .medusa/admin 2>/dev/null)" ]; then
        echo "Admin UI not found, building now (this will take 5-10 minutes on first start)..."
        NODE_OPTIONS="--max-old-space-size=2048" yarn build:admin || echo "⚠️ Admin build failed, continuing without admin UI"
    else
        echo "✓ Admin UI already built"
    fi
}

test_database() {
    parse_db_url
    
    echo "Testing database connection..."
    for i in $(seq 1 60); do
        if pg_isready -h "$DB_HOST" -p "$DB_PORT" -t 5 2>/dev/null; then
            echo "✓ Database connection test passed"
            if PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
               psql -h "$DB_HOST" -p "$DB_PORT" -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
               -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" -c "SELECT 1;" >/dev/null 2>&1; then
                echo "✓ Database accepts connections"
                return 0
            else
                echo "Database port open but not accepting connections yet..."
            fi
        else
            echo "Waiting for database... attempt $i/60 ($(date))"
        fi
        sleep 5
    done
    
    echo "❌ Database not ready after 5 minutes"
    return 1
}

test_redis() {
    parse_redis_url
    
    echo "Testing Redis connection..."
    for i in $(seq 1 30); do
        if nc -z "$REDIS_HOST" "$REDIS_PORT" 2>/dev/null; then
            echo "✓ Redis connection test passed"
            return 0
        fi
        echo "Waiting for Redis... attempt $i/30"
        sleep 2
    done
    
    echo "❌ Redis not ready after 1 minute"
    return 1
}

run_migrations() {
    echo "Running database migrations..."
    
    for attempt in $(seq 1 3); do
        echo "Migration attempt $attempt/3..."
        # Ignore CLI errors but check if migrations actually run
        if yarn medusa db:migrate 2>&1 | grep -E "(✓|completed|success)" >/dev/null; then
            echo "✓ Migrations completed successfully"
            return 0
        else
            echo "❌ Migration attempt $attempt failed"
            if [ $attempt -lt 3 ]; then
                echo "Retrying in 15 seconds..."
                sleep 15
            fi
        fi
    done
    
    echo "❌ All migration attempts failed"
    return 1
}

seed_database() {
    echo "Seeding database..."
    # Ignore CLI errors but attempt seeding
    yarn seed 2>/dev/null || echo "⚠️ Seeding skipped or failed (this may be normal)"
}

check_port() {
    if nc -z localhost "$PORT" 2>/dev/null; then
        echo "❌ Port $PORT is already in use"
        exit 1
    fi
}

start_medusa() {
    echo "Starting Medusa server..."
    # Use node directly to bypass CLI issues
    if [ -f ".medusa/server/src/index.js" ]; then
        echo "Starting from compiled server..."
        exec node .medusa/server/src/index.js
    else
        echo "Starting with yarn (may show CLI warnings)..."
        exec yarn start
    fi
}

main() {
    create_health_endpoint
    check_port
    
    if ! test_database; then
        exit 1
    fi
    
    if ! test_redis; then
        exit 1
    fi
    
    build_admin_if_needed

    if ! run_migrations; then
        exit 1
    fi
    
    seed_database
    
    start_medusa
}

error_handler() {
    echo "❌ Startup failed at line $1"
    echo "Container will restart automatically..."
    exit 1
}

trap 'error_handler $LINENO' ERR

main "$@"