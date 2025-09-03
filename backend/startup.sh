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

# Create publishable key using admin API
create_publishable_key() {
    echo "Creating publishable key..."
    
    # Check if key already exists and is valid
    if [ -n "$MEDUSA_PUBLISHABLE_KEY" ] && [ "$MEDUSA_PUBLISHABLE_KEY" != "" ]; then
        # Verify key exists in database
        parse_db_url
        key_exists=$(PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
            psql -h "$DB_HOST" -p "$DB_PORT" \
            -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
            -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
            -t -c "SELECT COUNT(*) FROM publishable_api_key WHERE id = '$MEDUSA_PUBLISHABLE_KEY';" 2>/dev/null | xargs)
        
        if [ "$key_exists" = "1" ]; then
            echo "✓ Using existing publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
            return 0
        else
            echo "⚠️ Provided key not found in database, creating new one..."
        fi
    fi
    
    echo "Starting temporary admin server for key creation..."
    
    # Enable admin and start server in background
    export MEDUSA_SETUP_PHASE=true
    export ADMIN_DISABLED=false
    
    # Start Medusa with admin enabled
    yarn start &
    SERVER_PID=$!
    
    # Wait for server to be ready
    echo "Waiting for admin server to start..."
    for i in $(seq 1 60); do
        if curl -f http://localhost:${PORT}/health >/dev/null 2>&1; then
            echo "✓ Server is ready"
            break
        fi
        echo "Waiting for server... $i/60"
        sleep 3
    done
    
    # Create admin user
    echo "Creating admin user..."
    curl -X POST http://localhost:${PORT}/admin/users \
        -H "Content-Type: application/json" \
        -d '{
            "email": "admin@medusa.com",
            "password": "supersecret123",
            "first_name": "Admin",
            "last_name": "User"
        }' >/dev/null 2>&1 || echo "Admin user might already exist"
    
    # Authenticate admin user
    echo "Authenticating admin user..."
    auth_response=$(curl -s -X POST http://localhost:${PORT}/admin/auth/session \
        -H "Content-Type: application/json" \
        -d '{"email": "admin@medusa.com", "password": "supersecret123"}' \
        -c /tmp/cookies.txt)
    
    if echo "$auth_response" | grep -q '"user"'; then
        echo "✓ Admin authentication successful"
        
        # Create publishable API key
        echo "Creating publishable API key..."
        key_response=$(curl -s -X POST http://localhost:${PORT}/admin/publishable-api-keys \
            -H "Content-Type: application/json" \
            -b /tmp/cookies.txt \
            -d '{"title": "Default Store Key"}')
        
        if echo "$key_response" | grep -q '"id"'; then
            new_key=$(echo "$key_response" | grep -o '"id":"pk_[^"]*"' | cut -d'"' -f4)
            echo "✓ Created publishable key: ${new_key:0:20}..."
            export MEDUSA_PUBLISHABLE_KEY="$new_key"
            
            # Save key to environment file
            echo "MEDUSA_PUBLISHABLE_KEY=$new_key" > /app/.env.publishable
            echo "✓ Publishable key saved"
        else
            echo "❌ Failed to create publishable key via API"
            echo "Response: $key_response"
            
            # Fallback: direct database insert
            echo "Attempting direct database insertion..."
            new_key="pk_$(openssl rand -hex 24)"
            parse_db_url
            
            PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
            psql -h "$DB_HOST" -p "$DB_PORT" \
            -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
            -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
            -c "INSERT INTO publishable_api_key (id, title, created_at, updated_at) VALUES ('$new_key', 'Default Store Key', NOW(), NOW()) ON CONFLICT (id) DO NOTHING;" 2>/dev/null
            
            export MEDUSA_PUBLISHABLE_KEY="$new_key"
            echo "MEDUSA_PUBLISHABLE_KEY=$new_key" > /app/.env.publishable
            echo "✓ Fallback key created: ${new_key:0:20}..."
        fi
    else
        echo "❌ Admin authentication failed"
        echo "Response: $auth_response"
        return 1
    fi
    
    # Stop temporary server
    echo "Stopping temporary admin server..."
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
    sleep 3
    
    # Cleanup
    rm -f /tmp/cookies.txt
    unset MEDUSA_SETUP_PHASE
    export ADMIN_DISABLED=true
    
    echo "✓ Publishable key creation completed"
}

# Start production server
start_production_server() {
    echo "Starting production Medusa server..."
    echo "- Admin: DISABLED"
    echo "- Port: $PORT"
    echo "- Publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
    
    # Disable admin for production
    export ADMIN_DISABLED=true
    unset MEDUSA_SETUP_PHASE
    
    exec yarn start
}

# Main execution flow
main() {
    echo "Starting Medusa B2B initialization..."
    
    # Basic connectivity tests
    test_database || exit 1
    test_redis || exit 1
    
    # Database setup
    run_migrations || exit 1
    seed_database
    
    # Create publishable key with admin enabled
    create_publishable_key || exit 1
    
    # Start production server with admin disabled
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