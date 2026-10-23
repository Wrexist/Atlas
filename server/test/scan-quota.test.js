import test from 'node:test';
import assert from 'node:assert/strict';
import handler from '../api/food-scan.js';
import { chargeScan, isoWeek, quotaWeek } from '../api/_lib/scan-quota.js';
import { fakeUpstash, REDIS_ENV, setEnv } from '../testutil/attest-fixtures.js';
import { makeStoreKitChain, signTransaction, transactionPayload } from '../testutil/storekit-fixtures.js';

const HOUR = 60 * 60 * 1000;
const INSTALL_ID = '6F9619FF-8B86-D011-B42D-00C04FC964FF';
const chain = makeStoreKitChain();

const BASE_ENV = {
  PROXY_SHARED_SECRET: 'test-secret',
  ANTHROPIC_API_KEY: 'test-key',
  ...REDIS_ENV,
  KV_REST_API_URL: undefined,
  KV_REST_API_TOKEN: undefined,
  ANTHROPIC_DAILY_REQUEST_BUDGET: '0',
  DEVICE_DAILY_QUOTA: '0',
  RATE_LIMIT_RPM: '1000',
  APP_ATTEST_MODE: 'off',
  FREE_SCANS_PER_WEEK: undefined,
  STOREKIT_ROOT_CA_FINGERPRINT: chain.rootFingerprint,
  STOREKIT_BUNDLE_ID: undefined,
};

const MEAL = {
  kind: 'meal', title: 'Toast', summary: '', package: null, tips: [], questions: [],
  items: [{ name: 'Toast', grams: 40 }],
};
const NOT_FOOD = { ...MEAL, kind: 'not_food', items: [] };

// Upstash double for the counters plus a canned Anthropic answer; the
// answer is swappable so one test can mix hits and misses.
function stubBackends(t) {
  const store = fakeUpstash(t);
  const upstash = globalThis.fetch;
  const upstream = { result: MEAL, calls: 0 };
  globalThis.fetch = async (url, init) => {
    if (String(url).startsWith(REDIS_ENV.UPSTASH_REDIS_REST_URL)) return upstash(url, init);
    upstream.calls += 1;
    const message = { model: 'm', stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify(upstream.result) }] };
    return new Response(JSON.stringify(message), { status: 200, headers: { 'content-type': 'application/json' } });
  };
  t.after(() => { globalThis.fetch = upstash; });
  return { store, upstream };
}

function scanReq({ ip = '10.9.0.1', installId = INSTALL_ID, metered = true, entitlement } = {}) {
  const headers = { 'x-peptide-proxy': 'test-secret', 'x-real-ip': ip, 'content-length': '100' };
  if (metered) headers['x-atlas-scan-metered'] = '1';
  if (installId) headers['x-atlas-install-id'] = installId;
  if (entitlement) headers['x-atlas-entitlement'] = entitlement;
  return { method: 'POST', headers, socket: {}, body: { mode: 'photo', image: 'AAAA' } };
}

function makeRes() {
  return {
    statusCode: null,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
    setHeader() {},
    send(payload) { this.body = payload; },
  };
}

async function scan(req) {
  const res = makeRes();
  await handler(req, res);
  return res;
}

test('test_isoWeek_followsIsoYearBoundaries', () => {
  assert.equal(isoWeek(new Date('2026-10-21T12:00:00Z')), '2026-W43');
  assert.equal(isoWeek(new Date('2021-01-03T12:00:00Z')), '2020-W53');
  assert.equal(isoWeek(new Date('2024-12-30T00:00:00Z')), '2025-W01');
});

test('test_quotaWeek_acceptsOnlyAWeekSomeTimeZoneIsIn', () => {
  // Sunday 20:00 UTC: Kiribati (UTC+14) is already in the next week.
  const now = Date.parse('2026-10-25T20:00:00Z');
  assert.equal(quotaWeek('2026-W44', now), '2026-W44');
  assert.equal(quotaWeek('2026-W43', now), '2026-W43');
  assert.equal(quotaWeek('2026-W45', now), '2026-W43');
  assert.equal(quotaWeek('garbage', now), '2026-W43');
  assert.equal(quotaWeek(undefined, now + 12 * HOUR), '2026-W44');
});

test('test_freeInstall_getsThreeScans_thenScanQuota429', async (t) => {
  setEnv(t, BASE_ENV);
  const { upstream } = stubBackends(t);
  for (let i = 0; i < 3; i += 1) {
    assert.equal((await scan(scanReq())).statusCode, 200);
  }
  const refused = await scan(scanReq());
  assert.equal(refused.statusCode, 429);
  assert.equal(refused.body.error.code, 'scan_quota');
  assert.equal(upstream.calls, 3, 'a refused scan never reaches Anthropic');
});

test('test_reinstall_keepsCount_becauseInstallIdOutlivesTheApp', async (t) => {
  setEnv(t, { ...BASE_ENV, FREE_SCANS_PER_WEEK: '1' });
  stubBackends(t);
  const installId = '11111111-2222-3333-4444-555555555555';
  assert.equal((await scan(scanReq({ ip: '10.9.1.1', installId }))).statusCode, 200);
  // New IP, same Keychain ID: still the same install.
  assert.equal((await scan(scanReq({ ip: '10.9.1.2', installId: installId.toLowerCase() }))).statusCode, 429);
});

