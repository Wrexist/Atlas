/**
 * Minimal Upstash Redis REST client shared by the rate limiter and
 * the App Attest key registry. One exported primitive — a pipeline
 * call — keeps the wire format in one place.
 *
 * Env vars:
 *   UPSTASH_REDIS_REST_URL / UPSTASH_REDIS_REST_TOKEN
 *       — set automatically by the Vercel Upstash integration.
 *         `KV_REST_API_URL` / `KV_REST_API_TOKEN` (legacy Vercel KV
 *         naming) are honoured as fallbacks.
 */

export function redisConfig() {
  const url = process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN;
  if (!url || !token) return null;
  return { url, token };
}

export function redisConfigured() {
  return redisConfig() !== null;
}

/**
 * Executes commands atomically-enough via the Upstash pipeline
 * endpoint. Returns the per-command results array
 * (`[{ result } | { error }, ...]`), or null when Redis is
 * unconfigured/unreachable — callers decide their own fallback.
 * The timeout is short by design: these calls sit in the request
 * path of every proxied AI call.
 */
export async function redisPipeline(commands, { timeoutMs = 2_000 } = {}) {
  const config = redisConfig();
  if (!config) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`${config.url}/pipeline`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${config.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(commands),
      signal: controller.signal,
    });
    if (!res.ok) return null;
    const results = await res.json();
    return Array.isArray(results) ? results : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}
