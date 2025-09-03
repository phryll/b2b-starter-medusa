#!/bin/sh
set -e

echo "Waiting for backend to be ready..."

BACKEND_URL=${NEXT_PUBLIC_MEDUSA_BACKEND_URL:-http://backend:9000}
MAX_RETRIES=180  # Increased timeout for key creation
RETRY_COUNT=0

BACKEND_HOST=$(echo $BACKEND_URL | sed 's|http://||' | cut -d: -f1)
BACKEND_PORT=$(echo $BACKEND_URL | sed 's|http://||' | cut -d: -f2)

if [ "$BACKEND_HOST" = "$BACKEND_PORT" ]; then
    BACKEND_PORT=9000
fi

echo "Checking backend readiness at $BACKEND_HOST:$BACKEND_PORT"

# Wait for backend health
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f -m 5 "$BACKEND_URL/health" >/dev/null 2>&1; then
        echo "✓ Backend health check passed"
        
        # Try to get publishable key from shared location
        if [ -f "/shared/.env.publishable" ]; then
            echo "✓ Loading publishable key from shared volume..."
            . /shared/.env.publishable
            export NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY="$MEDUSA_PUBLISHABLE_KEY"
            echo "✓ Publishable key loaded: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
            
            # Test store API with the key
            if curl -f -m 5 "$BACKEND_URL/store/regions" \
               -H "x-publishable-api-key: $MEDUSA_PUBLISHABLE_KEY" >/dev/null 2>&1; then
                echo "✓ Store API test successful with publishable key"
                break
            else
                echo "⚠️ Store API test failed, but continuing..."
                break
            fi
        else
            echo "⚠️ No publishable key file found, continuing without API calls..."
            break
        fi
    else
        echo "Backend not ready, waiting... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 3
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Backend did not become ready in time"
    echo "⚠️ Proceeding with build anyway (static mode)..."
fi

echo "✓ Starting storefront build..."