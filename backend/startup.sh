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
export ADMIN_DISABLED=true

echo "NODE_ENV: ${NODE_ENV}"
echo "PORT: ${PORT}"
echo "WORKER_MODE: ${WORKER_MODE}"
echo "ADMIN_DISABLED: ${ADMIN_DISABLED}"

# Check if publishable key is provided
if [ -n "$MEDUSA_PUBLISHABLE_KEY" ] && [ "$MEDUSA_PUBLISHABLE_KEY" != "" ]; then
    echo "✓ Using pre-configured publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:8}..."
else
    echo "⚠️ No publishable key provided, will generate one"
fi

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
        set +e
        migration_output=$(yarn medusa db:migrate 2>&1)
        migration_exit_code=$?
        set -e
        
        if echo "$migration_output" | grep -E "(✓|completed|success|Migration.*executed)" >/dev/null || [ $migration_exit_code -eq 0 ]; then
            echo "✓ Migrations completed successfully"
            return 0
        else
            echo "❌ Migration attempt $attempt failed"
            echo "Migration output: $migration_output"
            if [ $attempt -lt 3 ]; then
                echo "Retrying in 15 seconds..."
                sleep 15
            fi
        fi
    done
    
    echo "❌ All migration attempts failed"
    return 1
}

create_publishable_key() {
    echo "Creating publishable key..."
    
    # Wait for backend to be fully ready
    for i in $(seq 1 30); do
        if curl -f http://localhost:${PORT}/health >/dev/null 2>&1; then
            break
        fi
        echo "Waiting for backend to be ready for key creation... $i/30"
        sleep 2
    done
    
    # Create publishable key via Medusa CLI or API
    if [ -z "$MEDUSA_PUBLISHABLE_KEY" ] || [ "$MEDUSA_PUBLISHABLE_KEY" = "" ]; then
        echo "Creating new publishable key..."
        
        # Option A: Use Medusa CLI to create publishable key
        set +e
        key_output=$(yarn medusa exec "
            const { PG_URL } = process.env;
            const publishableKeyService = container.resolve('publishableKeyService');
            publishableKeyService.create().then(key => {
                console.log('PUBLISHABLE_KEY:' + key.id);
                process.exit(0);
            }).catch(e => {
                console.error('Failed to create key:', e);
                process.exit(1);
            });
        " 2>/dev/null)
        set -e
        
        if echo "$key_output" | grep -q "PUBLISHABLE_KEY:"; then
            new_key=$(echo "$key_output" | grep "PUBLISHABLE_KEY:" | cut -d: -f2)
            export MEDUSA_PUBLISHABLE_KEY="$new_key"
            echo "✓ Created publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:8}..."
        else
            echo "⚠️ Failed to create publishable key, using fallback"
            fallback_key="pk_dev_$(openssl rand -hex 16)"
            export MEDUSA_PUBLISHABLE_KEY="$fallback_key"
        fi
    fi
}

ensure_publishable_key() {
    # Only generate key if not already provided
    if [ -z "$MEDUSA_PUBLISHABLE_KEY" ] || [ "$MEDUSA_PUBLISHABLE_KEY" = "" ]; then
        echo "Generating fallback publishable key..."
        fallback_key="pk_dev_$(openssl rand -hex 16)"
        export MEDUSA_PUBLISHABLE_KEY="$fallback_key"
        echo "✓ Fallback key created: ${MEDUSA_PUBLISHABLE_KEY:0:8}..."
    fi
}

seed_database() {
    echo "Seeding database..."
    set +e
    yarn seed 2>/dev/null
    set -e
    echo "⚠️ Seeding completed (errors ignored)"
}

check_port() {
    if nc -z localhost "$PORT" 2>/dev/null; then
        echo "❌ Port $PORT is already in use"
        exit 1
    fi
}

start_medusa() {
    echo "Starting Medusa server..."
    echo "Admin disabled - backend API only"
    echo "Publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:8}..."
    
    export MEDUSA_PUBLISHABLE_KEY
    
    set +e
    exec yarn start
}

main() {
    echo "Starting main initialization..."
    
    check_port
    
    if ! test_database; then
        echo "Database test failed, exiting"
        exit 1
    fi
    
    if ! test_redis; then
        echo "Redis test failed, exiting"
        exit 1
    fi

    if ! run_migrations; then
        echo "Migrations failed, exiting"
        exit 1
    fi
    
    seed_database
    
    # Start backend temporarily to create publishable key
    echo "Starting backend temporarily for key creation..."
    yarn start &
    BACKEND_PID=$!
    
    sleep 10
    create_publishable_key
    
    # Stop temporary backend
    kill $BACKEND_PID 2>/dev/null || true
    wait $BACKEND_PID 2>/dev/null || true
    sleep 5
    
    echo "All checks passed, starting Medusa..."
    start_medusa
}

error_handler() {
    echo "❌ Startup failed at line $1"
    echo "Last command exit code: $?"
    echo "Container will restart automatically..."
    exit 1
}

trap 'error_handler $LINENO' ERR

echo "Calling main function..."
main "$@"