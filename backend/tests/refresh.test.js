'use strict';

const { request, app, registerUser, bearer, cleanup, disconnect, prisma } = require('./helpers');
const { hashToken } = require('../src/utils/tokens');

afterAll(async () => {
  await cleanup();
  await disconnect();
});

const refresh = (refreshToken) => request(app).post('/api/v1/auth/refresh').send({ refreshToken });

describe('refresh-token lifecycle', () => {
  test('rotation returns a different refresh token', async () => {
    const initial = await registerUser('rot');
    const response = await refresh(initial.refreshToken);
    expect(response.status).toBe(200);
    expect(response.body.refreshToken).not.toBe(initial.refreshToken);
    expect(response.body.accessToken).toEqual(expect.any(String));
  });

  test('reuse of an old token revokes the newer token family token', async () => {
    const initial = await registerUser('reuse');
    const rotated = await refresh(initial.refreshToken);
    expect(rotated.status).toBe(200);

    const reuse = await refresh(initial.refreshToken);
    expect(reuse.status).toBe(401);

    const newer = await refresh(rotated.body.refreshToken);
    expect(newer.status).toBe(401);
  });

  test('only token hashes are stored, never the raw token', async () => {
    const user = await registerUser('hash');
    const raw = await prisma.refreshToken.findFirst({ where: { tokenHash: user.refreshToken } });
    expect(raw).toBeNull();
    const hashed = await prisma.refreshToken.findUnique({ where: { tokenHash: hashToken(user.refreshToken) } });
    expect(hashed).not.toBeNull();
  });

  test('an expired refresh token is rejected', async () => {
    const user = await registerUser('exp');
    await prisma.refreshToken.update({
      where: { tokenHash: hashToken(user.refreshToken) },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });
    expect((await refresh(user.refreshToken)).status).toBe(401);
  });

  test('concurrent refreshes with the same token never yield two valid sessions', async () => {
    const user = await registerUser('race');
    const results = await Promise.all([refresh(user.refreshToken), refresh(user.refreshToken)]);
    const successes = results.filter((r) => r.status === 200);
    expect(successes.length).toBeLessThanOrEqual(1);
    for (const ok of successes) {
      expect((await refresh(ok.body.refreshToken)).status).toBe(401);
    }
  });

  test('logout makes the refresh token unusable', async () => {
    const tokens = await registerUser('out');
    const logout = await request(app).post('/api/v1/auth/logout').send({ refreshToken: tokens.refreshToken });
    expect(logout.status).toBe(204);
    expect((await refresh(tokens.refreshToken)).status).toBe(401);
  });

  test('logout with an unknown token still returns 204', async () => {
    const response = await request(app).post('/api/v1/auth/logout')
      .send({ refreshToken: 'x'.repeat(40) });
    expect(response.status).toBe(204);
  });

  test('logout-all revokes every session of the user', async () => {
    const first = await registerUser('all');
    const second = await request(app).post('/api/v1/auth/login')
      .send({ email: first.email, password: first.password });
    const response = await request(app).post('/api/v1/auth/logout-all').set(bearer(first.accessToken));
    expect(response.status).toBe(204);
    expect((await refresh(first.refreshToken)).status).toBe(401);
    expect((await refresh(second.body.refreshToken)).status).toBe(401);
  });

  test('logout-all requires authentication', async () => {
    const response = await request(app).post('/api/v1/auth/logout-all');
    expect(response.status).toBe(401);
  });
});
