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
 *       — per-principal upstream cost units per UTC day. Default 300.
 *         This is the control that stops one abusive client from
 *         draining the shared budget; 0 disables it.
 *   SHARED_IP_LIMIT_SCALE
 *       — multiplier on the per-minute and daily limits for an IPv4
 *         principal, which carrier NAT shares across many installs.
 *         Default 10. See `sharesIp`.
 *   ANTHROPIC_DAILY_REQUEST_BUDGET
 *       — hard cap on upstream Anthropic cost units per UTC day
 *         across ALL routes combined. Unset means 20 000 on a Vercel
 *         production deployment and no cap elsewhere; 0 disables it.
 *   BUDGET_FAIL_OPEN
 *       — set to `1` to allow traffic when a budget is configured but
 *         Redis is unreachable. Off by default: a spend ceiling that
 *         silently stops applying during an outage isn't a ceiling.
 *   ABUSE_STRIKES / ABUSE_BLOCK_SECONDS
 *       — a principal that trips the per-minute limit this many times
 *         in an hour is blocked outright for the cooldown.
 *         Defaults: 20 strikes, 900s. 0 disables. Never applied to a
 *         shared IPv4 principal.
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
// Abuse-block expiry per principal, used only when Redis can't hold the
// block — otherwise the cooldown silently did nothing without Upstash.
const memoryBlocks = new Map();
const DAY_SECONDS = 86_400;

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
// means the reset point drifts per instance. The window size is part of
// the key because minute, hour and day windows share this one Map.
function memoryBucket(key, windowMs) {
  return `${key}:${windowMs}:${Math.floor(Date.now() / windowMs)}`;
}

// Drops buckets whose own window has ended. Comparing against the
// caller's window index instead wiped every live daily quota and budget
// bucket whenever a per-minute check ran the cleanup.
function pruneExpiredBuckets() {
  const now = Date.now();
  for (const existing of memory.keys()) {
    const [windowMs, windowIndex] = existing.split(':').slice(-2).map(Number);
    if (windowIndex < Math.floor(now / windowMs)) memory.delete(existing);
  }
}

function memoryAllow(key, limit, windowMs, cost) {
  const bucketKey = memoryBucket(key, windowMs);
  const count = (memory.get(bucketKey) ?? 0) + cost;
  memory.set(bucketKey, count);
  // The map would otherwise grow without bound across windows.
  if (memory.size > 10_000) pruneExpiredBuckets();
  return count <= limit;
}

/**
 * Fixed-window counter. `name` scopes the counter (route name,
 * 'budget:anthropic', ...), `key` is the principal within it. A
 * non-finite or non-positive `limit` disables the check.
 *
 * `cost` lets one request consume more than one unit — see
 * `costForBody`.
 */
export async function allowRate({ name, key, limit, windowSeconds, cost = 1 }) {
  if (!Number.isFinite(limit) || limit <= 0) return true;
  const windowMs = windowSeconds * 1000;
  const windowIndex = Math.floor(Date.now() / windowMs);
  const count = await redisCount(`rl:${name}:${key}:${windowIndex}`, windowSeconds * 2, cost);
  if (count !== null) return count <= limit;
  return memoryAllow(`${name}:${key}`, limit, windowMs, cost);
}

function memoryRefund(key, windowMs, cost) {
  const bucketKey = memoryBucket(key, windowMs);
  const current = memory.get(bucketKey);
  if (current !== undefined) memory.set(bucketKey, Math.max(0, current - cost));
}

/**
 * Gives back units an `allowRate` call charged, on whichever store took
 * them. The EXPIRE matters when the charge landed in memory during a
 * Redis blip: DECRBY then creates a negative key, which must not
 * outlive its window and keep raising the ceiling.
 */
async function refundRate({ name, key, windowSeconds, cost }) {
  const windowMs = windowSeconds * 1000;
  const windowIndex = Math.floor(Date.now() / windowMs);
  const redisKey = `rl:${name}:${key}:${windowIndex}`;
  const results = await redisPipeline([
    ['DECRBY', redisKey, String(cost)],
    ['EXPIRE', redisKey, String(windowSeconds * 2)],
  ]);
  if (!results) memoryRefund(`${name}:${key}`, windowMs, cost);
}

/** Seconds until the current window of `windowSeconds` ends. */
export function secondsUntilWindowEnd(windowSeconds) {
  const windowMs = windowSeconds * 1000;
  return Math.ceil((windowMs - (Date.now() % windowMs)) / 1000);
}

/**
 * True for an IPv4 fallback principal. Mobile carriers put thousands
 * of installs behind one CGNAT IPv4 address, so a per-device limit on
 * it throttles every unattested user on that carrier together. IPv6
 * addresses are effectively per device and keep the per-device limits.
 */
export function sharesIp(principal) {
  return principal.startsWith('ip:') && principal.includes('.');
}

/** `limit` for one install, scaled up when the principal is a shared IP. */
export function principalLimit(principal, limit) {
  return sharesIp(principal) ? limit * intEnv('SHARED_IP_LIMIT_SCALE', 10) : limit;
}

// Production gets a ceiling even when nobody set one: unset used to
// mean unlimited, so a leaked secret had no upper bound on spend.
// ~20 000 units is roughly a few hundred dollars a day at Sonnet
// pricing. An explicit ANTHROPIC_DAILY_REQUEST_BUDGET=0 still disables it.
const PRODUCTION_DEFAULT_BUDGET = 20_000;

