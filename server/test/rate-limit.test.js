import test from 'node:test';
import assert from 'node:assert/strict';
import { allowRate, withinDailyBudget } from '../api/_lib/rate-limit.js';

// The module keeps one in-memory Map for the life of the process, so
// every test uses its own `name` to stay isolated. Tests that mock
// Date pin it far in the past (1970) — any key they leave behind is
// window-expired for tests running at real time.

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

const NO_REDIS = {
  UPSTASH_REDIS_REST_URL: undefined,
  UPSTASH_REDIS_REST_TOKEN: undefined,
  KV_REST_API_URL: undefined,
  KV_REST_API_TOKEN: undefined,
};

function stubFetch(t, impl) {
  const real = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (...args) => {
    calls.push(args);
    return impl(...args);
  };
  t.after(() => {
    globalThis.fetch = real;
  });
  return calls;
}

test('memory: allows up to the limit, denies past it', async (t) => {
  setEnv(t, NO_REDIS);
  const opts = { name: 'mem-basic', key: '1.2.3.4', limit: 2, windowSeconds: 60 };
  assert.equal(await allowRate(opts), true);
  assert.equal(await allowRate(opts), true);
  assert.equal(await allowRate(opts), false);
});

test('memory: distinct names and keys do not share a bucket', async (t) => {
  setEnv(t, NO_REDIS);
  assert.equal(await allowRate({ name: 'mem-iso-a', key: 'ip', limit: 1, windowSeconds: 60 }), true);
  assert.equal(await allowRate({ name: 'mem-iso-b', key: 'ip', limit: 1, windowSeconds: 60 }), true);
  assert.equal(await allowRate({ name: 'mem-iso-a', key: 'other', limit: 1, windowSeconds: 60 }), true);
  assert.equal(await allowRate({ name: 'mem-iso-a', key: 'ip', limit: 1, windowSeconds: 60 }), false);
});

test('memory: window expiry resets the count', async (t) => {
  setEnv(t, NO_REDIS);
  t.mock.timers.enable({ apis: ['Date'], now: 1_000_000 });
  const opts = { name: 'mem-window', key: 'ip', limit: 1, windowSeconds: 60 };
  assert.equal(await allowRate(opts), true);
  assert.equal(await allowRate(opts), false);
  t.mock.timers.tick(60_001);
  assert.equal(await allowRate(opts), true);
});

test('non-finite or non-positive limit disables the check', async (t) => {
  setEnv(t, NO_REDIS);
  for (const limit of [NaN, 0, -5]) {
    assert.equal(await allowRate({ name: 'mem-off', key: 'ip', limit, windowSeconds: 60 }), true);
  }
});

test('redis: post-increment count governs allow/deny', async (t) => {
  setEnv(t, {
    ...NO_REDIS,
    UPSTASH_REDIS_REST_URL: 'https://fake.upstash.test',
    UPSTASH_REDIS_REST_TOKEN: 'tok',
  });
  let n = 0;
  const calls = stubFetch(t, async () => {
    n += 1;
    return new Response(JSON.stringify([{ result: n }, { result: 1 }]), { status: 200 });
  });

  const opts = { name: 'redis-basic', key: '1.2.3.4', limit: 2, windowSeconds: 60 };
  assert.equal(await allowRate(opts), true);
  assert.equal(await allowRate(opts), true);
  assert.equal(await allowRate(opts), false);

  assert.equal(calls.length, 3);
  const [url, init] = calls[0];
  assert.equal(url, 'https://fake.upstash.test/pipeline');
  assert.equal(init.headers.Authorization, 'Bearer tok');
  const [incr, expire] = JSON.parse(init.body);
  assert.equal(incr[0], 'INCR');
  assert.match(incr[1], /^rl:redis-basic:1\.2\.3\.4:\d+$/);
  assert.deepEqual(expire, ['EXPIRE', incr[1], '120']);
});

test('redis: unreachable or non-2xx falls back to memory', async (t) => {
  setEnv(t, {
    ...NO_REDIS,
    UPSTASH_REDIS_REST_URL: 'https://fake.upstash.test',
    UPSTASH_REDIS_REST_TOKEN: 'tok',
  });
  let mode = 'throw';
  stubFetch(t, async () => {
    if (mode === 'throw') throw new Error('connect refused');
    return new Response('oops', { status: 500 });
  });

  const opts = { name: 'redis-down', key: 'ip', limit: 1, windowSeconds: 60 };
  assert.equal(await allowRate(opts), true); // memory count 1
  mode = '500';
  assert.equal(await allowRate(opts), false); // memory count 2 > limit
});

test('budget: unset env disables; set env caps per UTC day', async (t) => {
  setEnv(t, { ...NO_REDIS, ANTHROPIC_DAILY_REQUEST_BUDGET: undefined });
  assert.equal(await withinDailyBudget(), true);

  setEnv(t, { ANTHROPIC_DAILY_REQUEST_BUDGET: '2' });
  t.mock.timers.enable({ apis: ['Date'], now: 86_400_000 }); // 1970-01-02
  assert.equal(await withinDailyBudget(), true);
  assert.equal(await withinDailyBudget(), true);
  assert.equal(await withinDailyBudget(), false);
  t.mock.timers.tick(86_400_001); // next day → fresh budget
  assert.equal(await withinDailyBudget(), true);
});
