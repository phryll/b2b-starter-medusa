#!/bin/sh
set -e

# Env-Datei laden (Production)
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo "Using DATABASE_URL=$DATABASE_URL"

# Create DB if it doesn’t exist
yarn medusa db:create || true

# Run migrations
yarn medusa db:migrate

# Seed initial data
yarn run seed || true

# Start Medusa server
yarn medusa start
