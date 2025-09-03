#!/usr/bin/env node

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// Check if admin files exist
const adminPath = path.join(process.cwd(), '.medusa', 'admin', 'index.html');
const adminExists = fs.existsSync(adminPath);

// Set environment variable based on admin file existence
process.env.ADMIN_DISABLED = adminExists ? 'false' : 'true';

console.log(`Admin files ${adminExists ? 'found' : 'not found'} - setting ADMIN_DISABLED=${process.env.ADMIN_DISABLED}`);

// Start medusa with inherited environment
const medusa = spawn('yarn', ['medusa', 'start'], {
  stdio: 'inherit',
  env: process.env
});

medusa.on('close', (code) => {
  process.exit(code);
});

medusa.on('error', (err) => {
  console.error('Failed to start medusa:', err);
  process.exit(1);
});