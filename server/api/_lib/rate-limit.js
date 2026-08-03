/**
 * Shared rate limiting and spend control for every proxy route.
 * Counters live in Upstash Redis (REST API) when configured, so limits
 * hold globally across warm lambda instances and cold starts;
 * otherwise they fall back to the per-instance in-memory window.
 *
 * Env vars:
 *   UPSTASH_REDIS_REST_URL / UPSTASH_REDIS_REST_TOKEN
 *       — set automatically by the Vercel Upstash integration.
 *         `KV_REST_API_URL` / `KV_REST_API_TOKEN` (legacy Vercel KV
 *         naming) are honoured as fallbacks.
 *   RATE_LIMIT_RPM
 *       — per-principal requests per minute per route. Default 20.
 *   DEVICE_DAILY_QUOTA
 *       — per-principal upstream requests per UTC day. Default 300.
 *         This is the control that stops one abusive client from
 *         draining the shared budget; 0 disables it.
 *   ANTHROPIC_DAILY_REQUEST_BUDGET
 *       — hard cap on upstream Anthropic cost units per UTC day
 *         across ALL routes combined. Unset or 0 disables the budget.
 *   BUDGET_FAIL_OPEN
 *       — set to `1` to allow traffic when a budget is configured but
 *         Redis is unreachable. Off by default: a spend ceiling that
 *         silently stops applying during an outage isn't a ceiling.
 *   ABUSE_STRIKES / ABUSE_BLOCK_SECONDS
 *       — a principal that trips the per-minute limit this many times
 *         in an hour is blocked outright for the cooldown.
 *         Defaults: 20 strikes, 900s. 0 disables.
 *
 * **Fail-open vs fail-closed.** Per-principal limits degrade to the
 * in-memory fallback on a Redis outage — losing them briefly is
 * better than downtime. The *global spend budget* is the opposite:
 * it exists to bound the blast radius of a leaked secret, so when
 * Redis is configured-but-unreachable it denies rather than silently
 * uncapping spend. When Redis was never configured, there's no
 * outage to detect and the in-memory fallback applies as before.
 */

import { redisConfigured, redisPipeline } from './redis.js';

const memory = new Map();

// INCRBY + EXPIRE in one pipeline round trip. The key embeds the
// window index, so refreshing the TTL on every hit is harmless — the
// key itself rotates each window. Returns the post-increment count,
// or null when Redis is unconfigured/unreachable (caller decides).
async function redisCount(key, ttlSeconds, cost = 1) {
  const results = await redisPipeline([
    ['INCRBY', key, String(cost)],
    ['EXPIRE', key, String(ttlSeconds)],
  ]);
  const count = results?.[0]?.result;
  return typeof count === 'number' ? count : null;
}

// Window-indexed exactly like the Redis path, so both agree on where a
// window starts. Keying on first-hit wall-clock instead would let each
// lambda instance run its own floating "day", which for the spend budget
// means the reset point drifts per instance.
function memoryAllow(key, limit, windowMs, cost) {
  const windowIndex = Math.floor(Date.now() / windowMs);
  const bucketKey = `${key}:${windowIndex}`;
  const count = (memory.get(bucketKey) ?? 0) + cost;
  memory.set(bucketKey, count);
  // The map would otherwise grow without bound across windows. Anything
  // from an older window can never be read again, so drop it.
  if (memory.size > 10_000) {
    for (const existing of memory.keys()) {
      if (!existing.endsWith(`:${windowIndex}`)) memory.delete(existing);
    }
  }
  return count <= limit;
}

/**
 * Fixed-window counter. `name` scopes the counter (route name,
 * 'budget:anthropic', ...), `key` is the principal within it. A
 * non-finite or non-positive `limit` disables the check.
 *
 * `cost` lets one request consume more than one unit — see
 * `requestCost`.
 */
export async function allowRate({ name, key, limit, windowSeconds, cost = 1 }) {
  if (!Number.isFinite(limit) || limit <= 0) return true;
  const windowMs = windowSeconds * 1000;
  const windowIndex = Math.floor(Date.now() / windowMs);
  const count = await redisCount(`rl:${name}:${key}:${windowIndex}`, windowSeconds * 2, cost);
  if (count !== null) return count <= limit;
  return memoryAllow(`${name}:${key}`, limit, windowMs, cost);
}

/** Undo a `memoryAllow` charge that was rejected. See `withinDailyBudget`. */
function memoryRefund(key, windowMs, cost) {
  const bucketKey = `${key}:${Math.floor(Date.now() / windowMs)}`;
  const current = memory.get(bucketKey);
  if (current !== undefined) memory.set(bucketKey, Math.max(0, current - cost));
}

