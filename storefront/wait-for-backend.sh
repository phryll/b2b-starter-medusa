#!/bin/sh
until curl -f http://backend:3000/health 2>/dev/null; do
  echo "Waiting for backend to be ready..."
  sleep 5
done
echo "Backend is ready!"