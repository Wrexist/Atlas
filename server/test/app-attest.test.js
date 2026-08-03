import test from 'node:test';
import assert from 'node:assert/strict';
import { X509Certificate } from 'node:crypto';
import {
  fakeUpstash,
  makeAssertion,
  makeAttestationFixture,
  makeClientData,
  REDIS_ENV,
  setEnv,
  sha256,
} from '../testutil/attest-fixtures.js';
import {
  APPLE_APP_ATTEST_ROOT_CA_PEM,
  checkAppAttest,
  storeAttestKey,
  verifyAssertion,
  verifyAttestation,
} from '../api/_lib/app-attest.js';

// Shared fixture — minting certs shells out to openssl four times,
// so build once and reuse across tests.
const fixture = makeAttestationFixture();

test('pinned Apple root parses with the expected identity', () => {
  const root = new X509Certificate(APPLE_APP_ATTEST_ROOT_CA_PEM);
  assert.match(root.subject, /Apple App Attestation Root CA/);
  assert.equal(new Date(root.validFrom).getUTCFullYear(), 2020);
  assert.equal(new Date(root.validTo).getUTCFullYear(), 2045);
});

test('attestation verifies against its root and yields the credential key', () => {
  const { publicKeyPem, environment } = verifyAttestation({
    attestation: fixture.attestation,
    keyId: fixture.keyId,
    challenge: fixture.challenge,
    appId: fixture.appId,
    rootCAPem: fixture.rootPem,
  });
  assert.equal(environment, 'production');
  assert.match(publicKeyPem, /BEGIN PUBLIC KEY/);
});

test('attestation flags development-environment keys', () => {
  const dev = makeAttestationFixture({ environment: 'development' });
  const { environment } = verifyAttestation({
    attestation: dev.attestation,
    keyId: dev.keyId,
    challenge: dev.challenge,
    appId: dev.appId,
    rootCAPem: dev.rootPem,
  });
  assert.equal(environment, 'development');
});

test('attestation rejects wrong challenge, appId, keyId, and foreign roots', () => {
  const base = {
    attestation: fixture.attestation,
    keyId: fixture.keyId,
    challenge: fixture.challenge,
    appId: fixture.appId,
    rootCAPem: fixture.rootPem,
  };
  assert.throws(() => verifyAttestation({ ...base, challenge: Buffer.from('wrong') }), /nonce mismatch/);
  assert.throws(() => verifyAttestation({ ...base, appId: 'TEAM12345.com.other.app' }), /appId mismatch/);
  assert.throws(() => verifyAttestation({ ...base, keyId: Buffer.alloc(32, 9) }), /keyId does not match/);
  // The synthetic chain must NOT verify against the pinned Apple
  // root — this is the check that stops self-minted attestations.
  assert.throws(
    () => verifyAttestation({ ...base, rootCAPem: APPLE_APP_ATTEST_ROOT_CA_PEM }),
    /chain does not reach Apple root/
  );
});

test('assertion verifies, then rejects counter replay and tampering', () => {
  const { publicKeyPem } = verifyAttestation({
    attestation: fixture.attestation,
    keyId: fixture.keyId,
    challenge: fixture.challenge,
    appId: fixture.appId,
    rootCAPem: fixture.rootPem,
  });
  const clientData = makeClientData();
  const assertion = makeAssertion({
    leafKeyPem: fixture.leafKeyPem,
    appId: fixture.appId,
    counter: 5,
    clientData,
  });
  const verify = (overrides = {}) => verifyAssertion({
    assertion,
    publicKeyPem,
    clientDataHash: sha256(clientData),
    appId: fixture.appId,
    previousCounter: 4,
    ...overrides,
  });

  assert.equal(verify().counter, 5);
  assert.throws(() => verify({ previousCounter: 5 }), /counter replayed/);
  assert.throws(() => verify({ clientDataHash: sha256(Buffer.from('other')) }), /bad assertion signature/);
  assert.throws(() => verify({ appId: 'TEAM12345.com.other.app' }), /appId mismatch/);
});

test('checkAppAttest gate: enforce accepts a valid assertion once and blocks its replay', async (t) => {
  setEnv(t, {
    ...REDIS_ENV,
    APP_ATTEST_MODE: 'enforce',
    APP_ATTEST_APP_ID: fixture.appId,
    APP_ATTEST_ALLOW_DEVELOPMENT: undefined,
  });
  fakeUpstash(t);

  const { publicKeyPem } = verifyAttestation({
    attestation: fixture.attestation,
    keyId: fixture.keyId,
    challenge: fixture.challenge,
    appId: fixture.appId,
    rootCAPem: fixture.rootPem,
  });
  const keyIdB64 = fixture.keyId.toString('base64');
  assert.equal(await storeAttestKey(keyIdB64, { publicKeyPem, counter: 0, environment: 'production' }), true);

  const clientData = makeClientData();
  const assertion = makeAssertion({
    leafKeyPem: fixture.leafKeyPem,
    appId: fixture.appId,
    counter: 1,
    clientData,
  });
  const req = {
    headers: {
      'x-attest-key-id': keyIdB64,
      'x-attest-assertion': assertion.toString('base64'),
      'x-attest-client-data': clientData.toString('base64'),
    },
  };

  // The verified key id comes back so the rate limiter can count
  // against the install rather than the (rotatable) client IP.
  assert.deepEqual(
    await checkAppAttest(req, { logLabel: 'test' }),
    { ok: true, keyId: keyIdB64 }
  );
  // Same assertion again — counter no longer advances.
  const replay = await checkAppAttest(req, { logLabel: 'test' });
  assert.equal(replay.ok, false);
  assert.match(replay.reason, /replayed/);
  assert.equal(replay.keyId, undefined);
});

test('checkAppAttest gate: header absence rejects only in enforce mode', async (t) => {
  setEnv(t, {
    ...REDIS_ENV,
    APP_ATTEST_MODE: 'report',
    APP_ATTEST_APP_ID: fixture.appId,
  });
  assert.deepEqual(await checkAppAttest({ headers: {} }, { logLabel: 'test' }), { ok: true });

  setEnv(t, { APP_ATTEST_MODE: 'enforce' });
  const denied = await checkAppAttest({ headers: {} }, { logLabel: 'test' });
  assert.equal(denied.ok, false);

  setEnv(t, { APP_ATTEST_MODE: 'off' });
  assert.deepEqual(await checkAppAttest({ headers: {} }, { logLabel: 'test' }), { ok: true });
});

test('checkAppAttest gate: stale client data is rejected in enforce mode', async (t) => {
  setEnv(t, {
    ...REDIS_ENV,
    APP_ATTEST_MODE: 'enforce',
    APP_ATTEST_APP_ID: fixture.appId,
  });
  fakeUpstash(t);
  const req = {
    headers: {
      'x-attest-key-id': 'any',
      'x-attest-assertion': 'any',
      'x-attest-client-data': makeClientData(10 * 60 * 1000).toString('base64'),
    },
  };
  const denied = await checkAppAttest(req, { logLabel: 'test' });
  assert.equal(denied.ok, false);
  assert.match(denied.reason, /stale/);
});
