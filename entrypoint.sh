#!/bin/sh
set -e

# Env-Datei laden (Production)
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo "Using DATABASE_URL=$DATABASE_URL"
echo "Using REDIS_URL=$REDIS_URL"

# Force PostgreSQL to not use SSL
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

# Skip database creation - just run migrations
echo "Running database migrations..."
yarn medusa db:migrate

# Seed initial data
echo "Seeding initial data..."
yarn run seed || true

# Start Medusa server
echo "Starting Medusa server..."
exec yarn medusa start
