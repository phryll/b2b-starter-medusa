#!/bin/sh
set -e

echo "==============================================="
echo "Storefront: Waiting for backend before build"
echo "==============================================="

BACKEND_URL=${NEXT_PUBLIC_MEDUSA_BACKEND_URL:-http://backend:9000}
MAX_RETRIES=60
RETRY_COUNT=0

echo "Backend URL: $BACKEND_URL"
echo "Publishable Key: ${NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY:0:20}..."

# Wait for backend health AND publishable key validation
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Test 1: Basic health check
    if curl -f -m 5 "$BACKEND_URL/health" >/dev/null 2>&1; then
        echo "✓ Backend health check passed"
        
        # Test 2: Publishable key validation
        if [ -n "$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" ]; then
            if curl -f -m 10 "$BACKEND_URL/store/regions" \
               -H "x-publishable-api-key: $NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" >/dev/null 2>&1; then
                echo "✓ Publishable key validation successful"
                echo "✓ Backend is ready for storefront build"
                break
            else
                echo "⚠️ Publishable key validation failed, retrying..."
            fi
        else
            echo "⚠️ No publishable key available, retrying..."
        fi
    else
        echo "Backend not ready, waiting... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Backend not ready after timeout"
    echo "⚠️ Proceeding with build anyway (may use fallbacks)"
fi

echo "==============================================="
echo "Starting Next.js build with backend ready"
echo "==============================================="