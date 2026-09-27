import test from 'node:test';
import assert from 'node:assert/strict';
import { createPublicKey, generateKeyPairSync, verify } from 'node:crypto';
import handler, { clientSecret } from '../api/apple-revoke.js';

function setEnv(t, vars) {
  const saved = {};
  for (const [k, v] of Object.entries(vars)) {
    saved[k] = process.env[k];
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  t.after(() => {
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  });
}

const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const PRIVATE_PEM = privateKey.export({ type: 'pkcs8', format: 'pem' });

const BASE_ENV = {
  PROXY_SHARED_SECRET: 'test-secret',
  APPLE_TEAM_ID: 'TEAM123456',
  APPLE_KEY_ID: 'KEY1234567',
  APPLE_PRIVATE_KEY: PRIVATE_PEM.replace(/\n/g, '\\n'),
  APPLE_CLIENT_ID: 'com.peptidesai.app',
  REVOKE_RPM: '1000',
  UPSTASH_REDIS_REST_URL: undefined,
  UPSTASH_REDIS_REST_TOKEN: undefined,
  KV_REST_API_URL: undefined,
  KV_REST_API_TOKEN: undefined,
};

function stubApple(t, { tokenStatus = 200, revokeStatus = 200 } = {}) {
  const real = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, form: new URLSearchParams(init.body) });
    if (url.endsWith('/auth/token')) {
      return new Response(JSON.stringify({ refresh_token: 'r-token', access_token: 'a-token' }), {
        status: tokenStatus,
        headers: { 'content-type': 'application/json' },
      });
    }
    return new Response('', { status: revokeStatus });
  };
  t.after(() => {
    globalThis.fetch = real;
  });
  return calls;
}

function makeReq(body, secret = 'test-secret') {
  return {
    method: 'POST',
    headers: { 'x-peptide-proxy': secret, 'x-real-ip': '10.1.0.1' },
    socket: {},
    body,
  };
}

function makeRes() {
  return {
    statusCode: null,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
    send(payload) { this.body = payload; return this; },
  };
}

async function call(req) {
  const res = makeRes();
  await handler(req, res);
  return res;
}

test('a valid code is exchanged and its refresh token revoked', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubApple(t);

  const res = await call(makeReq({ authorizationCode: 'c-123' }));

  assert.equal(res.statusCode, 204);
  assert.equal(calls.length, 2);
  assert.match(calls[0].url, /\/auth\/token$/);
  assert.equal(calls[0].form.get('code'), 'c-123');
  assert.equal(calls[0].form.get('grant_type'), 'authorization_code');
  assert.match(calls[1].url, /\/auth\/revoke$/);
  assert.equal(calls[1].form.get('token'), 'r-token');
  assert.equal(calls[1].form.get('token_type_hint'), 'refresh_token');
});

test('the client secret is an ES256 JWT Apple can verify', () => {
  const now = Date.UTC(2026, 8, 27);
  const jwt = clientSecret({
    teamId: 'TEAM123456', keyId: 'KEY1234567', privateKey: PRIVATE_PEM, clientId: 'com.peptidesai.app',
  }, now);
  const [header, payload, signature] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), { alg: 'ES256', kid: 'KEY1234567' });
  const claims = JSON.parse(Buffer.from(payload, 'base64url'));
  assert.equal(claims.iss, 'TEAM123456');
  assert.equal(claims.sub, 'com.peptidesai.app');
  assert.equal(claims.aud, 'https://appleid.apple.com');
  assert.equal(claims.exp - claims.iat, 300);
  const ok = verify(
    'sha256',
    Buffer.from(`${header}.${payload}`),
    { key: createPublicKey(PRIVATE_PEM), dsaEncoding: 'ieee-p1363' },
    Buffer.from(signature, 'base64url')
  );
  assert.equal(ok, true);
});

test('a wrong shared secret is refused before contacting Apple', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubApple(t);
  const res = await call(makeReq({ authorizationCode: 'c-123' }, 'wrong'));
  assert.equal(res.statusCode, 401);
  assert.equal(calls.length, 0);
});

test('a missing or oversized code is rejected 400', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubApple(t);
  assert.equal((await call(makeReq({}))).statusCode, 400);
  assert.equal((await call(makeReq({ authorizationCode: 'x'.repeat(1025) }))).statusCode, 400);
  assert.equal(calls.length, 0);
});

test('missing Apple key configuration answers 503', async (t) => {
  setEnv(t, { ...BASE_ENV, APPLE_PRIVATE_KEY: undefined });
  const calls = stubApple(t);
  assert.equal((await call(makeReq({ authorizationCode: 'c-123' }))).statusCode, 503);
  assert.equal(calls.length, 0);
});

test('an Apple failure surfaces as 502 and skips the revoke call', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubApple(t, { tokenStatus: 400 });
  assert.equal((await call(makeReq({ authorizationCode: 'c-123' }))).statusCode, 502);
  assert.equal(calls.length, 1);
});
