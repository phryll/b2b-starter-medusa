#!/bin/sh
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

seed_database() {
    echo "Seeding database..."
    set +e
    yarn seed 2>/dev/null
    set -e
    echo "⚠️ Seeding completed (errors ignored)"
}

create_publishable_key() {
    echo "Creating publishable key..."
    
    # Start backend temporarily
    echo "Starting backend temporarily for key creation..."
    export MEDUSA_PUBLISHABLE_KEY="pk_temp_$(openssl rand -hex 8)"
    yarn start &
    BACKEND_PID=$!
    
    # Wait for backend to be ready
    echo "Waiting for backend to start..."
    for i in $(seq 1 60); do
        if curl -f http://localhost:${PORT}/health >/dev/null 2>&1; then
            echo "✓ Backend is ready for key creation"
            break
        fi
        echo "Waiting for backend... $i/60"
        sleep 3
    done
    
    # Create publishable key through Medusa's API
    echo "Creating publishable key via Medusa API..."
    set +e
    
    # Create admin user first if needed
    curl -X POST http://localhost:${PORT}/admin/users \
        -H "Content-Type: application/json" \
        -d '{"email":"admin@medusa.com","password":"supersecret"}' \
        >/dev/null 2>&1
    
    # Login to get auth token
    auth_response=$(curl -s -X POST http://localhost:${PORT}/admin/auth/session \
        -H "Content-Type: application/json" \
        -d '{"email":"admin@medusa.com","password":"supersecret"}' 2>/dev/null)
    
    # Create publishable key
    key_response=$(curl -s -X POST http://localhost:${PORT}/admin/publishable-api-keys \
        -H "Content-Type: application/json" \
        -H "Cookie: connect.sid=$(echo $auth_response | grep -o '"connect.sid":"[^"]*"' | cut -d'"' -f4)" \
        -d '{"title":"Default Store Key"}' 2>/dev/null)
    
    set -e
    
    # Extract the key from response
    if echo "$key_response" | grep -q '"id"'; then
        new_key=$(echo "$key_response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        export MEDUSA_PUBLISHABLE_KEY="$new_key"
        echo "✓ Created publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
    else
        echo "⚠️ API key creation failed, using CLI method..."
        
        # Fallback: Create via direct database insert
        new_key="pk_$(openssl rand -hex 16)"
        export MEDUSA_PUBLISHABLE_KEY="$new_key"
        
        # Insert directly into database
        PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
        -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
        -c "INSERT INTO publishable_api_key (id, title, created_at, updated_at) VALUES ('$new_key', 'Default Store Key', NOW(), NOW()) ON CONFLICT (id) DO NOTHING;" >/dev/null 2>&1
        
        echo "✓ Created publishable key via database: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
    fi
    
    # Stop temporary backend
    echo "Stopping temporary backend..."
    kill $BACKEND_PID 2>/dev/null || true
    wait $BACKEND_PID 2>/dev/null || true
    sleep 5
    
    # Write key to file for storefront
    echo "MEDUSA_PUBLISHABLE_KEY=$MEDUSA_PUBLISHABLE_KEY" > /app/.env.publishable
    echo "✓ Publishable key saved for storefront"
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
    echo "Publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
    
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
    
    # Create publishable key if not provided or if temp key
    if [ -z "$MEDUSA_PUBLISHABLE_KEY" ] || echo "$MEDUSA_PUBLISHABLE_KEY" | grep -q "pk_temp"; then
        create_publishable_key
    else
        echo "✓ Using provided publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
    fi
    
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