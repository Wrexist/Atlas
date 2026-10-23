import test from 'node:test';
import assert from 'node:assert/strict';
import handler from '../api/ai-research.js';
import { makeStoreKitChain, signTransaction, transactionPayload } from '../testutil/storekit-fixtures.js';

const chain = makeStoreKitChain();
const PRO = { 'x-atlas-entitlement': signTransaction(chain, transactionPayload()) };

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

const BASE_ENV = {
  PROXY_SHARED_SECRET: 'test-secret',
  ANTHROPIC_API_KEY: 'test-key',
  UPSTASH_REDIS_REST_URL: undefined,
  UPSTASH_REDIS_REST_TOKEN: undefined,
  KV_REST_API_URL: undefined,
  KV_REST_API_TOKEN: undefined,
  ANTHROPIC_DAILY_REQUEST_BUDGET: undefined,
  ALLOWED_MODELS: undefined,
  RATE_LIMIT_RPM: '1000',
  SHARED_IP_LIMIT_SCALE: '1',
  DEVICE_DAILY_QUOTA: undefined,
  APP_ATTEST_MODE: 'off',
  STOREKIT_ROOT_CA_FINGERPRINT: chain.rootFingerprint,
  STOREKIT_BUNDLE_ID: undefined,
  PRO_GATE_MODE: undefined,
};

function stubUpstream(t) {
  const real = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (...args) => {
    calls.push(args);
    return new Response(
      JSON.stringify({ stop_reason: 'end_turn', content: [{ type: 'text', text: 'HRV is beat-to-beat variation.' }] }),
      { status: 200, headers: { 'content-type': 'application/json' } }
    );
  };
  t.after(() => { globalThis.fetch = real; });
  return calls;
}

function makeReq(ip, headers = {}) {
  return {
    method: 'POST',
    headers: {
      'x-peptide-proxy': 'test-secret',
      'x-real-ip': ip,
      'content-length': '100',
      'content-type': 'application/json',
      ...headers,
    },
    socket: {},
    body: { messages: [{ role: 'user', content: 'What is HRV?' }] },
  };
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

test('test_aiResearch_withVerifiedProEntitlement_reachesUpstream', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubUpstream(t);
  const res = makeRes();
  await handler(makeReq('10.3.0.1', PRO), res);
  assert.equal(res.statusCode, 200);
  assert.equal(calls.length, 1);
});

test('test_aiResearch_withoutVerifiedProEntitlement_isRefused403BeforeUpstream', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubUpstream(t);
  const forged = { 'x-atlas-entitlement': signTransaction(makeStoreKitChain(), transactionPayload()) };
  for (const headers of [{}, forged]) {
    const res = makeRes();
    await handler(makeReq('10.3.0.2', headers), res);
    assert.equal(res.statusCode, 403);
    assert.equal(res.body.error.code, 'pro_required');
  }
  assert.equal(calls.length, 0);
});

test('test_aiResearch_proGateReportMode_letsUnverifiedQuestionThrough', async (t) => {
  setEnv(t, { ...BASE_ENV, PRO_GATE_MODE: 'report' });
  const calls = stubUpstream(t);
  const res = makeRes();
  await handler(makeReq('10.3.0.3'), res);
  assert.equal(res.statusCode, 200);
  assert.equal(calls.length, 1);
});
