'use strict';

const bcrypt = require('bcrypt');
const crypto = require('node:crypto');
const { prisma } = require('../repositories/task.repository');
const userRepository = require('../repositories/user.repository');
const tokenRepository = require('../repositories/refresh-token.repository');
const { env } = require('../config');
const { createAccessToken, createRefreshToken, hashToken } = require('../utils/tokens');

// A lower cost keeps the automated tests fast; real environments use 12.
const BCRYPT_COST = env.NODE_ENV === 'test' ? 4 : 12;
const REFRESH_TTL_MS = 7 * 24 * 60 * 60 * 1000;

// A real hash of a random value, so unknown emails cost the same bcrypt work
// as known ones and login timing does not reveal which accounts exist.
const DUMMY_PASSWORD_HASH = bcrypt.hashSync(crypto.randomUUID(), BCRYPT_COST);

/** Creates a safe authentication error with an HTTP status and code. */
function authError(message = 'Authentication required.') {
  const error = new Error(message);
  error.status = 401;
  error.code = 'UNAUTHENTICATED';
  return error;
}

/** Registers a user with a one-way password hash. */
async function register({ email, password }) {
  const passwordHash = await bcrypt.hash(password, BCRYPT_COST);
  try {
    const user = await userRepository.create({ email, passwordHash });
    return await issueTokens(user.id, crypto.randomUUID());
  } catch (error) {
    if (error.code === 'P2002') {
      const conflict = new Error('An account with this email already exists.');
      conflict.status = 409;
      conflict.code = 'CONFLICT';
      throw conflict;
    }
    throw error;
  }
}

/** Authenticates credentials with a generic failure response. */
async function login({ email, password }) {
  const user = await userRepository.findByEmail(email);
  const passwordHash = user?.passwordHash || DUMMY_PASSWORD_HASH;
  const matches = await bcrypt.compare(password, passwordHash);
  if (!user || !matches) throw authError('Invalid email or password.');
  return issueTokens(user.id, crypto.randomUUID());
}

/** Issues an access/refresh pair and persists only the refresh-token hash. */
async function issueTokens(userId, familyId, db = prisma) {
  const refreshToken = createRefreshToken();
  await tokenRepository.createToken({
    userId,
    tokenHash: hashToken(refreshToken),
    familyId,
    expiresAt: new Date(Date.now() + REFRESH_TTL_MS),
  }, db);
  return { accessToken: createAccessToken(userId), refreshToken, expiresIn: 600 };
}

/** Rotates a refresh token transactionally and detects reuse of revoked tokens. */
async function refresh(refreshToken) {
  const outcome = await prisma.$transaction(async (tx) => {
    const record = await tokenRepository.findByHash(hashToken(refreshToken), tx);
    if (!record || record.expiresAt <= new Date()) return { error: true };
    if (record.revokedAt) {
      await tokenRepository.revokeFamily(record.familyId, tx);
      return { error: true };
    }
    // If two requests race with the same token, only one revocation succeeds;
    // the loser is treated as reuse and the whole family is revoked.
    const revoked = await tokenRepository.revokeToken(record.id, tx);
    if (revoked.count !== 1) {
      await tokenRepository.revokeFamily(record.familyId, tx);
      return { error: true };
    }
    return { tokens: await issueTokens(record.userId, record.familyId, tx) };
  });
  if (outcome.error) throw authError('Refresh token is invalid or expired.');
  return outcome.tokens;
}

/** Revokes the entire refresh-token family associated with this token. */
async function logout(refreshToken) {
  const record = await tokenRepository.findByHash(hashToken(refreshToken));
  if (record) await tokenRepository.revokeFamily(record.familyId);
}

/** Revokes all active refresh tokens for the authenticated user. */
function logoutAll(userId) {
  return tokenRepository.revokeAllForUser(userId);
}

module.exports = { register, login, issueTokens, refresh, logout, logoutAll };
