/**
 * StoreKit 2 signed-transaction fixtures for the scan-quota suites.
 * Lives outside `test/` so `node --test` never runs it as a test file.
 * The chain (test root → intermediate → leaf) is minted with the
 * openssl CLI and carries Apple's marker OIDs, so only the pinned root
 * fingerprint separates it from a real App Store JWS — tests point
 * `STOREKIT_ROOT_CA_FINGERPRINT` at `rootFingerprint` to trust it.
 */
import { execFileSync } from 'node:child_process';
import { createSign, X509Certificate } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export function makeStoreKitChain({ leafMarker = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'storekit-'));
  const sh = (args) => execFileSync('openssl', args, { cwd: dir, stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    sh(['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'root.key']);
    sh(['req', '-new', '-x509', '-key', 'root.key', '-subj', '/CN=Test StoreKit Root', '-days', '30', '-out', 'root.pem']);
    sh(['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'int.key']);
    sh(['req', '-new', '-key', 'int.key', '-subj', '/CN=Test WWDR', '-out', 'int.csr']);
    writeFileSync(join(dir, 'int.cnf'), 'basicConstraints=CA:TRUE\n1.2.840.113635.100.6.2.1=ASN1:NULL\n');
    sh(['x509', '-req', '-in', 'int.csr', '-CA', 'root.pem', '-CAkey', 'root.key', '-CAcreateserial', '-days', '30', '-extfile', 'int.cnf', '-out', 'int.pem']);
    sh(['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'leaf.key']);
    sh(['req', '-new', '-key', 'leaf.key', '-subj', '/CN=Test StoreKit Signing', '-out', 'leaf.csr']);
    writeFileSync(join(dir, 'leaf.cnf'), leafMarker ? '1.2.840.113635.100.6.11.1=ASN1:NULL\n' : 'basicConstraints=CA:FALSE\n');
    sh(['x509', '-req', '-in', 'leaf.csr', '-CA', 'int.pem', '-CAkey', 'int.key', '-CAcreateserial', '-days', '30', '-extfile', 'leaf.cnf', '-out', 'leaf.pem']);

    const der = (name) => new X509Certificate(readFileSync(join(dir, name))).raw.toString('base64');
    return {
      x5c: [der('leaf.pem'), der('int.pem'), der('root.pem')],
      leafKeyPem: readFileSync(join(dir, 'leaf.key'), 'utf8'),
      rootFingerprint: new X509Certificate(readFileSync(join(dir, 'root.pem'))).fingerprint256,
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

export function transactionPayload(overrides = {}) {
  const now = Date.now();
  return {
    bundleId: 'com.peptidesai.app',
    productId: 'com.peptidesai.app.pro.monthly',
    signedDate: now,
    expiresDate: now + 30 * 24 * 60 * 60 * 1000,
    environment: 'Production',
    ...overrides,
  };
}

export function signTransaction(chain, payload) {
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', x5c: chain.x5c })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = createSign('SHA256')
    .update(`${header}.${body}`)
    .sign({ key: chain.leafKeyPem, dsaEncoding: 'ieee-p1363' })
    .toString('base64url');
  return `${header}.${body}.${signature}`;
}
