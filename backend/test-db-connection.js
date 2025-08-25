const { Client } = require('pg');

async function testConnection() {
  console.log('Testing database connection...');
  console.log('Environment variables:');
  console.log('- PGSSLMODE:', process.env.PGSSLMODE);
  console.log('- PGSSL:', process.env.PGSSL);
  console.log('- NODE_TLS_REJECT_UNAUTHORIZED:', process.env.NODE_TLS_REJECT_UNAUTHORIZED);
  
  const connectionString = process.env.DATABASE_URL;
  console.log('Connection string:', connectionString);
  
  // Parse connection string to show components
  try {
    const url = new URL(connectionString);
    console.log('Connection components:');
    console.log('- Protocol:', url.protocol);
    console.log('- Host:', url.hostname);
    console.log('- Port:', url.port);
    console.log('- Database:', url.pathname.slice(1));
    console.log('- Search params:', url.searchParams.toString());
  } catch (e) {
    console.log('Could not parse connection string as URL');
  }
  
  const client = new Client({
    connectionString: connectionString,
    ssl: false,
    rejectUnauthorized: false,
    // Additional SSL disable options
    sslmode: 'disable',
    ssl: false
  });
  
  try {
    console.log('Attempting to connect with SSL disabled...');
    await client.connect();
    console.log('✅ Database connection successful! SSL is disabled.');
    
    const result = await client.query('SELECT version()');
    console.log('Database version:', result.rows[0].version);
    
    // Test a simple query
    const testResult = await client.query('SELECT 1 as test');
    console.log('Test query result:', testResult.rows[0]);
    
    await client.end();
    return true;
  } catch (error) {
    console.error('❌ Database connection failed:', error.message);
    console.error('Error details:', error);
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