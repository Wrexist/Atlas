import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyProTransaction } from '../api/_lib/storekit-jws.js';
import { setEnv } from '../testutil/attest-fixtures.js';
import { makeStoreKitChain, signTransaction, transactionPayload } from '../testutil/storekit-fixtures.js';

const chain = makeStoreKitChain();
const DAY = 24 * 60 * 60 * 1000;

function trustTestRoot(t) {
  setEnv(t, { STOREKIT_ROOT_CA_FINGERPRINT: chain.rootFingerprint, STOREKIT_BUNDLE_ID: undefined });
}

function rejects(jws, reason) {
  assert.throws(() => verifyProTransaction(jws), (err) => err.storeKit === true && err.message === reason);
}

test('test_activeProSubscription_verifies', (t) => {
  trustTestRoot(t);
  const payload = verifyProTransaction(signTransaction(chain, transactionPayload()));
  assert.equal(payload.productId, 'com.peptidesai.app.pro.monthly');
});

test('test_lifetimePurchaseWithoutExpiry_verifies', (t) => {
  trustTestRoot(t);
  const jws = signTransaction(chain, transactionPayload({
    productId: 'com.peptidesai.app.pro.lifetime', expiresDate: undefined,
  }));
  assert.equal(verifyProTransaction(jws).productId, 'com.peptidesai.app.pro.lifetime');
});

test('test_chainNotFromAppleRoot_isRejectedByDefault', (t) => {
  setEnv(t, { STOREKIT_ROOT_CA_FINGERPRINT: undefined });
  rejects(signTransaction(chain, transactionPayload()), 'chain does not reach Apple root');
});

test('test_tamperedPayload_failsSignature', (t) => {
  trustTestRoot(t);
  const [header, , signature] = signTransaction(chain, transactionPayload()).split('.');
  const forged = Buffer.from(JSON.stringify(transactionPayload({ productId: 'com.peptidesai.app.pro.lifetime' })))
    .toString('base64url');
  rejects(`${header}.${forged}.${signature}`, 'bad JWS signature');
});

test('test_leafWithoutStoreKitMarker_isRejected', (t) => {
  const unmarked = makeStoreKitChain({ leafMarker: false });
  setEnv(t, { STOREKIT_ROOT_CA_FINGERPRINT: unmarked.rootFingerprint });
  rejects(signTransaction(unmarked, transactionPayload()), 'leaf is not a StoreKit signing certificate');
});

test('test_payloadChecks_rejectOtherAppsProductsAndLapsedAccess', (t) => {
  trustTestRoot(t);
  rejects(signTransaction(chain, transactionPayload({ bundleId: 'com.example.other' })), 'wrong bundle');
  rejects(signTransaction(chain, transactionPayload({ productId: 'com.peptidesai.app.tip' })), 'not a Pro product');
  rejects(signTransaction(chain, transactionPayload({ revocationDate: Date.now() })), 'transaction revoked');
  rejects(signTransaction(chain, transactionPayload({ expiresDate: Date.now() - 17 * DAY })), 'entitlement expired');
});

test('test_expiredInsideGraceWindow_stillVerifies', (t) => {
  trustTestRoot(t);
  const jws = signTransaction(chain, transactionPayload({ expiresDate: Date.now() - 3 * DAY }));
  assert.ok(verifyProTransaction(jws));
});

test('test_malformedInput_isRejectedWithStableReasons', (t) => {
  trustTestRoot(t);
  rejects(undefined, 'missing JWS');
  rejects('a.b', 'malformed JWS');
  rejects('!!.!!.!!', 'unparseable JWS segment');
  const header = Buffer.from(JSON.stringify({ alg: 'none', x5c: chain.x5c })).toString('base64url');
  rejects(`${header}.e30.`, 'unexpected JWS algorithm');
  const noChain = Buffer.from(JSON.stringify({ alg: 'ES256' })).toString('base64url');
  rejects(`${noChain}.e30.`, 'x5c must hold three certificates');
});
