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

verify_admin_build() {
    echo "Verifying admin build..."
    if [ "$ADMIN_DISABLED" = "true" ]; then
        echo "✓ Admin disabled, skipping verification"
        return 0
    fi
    
    if [ -f ".medusa/admin/index.html" ]; then
        echo "✓ Admin build found and verified"
        return 0
    else
        echo "❌ Admin build missing, attempting emergency rebuild..."
        return 1
    fi
}

emergency_admin_rebuild() {
    echo "Attempting emergency admin rebuild..."
    
    # Try to rebuild admin only
    if NODE_OPTIONS="--max-old-space-size=2048" yarn medusa build --admin-only 2>&1; then
        if [ -f ".medusa/admin/index.html" ]; then
            echo "✓ Emergency admin rebuild successful"
            return 0
        fi
    fi
    
    echo "❌ Emergency admin rebuild failed"
    echo "Setting ADMIN_DISABLED=true to continue without admin UI"
    export ADMIN_DISABLED=true
    return 1
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
        if yarn medusa db:migrate 2>&1 | grep -E "(✓|completed|success|Migration.*executed)" >/dev/null; then
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
    echo "Admin status: ${ADMIN_DISABLED:-false}"
    exec yarn start
}

main() {
    check_port
    
    if ! test_database; then
        exit 1
    fi
    
    if ! test_redis; then
        exit 1
    fi
    
    # Verify admin build exists (if admin is enabled)
    if ! verify_admin_build; then
        emergency_admin_rebuild || true  # Continue even if rebuild fails
    fi

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