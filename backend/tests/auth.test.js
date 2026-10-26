'use strict';

const { request, app, PASSWORD, uniqueEmail, registerUser, bearer, cleanup, disconnect } = require('./helpers');

afterAll(async () => {
  await cleanup();
  await disconnect();
});

describe('registration and login', () => {
  test('registers a user and returns a token pair', async () => {
    const email = uniqueEmail('reg');
    const response = await request(app).post('/api/v1/auth/register').send({ email, password: PASSWORD });
    expect(response.status).toBe(201);
    expect(typeof response.body.accessToken).toBe('string');
    expect(typeof response.body.refreshToken).toBe('string');
    expect(response.body.passwordHash).toBeUndefined();
  });

  test('rejects a duplicate email with 409', async () => {
    const user = await registerUser('dup');
    const response = await request(app).post('/api/v1/auth/register')
      .send({ email: user.email, password: PASSWORD });
    expect(response.status).toBe(409);
  });

  test('rejects short passwords and invalid emails', async () => {
    const short = await request(app).post('/api/v1/auth/register')
      .send({ email: uniqueEmail('short'), password: 'short' });
    expect(short.status).toBe(400);
    expect(short.body.error.code).toBe('VALIDATION_ERROR');

    const bad = await request(app).post('/api/v1/auth/register')
      .send({ email: 'not-an-email', password: PASSWORD });
    expect(bad.status).toBe(400);
  });

  test('logs in with correct credentials', async () => {
    const user = await registerUser('login');
    const response = await request(app).post('/api/v1/auth/login')
      .send({ email: user.email, password: user.password });
    expect(response.status).toBe(200);
    expect(typeof response.body.accessToken).toBe('string');
  });

  test('wrong password and unknown email give the same generic 401', async () => {
    const user = await registerUser('wrong');
    const wrongPassword = await request(app).post('/api/v1/auth/login')
      .send({ email: user.email, password: 'definitely-the-wrong-one' });
    const unknownEmail = await request(app).post('/api/v1/auth/login')
      .send({ email: uniqueEmail('ghost'), password: 'definitely-the-wrong-one' });
    expect(wrongPassword.status).toBe(401);
    expect(unknownEmail.status).toBe(401);
    expect(wrongPassword.body).toEqual(unknownEmail.body);
  });
});

describe('access token enforcement', () => {
  test('rejects missing, malformed, and forged tokens', async () => {
    const missing = await request(app).get('/api/v1/tasks');
    expect(missing.status).toBe(401);

    const malformed = await request(app).get('/api/v1/tasks').set('Authorization', 'Bearer not-a-jwt');
    expect(malformed.status).toBe(401);

    const jwt = require('jsonwebtoken');
    const forged = jwt.sign({ sub: 'someone', type: 'access' }, 'a-different-secret-that-is-long-enough-xx', {
      algorithm: 'HS256', issuer: 'task-manager-api', audience: 'task-manager-client',
    });
    const response = await request(app).get('/api/v1/tasks').set(bearer(forged));
    expect(response.status).toBe(401);
  });

  test('a refresh token is not accepted as an access token', async () => {
    const user = await registerUser('mixup');
    const response = await request(app).get('/api/v1/tasks').set(bearer(user.refreshToken));
    expect(response.status).toBe(401);
  });
});
