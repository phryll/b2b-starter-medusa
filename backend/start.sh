#!/bin/bash
set -e

echo "Starting Medusa application..."

# Wait for database
echo "Waiting for database..."
until pg_isready -h "$(echo $DATABASE_URL | sed 's/.*@\([^:]*\):.*/\1/')" -p "$(echo $DATABASE_URL | sed 's/.*:\([0-9]*\)\/.*/\1/')"; do
  echo "Database is unavailable - sleeping"
  sleep 2
done

echo "Database is ready!"

# Run migrations
echo "Running database migrations..."
npx medusa db:migrate

# Seed database if needed
echo "Seeding database..."
npm run seed || echo "Seeding skipped"

# Start the server
echo "Starting Medusa server..."
exec npm start