#!/bin/sh
set -e

# Wait until DB is ready (optional, if using something like pg_isready)
echo "Waiting for database..."
# Example: while ! pg_isready -h $DB_HOST -p $DB_PORT; do sleep 1; done

# Create DB if it doesn’t exist
yarn medusa db:create || true

# Run migrations
yarn medusa db:migrate

# Seed initial data
yarn run seed || true

# Start Medusa server
yarn medusa start
