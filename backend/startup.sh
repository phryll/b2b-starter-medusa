#!/bin/sh
set -e

echo "========================================="
echo "Medusa B2B Starter - Starting Up (Yarn)"
echo "========================================="

# Environment setup
export PGSSLMODE=disable
export NODE_TLS_REJECT_UNAUTHORIZED=0
export MIKRO_ORM_SSL=false
export MIKRO_ORM_REJECT_UNAUTHORIZED=false
export NODE_ENV=${NODE_ENV:-production}
export PORT=${PORT:-9000}
export WORKER_MODE=${WORKER_MODE:-shared}

echo "Configuration:"
echo "- NODE_ENV: ${NODE_ENV}"
echo "- PORT: ${PORT}"
echo "- WORKER_MODE: ${WORKER_MODE}"

# Parse database connection details
parse_db_url() {
    if [ -z "$DATABASE_URL" ]; then
        echo "❌ DATABASE_URL not set"
        exit 1
    fi
    
    DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*://[^@]*@\([^:]*\):.*|\1|p')
    DB_PORT=$(echo "$DATABASE_URL" | sed -n 's|.*://[^@]*@[^:]*:\([0-9]*\)/.*|\1|p')
    
    if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ]; then
        echo "❌ Failed to parse DATABASE_URL"
        exit 1
    fi
    
    echo "Database: $DB_HOST:$DB_PORT"
}

# Check if port is already in use
check_port() {
    if nc -z localhost "$PORT" 2>/dev/null; then
        echo "❌ Port $PORT is already in use"
        exit 1
    fi
    echo "✓ Port $PORT is available"
}

# Test database connectivity
test_database() {
    parse_db_url
    echo "Testing database connection..."
    
    for i in $(seq 1 60); do
        if pg_isready -h "$DB_HOST" -p "$DB_PORT" -t 5 2>/dev/null; then
            echo "✓ Database connection successful"
            return 0
        fi
        echo "Waiting for database... attempt $i/60"
        sleep 5
    done
    
    echo "❌ Database not ready after 5 minutes"
    return 1
}

# Test Redis connectivity
test_redis() {
    REDIS_HOST=$(echo "$REDIS_URL" | sed -n 's|redis://\([^:]*\):.*|\1|p')
    REDIS_PORT=$(echo "$REDIS_URL" | sed -n 's|redis://[^:]*:\([0-9]*\).*|\1|p')
    
    if [ -z "$REDIS_HOST" ]; then
        REDIS_HOST=$(echo "$REDIS_URL" | sed -n 's|redis://\([^:]*\)|\1|p')
        REDIS_PORT="6379"
    fi
    
    echo "Testing Redis connection at $REDIS_HOST:$REDIS_PORT..."
    for i in $(seq 1 30); do
        if nc -z "$REDIS_HOST" "$REDIS_PORT" 2>/dev/null; then
            echo "✓ Redis connection successful"
            return 0
        fi
        echo "Waiting for Redis... attempt $i/30"
        sleep 2
    done
    
    echo "❌ Redis not ready after 1 minute"
    return 1
}

# Run database migrations
run_migrations() {
    echo "Running database migrations..."
    
    for attempt in $(seq 1 3); do
        echo "Migration attempt $attempt/3..."
        if yarn medusa db:migrate 2>&1; then
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

# Seed database with sample data
seed_database() {
    echo "Seeding database..."
    set +e  # Allow seeding to fail
    yarn seed 2>/dev/null || echo "⚠️ Seeding failed (continuing anyway)"
    set -e
}

# Create publishable key via direct database insertion
create_publishable_key() {
    echo "Creating publishable key via direct database insertion..."
    
    # Check if key already provided and exists in database
    if [ -n "$MEDUSA_PUBLISHABLE_KEY" ] && [ "$MEDUSA_PUBLISHABLE_KEY" != "" ]; then
        parse_db_url
        key_exists=$(PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
            psql -h "$DB_HOST" -p "$DB_PORT" \
            -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
            -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
            -t -c "SELECT COUNT(*) FROM publishable_api_key WHERE id = '$MEDUSA_PUBLISHABLE_KEY';" 2>/dev/null | xargs)
        
        if [ "$key_exists" = "1" ]; then
            echo "✓ Using existing publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
            echo "MEDUSA_PUBLISHABLE_KEY=$MEDUSA_PUBLISHABLE_KEY" > /app/.env.publishable
            return 0
        fi
    fi
    
    # Generate new publishable key
    new_key="pk_$(openssl rand -hex 24)"
    echo "Generated new key: ${new_key:0:20}..."
    
    # Insert directly into database
    parse_db_url
    echo "Inserting publishable key into database..."
    
    insert_result=$(PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
        psql -h "$DB_HOST" -p "$DB_PORT" \
        -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
        -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
        -c "INSERT INTO publishable_api_key (id, title, created_at, updated_at) VALUES ('$new_key', 'Auto-Generated Store Key', NOW(), NOW()) ON CONFLICT (id) DO NOTHING; SELECT '$new_key' as key;" 2>/dev/null)
    
    if echo "$insert_result" | grep -q "$new_key"; then
        export MEDUSA_PUBLISHABLE_KEY="$new_key"
        echo "MEDUSA_PUBLISHABLE_KEY=$new_key" > /app/.env.publishable
        echo "✓ Created publishable key via database: ${new_key:0:20}..."
        
        # Verify the key exists
        verification=$(PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
            psql -h "$DB_HOST" -p "$DB_PORT" \
            -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
            -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
            -t -c "SELECT COUNT(*) FROM publishable_api_key WHERE id = '$new_key';" 2>/dev/null | xargs)
        
        if [ "$verification" = "1" ]; then
            echo "✓ Key verified in database"
            return 0
        else
            echo "❌ Key verification failed"
            return 1
        fi
    else
        echo "❌ Failed to insert publishable key"
        return 1
    fi
}

# Start production server
start_production_server() {
    echo "Starting production Medusa server..."
    echo "- Admin: DISABLED"
    echo "- Port: $PORT"
    echo "- Publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
    
    # Ensure admin is disabled for production
    export ADMIN_DISABLED=true
    unset MEDUSA_SETUP_PHASE
    
    exec yarn start
}

# Main execution flow
main() {
    echo "Starting Medusa B2B initialization..."
    
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
    
    # Create publishable key via direct database insertion
    if ! create_publishable_key; then
        echo "❌ Failed to create publishable key"
        exit 1
    fi
    
    echo "All checks passed, starting Medusa..."
    start_production_server
}

# Error handling
error_handler() {
    echo "❌ Startup failed at line $1"
    echo "Exit code: $?"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Execute main function
main "$@"