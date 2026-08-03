/**
 * Apple App Attest verification (DCAppAttestService server side).
 * Implements Apple's documented attestation + assertion checks with
 * node:crypto only — no dependencies.
 *
 * Attestation (once per install, via /api/attest-register):
 *   cert chain → pinned Apple root, nonce-in-cert-extension binding
 *   to a server-issued challenge, keyId/appId/counter/aaguid checks.
 *   On success the credential public key is stored in Redis.
 *
 * Assertion (per proxied request, via `checkAppAttest`):
 *   ECDSA signature over SHA256(authenticatorData ‖ clientDataHash)
 *   with the stored key, RP ID check, strictly-increasing counter
 *   (replay protection without a per-request server challenge).
 *   clientData is a client-generated blob carried in a header — the
 *   assertion authenticates the *caller*, not the request payload.
 *
 * Env vars:
 *   APP_ATTEST_MODE    — off | report | enforce. Default `report`:
 *                        verify and log when headers are present,
 *                        never reject. `enforce` requires a valid
 *                        assertion. IMPORTANT: keep off/report until
 *                        a real TestFlight build has round-tripped
 *                        registration + assertions in the logs —
 *                        this implementation is validated against
 *                        synthetic fixtures, not yet a real device.
 *   APP_ATTEST_APP_ID  — `<TeamID>.<BundleID>`. Required for any
 *                        verification; unset disables checks.
 *   APP_ATTEST_ALLOW_DEVELOPMENT — accept keys attested by the
 *                        development aaguid in enforce mode
 *                        (Xcode-run builds; TestFlight/App Store use
 *                        production).
 */
import { createHash, createVerify, timingSafeEqual, X509Certificate } from 'node:crypto';
import { decodeCBOR } from './cbor.js';
import { redisConfigured, redisPipeline } from './redis.js';

// Apple App Attestation Root CA (https://www.apple.com/certificateauthority/
// Apple_App_Attestation_Root_CA.pem, valid 2020-03-18 → 2045-03-15).
// Embedded because this runtime can't fetch at boot. Before flipping
// APP_ATTEST_MODE=enforce, re-download from Apple and diff against
// this constant — the unit test pins subject + validity as a
// corruption tripwire, but only a byte-for-byte diff proves identity.
export const APPLE_APP_ATTEST_ROOT_CA_PEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

const AAGUID_PRODUCTION = Buffer.concat([Buffer.from('appattest', 'utf8'), Buffer.alloc(7)]);
const AAGUID_DEVELOPMENT = Buffer.from('appattestdevelop', 'utf8');

// DER prefix of the credCert nonce extension value: the single-nonce
// encoding SEQUENCE(0x24){ [1](0x22){ OCTET STRING(0x20) } } that
// every App Attest leaf certificate carries under OID
// 1.2.840.113635.100.8.2. The OID's own DER follows for locating the
// extension inside the certificate.
const NONCE_VALUE_PREFIX = Buffer.from([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20]);
const NONCE_EXTENSION_OID_DER = Buffer.from([
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02,
]);

const sha256 = (data) => createHash('sha256').update(data).digest();

// Trust anchor for attestation chains. `APP_ATTEST_ROOT_CA_PEM`
// exists for integration tests and staging only — production
// deployments must leave it unset so the pinned Apple root applies.
const defaultRootCA = () => process.env.APP_ATTEST_ROOT_CA_PEM || APPLE_APP_ATTEST_ROOT_CA_PEM;

function fail(reason) {
  const err = new Error(reason);
  err.appAttest = true;
  return err;
}

function parseAuthData(authData, { requireCredential }) {
  if (!Buffer.isBuffer(authData) || authData.length < 37) throw fail('authData too short');
  const parsed = {
    rpIdHash: authData.subarray(0, 32),
    counter: authData.readUInt32BE(33),
  };
  if (requireCredential) {
    if (authData.length < 55) throw fail('authData missing credential data');
    parsed.aaguid = authData.subarray(37, 53);
    const credIdLength = authData.readUInt16BE(53);
    if (authData.length < 55 + credIdLength) throw fail('authData credentialId truncated');
    parsed.credentialId = authData.subarray(55, 55 + credIdLength);
  }
  return parsed;
}

function uncompressedPoint(keyObject) {
  const jwk = keyObject.export({ format: 'jwk' });
  if (jwk.kty !== 'EC' || jwk.crv !== 'P-256') throw fail('credCert key is not EC P-256');
  return Buffer.concat([
    Buffer.from([0x04]),
    Buffer.from(jwk.x, 'base64url'),
    Buffer.from(jwk.y, 'base64url'),
  ]);
}

