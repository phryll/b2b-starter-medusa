#!/bin/sh
set -e

echo "Waiting for backend to be ready..."

BACKEND_URL=${NEXT_PUBLIC_MEDUSA_BACKEND_URL:-http://backend:9000}
MAX_RETRIES=60
RETRY_COUNT=0

echo "Checking backend readiness at $BACKEND_URL"

# Wait for backend health check
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f -m 5 "$BACKEND_URL/health" >/dev/null 2>&1; then
        echo "✓ Backend health check passed"
        
        # SIMPLIFIED: Only check environment variable (no file operations)
        if [ -n "$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" ]; then
            key_display=$(echo "$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" | cut -c1-20)
            echo "✓ Found publishable key: ${key_display}..."
            
            # Test store API with publishable key
            echo "Testing store API with publishable key..."
            if curl -f -m 10 "$BACKEND_URL/store/regions" \
               -H "x-publishable-api-key: $NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" >/dev/null 2>&1; then
                echo "✓ Store API test successful"
                break
            else
                echo "⚠️ Store API test failed, but backend is responsive"
                echo "⚠️ This may indicate the key is not yet in the database"
                break
            fi
        else
            echo "⚠️ No publishable key found in environment"
            echo "⚠️ Build will use fallback mechanisms"
            break
        fi
    else
        echo "Backend not ready, waiting... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 5
done

# Final status
if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Backend failed to become ready within timeout"
    echo "⚠️ Proceeding with build anyway (will use fallbacks)"
else
    echo "✓ Backend is ready"
fi

# Display final status
if [ -n "$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" ]; then
    key_display=$(echo "$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" | cut -c1-20)
    echo "✓ Starting storefront build with key: ${key_display}..."
else
    echo "⚠️ Starting storefront build without publishable key"
    echo "⚠️ Build will use safe fallback mechanisms"
fi

echo "=== Storefront build starting ==="