function intEnv(name, fallback) {
  const parsed = parseInt(process.env[name] ?? '', 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

/**
 * Cost units a request consumes against the daily budget and the
 * per-device quota.
 *
 * A meal scan carrying a multi-megabyte JPEG costs Anthropic far more
 * than a text turn, so counting both as "one request" makes the spend
 * ceiling a poor proxy for spend. One unit per 256 KB of payload,
 * minimum one, keeps the budget roughly proportional to tokens
 * without needing the upstream usage numbers (which arrive too late
 * to gate on).
 */
export function costForBytes(bytes) {
  return Math.max(1, Math.ceil((Number(bytes) || 0) / (256 * 1024)));
}

export function requestCost(req) {
  return costForBytes(req?.headers?.['content-length']);
}

/**
 * Per-principal daily cap. This is what prevents a single extracted
 * secret from burning the whole shared budget: an abuser is bounded
 * by their own quota long before the global ceiling is reached, so
 * legitimate users keep working.
 */
export async function withinDeviceQuota({ principal, cost = 1 }) {
  const quota = intEnv('DEVICE_DAILY_QUOTA', 300);
  if (quota <= 0) return true;
  return allowRate({
    name: 'quota:device',
    key: principal,
    limit: quota,
    windowSeconds: 86_400,
    cost,
  });
}

/**
 * Global daily budget on upstream Anthropic cost units — the hard
 * ceiling on spend if a secret leaks or a client runs hot. Call it
 * once per request, immediately before the upstream fetch, so only
 * requests that would actually reach Anthropic consume budget.
 *
 * Fails closed when Redis is configured but unreachable; see the
 * module header.
 */
export async function withinDailyBudget({ cost = 1 } = {}) {
  const budget = intEnv('ANTHROPIC_DAILY_REQUEST_BUDGET', 0);
  if (budget <= 0) return true;

  const windowSeconds = 86_400;
  const windowIndex = Math.floor(Date.now() / (windowSeconds * 1000));
  const key = `rl:budget:anthropic:global:${windowIndex}`;
  const count = await redisCount(key, windowSeconds * 2, cost);
  if (count !== null) {
    if (count <= budget) return true;
    // Give the units back. The counter is shared by everyone, and a
    // request rejected here never reaches Anthropic, so charging it
    // would let one client burn the whole budget on requests that cost
    // nothing upstream — 503ing everybody else without a single token
    // spent. Without the refund, one oversized request landing at
    // budget-1 also locks out every small request behind it for the
    // rest of the day.
    await redisPipeline([['DECRBY', key, String(cost)]]);
    return false;
  }

  // Redis said nothing. If it was never configured, there's no outage
  // — use the in-memory window as before. If it *is* configured, this
  // is an outage, and an uncapped spend ceiling is worse than a brief
  // 503.
  if (redisConfigured() && process.env.BUDGET_FAIL_OPEN !== '1') return false;
  const allowed = memoryAllow('budget:anthropic:global', budget, windowSeconds * 1000, cost);
  if (!allowed) memoryRefund('budget:anthropic:global', windowSeconds * 1000, cost);
  return allowed;
}

/**
 * Records that a principal tripped the per-minute limit, and reports
 * whether it has now earned a block.
 *
 * Rate limiting alone doesn't discourage a script: it retries at the
 * limit forever, which is still 28,800 requests a day. Counting
 * refusals and blocking a persistent offender turns "throttled" into
 * "stopped" without touching well-behaved clients, who never trip it
 * often enough to accumulate strikes.
 */
export async function recordLimitStrike({ principal }) {
  const strikes = intEnv('ABUSE_STRIKES', 20);
  if (strikes <= 0) return false;
  const overStrikeBudget = !(await allowRate({
    name: 'abuse:strikes',
    key: principal,
    limit: strikes,
    windowSeconds: 3_600,
  }));
  if (!overStrikeBudget) return false;
  const blockSeconds = intEnv('ABUSE_BLOCK_SECONDS', 900);
  if (blockSeconds > 0) {
    await redisPipeline([['SET', `block:${principal}`, '1', 'EX', String(blockSeconds)]]);
  }
  return true;
}

/** True when a principal is inside an active abuse cooldown. */
export async function isBlocked({ principal }) {
  if (intEnv('ABUSE_BLOCK_SECONDS', 900) <= 0) return false;
  const results = await redisPipeline([['GET', `block:${principal}`]]);
  return results?.[0]?.result != null;
}
