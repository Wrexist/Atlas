import test from 'node:test';
import assert from 'node:assert/strict';
import handler from '../api/attest-register.js';
import {
  fakeUpstash,
  makeAttestationFixture,
  REDIS_ENV,
  setEnv,
} from '../testutil/attest-fixtures.js';

const APP_ID = 'TEAM12345.com.peptidesai.app';

const BASE_ENV = {
  ...REDIS_ENV,
  PROXY_SHARED_SECRET: 'test-secret',
  APP_ATTEST_APP_ID: APP_ID,
  ATTEST_RPM: '100',
  APP_ATTEST_ROOT_CA_PEM: undefined,
};

function makeReq({ method, ip, body, secret = 'test-secret' } = {}) {
  return {
    method,
    headers: {
      'x-peptide-proxy': secret,
      'x-real-ip': ip,
    },
    socket: {},
    body,
  };
}

function makeRes() {
  return {
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

test('rejects bad auth and missing configuration', async (t) => {
  setEnv(t, BASE_ENV);
  fakeUpstash(t);

  const unauthorized = makeRes();
  await handler(makeReq({ method: 'GET', ip: '10.2.0.1', secret: 'wrong' }), unauthorized);
  assert.equal(unauthorized.statusCode, 401);

  setEnv(t, { APP_ATTEST_APP_ID: undefined });
  const unconfigured = makeRes();
  await handler(makeReq({ method: 'GET', ip: '10.2.0.2' }), unconfigured);
  assert.equal(unconfigured.statusCode, 503);
});

test('GET issues a single-use 32-byte challenge', async (t) => {
  setEnv(t, BASE_ENV);
  const store = fakeUpstash(t);

  const res = makeRes();
  await handler(makeReq({ method: 'GET', ip: '10.2.0.3' }), res);
  assert.equal(res.statusCode, 200);
  assert.match(res.body.challengeId, /^[0-9a-f]{32}$/);
  assert.equal(Buffer.from(res.body.challenge, 'base64').length, 32);
  assert.ok(store.has(`attest:challenge:${res.body.challengeId}`));
});

test('POST registers a valid attestation exactly once per challenge', async (t) => {
  setEnv(t, BASE_ENV);
  const store = fakeUpstash(t);

  // 1. Obtain a challenge from the endpoint.
  const challengeRes = makeRes();
  await handler(makeReq({ method: 'GET', ip: '10.2.0.4' }), challengeRes);
  assert.equal(challengeRes.statusCode, 200);
  const { challengeId, challenge } = challengeRes.body;

  // 2. Mint an attestation bound to that challenge; trust its test
  //    root via the documented staging override.
  const fixture = makeAttestationFixture({
    appId: APP_ID,
    challenge: Buffer.from(challenge, 'base64'),
  });
  setEnv(t, { APP_ATTEST_ROOT_CA_PEM: fixture.rootPem });

  const body = {
    keyId: fixture.keyId.toString('base64'),
    challengeId,
    attestation: fixture.attestation.toString('base64'),
  };
  const registered = makeRes();
  await handler(makeReq({ method: 'POST', ip: '10.2.0.5', body }), registered);
  assert.equal(registered.statusCode, 200);
  assert.deepEqual(registered.body, { registered: true });

  const record = JSON.parse(store.get(`attest:key:${body.keyId}`));
  assert.match(record.publicKeyPem, /BEGIN PUBLIC KEY/);
  assert.equal(record.counter, 0);
  assert.equal(record.environment, 'production');

  // 3. The challenge is consumed — replaying the registration fails.
  const replay = makeRes();
  await handler(makeReq({ method: 'POST', ip: '10.2.0.6', body }), replay);
  assert.equal(replay.statusCode, 400);
});

test('POST rejects attestations that fail verification', async (t) => {
  setEnv(t, BASE_ENV);
  fakeUpstash(t);

  const challengeRes = makeRes();
  await handler(makeReq({ method: 'GET', ip: '10.2.0.7' }), challengeRes);
  const { challengeId } = challengeRes.body;

  // Attestation minted for a DIFFERENT challenge → nonce mismatch.
  const fixture = makeAttestationFixture({ appId: APP_ID, challenge: Buffer.from('other') });
  setEnv(t, { APP_ATTEST_ROOT_CA_PEM: fixture.rootPem });

  const res = makeRes();
  await handler(makeReq({
    method: 'POST',
    ip: '10.2.0.8',
    body: {
      keyId: fixture.keyId.toString('base64'),
      challengeId,
      attestation: fixture.attestation.toString('base64'),
    },
  }), res);
  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error.message, 'Registration failed');
});

test('POST rejects malformed and oversized registrations', async (t) => {
  setEnv(t, BASE_ENV);
  fakeUpstash(t);

  const malformed = makeRes();
  await handler(makeReq({
    method: 'POST',
    ip: '10.2.0.9',
    body: { keyId: 'short', challengeId: 'zz', attestation: 'aaaa' },
  }), malformed);
  assert.equal(malformed.statusCode, 400);

  const oversized = makeRes();
  await handler(makeReq({
    method: 'POST',
    ip: '10.2.0.10',
    body: { keyId: 'a'.repeat(44), challengeId: 'b'.repeat(32), attestation: 'c'.repeat(40_000) },
  }), oversized);
  assert.equal(oversized.statusCode, 413);
});

// One full challenge → attestation → POST round from `ip`.
async function registerFresh(t, ip) {
  const challengeRes = makeRes();
  await handler(makeReq({ method: 'GET', ip }), challengeRes);
  const { challengeId, challenge } = challengeRes.body;
  const fixture = makeAttestationFixture({ appId: APP_ID, challenge: Buffer.from(challenge, 'base64') });
  setEnv(t, { APP_ATTEST_ROOT_CA_PEM: fixture.rootPem });
  const body = {
    keyId: fixture.keyId.toString('base64'),
    challengeId,
    attestation: fixture.attestation.toString('base64'),
  };
  const res = makeRes();
  await handler(makeReq({ method: 'POST', ip, body }), res);
  return { res, keyId: body.keyId };
}

test('test_registeredKey_isStoredWithExpiry', async (t) => {
  setEnv(t, BASE_ENV);
  fakeUpstash(t);
  const fake = globalThis.fetch;
  const commands = [];
  globalThis.fetch = async (url, init) => {
    commands.push(...JSON.parse(init.body));
    return fake(url, init);
  };

  const { res, keyId } = await registerFresh(t, '10.2.1.1');
  assert.equal(res.statusCode, 200);
  const set = commands.find(([cmd, key]) => cmd === 'SET' && key === `attest:key:${keyId}`);
  assert.deepEqual(set.slice(3), ['EX', String(90 * 24 * 60 * 60)]);
});

test('test_registrationsOverDailyCapFromOneAddress_areRefused429', async (t) => {
  setEnv(t, { ...BASE_ENV, ATTEST_REGISTRATIONS_PER_DAY: '2', SHARED_IP_LIMIT_SCALE: '1' });
  const store = fakeUpstash(t);

  assert.equal((await registerFresh(t, '10.2.1.2')).res.statusCode, 200);
  assert.equal((await registerFresh(t, '10.2.1.2')).res.statusCode, 200);
  const third = await registerFresh(t, '10.2.1.2');
  assert.equal(third.res.statusCode, 429);
  assert.equal(store.has(`attest:key:${third.keyId}`), false);
  // Another address keeps its own allowance.
  assert.equal((await registerFresh(t, '10.2.1.3')).res.statusCode, 200);
});
