#!/bin/sh
set -e

# Env-Datei laden (Production)
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo "Using DATABASE_URL=$DATABASE_URL"
echo "Using REDIS_URL=$REDIS_URL"

# Try to create database (will fail if it exists, which is fine)
echo "Checking database connection..."
yarn medusa db:create 2>/dev/null || echo "Database may already exist, continuing..."

# Run migrations
echo "Running database migrations..."
yarn medusa db:migrate

# Seed initial data
echo "Seeding initial data..."
yarn run seed || true

# Start Medusa server
echo "Starting Medusa server..."
exec yarn medusa start
