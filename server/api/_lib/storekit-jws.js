/**
 * Verifies a StoreKit 2 signed transaction (the JWS the app reads from
 * `VerificationResult.jwsRepresentation`) so the proxy can tell a Pro
 * subscriber from a free user without trusting a client-asserted flag.
 *
 * Checks, in order: the x5c chain leaf ← intermediate ← root, with the
 * root pinned by its SHA-256 fingerprint (Apple Root CA - G3) and each
 * certificate carrying Apple's marker OID; the ES256 signature over the
 * JWS with the leaf key; then the payload — bundle ID, a Pro product,
 * not revoked, not expired beyond the billing grace window.
 *
 * Env vars:
 *   STOREKIT_BUNDLE_ID   — expected `bundleId`. Default com.peptidesai.app.
 *   STOREKIT_ROOT_CA_FINGERPRINT
 *                        — integration tests and staging only; production
 *                          must leave it unset so the Apple root applies.
 *
 * A valid JWS is a bearer credential: anyone holding a subscriber's JWS
 * passes this check until it expires. That bounds the damage to free
 * scans and is the proportionate trade-off against calling the App Store
 * Server API on every scan.
 */
import { verify, X509Certificate } from 'node:crypto';

// SHA-256 of Apple Root CA - G3
// (https://www.apple.com/certificateauthority/AppleRootCA-G3.cer), the
// anchor Apple's own App Store Server Library pins for StoreKit JWS.
export const APPLE_ROOT_CA_G3_FINGERPRINT =
  '63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79';

// Apple marks the StoreKit signing leaf with 1.2.840.113635.100.6.11.1
// and its intermediate (Apple WWDR) with 1.2.840.113635.100.6.2.1. DER
// of each OID, located in the raw certificate bytes.
const LEAF_MARKER_OID = Buffer.from([0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x0b, 0x01]);
const INTERMEDIATE_MARKER_OID = Buffer.from([0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x02, 0x01]);

// Mirrors StoreService.monthlyID / annualID / lifetimeID.
export const PRO_PRODUCT_IDS = new Set([
  'com.peptidesai.app.pro.monthly',
  'com.peptidesai.app.pro.annual',
  'com.peptidesai.app.pro.lifetime',
]);

// Apple's longest billing grace period. The app keeps Pro through grace
// (StoreService), but the JWS alone cannot show grace state, so the proxy
// allows the full window rather than meter a paying user whose card
// hiccupped.
const GRACE_MS = 16 * 24 * 60 * 60 * 1000;

const rootFingerprint = () => process.env.STOREKIT_ROOT_CA_FINGERPRINT || APPLE_ROOT_CA_G3_FINGERPRINT;

function fail(reason) {
  const err = new Error(reason);
  err.storeKit = true;
  return err;
}

function decodeSegment(segment) {
  try {
    return JSON.parse(Buffer.from(segment, 'base64url').toString('utf8'));
  } catch {
    throw fail('unparseable JWS segment');
  }
}

function verifyChain(x5c, signedAt) {
  if (!Array.isArray(x5c) || x5c.length !== 3) throw fail('x5c must hold three certificates');
  let leaf;
  let intermediate;
  let root;
  try {
    [leaf, intermediate, root] = x5c.map((b64) => new X509Certificate(Buffer.from(b64, 'base64')));
  } catch {
    throw fail('unparseable certificate in x5c');
  }
  if (root.fingerprint256 !== rootFingerprint()) throw fail('chain does not reach Apple root');
  if (!root.verify(root.publicKey)) throw fail('root is not self-signed');
  if (!intermediate.verify(root.publicKey)) throw fail('broken certificate chain');
  if (!leaf.verify(intermediate.publicKey)) throw fail('broken certificate chain');
  if (!leaf.raw.includes(LEAF_MARKER_OID)) throw fail('leaf is not a StoreKit signing certificate');
  if (!intermediate.raw.includes(INTERMEDIATE_MARKER_OID)) throw fail('intermediate is not Apple WWDR');
  // Checked at the signing time, as Apple's library does: a transaction
  // signed while the leaf was valid stays valid after the leaf rotates.
  for (const cert of [leaf, intermediate, root]) {
    if (signedAt < new Date(cert.validFrom) || signedAt > new Date(cert.validTo)) {
      throw fail('certificate outside validity window');
    }
  }
  return leaf;
}

/**
 * Returns the decoded transaction payload when `jws` proves an active Pro
 * entitlement for this app; throws with a stable `reason` otherwise.
 */
export function verifyProTransaction(jws, { now = Date.now() } = {}) {
  if (typeof jws !== 'string') throw fail('missing JWS');
  const parts = jws.split('.');
  if (parts.length !== 3) throw fail('malformed JWS');
  const [headerB64, payloadB64, signatureB64] = parts;

  const header = decodeSegment(headerB64);
  if (header.alg !== 'ES256') throw fail('unexpected JWS algorithm');
  const payload = decodeSegment(payloadB64);

  const signedAt = new Date(Number(payload.signedDate) || now);
  const leaf = verifyChain(header.x5c, signedAt);
  const signatureOk = verify(
    'sha256',
    Buffer.from(`${headerB64}.${payloadB64}`, 'ascii'),
    { key: leaf.publicKey, dsaEncoding: 'ieee-p1363' },
    Buffer.from(signatureB64, 'base64url')
  );
  if (!signatureOk) throw fail('bad JWS signature');

  if (payload.bundleId !== (process.env.STOREKIT_BUNDLE_ID || 'com.peptidesai.app')) throw fail('wrong bundle');
  if (!PRO_PRODUCT_IDS.has(payload.productId)) throw fail('not a Pro product');
  if (payload.revocationDate) throw fail('transaction revoked');
  if (payload.expiresDate !== undefined && Number(payload.expiresDate) + GRACE_MS < now) {
    throw fail('entitlement expired');
  }
  return payload;
}
