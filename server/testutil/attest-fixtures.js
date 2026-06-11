/**
 * Shared helpers for the App Attest test suites. Lives outside
 * `test/` so `node --test` never executes it as a test file.
 * Fixtures are minted with the openssl CLI — a test root +
 * intermediate + leaf carrying Apple's nonce extension — which is
 * the closest a test can get without a physical device.
 */
import { execFileSync } from 'node:child_process';
import { createHash, createPublicKey, createSign, randomFillSync, X509Certificate } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { encodeCBOR } from '../api/_lib/cbor.js';

export const sha256 = (data) => createHash('sha256').update(data).digest();

export const REDIS_ENV = {
  UPSTASH_REDIS_REST_URL: 'https://fake.upstash.test',
  UPSTASH_REDIS_REST_TOKEN: 'tok',
};

export function setEnv(t, vars) {
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
export function fakeUpstash(t) {
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

export function uncompressedPoint(keyObject) {
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
export function makeAttestationFixture({
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

export function makeAssertion({ leafKeyPem, appId, counter, clientData }) {
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

export function makeClientData(ageMs = 0) {
  const data = Buffer.alloc(24);
  randomFillSync(data, 0, 16);
  data.writeBigUInt64BE(BigInt(Date.now() - ageMs), 16);
  return data;
}
