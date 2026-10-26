'use strict';

const request = require('supertest');
const { app } = require('../src/app');
const { prisma } = require('../src/repositories/task.repository');

const EMAIL_DOMAIN = '@tests.example';
const PASSWORD = 'a-long-test-password';

/** Returns a unique email address that cleanup() knows how to remove. */
function uniqueEmail(prefix = 'user') {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}${EMAIL_DOMAIN}`;
}

/** Registers a new user and returns its credentials and token pair. */
async function registerUser(prefix) {
  const email = uniqueEmail(prefix);
  const response = await request(app).post('/api/v1/auth/register').send({ email, password: PASSWORD });
  if (response.status !== 201) throw new Error(`register failed with ${response.status}`);
  return { email, password: PASSWORD, ...response.body };
}

/** Builds an Authorization header for an access token. */
function bearer(token) {
  return { Authorization: `Bearer ${token}` };
}

/** Deletes every user created by the tests (tasks and tokens cascade). */
async function cleanup() {
  await prisma.user.deleteMany({ where: { email: { endsWith: EMAIL_DOMAIN } } });
}

/** Closes the shared Prisma connection. */
async function disconnect() {
  await prisma.$disconnect();
}

module.exports = { app, request, prisma, PASSWORD, uniqueEmail, registerUser, bearer, cleanup, disconnect };
