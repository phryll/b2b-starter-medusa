const { Client } = require('pg');

async function testConnection() {
  console.log('Testing database connection...');
  
  const connectionString = process.env.DATABASE_URL;
  console.log('Connection string:', connectionString);
  
  const client = new Client({
    connectionString: connectionString,
    ssl: false,
    rejectUnauthorized: false
  });
  
  try {
    await client.connect();
    console.log('✅ Database connection successful! SSL is disabled.');
    
    const result = await client.query('SELECT version()');
    console.log('Database version:', result.rows[0].version);
    
    await client.end();
    return true;
  } catch (error) {
    console.error('❌ Database connection failed:', error.message);
    return false;
  }
}

// Run the test
testConnection().then(success => {
  if (success) {
    console.log('Database connection test passed');
    process.exit(0);
  } else {
    console.log('Database connection test failed');
    process.exit(1);
  }
}); 