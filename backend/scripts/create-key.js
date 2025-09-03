#!/usr/bin/env node

const { execSync } = require('child_process');

async function createPublishableKey() {
  try {
    console.log("Checking for existing publishable keys...");
    
    // Use SQL query to check for existing keys
    const checkSql = `
      SELECT token FROM api_key 
      WHERE type = 'publishable' 
      AND deleted_at IS NULL 
      LIMIT 1;
    `;
    
    const existingKey = execSync(
      `PGPASSWORD="${process.env.DATABASE_URL.split(':')[2].split('@')[0]}" psql "${process.env.DATABASE_URL}" -t -c "${checkSql}"`,
      { encoding: 'utf8' }
    ).trim();

    if (existingKey && existingKey !== '') {
      console.log(`MEDUSA_PUBLISHABLE_KEY=${existingKey}`);
      return existingKey;
    }

    console.log("No existing key found, creating new one...");
    
    // Generate a new publishable key
    const crypto = require('crypto');
    const newToken = 'pk_' + crypto.randomBytes(32).toString('hex');
    
    // Insert into database
    const insertSql = `
      INSERT INTO api_key (id, token, type, created_by, created_at, updated_at)
      VALUES (
        '${crypto.randomUUID()}',
        '${newToken}',
        'publishable',
        'system',
        NOW(),
        NOW()
      );
    `;
    
    execSync(
      `PGPASSWORD="${process.env.DATABASE_URL.split(':')[2].split('@')[0]}" psql "${process.env.DATABASE_URL}" -c "${insertSql}"`,
      { encoding: 'utf8' }
    );

    console.log(`MEDUSA_PUBLISHABLE_KEY=${newToken}`);
    return newToken;

  } catch (error) {
    console.error("Failed to create publishable key:", error.message);
    // Generate a temporary key for development
    const crypto = require('crypto');
    const tempKey = 'pk_dev_' + crypto.randomBytes(16).toString('hex');
    console.log(`MEDUSA_PUBLISHABLE_KEY=${tempKey}`);
    return tempKey;
  }
}

createPublishableKey().catch(console.error);