'use strict';

/**
 * Creates the isolated test database (if missing) and applies migrations to it.
 * Reads DATABASE_URL from .env.test and refuses anything not ending in _test.
 */
const path = require('node:path');
const { execSync } = require('node:child_process');
const dotenv = require('dotenv');
const { PrismaClient } = require('@prisma/client');

// override: true so .env.test always wins over a DATABASE_URL already set in the shell.
dotenv.config({ path: path.join(__dirname, '..', '.env.test'), override: true, quiet: true });

const url = new URL(process.env.DATABASE_URL);
const dbName = url.pathname.replace(/^\//, '');
if (!/^[A-Za-z0-9_]+_test$/.test(dbName)) {
  throw new Error(`Refusing to continue: the database name must end in _test (found "${dbName}").`);
}

async function main() {
  const admin = new URL(url.toString());
  admin.pathname = '/postgres';
  const prisma = new PrismaClient({ datasources: { db: { url: admin.toString() } } });
  try {
    const rows = await prisma.$queryRaw`SELECT 1 FROM pg_database WHERE datname = ${dbName}`;
    if (rows.length === 0) {
      await prisma.$executeRawUnsafe(`CREATE DATABASE "${dbName}"`);
      console.info(`Created database ${dbName}`);
    }
  } finally {
    await prisma.$disconnect();
  }
  execSync('npx prisma migrate deploy', { stdio: 'inherit', env: process.env });
  console.info(`Test database ${dbName} is ready.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
