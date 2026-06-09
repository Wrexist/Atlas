import test from 'node:test';
import assert from 'node:assert/strict';
import handler from '../api/weekly-summary.js';

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
  WEEKLY_RPM: undefined,
  APP_ATTEST_MODE: 'off',
  APP_ATTEST_APP_ID: undefined,
};

function stubUpstream(t) {
  const real = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (...args) => {
    calls.push(args);
    return new Response(
      JSON.stringify({ content: [{ type: 'text', text: 'A solid week.' }] }),
      { status: 200, headers: { 'content-type': 'application/json' } }
    );
  };
  t.after(() => {
    globalThis.fetch = real;
  });
  return calls;
}

function makeReq(ip, body) {
  return {
    method: 'POST',
    headers: {
      'x-peptide-proxy': 'test-secret',
      'x-real-ip': ip,
      'content-length': '100',
    },
    socket: {},
    body: body ?? {
      aggregate: {
        weekStart: '2026-06-01',
        compliance: { completed: 5, total: 7, pct: 71 },
      },
    },
  };
}

function makeRes() {
  return {
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

test('over-RPM weekly-summary request is rejected 429', async (t) => {
  setEnv(t, { ...BASE_ENV, WEEKLY_RPM: '1' });
  const upstream = stubUpstream(t);

  const first = makeRes();
  await handler(makeReq('10.1.0.1'), first);
  assert.equal(first.statusCode, 200);
  assert.equal(first.body.text, 'A solid week.');

  const second = makeRes();
  await handler(makeReq('10.1.0.1'), second);
  assert.equal(second.statusCode, 429);

  assert.equal(upstream.length, 1);
});

test('oversized parsed body is rejected 413 regardless of content-length', async (t) => {
  setEnv(t, BASE_ENV);
  const upstream = stubUpstream(t);

  const req = makeReq('10.1.0.2', {
    aggregate: {
      weekStart: '2026-06-01',
      compliance: { completed: 5, total: 7 },
      topInsightCategory: 'x'.repeat(70_000),
    },
  });
  const res = makeRes();
  await handler(req, res);

  assert.equal(res.statusCode, 413);
  assert.equal(upstream.length, 0);
});
