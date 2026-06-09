import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash, createPublicKey, createSign, randomFillSync, X509Certificate } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { encodeCBOR } from '../api/_lib/cbor.js';
import {
  APPLE_APP_ATTEST_ROOT_CA_PEM,
  checkAppAttest,
  storeAttestKey,
  verifyAssertion,
  verifyAttestation,
} from '../api/_lib/app-attest.js';

const sha256 = (data) => createHash('sha256').update(data).digest();

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

// In-memory Upstash double: honours the pipeline commands the attest
// registry and rate limiter issue.
function fakeUpstash(t) {
  const store = new Map();
  const real = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    const commands = JSON.parse(init.body);
    const results = commands.map(([cmd, ...args]) => {
      switch (cmd) {
        case 'SET': {
          if (args.includes('NX') && store.has(args[0])) return { result: null };
          store.set(args[0], args[1]);
          return { result: 'OK' };
        }
        case 'GET':
          return { result: store.has(args[0]) ? store.get(args[0]) : null };
        case 'GETDEL': {
          const v = store.has(args[0]) ? store.get(args[0]) : null;
          store.delete(args[0]);
          return { result: v };
        }
        case 'INCR': {
          const v = parseInt(store.get(args[0]) ?? '0', 10) + 1;
          store.set(args[0], String(v));
          return { result: v };
        }
        case 'EXPIRE':
          return { result: 1 };
        default:
          return { error: `unsupported ${cmd}` };
      }
    });
    return new Response(JSON.stringify(results), { status: 200 });
  };
  t.after(() => {
    globalThis.fetch = real;
  });
  return store;
}

const REDIS_ENV = {
  UPSTASH_REDIS_REST_URL: 'https://fake.upstash.test',
  UPSTASH_REDIS_REST_TOKEN: 'tok',
};

function uncompressedPoint(keyObject) {
  const jwk = keyObject.export({ format: 'jwk' });
  return Buffer.concat([
    Buffer.from([0x04]),
    Buffer.from(jwk.x, 'base64url'),
    Buffer.from(jwk.y, 'base64url'),
  ]);
}

/**
 * Mints a synthetic attestation: test root → intermediate → leaf
 * carrying Apple's nonce extension, plus the matching authData. The
 * chain anchors at the TEST root, so production code paths that pin
 * the Apple root must reject it — that rejection is itself a test.
 */
function makeAttestationFixture({
  appId = 'TEAM12345.com.peptidesai.app',
  environment = 'production',
  challenge = Buffer.from('register-challenge'),
} = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'attest-'));
  const sh = (args) => execFileSync('openssl', args, { cwd: dir, stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    sh(['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'root.key']);
    sh(['req', '-new', '-x509', '-key', 'root.key', '-subj', '/CN=Test Attest Root', '-days', '30', '-out', 'root.pem']);
    sh(['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'int.key']);
    sh(['req', '-new', '-key', 'int.key', '-subj', '/CN=Test Intermediate', '-out', 'int.csr']);
    writeFileSync(join(dir, 'int.cnf'), 'basicConstraints=CA:TRUE\n');
    sh(['x509', '-req', '-in', 'int.csr', '-CA', 'root.pem', '-CAkey', 'root.key', '-CAcreateserial', '-days', '30', '-extfile', 'int.cnf', '-out', 'int.pem']);
    sh(['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'leaf.key']);
    sh(['req', '-new', '-key', 'leaf.key', '-subj', '/CN=Test Leaf', '-out', 'leaf.csr']);

    const leafKeyPem = readFileSync(join(dir, 'leaf.key'), 'utf8');
    const keyId = sha256(uncompressedPoint(createPublicKey(leafKeyPem)));

    const aaguid = environment === 'production'
      ? Buffer.concat([Buffer.from('appattest', 'utf8'), Buffer.alloc(7)])
      : Buffer.from('appattestdevelop', 'utf8');
    const credIdLength = Buffer.alloc(2);
    credIdLength.writeUInt16BE(32);
    const authData = Buffer.concat([
      sha256(Buffer.from(appId, 'utf8')),
      Buffer.from([0x40]),
      Buffer.alloc(4), // counter 0
      aaguid,
      credIdLength,
      keyId,
    ]);

    const nonce = sha256(Buffer.concat([authData, sha256(challenge)]));
    const nonceHex = [...nonce].map((b) => b.toString(16).padStart(2, '0')).join(':');
    writeFileSync(join(dir, 'leaf.cnf'), `1.2.840.113635.100.8.2=DER:30:24:A1:22:04:20:${nonceHex}\n`);
    sh(['x509', '-req', '-in', 'leaf.csr', '-CA', 'int.pem', '-CAkey', 'int.key', '-CAcreateserial', '-days', '30', '-extfile', 'leaf.cnf', '-out', 'leaf.pem']);

    const attestation = encodeCBOR(new Map([
      ['fmt', 'apple-appattest'],
      ['attStmt', new Map([
        ['x5c', [
          new X509Certificate(readFileSync(join(dir, 'leaf.pem'))).raw,
          new X509Certificate(readFileSync(join(dir, 'int.pem'))).raw,
        ]],
        ['receipt', Buffer.alloc(0)],
      ])],
      ['authData', authData],
    ]));

    return {
      attestation,
      keyId,
      challenge,
      appId,
      rootPem: readFileSync(join(dir, 'root.pem'), 'utf8'),
      leafKeyPem,
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function makeAssertion({ leafKeyPem, appId, counter, clientData }) {
  const counterBytes = Buffer.alloc(4);
  counterBytes.writeUInt32BE(counter);
  const authData = Buffer.concat([
    sha256(Buffer.from(appId, 'utf8')),
    Buffer.from([0x40]),
    counterBytes,
  ]);
  const nonce = sha256(Buffer.concat([authData, sha256(clientData)]));
  const signature = createSign('SHA256').update(nonce).sign(leafKeyPem);
  return encodeCBOR(new Map([['signature', signature], ['authenticatorData', authData]]));
}

function makeClientData(ageMs = 0) {
  const data = Buffer.alloc(24);
  randomFillSync(data, 0, 16);
  data.writeBigUInt64BE(BigInt(Date.now() - ageMs), 16);
  return data;
}

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

  assert.deepEqual(await checkAppAttest(req, { logLabel: 'test' }), { ok: true });
  // Same assertion again — counter no longer advances.
  const replay = await checkAppAttest(req, { logLabel: 'test' });
  assert.equal(replay.ok, false);
  assert.match(replay.reason, /replayed/);
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
