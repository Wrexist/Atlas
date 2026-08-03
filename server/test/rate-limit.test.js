import test from 'node:test';
import assert from 'node:assert/strict';
import {
  allowRate,
  isBlocked,
  recordLimitStrike,
  requestCost,
  withinDailyBudget,
  withinDeviceQuota,
} from '../api/_lib/rate-limit.js';

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
  // INCRBY, not INCR: a request can consume more than one unit so the
  // budget tracks payload size rather than bare request count.
  assert.deepEqual([incr[0], incr[2]], ['INCRBY', '1']);
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

// ---------------------------------------------------------------------------
// Abuse controls
//
// These are the limits that decide whether one caller with an extracted
// secret can (a) run the bill up and (b) take the service down for everyone
// else. Each test states the abuse it's preventing.
// ---------------------------------------------------------------------------

test('requestCost scales with payload so an image costs more than a text turn', () => {
  assert.equal(requestCost({ headers: {} }), 1);
  assert.equal(requestCost({ headers: { 'content-length': '1000' } }), 1);
  // A ~5 MB meal-scan JPEG shouldn't spend the same budget as a chat turn.
  assert.equal(requestCost({ headers: { 'content-length': String(5 * 1024 * 1024) } }), 20);
});

test('device quota bounds one principal without touching another', async (t) => {
  setEnv(t, { ...NO_REDIS, DEVICE_DAILY_QUOTA: '3' });
  const abuser = { principal: 'quota-test-abuser' };
  const bystander = { principal: 'quota-test-bystander' };

  assert.equal(await withinDeviceQuota(abuser), true);
  assert.equal(await withinDeviceQuota(abuser), true);
  assert.equal(await withinDeviceQuota(abuser), true);
  assert.equal(await withinDeviceQuota(abuser), false, 'fourth request is over quota');
  // The whole point: one bad actor must not consume anyone else's allowance.
  assert.equal(await withinDeviceQuota(bystander), true);
});

test('device quota charges the request cost, not one per call', async (t) => {
  setEnv(t, { ...NO_REDIS, DEVICE_DAILY_QUOTA: '10' });
  const principal = 'quota-cost-test';
  assert.equal(await withinDeviceQuota({ principal, cost: 8 }), true);
  assert.equal(await withinDeviceQuota({ principal, cost: 8 }), false);
});

test('device quota disabled at 0', async (t) => {
  setEnv(t, { ...NO_REDIS, DEVICE_DAILY_QUOTA: '0' });
  for (let i = 0; i < 50; i += 1) {
    assert.equal(await withinDeviceQuota({ principal: 'quota-off' }), true);
  }
});

test('daily budget fails CLOSED when redis is configured but unreachable', async (t) => {
  setEnv(t, {
    ...NO_REDIS,
    UPSTASH_REDIS_REST_URL: 'https://fake.upstash.test',
    UPSTASH_REDIS_REST_TOKEN: 'tok',
    ANTHROPIC_DAILY_REQUEST_BUDGET: '100',
    BUDGET_FAIL_OPEN: undefined,
  });
  stubFetch(t, async () => {
    throw new Error('redis down');
  });
  // A spend ceiling that stops applying during an outage is not a ceiling:
  // an outage is exactly when a runaway client would go unnoticed.
  assert.equal(await withinDailyBudget({ cost: 1 }), false);
});

test('daily budget fail-closed is opt-out for deployments that accept the risk', async (t) => {
  setEnv(t, {
    ...NO_REDIS,
    UPSTASH_REDIS_REST_URL: 'https://fake.upstash.test',
    UPSTASH_REDIS_REST_TOKEN: 'tok',
    ANTHROPIC_DAILY_REQUEST_BUDGET: '100',
    BUDGET_FAIL_OPEN: '1',
  });
  stubFetch(t, async () => {
    throw new Error('redis down');
  });
  assert.equal(await withinDailyBudget({ cost: 1 }), true);
});

test('daily budget still uses the memory window when redis was never configured', async (t) => {
  setEnv(t, { ...NO_REDIS, ANTHROPIC_DAILY_REQUEST_BUDGET: '2', BUDGET_FAIL_OPEN: undefined });
  // The memory fallback keys on a single global bucket, so pin a distinct
  // day the way the budget test above does — otherwise this inherits
  // whatever count earlier tests left in the current window.
  t.mock.timers.enable({ apis: ['Date'], now: 5 * 86_400_000 }); // 1970-01-06
  // No Redis configured is not an outage — small deployments keep the
  // best-effort per-instance behaviour rather than being locked out.
  assert.equal(await withinDailyBudget({ cost: 1 }), true);
  assert.equal(await withinDailyBudget({ cost: 1 }), true);
  assert.equal(await withinDailyBudget({ cost: 1 }), false);
});

test('repeat limit strikes escalate to a block', async (t) => {
  setEnv(t, {
    ...NO_REDIS,
    UPSTASH_REDIS_REST_URL: 'https://fake.upstash.test',
    UPSTASH_REDIS_REST_TOKEN: 'tok',
    ABUSE_STRIKES: '3',
    ABUSE_BLOCK_SECONDS: '900',
  });
  let counter = 0;
  const calls = stubFetch(t, async (_url, init) => {
    const [cmd] = JSON.parse(init.body);
    if (cmd[0] === 'INCRBY') {
      counter += 1;
      return new Response(JSON.stringify([{ result: counter }, { result: 1 }]), { status: 200 });
    }
    return new Response(JSON.stringify([{ result: 'OK' }]), { status: 200 });
  });

  const principal = 'striker';
  assert.equal(await recordLimitStrike({ principal }), false);
  assert.equal(await recordLimitStrike({ principal }), false);
  assert.equal(await recordLimitStrike({ principal }), false);
  // Fourth strike crosses the threshold and writes the block key.
  assert.equal(await recordLimitStrike({ principal }), true);

  const setCall = calls.map(([, init]) => JSON.parse(init.body)[0]).find((c) => c[0] === 'SET');
  assert.deepEqual(setCall, ['SET', 'block:striker', '1', 'EX', '900']);
});

test('isBlocked reports an active cooldown and is off when disabled', async (t) => {
  setEnv(t, {
    ...NO_REDIS,
    UPSTASH_REDIS_REST_URL: 'https://fake.upstash.test',
    UPSTASH_REDIS_REST_TOKEN: 'tok',
    ABUSE_BLOCK_SECONDS: '900',
  });
  let stored = null;
  stubFetch(t, async () => new Response(JSON.stringify([{ result: stored }]), { status: 200 }));

  assert.equal(await isBlocked({ principal: 'p' }), false);
  stored = '1';
  assert.equal(await isBlocked({ principal: 'p' }), true);

  process.env.ABUSE_BLOCK_SECONDS = '0';
  assert.equal(await isBlocked({ principal: 'p' }), false, 'disabled by config');
});
