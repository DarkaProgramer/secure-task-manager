'use strict';

// Loads the isolated test configuration before any application module runs.
const path = require('node:path');
const dotenv = require('dotenv');

dotenv.config({ path: path.join(__dirname, '..', '.env.test'), override: true, quiet: true });
process.env.NODE_ENV = 'test';

// Safety net: refuse to run against anything that is not an obvious test database.
const url = process.env.DATABASE_URL || '';
if (!/\/[A-Za-z0-9_]*_test(\?|$)/.test(url)) {
  throw new Error('Tests refuse to run: DATABASE_URL must point to a database whose name ends in _test.');
}
