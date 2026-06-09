/**
 * Shared rate limiting for every proxy route. Counters live in
 * Upstash Redis (REST API) when configured, so limits hold globally
 * across warm lambda instances and cold starts; otherwise they fall
 * back to the per-instance in-memory window the routes always had.
 *
 * Env vars:
 *   UPSTASH_REDIS_REST_URL / UPSTASH_REDIS_REST_TOKEN
 *       — set automatically by the Vercel Upstash integration.
 *         `KV_REST_API_URL` / `KV_REST_API_TOKEN` (legacy Vercel KV
 *         naming) are honoured as fallbacks.
 *   ANTHROPIC_DAILY_REQUEST_BUDGET
 *       — hard cap on upstream Anthropic requests per UTC day across
 *         ALL routes combined. Unset or 0 disables the budget.
 *
 * A Redis outage degrades to the in-memory fallback rather than
 * rejecting traffic: per-IP limits and the daily budget then only
 * hold per warm instance until Redis recovers.
 */

const memory = new Map();

function redisConfig() {
  const url = process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN;
  if (!url || !token) return null;
  return { url, token };
}

// INCR + EXPIRE in one pipeline round trip. The key embeds the window
// index, so refreshing the TTL on every hit is harmless — the key
// itself rotates each window. Returns the post-increment count, or
// null when Redis is unconfigured/unreachable (caller falls back).
async function redisCount(key, ttlSeconds) {
  const config = redisConfig();
  if (!config) return null;
  const controller = new AbortController();
  // A limiter check must never add meaningful latency to the request
  // it guards — give Redis 2s, then fall back.
  const timer = setTimeout(() => controller.abort(), 2_000);
  try {
    const res = await fetch(`${config.url}/pipeline`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${config.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify([['INCR', key], ['EXPIRE', key, String(ttlSeconds)]]),
      signal: controller.signal,
    });
    if (!res.ok) return null;
    const results = await res.json();
    const count = results?.[0]?.result;
    return typeof count === 'number' ? count : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function memoryAllow(key, limit, windowMs) {
  const now = Date.now();
  const bucket = memory.get(key);
  if (!bucket || now - bucket.start > windowMs) {
    memory.set(key, { start: now, count: 1 });
    return true;
  }
  bucket.count += 1;
  return bucket.count <= limit;
}

/**
 * Fixed-window counter. `name` scopes the counter (route name,
 * 'budget:anthropic', ...), `key` is the principal within it (client
 * IP, 'global'). A non-finite or non-positive `limit` disables the
 * check — same semantics RATE_LIMIT_RPM always had.
 */
export async function allowRate({ name, key, limit, windowSeconds }) {
  if (!Number.isFinite(limit) || limit <= 0) return true;
  const windowMs = windowSeconds * 1000;
  const windowIndex = Math.floor(Date.now() / windowMs);
  const count = await redisCount(`rl:${name}:${key}:${windowIndex}`, windowSeconds * 2);
  if (count !== null) return count <= limit;
  return memoryAllow(`${name}:${key}`, limit, windowMs);
}

/**
 * Global daily budget on upstream Anthropic calls — the hard ceiling
 * on spend if a secret leaks or a client runs hot. Call it once per
 * request, immediately before the upstream fetch, so only requests
 * that would actually reach Anthropic consume budget.
 */
export async function withinDailyBudget() {
  const budget = parseInt(process.env.ANTHROPIC_DAILY_REQUEST_BUDGET || '', 10);
  if (!Number.isFinite(budget) || budget <= 0) return true;
  return allowRate({
    name: 'budget:anthropic',
    key: 'global',
    limit: budget,
    windowSeconds: 86_400,
  });
}
