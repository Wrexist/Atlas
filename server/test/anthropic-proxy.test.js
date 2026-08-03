import test from 'node:test';
import assert from 'node:assert/strict';
import { forwardToAnthropic } from '../api/_lib/anthropic-proxy.js';

// Handler-level wiring tests on the in-memory limiter path (no Redis
// env). Each test uses its own logLabel and client IPs so the module's
// process-wide per-IP buckets stay isolated. The daily-budget bucket
// is global by design, so exactly one test exercises it.

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
  RATE_LIMIT_RPM: undefined,
  APP_ATTEST_MODE: 'off',
  APP_ATTEST_APP_ID: undefined,
};

function stubUpstream(t) {
  const real = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (...args) => {
    calls.push(args);
    return new Response('{"content":[{"type":"text","text":"ok"}]}', {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  };
  t.after(() => {
    globalThis.fetch = real;
  });
  return calls;
}

function makeReq(ip) {
  return {
    method: 'POST',
    headers: {
      'x-peptide-proxy': 'test-secret',
      'x-real-ip': ip,
      'content-length': '100',
    },
    socket: {},
    body: { messages: [{ role: 'user', content: 'hi' }] },
  };
}

function makeRes() {
  return {
    statusCode: null,
    body: null,
    headers: {},
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
    setHeader(name, value) {
      this.headers[name] = value;
    },
    send(payload) {
      this.body = payload;
    },
  };
}

async function forward(req, logLabel) {
  const res = makeRes();
  await forwardToAnthropic(req, res, { logLabel });
  return res;
}

test('over-RPM request is rejected 429 before reaching Anthropic', async (t) => {
  setEnv(t, { ...BASE_ENV, RATE_LIMIT_RPM: '1' });
  const upstream = stubUpstream(t);

  const first = await forward(makeReq('10.0.0.1'), 'test-rpm');
  assert.equal(first.statusCode, 200);

  const second = await forward(makeReq('10.0.0.1'), 'test-rpm');
  assert.equal(second.statusCode, 429);

  assert.equal(upstream.length, 1);
});

test('enforce mode rejects requests without assertion headers', async (t) => {
  setEnv(t, {
    ...BASE_ENV,
    APP_ATTEST_MODE: 'enforce',
    APP_ATTEST_APP_ID: 'TEAM12345.com.peptidesai.app',
  });
  const upstream = stubUpstream(t);

  const denied = await forward(makeReq('10.0.0.9'), 'test-attest');
  assert.equal(denied.statusCode, 401);
  assert.equal(denied.body.error.code, 'attest_required');
  assert.equal(upstream.length, 0);

  // Report mode (the default) must not block the same request.
  setEnv(t, { APP_ATTEST_MODE: 'report' });
  const reported = await forward(makeReq('10.0.0.10'), 'test-attest');
  assert.equal(reported.statusCode, 200);
});

test('daily budget fails closed and only upstream-bound requests spend it', async (t) => {
  setEnv(t, { ...BASE_ENV, ANTHROPIC_DAILY_REQUEST_BUDGET: '2' });
  const upstream = stubUpstream(t);

  // 1st valid request → budget 1/2.
  const a = await forward(makeReq('10.0.0.2'), 'test-budget');
  assert.equal(a.statusCode, 200);

  // Malformed body → 400 before the budget gate; must not spend.
  const badReq = makeReq('10.0.0.3');
  badReq.body = { messages: [] };
  const b = await forward(badReq, 'test-budget');
  assert.equal(b.statusCode, 400);

  // 2nd valid request still fits → budget 2/2. Fails if the 400 spent.
  const c = await forward(makeReq('10.0.0.4'), 'test-budget');
  assert.equal(c.statusCode, 200);

  // Budget spent → 503, regardless of IP.
  const d = await forward(makeReq('10.0.0.5'), 'test-budget');
  assert.equal(d.statusCode, 503);

  assert.equal(upstream.length, 2);
});

// ---------------------------------------------------------------------------
// Abuse containment, end to end through the handler.
//
// The scenario each of these is about: someone pulls the shared secret out of
// the .ipa and scripts the endpoint. Rate limiting alone doesn't stop that —
// a script simply retries at the limit forever. These are the controls that
// bound both the bill and the damage to everyone else.
// ---------------------------------------------------------------------------

test('one abusive caller is capped by daily quota without affecting others', async (t) => {
  setEnv(t, { ...BASE_ENV, DEVICE_DAILY_QUOTA: '3', RATE_LIMIT_RPM: '1000' });
  const upstream = stubUpstream(t);

  for (let i = 0; i < 3; i += 1) {
    assert.equal((await forward(makeReq('9.9.9.1'), 'quota-e2e')).statusCode, 200);
  }
  const denied = await forward(makeReq('9.9.9.1'), 'quota-e2e');
  assert.equal(denied.statusCode, 429);
  assert.match(denied.body.error.message, /Daily limit/);

  // A different caller is untouched — the abuser spends their own
  // allowance, not the shared one.
  assert.equal((await forward(makeReq('9.9.9.2'), 'quota-e2e')).statusCode, 200);
  assert.equal(upstream.length, 4, 'only the allowed requests reached Anthropic');
});

test('a large payload spends more quota than a small one', async (t) => {
  setEnv(t, { ...BASE_ENV, DEVICE_DAILY_QUOTA: '5', RATE_LIMIT_RPM: '1000' });
  stubUpstream(t);

  const big = makeReq('9.9.9.3');
  big.headers['content-length'] = String(1024 * 1024); // 1 MB ⇒ 4 units
  assert.equal((await forward(big, 'quota-cost-e2e')).statusCode, 200);
  // 4 of 5 units spent; a second megabyte would be 8 and must be refused.
  const second = makeReq('9.9.9.3');
  second.headers['content-length'] = String(1024 * 1024);
  assert.equal((await forward(second, 'quota-cost-e2e')).statusCode, 429);
});

test('quota rejection never reaches Anthropic', async (t) => {
  setEnv(t, { ...BASE_ENV, DEVICE_DAILY_QUOTA: '1', RATE_LIMIT_RPM: '1000' });
  const upstream = stubUpstream(t);
  await forward(makeReq('9.9.9.4'), 'quota-noupstream');
  await forward(makeReq('9.9.9.4'), 'quota-noupstream');
  assert.equal(upstream.length, 1, 'the refused request cost nothing');
});

test('per-principal limits are per route, so one route cannot starve another', async (t) => {
  setEnv(t, { ...BASE_ENV, RATE_LIMIT_RPM: '1', DEVICE_DAILY_QUOTA: '0' });
  stubUpstream(t);
  assert.equal((await forward(makeReq('9.9.9.5'), 'route-a')).statusCode, 200);
  assert.equal((await forward(makeReq('9.9.9.5'), 'route-a')).statusCode, 429);
  // Same caller, different route — still has its own allowance.
  assert.equal((await forward(makeReq('9.9.9.5'), 'route-b')).statusCode, 200);
});