function defaultDailyBudget() {
  return process.env.VERCEL_ENV === 'production' ? PRODUCTION_DEFAULT_BUDGET : 0;
}

export function dailyBudgetLimit() {
  return intEnv('ANTHROPIC_DAILY_REQUEST_BUDGET', defaultDailyBudget());
}

function intEnv(name, fallback) {
  const parsed = parseInt(process.env[name] ?? '', 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

/**
 * Byte cost of a payload: one unit per 256 KB, minimum one. The floor
 * under `costForBody`, so a large photo never costs less than its size.
 */
export function costForBytes(bytes) {
  return Math.max(1, Math.ceil((Number(bytes) || 0) / (256 * 1024)));
}

// Rough token estimate for a sanitised body: ~4 characters per text
// token, a flat ~3 000 tokens per image (the app sends 1568 px photos,
// which high-resolution models read as ~2 500+ tokens), plus the
// requested output.
const CHARS_PER_TOKEN = 4;
const TOKENS_PER_IMAGE = 3000;
const TOKENS_PER_UNIT = 4000;
// Price relative to Sonnet 4.6 ($3 / $15 per MTok), the model the
// budget's units are calibrated against. Unlisted models count as 1.
const MODEL_COST_WEIGHT = { 'claude-opus-5-5': 4 / 3 };

function estimatedTokens(body) {
  let tokens = Number(body?.max_tokens) || 0;
  tokens += Math.ceil(String(body?.system ?? '').length / CHARS_PER_TOKEN);
  for (const message of body?.messages ?? []) {
    const parts = typeof message.content === 'string'
      ? [{ type: 'text', text: message.content }]
      : message.content;
    for (const part of parts) {
      tokens += part.type === 'image'
        ? TOKENS_PER_IMAGE
        : Math.ceil(String(part.text ?? '').length / CHARS_PER_TOKEN);
    }
  }
  return tokens;
}

/**
 * Cost of a sanitised request: the larger of its byte cost and its
 * estimated token cost. Bytes alone charged 256 KB of text (~64k
 * tokens) the same single unit as a short question, so text-heavy
 * calls were ~40x under-billed next to photos.
 */
export function costForBody(body, bytes) {
  const weight = MODEL_COST_WEIGHT[body?.model] ?? 1;
  const tokenCost = Math.ceil((estimatedTokens(body) * weight) / TOKENS_PER_UNIT);
  return Math.max(costForBytes(bytes), tokenCost);
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
  const counter = { name: 'quota:device', key: principal, windowSeconds: DAY_SECONDS, cost };
  if (await allowRate({ ...counter, limit: principalLimit(principal, quota) })) return true;
  // A refused request never reaches Anthropic, so it gives its units
  // back. Kept charged, one large photo scan would park the counter
  // above the quota and every later request — even one that fits —
  // would be refused for the rest of the day.
  await refundRate(counter);
  return false;
}

/**
 * Returns a request's charge to the device quota and the global
 * budget when it never produced upstream tokens — otherwise client
 * retries during an Anthropic outage drain both without a single
 * token spent.
 */
export async function refundSpend({ principal, cost, budget = true }) {
  if (intEnv('DEVICE_DAILY_QUOTA', 300) > 0) {
    await refundRate({ name: 'quota:device', key: principal, windowSeconds: DAY_SECONDS, cost });
  }
  if (budget && dailyBudgetLimit() > 0) {
    await refundRate({ name: 'budget:anthropic', key: 'global', windowSeconds: DAY_SECONDS, cost });
  }
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
  const budget = dailyBudgetLimit();
  if (budget <= 0) return true;

  const windowIndex = Math.floor(Date.now() / (DAY_SECONDS * 1000));
  const key = `rl:budget:anthropic:global:${windowIndex}`;
  const count = await redisCount(key, DAY_SECONDS * 2, cost);
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
  const allowed = memoryAllow('budget:anthropic:global', budget, DAY_SECONDS * 1000, cost);
  if (!allowed) memoryRefund('budget:anthropic:global', DAY_SECONDS * 1000, cost);
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
  // A shared IPv4 address is many installs; blocking it would lock out
  // every innocent user behind the same carrier NAT.
  if (strikes <= 0 || sharesIp(principal)) return false;
  const overStrikeBudget = !(await allowRate({
    name: 'abuse:strikes',
    key: principal,
    limit: strikes,
    windowSeconds: 3_600,
  }));
  if (!overStrikeBudget) return false;
  const blockSeconds = abuseBlockSeconds();
  if (blockSeconds > 0) {
    const stored = await redisPipeline([['SET', `block:${principal}`, '1', 'EX', String(blockSeconds)]]);
    if (!stored) memoryBlocks.set(principal, Date.now() + blockSeconds * 1000);
  }
  return true;
}

export function abuseBlockSeconds() {
  return intEnv('ABUSE_BLOCK_SECONDS', 900);
}

/** True when a principal is inside an active abuse cooldown. */
export async function isBlocked({ principal }) {
  if (abuseBlockSeconds() <= 0) return false;
  const results = await redisPipeline([['GET', `block:${principal}`]]);
  if (results) return results[0]?.result != null;
  const until = memoryBlocks.get(principal);
  if (until === undefined) return false;
  if (until > Date.now()) return true;
  memoryBlocks.delete(principal);
  return false;
}
