'use strict';

const { prisma } = require('./task.repository');

/** Finds a user by normalized email address. */
function findByEmail(email) {
  return prisma.user.findUnique({ where: { email } });
}

/** Creates a user from an email address and a password hash. */
function create({ email, passwordHash }) {
  return prisma.user.create({ data: { email, passwordHash } });
}

module.exports = { findByEmail, create };