test('test_scanWithoutFood_isRefunded', async (t) => {
  setEnv(t, { ...BASE_ENV, FREE_SCANS_PER_WEEK: '1' });
  const { upstream } = stubBackends(t);
  const installId = '22222222-2222-3333-4444-555555555555';
  upstream.result = NOT_FOOD;
  assert.equal((await scan(scanReq({ installId }))).statusCode, 200);
  upstream.result = MEAL;
  assert.equal((await scan(scanReq({ installId }))).statusCode, 200);
  assert.equal((await scan(scanReq({ installId }))).statusCode, 429);
});

test('test_scanQuotaRefusal_givesBackTheDeviceQuotaItCharged', async (t) => {
  setEnv(t, { ...BASE_ENV, FREE_SCANS_PER_WEEK: '1', DEVICE_DAILY_QUOTA: '1000' });
  const { store } = stubBackends(t);
  const installId = '66666666-2222-3333-4444-555555555555';
  const deviceSpend = () => [...store.entries()]
    .filter(([key]) => key.includes('quota:device'))
    .map(([, value]) => Number(value));
  assert.equal((await scan(scanReq({ ip: '10.9.3.1', installId }))).statusCode, 200);
  const afterScan = deviceSpend();
  assert.equal(afterScan.length, 1);
  assert.equal((await scan(scanReq({ ip: '10.9.3.1', installId }))).statusCode, 429);
  assert.deepEqual(deviceSpend(), afterScan);
});

test('test_budgetRefusal_refundsTheFreeScan', async (t) => {
  setEnv(t, { ...BASE_ENV, FREE_SCANS_PER_WEEK: '1', ANTHROPIC_DAILY_REQUEST_BUDGET: '1' });
  const { store } = stubBackends(t);
  const installId = '77777777-2222-3333-4444-555555555555';
  assert.equal((await scan(scanReq({ installId }))).statusCode, 503);
  const scanCounts = [...store.entries()]
    .filter(([key]) => key.startsWith('scanq:'))
    .map(([, value]) => Number(value));
  assert.deepEqual(scanCounts, [0]);
});

test('test_unmeteredRequests_areNeverCounted', async (t) => {
  setEnv(t, { ...BASE_ENV, FREE_SCANS_PER_WEEK: '1' });
  const { store } = stubBackends(t);
  const installId = '33333333-2222-3333-4444-555555555555';
  for (let i = 0; i < 3; i += 1) {
    assert.equal((await scan(scanReq({ installId, metered: false }))).statusCode, 200);
  }
  assert.ok(![...store.keys()].some((key) => key.startsWith('scanq:')));
});

test('test_verifiedProEntitlement_skipsQuota_butForgedOneDoesNot', async (t) => {
  setEnv(t, { ...BASE_ENV, FREE_SCANS_PER_WEEK: '1' });
  stubBackends(t);
  const pro = signTransaction(chain, transactionPayload());
  const proId = '44444444-2222-3333-4444-555555555555';
  for (let i = 0; i < 3; i += 1) {
    assert.equal((await scan(scanReq({ installId: proId, entitlement: pro }))).statusCode, 200);
  }
  const forged = signTransaction(makeStoreKitChain(), transactionPayload());
  const freeId = '55555555-2222-3333-4444-555555555555';
  assert.equal((await scan(scanReq({ installId: freeId, entitlement: forged }))).statusCode, 200);
  assert.equal((await scan(scanReq({ installId: freeId, entitlement: forged }))).statusCode, 429);
});

test('test_missingInstallId_fallsBackToRequestPrincipal', async (t) => {
  setEnv(t, { ...BASE_ENV, FREE_SCANS_PER_WEEK: '1' });
  stubBackends(t);
  assert.equal((await scan(scanReq({ ip: '10.9.2.1', installId: 'not-a-uuid' }))).statusCode, 200);
  assert.equal((await scan(scanReq({ ip: '10.9.2.1', installId: null }))).statusCode, 429);
  assert.equal((await scan(scanReq({ ip: '10.9.2.2', installId: null }))).statusCode, 200);
});

test('test_noStoreConfigured_failsOpen', async (t) => {
  setEnv(t, { ...BASE_ENV, UPSTASH_REDIS_REST_URL: undefined, UPSTASH_REDIS_REST_TOKEN: undefined });
  const verdict = await chargeScan(scanReq(), { principal: 'ip:x', logLabel: 'test' });
  assert.equal(verdict.allowed, true);
});

test('test_storeUnreachable_failsOpen', async (t) => {
  setEnv(t, BASE_ENV);
  const real = globalThis.fetch;
  globalThis.fetch = async () => { throw new Error('ECONNREFUSED'); };
  t.after(() => { globalThis.fetch = real; });
  const verdict = await chargeScan(scanReq(), { principal: 'ip:x', logLabel: 'test' });
  assert.equal(verdict.allowed, true);
});
