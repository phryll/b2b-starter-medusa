#!/bin/bash

# Find and replace zod/v3 imports
find ./src -name "*.ts" -type f -exec grep -l "from.*zod/v3" {} \; | while read file; do
  echo "Fixing $file"
  sed -i "s|from 'zod/v3'|from 'zod'|g" "$file"
  sed -i "s|from \"zod/v3\"|from \"zod\"|g" "$file"
done

# Find files using createOperatorMap
grep -r "createOperatorMap" ./src --include="*.ts" | cut -d: -f1 | sort -u | while read file; do
  echo "Checking $file for createOperatorMap usage"
  # Add import if not present
  if ! grep -q "@/utils/zod-operators" "$file"; then
    sed -i "1i import { createOperatorMap } from '@/utils/zod-operators';" "$file"
  fi
done