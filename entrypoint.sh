#!/bin/sh
set -e

# Env-Datei laden (Production)
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo "Using DATABASE_URL=$DATABASE_URL"
echo "Using REDIS_URL=$REDIS_URL"

# Wait for database to be ready
echo "Waiting for database to be ready..."
until yarn medusa db:create 2>/dev/null; do
  echo "Database not ready, waiting..."
  sleep 2
done

# Run migrations
echo "Running database migrations..."
yarn medusa db:migrate

# Seed initial data
echo "Seeding initial data..."
yarn run seed || true

# Start Medusa server
echo "Starting Medusa server..."
exec yarn medusa start
