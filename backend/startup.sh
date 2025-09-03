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
    
    # Check if we already have regions/countries to avoid conflicts
    parse_db_url
    
    existing_regions=$(PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
        psql -h "$DB_HOST" -p "$DB_PORT" \
        -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
        -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
        -t -c "SELECT COUNT(*) FROM region;" 2>/dev/null | xargs || echo "0")
    
    if [ "$existing_regions" -gt "0" ]; then
        echo "⚠️ Database already has $existing_regions regions, skipping seeding to avoid conflicts"
        return 0
    fi
    
    # Only seed if database is empty
    echo "Database appears empty, running seeding..."
    set +e  # Allow seeding to fail without stopping deployment
    
    seed_output=$(yarn seed 2>&1)
    seed_exit_code=$?
    
    if [ $seed_exit_code -eq 0 ]; then
        echo "✓ Seeding completed successfully"
    else
        echo "⚠️ Seeding failed but continuing deployment"
        echo "Seed output: $seed_output"
        
        # Check if the failure was due to existing data (not critical)
        if echo "$seed_output" | grep -q "already assigned to a region"; then
            echo "⚠️ Seeding failed due to existing data - this is normal for redeployments"
        else
            echo "⚠️ Seeding failed for other reasons - check logs if store has no products"
        fi
    fi
    
    set -e
}

validate_database_schema() {
    echo "Validating database schema..."
    parse_db_url
    
    # Check for critical tables
    critical_tables="region store currency product publishable_api_key"
    
    for table in $critical_tables; do
        table_exists=$(PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
            psql -h "$DB_HOST" -p "$DB_PORT" \
            -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
            -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
            -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '$table');" 2>/dev/null | xargs)
        
        if [ "$table_exists" = "t" ]; then
            echo "✓ Table '$table' exists"
        else
            echo "⚠️ Table '$table' missing - may cause issues"
        fi
    done
}

# Create publishable key via direct database insertion
create_publishable_key() {
    echo "Creating publishable key via direct database insertion..."
    
    # Check if key already provided via environment and exists in database
    if [ -n "$MEDUSA_PUBLISHABLE_KEY" ] && [ "$MEDUSA_PUBLISHABLE_KEY" != "" ]; then
        echo "Checking provided publishable key: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
        parse_db_url
        
        # Check if publishable_api_key table exists
        table_exists=$(PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
            psql -h "$DB_HOST" -p "$DB_PORT" \
            -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
            -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
            -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'publishable_api_key');" 2>/dev/null | xargs)
        
        if [ "$table_exists" = "t" ]; then
            key_exists=$(PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
                psql -h "$DB_HOST" -p "$DB_PORT" \
                -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
                -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
                -t -c "SELECT COUNT(*) FROM publishable_api_key WHERE id = '$MEDUSA_PUBLISHABLE_KEY';" 2>/dev/null | xargs)
            
            if [ "$key_exists" = "1" ]; then
                echo "✓ Using existing publishable key from environment: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
                
                # Save key to both local and shared locations
                echo "MEDUSA_PUBLISHABLE_KEY=$MEDUSA_PUBLISHABLE_KEY" > /app/.env.publishable
                echo "NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=$MEDUSA_PUBLISHABLE_KEY" >> /app/.env.publishable
                
                # Copy to shared volume if mounted
                if [ -d "/shared" ]; then
                    cp /app/.env.publishable /shared/
                    echo "✓ Publishable key copied to shared volume"
                fi
                
                return 0
            else
                echo "⚠️ Provided key not found in database, will create new one"
            fi
        else
            echo "⚠️ publishable_api_key table does not exist yet"
        fi
    fi
    
    # Generate new publishable key with multiple fallback methods
    if command -v openssl >/dev/null 2>&1; then
        # Method 1: OpenSSL (preferred)
        random_hex=$(openssl rand -hex 24)
        new_key="pk_${random_hex}"
        echo "Generated key using OpenSSL: ${new_key:0:20}..."
    elif [ -f /dev/urandom ]; then
        # Method 2: /dev/urandom fallback
        random_hex=$(dd if=/dev/urandom bs=24 count=1 2>/dev/null | xxd -p -c 24)
        new_key="pk_${random_hex}"
        echo "Generated key using /dev/urandom: ${new_key:0:20}..."
    else
        # Method 3: Date/PID based fallback (less secure but functional)
        timestamp=$(date +%s)
        pid=$$
        random_suffix=$(echo "${timestamp}${pid}" | sha256sum | cut -c1-48)
        new_key="pk_${random_suffix}"
        echo "Generated key using timestamp fallback: ${new_key:0:20}..."
    fi
    
    # Ensure publishable_api_key table exists
    parse_db_url
    echo "Ensuring publishable_api_key table exists..."
    
    # Create table if it doesn't exist (matching Medusa's schema)
    table_creation=$(PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
        psql -h "$DB_HOST" -p "$DB_PORT" \
        -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
        -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
        -c "CREATE TABLE IF NOT EXISTS publishable_api_key (
            id text PRIMARY KEY,
            title text,
            created_at timestamptz DEFAULT NOW(),
            updated_at timestamptz DEFAULT NOW(),
            deleted_at timestamptz,
            created_by text,
            revoked_by text,
            revoked_at timestamptz
        );" 2>&1)
    
    if echo "$table_creation" | grep -q "ERROR"; then
        echo "❌ Failed to create publishable_api_key table: $table_creation"
        return 1
    else
        echo "✓ publishable_api_key table ready"
    fi
    
    # Insert the new key
    echo "Inserting publishable key into database..."
    
    insert_result=$(PGPASSWORD="$(echo "$DATABASE_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')" \
        psql -h "$DB_HOST" -p "$DB_PORT" \
        -U "$(echo "$DATABASE_URL" | sed -n 's|.*://\([^:]*\):.*|\1|p')" \
        -d "$(echo "$DATABASE_URL" | sed -n 's|.*/\([^?]*\).*|\1|p')" \
        -c "INSERT INTO publishable_api_key (id, title, created_at, updated_at) 
            VALUES ('$new_key', 'Auto-Generated Store Key', NOW(), NOW()) 
            ON CONFLICT (id) DO NOTHING 
            RETURNING id;" 2>&1)
    
    if echo "$insert_result" | grep -q "$new_key" || echo "$insert_result" | grep -q "INSERT 0 1"; then
        export MEDUSA_PUBLISHABLE_KEY="$new_key"
        
        # Save key to local file (both backend and frontend formats)
        echo "MEDUSA_PUBLISHABLE_KEY=$new_key" > /app/.env.publishable
        echo "NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=$new_key" >> /app/.env.publishable
        
        # Copy to shared volume if mounted
        if [ -d "/shared" ]; then
            cp /app/.env.publishable /shared/
            echo "✓ Publishable key saved to shared volume"
        fi
        
        echo "✓ Created publishable key via database: ${new_key:0:20}..."
        echo "📋 IMPORTANT: Save this key in Dokploy environment variables:"
        echo "    Variable: MEDUSA_PUBLISHABLE_KEY"
        echo "    Value: $new_key"
        
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
        echo "❌ Failed to insert publishable key: $insert_result"
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
    
    # Validate schema after migrations
    validate_database_schema
    
    # Seed database (with conflict handling)
    seed_database
    
    # Create publishable key (with multiple fallbacks)
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