#!/bin/sh
set -e

# Env-Datei laden (Production)
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo "Using DATABASE_URL=$DATABASE_URL"
echo "Using REDIS_URL=$REDIS_URL"

# Force PostgreSQL to not use SSL - MULTIPLE LAYERS
export PGSSLMODE=disable
export PGSSLCERT=""
export PGSSLKEY=""
export PGSSLROOTCERT=""
export PGSSL=0
export NODE_TLS_REJECT_UNAUTHORIZED=0

# Additional PostgreSQL SSL disable
export PGSSLMODE=disable
export PGSSLCERT=""
export PGSSLKEY=""
export PGSSLROOTCERT=""

# Ensure DATABASE_URL has proper SSL disable parameters
if echo "$DATABASE_URL" | grep -q "sslmode=disable"; then
  echo "DATABASE_URL already has sslmode=disable"
else
  if echo "$DATABASE_URL" | grep -q "?"; then
    export DATABASE_URL="${DATABASE_URL}&sslmode=disable"
  else
    export DATABASE_URL="${DATABASE_URL}?sslmode=disable"
  fi
  echo "Updated DATABASE_URL=$DATABASE_URL"
fi

# Force additional SSL parameters in connection string
if echo "$DATABASE_URL" | grep -q "sslmode=disable"; then
  # Add more SSL disable parameters
  if echo "$DATABASE_URL" | grep -q "?"; then
    export DATABASE_URL="${DATABASE_URL}&ssl=false&rejectUnauthorized=false"
  else
    export DATABASE_URL="${DATABASE_URL}?ssl=false&rejectUnauthorized=false"
  fi
  echo "Enhanced DATABASE_URL=$DATABASE_URL"
fi

# Test database connection first
echo "Testing database connection..."
if node test-db-connection.js; then
  echo "✅ Database connection test passed"
else
  echo "❌ Database connection test failed - trying alternative approach..."
  
  # Try to force SSL disable in the connection string even more aggressively
  export DATABASE_URL=$(echo "$DATABASE_URL" | sed 's/sslmode=disable/sslmode=disable&ssl=false&rejectUnauthorized=false&sslmode=disable/g')
  echo "Super-enhanced DATABASE_URL=$DATABASE_URL"
  
  # Test again
  if node test-db-connection.js; then
    echo "✅ Database connection test passed with enhanced settings"
  else
    echo "❌ Database connection test still failed - exiting"
    exit 1
  fi
fi

# Skip database creation - just run migrations
echo "Running database migrations..."
yarn medusa db:migrate

# Seed initial data
echo "Seeding initial data..."
yarn run seed || true

# Start Medusa server
echo "Starting Medusa server..."
exec yarn medusa start
