#!/bin/sh
set -e

echo "Waiting for backend to be ready..."

BACKEND_URL=${NEXT_PUBLIC_MEDUSA_BACKEND_URL:-http://backend:9000}
MAX_RETRIES=120  # Increased for key creation
RETRY_COUNT=0

BACKEND_HOST=$(echo $BACKEND_URL | sed 's|http://||' | cut -d: -f1)
BACKEND_PORT=$(echo $BACKEND_URL | sed 's|http://||' | cut -d: -f2)

if [ "$BACKEND_HOST" = "$BACKEND_PORT" ]; then
    BACKEND_PORT=9000
fi

echo "Checking backend at $BACKEND_HOST:$BACKEND_PORT"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if nc -z "$BACKEND_HOST" "$BACKEND_PORT"; then
        echo "Backend is responding on port $BACKEND_PORT"
        
        # Check health endpoint
        if curl -f "$BACKEND_URL/health" >/dev/null 2>&1; then
            echo "✓ Backend health check passed"
            
            # Check for publishable key file
            if [ -f "/app/.env.publishable" ]; then
                echo "✓ Found publishable key file, loading..."
                . /app/.env.publishable
                export NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY="$MEDUSA_PUBLISHABLE_KEY"
                echo "✓ Publishable key loaded: ${MEDUSA_PUBLISHABLE_KEY:0:20}..."
            fi
            
            # Test API with publishable key
            if [ -n "$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" ]; then
                if curl -f "$BACKEND_URL/store/products?limit=1" \
                   -H "x-publishable-api-key: $NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" >/dev/null 2>&1; then
                    echo "✓ API test with publishable key successful"
                    break
                else
                    echo "API test failed, but continuing..."
                    break
                fi
            else
                echo "⚠️ No publishable key available, continuing anyway..."
                break
            fi
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
    echo "⚠️ Continuing with storefront build anyway..."
fi

echo "✓ Backend is ready, starting storefront build..."