function bufEqual(a, b) {
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * Verifies a registration-time attestation object. Returns
 * `{ publicKeyPem, environment }` or throws with a stable reason.
 * `rootCAPem` is injectable for tests; production callers use the
 * pinned Apple root.
 */
export function verifyAttestation({
  attestation,
  keyId,
  challenge,
  appId,
  rootCAPem = defaultRootCA(),
}) {
  const decoded = decodeCBOR(attestation);
  if (!(decoded instanceof Map) || decoded.get('fmt') !== 'apple-appattest') {
    throw fail('unexpected attestation format');
  }
  const attStmt = decoded.get('attStmt');
  const authData = decoded.get('authData');
  const x5c = attStmt instanceof Map ? attStmt.get('x5c') : null;
  if (!Array.isArray(x5c) || x5c.length < 2 || !Buffer.isBuffer(authData)) {
    throw fail('malformed attestation statement');
  }

  // 1. Certificate chain: credCert ← intermediate(s) ← pinned root.
  const root = new X509Certificate(rootCAPem);
  let certs;
  try {
    certs = x5c.map((der) => new X509Certificate(der));
  } catch {
    throw fail('unparseable certificate in x5c');
  }
  const now = new Date();
  for (const cert of certs) {
    if (now < new Date(cert.validFrom) || now > new Date(cert.validTo)) {
      throw fail('certificate outside validity window');
    }
  }
  for (let i = 0; i < certs.length - 1; i += 1) {
    if (!certs[i].verify(certs[i + 1].publicKey)) throw fail('broken certificate chain');
  }
  if (!certs[certs.length - 1].verify(root.publicKey)) throw fail('chain does not reach Apple root');

  // 2-3. Nonce binding: the credCert carries
  // SHA256(authData ‖ SHA256(challenge)) in the Apple extension.
  const credCert = certs[0];
  const nonce = sha256(Buffer.concat([authData, sha256(challenge)]));
  const raw = credCert.raw;
  const oidIndex = raw.indexOf(NONCE_EXTENSION_OID_DER);
  if (oidIndex === -1) throw fail('nonce extension missing');
  // The extension value follows within a few bytes of the OID
  // (optional critical flag + OCTET STRING wrapper); locate the
  // canonical single-nonce DER prefix and compare what follows.
  const window = raw.subarray(oidIndex, oidIndex + NONCE_EXTENSION_OID_DER.length + 16);
  const prefixAt = window.indexOf(NONCE_VALUE_PREFIX);
  if (prefixAt === -1) throw fail('nonce extension malformed');
  const embedded = raw.subarray(
    oidIndex + prefixAt + NONCE_VALUE_PREFIX.length,
    oidIndex + prefixAt + NONCE_VALUE_PREFIX.length + 32
  );
  if (!bufEqual(embedded, nonce)) throw fail('nonce mismatch');

  // 4. keyId is the SHA256 of the credential public key.
  if (!bufEqual(sha256(uncompressedPoint(credCert.publicKey)), keyId)) {
    throw fail('keyId does not match credential key');
  }

  // 5-8. authData: RP ID, fresh counter, environment, credentialId.
  const parsed = parseAuthData(authData, { requireCredential: true });
  if (!bufEqual(parsed.rpIdHash, sha256(Buffer.from(appId, 'utf8')))) throw fail('appId mismatch');
  if (parsed.counter !== 0) throw fail('attestation counter not zero');
  let environment;
  if (parsed.aaguid.equals(AAGUID_PRODUCTION)) environment = 'production';
  else if (parsed.aaguid.equals(AAGUID_DEVELOPMENT)) environment = 'development';
  else throw fail('unknown aaguid');
  if (!bufEqual(parsed.credentialId, keyId)) throw fail('credentialId mismatch');

  return {
    publicKeyPem: credCert.publicKey.export({ type: 'spki', format: 'pem' }),
    environment,
  };
}

/**
 * Verifies a per-request assertion against a stored public key.
 * Returns `{ counter }` (caller persists it) or throws.
 */
export function verifyAssertion({ assertion, publicKeyPem, clientDataHash, appId, previousCounter }) {
  const decoded = decodeCBOR(assertion);
  if (!(decoded instanceof Map)) throw fail('malformed assertion');
  const signature = decoded.get('signature');
  const authData = decoded.get('authenticatorData');
  if (!Buffer.isBuffer(signature) || !Buffer.isBuffer(authData)) throw fail('malformed assertion');

  const nonce = sha256(Buffer.concat([authData, clientDataHash]));
  const verifier = createVerify('SHA256');
  verifier.update(nonce);
  if (!verifier.verify(publicKeyPem, signature)) throw fail('bad assertion signature');

  const parsed = parseAuthData(authData, { requireCredential: false });
  if (!bufEqual(parsed.rpIdHash, sha256(Buffer.from(appId, 'utf8')))) throw fail('appId mismatch');
  if (parsed.counter <= previousCounter) throw fail('assertion counter replayed');
  return { counter: parsed.counter };
}

// MARK: Key registry (Redis)

const keySlot = (keyIdB64) => `attest:key:${keyIdB64}`;

export async function storeAttestKey(keyIdB64, record) {
  const results = await redisPipeline([['SET', keySlot(keyIdB64), JSON.stringify(record)]]);
  return results?.[0]?.result === 'OK';
}

export async function loadAttestKey(keyIdB64) {
  const results = await redisPipeline([['GET', keySlot(keyIdB64)]]);
  const raw = results?.[0]?.result;
  if (typeof raw !== 'string') return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

// Read-modify-write without a transaction: two truly concurrent
// requests can both pass the counter check before either write
// lands. The window is one in-flight request per key; counters still
// only move forward, so a captured assertion stops replaying the
// moment any newer one is seen. Accepted.
async function persistCounter(keyIdB64, record, counter) {
  await redisPipeline([['SET', keySlot(keyIdB64), JSON.stringify({ ...record, counter })]]);
}

// MARK: Per-request gate

const CLIENT_DATA_MAX_AGE_MS = 5 * 60 * 1000;

function attestMode() {
  const mode = (process.env.APP_ATTEST_MODE || 'report').toLowerCase();
  return ['off', 'report', 'enforce'].includes(mode) ? mode : 'report';
}

/**
 * Checks the App Attest assertion headers on a proxied request.
 *
 * Returns `{ ok, reason?, keyId? }`; `ok: false` only ever in enforce
 * mode, and callers reject with 401 when it is. `keyId` is set only
 * when an assertion actually verified — it's the one per-install
 * identity the server can trust, so the rate limiter keys on it in
 * preference to the client IP (which rotates freely on mobile data
 * and behind VPNs, making per-IP limits close to meaningless for a
 * determined caller).
 */
export async function checkAppAttest(req, { logLabel }) {
  const mode = attestMode();
  if (mode === 'off') return { ok: true };

  const appId = process.env.APP_ATTEST_APP_ID;
  const enforce = mode === 'enforce';
  const deny = (reason) => {
    console.warn(`[${logLabel}] app-attest ${enforce ? 'reject' : 'report'}: ${reason}`);
    return enforce ? { ok: false, reason } : { ok: true };
  };

  if (!appId) {
    // Misconfiguration must not lock the API: log and pass.
    console.error(`[${logLabel}] APP_ATTEST_MODE set but APP_ATTEST_APP_ID missing`);
    return { ok: true };
  }

  const keyIdB64 = req.headers['x-attest-key-id'];
  const assertionB64 = req.headers['x-attest-assertion'];
  const clientDataB64 = req.headers['x-attest-client-data'];
  if (!keyIdB64 || !assertionB64 || !clientDataB64) return deny('assertion headers missing');

  if (!redisConfigured()) {
    // No key registry → nothing to verify against. Fail open so a
    // Redis outage degrades to secret-only auth instead of downtime.
    console.error(`[${logLabel}] app-attest skipped: redis not configured`);
    return { ok: true };
  }

  const clientData = Buffer.from(String(clientDataB64), 'base64');
  // clientData = 16 random bytes ‖ uint64BE millisecond timestamp.
  // The staleness bound is a cheap sanity check; real replay
  // protection is the strictly-increasing counter below.
  if (clientData.length !== 24) return deny('bad client data');
  const stampedAt = Number(clientData.readBigUInt64BE(16));
  if (Math.abs(Date.now() - stampedAt) > CLIENT_DATA_MAX_AGE_MS) return deny('stale client data');

  const record = await loadAttestKey(String(keyIdB64));
  if (!record) return deny('unknown attest key');
  if (record.environment === 'development' && enforce && process.env.APP_ATTEST_ALLOW_DEVELOPMENT !== '1') {
    return deny('development key in enforce mode');
  }

  try {
    const { counter } = verifyAssertion({
      assertion: Buffer.from(String(assertionB64), 'base64'),
      publicKeyPem: record.publicKeyPem,
      clientDataHash: sha256(clientData),
      appId,
      previousCounter: record.counter ?? 0,
    });
    await persistCounter(String(keyIdB64), record, counter);
    if (!enforce) console.log(`[${logLabel}] app-attest ok (counter ${counter})`);
    return { ok: true, keyId: String(keyIdB64) };
  } catch (err) {
    return deny(err?.appAttest ? err.message : 'assertion verification error');
  }
}
