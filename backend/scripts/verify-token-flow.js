'use strict';

/**
 * Runs the tutorial's section 19a checks (rotation, reuse, logout, logout-all)
 * against a running local API using a throwaway account. Prints only statuses.
 * Usage: node scripts/verify-token-flow.js [baseUrl]
 */
const BASE = process.argv[2] || 'http://localhost:3000/api/v1';
const email = `student-${Math.floor(Math.random() * 1e9)}@example.test`;
const password = 'a-long-local-test-password-for-this-exercise';

async function post(path, body, accessToken) {
  const response = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = response.status === 204 ? {} : await response.json().catch(() => ({}));
  return { status: response.status, json };
}

const results = [];
function check(name, expected, actual) {
  const pass = expected === actual;
  results.push(pass);
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}  (expected ${expected}, got ${actual})`);
}

(async () => {
  const registered = await post('/auth/register', { email, password });
  check('Register', 201, registered.status);

  const oldRefresh = registered.json.refreshToken;
  const rotated = await post('/auth/refresh', { refreshToken: oldRefresh });
  check('Refresh with valid token', 200, rotated.status);
  check('Rotated refresh token differs from the old one', 'different',
    rotated.json.refreshToken !== oldRefresh ? 'different' : 'same');

  check('Refresh with old token (reuse)', 401, (await post('/auth/refresh', { refreshToken: oldRefresh })).status);
  check('Refresh with newest token after reuse', 401,
    (await post('/auth/refresh', { refreshToken: rotated.json.refreshToken })).status);

  const login = await post('/auth/login', { email, password });
  check('Login after reuse', 200, login.status);
  check('Logout', 204, (await post('/auth/logout', { refreshToken: login.json.refreshToken })).status);
  check('Refresh after logout', 401, (await post('/auth/refresh', { refreshToken: login.json.refreshToken })).status);

  const one = await post('/auth/login', { email, password });
  const two = await post('/auth/login', { email, password });
  check('Logout-all', 204, (await post('/auth/logout-all', null, one.json.accessToken)).status);
  check('Refresh after logout-all (session 1)', 401, (await post('/auth/refresh', { refreshToken: one.json.refreshToken })).status);
  check('Refresh after logout-all (session 2)', 401, (await post('/auth/refresh', { refreshToken: two.json.refreshToken })).status);

  console.log(results.every(Boolean) ? '\nAll checks passed.' : '\nSome checks FAILED.');
  process.exit(results.every(Boolean) ? 0 : 1);
})().catch((error) => {
  console.error(`Could not reach the API at ${BASE}: ${error.message}`);
  process.exit(1);
});
