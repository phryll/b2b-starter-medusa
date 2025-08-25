#!/bin/sh
set -e

# Env-Datei laden (Production)
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo "Using DATABASE_URL=$DATABASE_URL"
echo "Using REDIS_URL=$REDIS_URL"

# Skip database creation - just run migrations
echo "Running database migrations..."
yarn medusa db:migrate

# Seed initial data
echo "Seeding initial data..."
yarn run seed || true

# Start Medusa server
echo "Starting Medusa server..."
exec yarn medusa start
