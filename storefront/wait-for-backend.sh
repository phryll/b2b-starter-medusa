#!/bin/bash
set -e

echo "Waiting for backend to be ready..."

BACKEND_URL=${NEXT_PUBLIC_MEDUSA_BACKEND_URL:-http://backend:9000}
MAX_RETRIES=60
RETRY_COUNT=0

# Extract host and port from URL
BACKEND_HOST=$(echo $BACKEND_URL | sed 's|http://||' | cut -d: -f1)
BACKEND_PORT=$(echo $BACKEND_URL | sed 's|http://||' | cut -d: -f2)

# If no port specified, use default 9000
if [ "$BACKEND_HOST" = "$BACKEND_PORT" ]; then
    BACKEND_PORT=9000
fi

echo "Checking backend at $BACKEND_HOST:$BACKEND_PORT"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if nc -z "$BACKEND_HOST" "$BACKEND_PORT"; then
        echo "Backend is responding on port $BACKEND_PORT"
        
        # Additional health check via HTTP
        if curl -f "$BACKEND_URL/health" >/dev/null 2>&1; then
            echo "✓ Backend health check passed"
            break
        else
            echo "Backend port open but health check failed, retrying..."
        fi
    else
        echo "Backend not ready, waiting... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Backend failed to start after $((MAX_RETRIES * 5)) seconds"
    exit 1
fi

echo "✓ Backend is ready, starting storefront build..."