#!/bin/sh
set -e

echo "Waiting for backend to be ready..."

BACKEND_URL=${NEXT_PUBLIC_MEDUSA_BACKEND_URL:-http://backend:9000}
MAX_RETRIES=120
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
        
        # Check for publishable key in multiple locations
        publishable_key=""
        
        # Method 1: Check environment variable
        if [ -n "$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" ]; then
            publishable_key="$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY"
            echo "✓ Found publishable key in environment: ${publishable_key:0:20}..."
        # Method 2: Check shared volume file
        elif [ -f "/shared/.env.publishable" ]; then
            echo "✓ Loading publishable key from shared volume..."
            . /shared/.env.publishable
            if [ -n "$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY" ]; then
                publishable_key="$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY"
                export NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY="$publishable_key"
                echo "✓ Publishable key loaded from shared volume: ${publishable_key:0:20}..."
            elif [ -n "$MEDUSA_PUBLISHABLE_KEY" ]; then
                publishable_key="$MEDUSA_PUBLISHABLE_KEY"
                export NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY="$publishable_key"
                echo "✓ Publishable key loaded from shared volume: ${publishable_key:0:20}..."
            fi
        fi
        
        # Test API with publishable key if available
        if [ -n "$publishable_key" ]; then
            echo "Testing store API with publishable key..."
            if curl -f -m 10 "$BACKEND_URL/store/regions" \
               -H "x-publishable-api-key: $publishable_key" >/dev/null 2>&1; then
                echo "✓ Store API test successful with publishable key"
                break
            else
                echo "⚠️ Store API test failed with key, but continuing..."
                # Still break because backend is responsive
                break
            fi
        else
            echo "⚠️ No publishable key found, continuing without API verification..."
            break
        fi
    else
        echo "Backend not ready, waiting... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 3
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Backend failed to become ready in time"
    echo "⚠️ Proceeding with build anyway..."
fi

echo "✓ Starting storefront build with key: ${NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY:0:20:-none}..."