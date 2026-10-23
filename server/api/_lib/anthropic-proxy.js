/**
 * Shared proxy logic for every Atlas → Anthropic route. Holds the
 * server-side API key, authenticates clients via a shared secret,
 * sanitises the request body, throttles per principal, and forwards to
 * `api.anthropic.com/v1/messages`. The iOS client never sees the
 * upstream Anthropic key.
 *
 * Routes (meal-scan, food-scan, ai-research) thin-wrap
 * `forwardToAnthropic`, so a new defense is a one-place change.
 * weekly-summary shares the limiter and `refuse` but owns its upstream
 * call.
 *
 * Env vars (set on the Vercel deployment):
 *   ANTHROPIC_API_KEY    — server-side Anthropic key.
 *   PROXY_SHARED_SECRET  — random 32+ byte string the iOS client
 *                          echoes as `X-Peptide-Proxy`.
 *   ALLOWED_MODELS       — comma-separated Anthropic model IDs.
 *                          Default: claude-sonnet-5,claude-sonnet-4-6.
 *                          A deployment that sets this explicitly must
 *                          list every model the app sends, or the
 *                          sanitiser rewrites the missing ones to the
 *                          first entry — silently, with no client error.
 *                          meal-scan and ai-research send THINKING_OFF,
 *                          which Sonnet 5.5 / Opus 5.5 reject; see there.
 *   RATE_LIMIT_RPM       — requests per minute per principal per
 *                          route. Default 20.
 *   DEVICE_DAILY_QUOTA   — upstream cost units per principal per UTC
 *                          day. Default 300.
 *   SHARED_IP_LIMIT_SCALE
 *                        — multiplier on both for an IPv4 principal
 *                          (carrier NAT). Default 10.
 *   ABUSE_STRIKES / ABUSE_BLOCK_SECONDS
 *                        — cooldown for a principal that keeps
 *                          tripping the limit. Defaults 20 / 900.
 *   UPSTASH_REDIS_REST_URL / UPSTASH_REDIS_REST_TOKEN
 *                        — optional Redis backing so the limits hold
 *                          across all instances (see _lib/rate-limit.js).
 *   ANTHROPIC_DAILY_REQUEST_BUDGET
 *                        — optional hard cap on upstream cost units
 *                          per UTC day across all routes; 503 once
 *                          spent. Unset means 20 000 on a Vercel
 *                          production deployment, no cap elsewhere.
 *                          Fails closed if Redis is configured but
 *                          unreachable (BUDGET_FAIL_OPEN=1 opts out).
 *
 * Limits are counted per *principal*: the verified App Attest key
 * when one is present, else the client IP. See `principalFor` — an
 * IP-only limit is close to meaningless against a caller who can
 * rotate it at will.
 *   APP_ATTEST_MODE / APP_ATTEST_APP_ID
 *                        — App Attest assertion gate; see
 *                          _lib/app-attest.js for modes and rollout.
 *   FREE_SCANS_PER_WEEK  — free-tier scan allowance on routes that
 *                          pass `scanSucceeded`; see _lib/scan-quota.js.
 *
 * iOS clients pull the proxy URL and the matching secret from
 * Info.plist (or scheme env): `MEAL_SCANNER_ENDPOINT` +
 * `MEAL_SCANNER_SECRET`, `AI_RESEARCH_ENDPOINT` + `AI_RESEARCH_SECRET`,
 * and `WEEKLY_SUMMARY_ENDPOINT` + `WEEKLY_SUMMARY_SECRET`. The same
 * `PROXY_SHARED_SECRET` server-side value goes into every client secret.
 *
 * Refusals carry a stable `error.code` (see `refuse`) so the app can
 * tell "slow down" from "come back tomorrow" from "we're down".
 */
import { checkAppAttest } from './app-attest.js';
import { authorize } from './auth.js';
import { chargeScan } from './scan-quota.js';
import {
  abuseBlockSeconds,
  allowRate,
  costForBody,
  isBlocked,
  principalLimit,
  recordLimitStrike,
  refundSpend,
  secondsUntilWindowEnd,
  withinDailyBudget,
  withinDeviceQuota,
} from './rate-limit.js';

// The app sends Sonnet 5 on every route. 4.6 stays allowed for older
// app builds whose ai-research still asks for it; without it the
// sanitiser would silently rewrite their model. Index 0 is also the
// fallback for an unrecognised model, which is why the stronger one
// leads.
const DEFAULT_ALLOWED_MODELS = ['claude-sonnet-5', 'claude-sonnet-4-6'];
const MAX_TOKENS_HARDCAP = 800;
// Cap large enough for the AI research multi-turn chat flow (history +
// new turn). 4 was too small — the third user turn already produced 5
// messages and the proxy rejected it.
const MAX_MESSAGES = 40;
// Absolute body-size ceiling, just under the 4.5 MB request payload
// limit Vercel functions enforce before the handler runs. Each route
// can pass a tighter `maxBodyBytes` — ai-research is text-only.
const MAX_BODY_BYTES = 4_400_000;
// The client-supplied part of a route's system prompt is cut to this
// unless the route allows more (`maxClientSystemChars`).
const MAX_CLIENT_SYSTEM_CHARS = 4000;

/**
 * Thinking off, for the routes whose `max_tokens` was sized for the
 * answer alone. Claude Sonnet 5 runs adaptive thinking at effort high
 * when `thinking` is omitted, and `max_tokens` caps thinking plus text
 * together, so those small caps truncated replies. Sonnet 5 and 4.6
 * accept `disabled` (Sonnet 5 at effort high or below, the default).
 *
 * Claude Sonnet 5.5 rejects `{ type: 'disabled' }` with a 400: moving
 * a route to it means sending `{ type: 'between_tools' }` or
 * `output_config.effort: 'low'` instead.
 */
export const THINKING_OFF = Object.freeze({ type: 'disabled' });

function getAllowedModels() {
  const raw = process.env.ALLOWED_MODELS;
  if (!raw) return DEFAULT_ALLOWED_MODELS;
  return raw.split(',').map((s) => s.trim()).filter(Boolean);
}

// Exported so the other proxy files (`weekly-summary.js`) can share the
// Vercel-aware rate-limit key derivation.
export function clientKey(req) {
  // Vercel sets `x-vercel-forwarded-for` server-side from its own edge
  // and strips any client-supplied copy of the same header, so it
  // can't be spoofed by the caller — unlike `x-forwarded-for`, which
  // a client can set freely (rotating a fresh value per request would
  // bypass the per-IP limiter and drain the Anthropic key).
  const vercel = (req.headers['x-vercel-forwarded-for'] || '').split(',')[0].trim();
  if (vercel) return vercel;
  // `x-real-ip` is also set by Vercel itself and is single-valued.
  const real = (req.headers['x-real-ip'] || '').trim();
  if (real) return real;
  // Fall back to the socket remote — only happens on local `vercel dev`
  // or self-hosted Node, where the proxy isn't behind Vercel's edge.
  return req.socket?.remoteAddress || 'unknown';
}

/**
 * The principal every limit is counted against.
 *
 * A verified App Attest key is one physical install and can't be
 * rotated by the caller, so it's the honest identity. The client IP
 * is the fallback, and a weak one — mobile carriers rotate it per
 * request and a VPN makes it free to change, so an IP-only limit is
 * a speed bump rather than a cap. This is why attestation matters
 * beyond authentication: it's what makes per-user quotas possible.
 */
export function principalFor(req, attest) {
  if (attest?.keyId) return `k:${attest.keyId}`;
  return `ip:${clientKey(req)}`;
}

// Scoped per route (logLabel) so a meal-scan burst can't starve
// ai-research — the same isolation the old per-lambda Maps had by
// accident of deployment topology. Counts requests, not cost units:
// spend is bounded by the daily quota and budget, and charging a photo
// ~4 units here throttled a user after a handful of scans.
function checkRateLimit(principal, logLabel) {
  const limit = parseInt(process.env.RATE_LIMIT_RPM || '20', 10);
  return allowRate({ name: logLabel, key: principal, limit: principalLimit(principal, limit), windowSeconds: 60 });
}

const REFUSALS = {
  rate_limited: { status: 429, message: 'Too many requests', retryAfter: () => 60 },
  blocked: { status: 429, message: 'Too many requests', retryAfter: abuseBlockSeconds },
  daily_quota: {
    status: 429,
    message: 'Daily limit reached; try again tomorrow',
    retryAfter: () => secondsUntilWindowEnd(86_400),
  },
  // The free weekly scan allowance (scan-quota.js); no Retry-After,
  // since the app answers it with the paywall, not a retry.
  scan_quota: { status: 429, message: 'Free scan limit reached' },
  unavailable: { status: 503, message: 'Service unavailable' },
};

/**
 * Sends one of the limit / availability refusals with its stable
 * `error.code` and, where the wait is known, a `Retry-After` header.
 */
export function refuse(res, code) {
  const { status, message, retryAfter } = REFUSALS[code];
  if (retryAfter) res.setHeader('Retry-After', String(retryAfter()));
  res.status(status).json({ error: { message, code } });
}

// Anthropic accepts content parts of these typed shapes. Anything else
// (tool_use, tool_result, document, ...) is rejected so a tampered
// client can't reach features the app doesn't ship — and so the proxy
// surface only exposes what the iOS code actually sends.
// Each part is rebuilt from its allow-listed fields: extra keys such as
// `cache_control` are dropped, and images must be inline base64 — a
// `url` source would let a 1 KB body make Anthropic fetch arbitrarily
// large images while the byte-based quota charged almost nothing.
const ALLOWED_IMAGE_MEDIA_TYPES = new Set(['image/jpeg', 'image/png']);

function sanitisePart(part) {
  if (!part || typeof part !== 'object') return null;
  if (part.type === 'text') {
    return typeof part.text === 'string' ? { type: 'text', text: part.text } : null;
  }
  if (part.type === 'image') {
    const source = part.source;
    if (!source || source.type !== 'base64') return null;
    if (!ALLOWED_IMAGE_MEDIA_TYPES.has(source.media_type)) return null;
    if (typeof source.data !== 'string') return null;
    return { type: 'image', source: { type: 'base64', media_type: source.media_type, data: source.data } };
  }
  return null;
}

function sanitiseContent(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return null;
  const parts = content.map(sanitisePart);
  return parts.includes(null) ? null : parts;
}

// Optional per-route limits on top of the generic sanitiser, so a
// route can accept only the payload its iOS caller actually sends.
function fitsShape(messages, shape) {
  if (!shape) return true;
  let images = 0;
  let textChars = 0;
  for (const m of messages) {
    const parts = typeof m.content === 'string' ? [{ type: 'text', text: m.content }] : m.content;
    for (const part of parts) {
      if (part.type === 'image') images += 1;
      else textChars += part.text.length;
    }
  }
  if (shape.maxImages !== undefined && images > shape.maxImages) return false;
  if (shape.maxTextChars !== undefined && textChars > shape.maxTextChars) return false;
  return true;
}

function sanitiseBody(raw, options) {
  if (!raw || typeof raw !== 'object') return null;
  const allowedModels = getAllowedModels();
  const model = typeof raw.model === 'string' && allowedModels.includes(raw.model)
    ? raw.model
    : allowedModels[0];

  const cap = options?.maxTokens ?? MAX_TOKENS_HARDCAP;
  const maxTokensRaw = Number(raw.max_tokens);
  const max_tokens = Number.isFinite(maxTokensRaw) && maxTokensRaw > 0
    ? Math.min(Math.floor(maxTokensRaw), cap)
    : cap;

  if (!Array.isArray(raw.messages) || raw.messages.length === 0) return null;
  if (raw.messages.length > (options?.shape?.maxMessages ?? MAX_MESSAGES)) return null;

  const messages = raw.messages.map((m) => {
    if (!m || (m.role !== 'user' && m.role !== 'assistant')) return null;
    const content = sanitiseContent(m.content);
    if (content === null) return null;
    return { role: m.role, content };
  });
  if (messages.some((m) => m === null)) return null;
  if (!fitsShape(messages, options?.shape)) return null;

  const out = { model, max_tokens, messages };
  if (options?.thinking) out.thinking = options.thinking;

  // System-prompt handling. Routes that don't expect a client system
  // (`allowClientSystem: false`) drop any client-supplied value
  // entirely. Routes that do still always get the pinned safety
  // prefix prepended, so an injected client system can extend the
  // grounding but never override it.
  const allowClientSystem = options?.allowClientSystem !== false;
  const pinnedPrefix = typeof options?.systemPrefix === 'string' ? options.systemPrefix : '';
  const clientSystem = allowClientSystem && typeof raw.system === 'string'
    ? raw.system.slice(0, options?.maxClientSystemChars ?? MAX_CLIENT_SYSTEM_CHARS)
    : '';
  const composed = pinnedPrefix && clientSystem
    ? `${pinnedPrefix}\n\n${clientSystem}`
    : (pinnedPrefix || clientSystem);
  if (composed) out.system = composed;
  return out;
}

export async function forwardToAnthropic(req, res, {
  logLabel,
  systemPrefix,
  allowClientSystem,
  maxClientSystemChars,
  maxBodyBytes,
  shape,
  maxTokens,
  thinking,
  buildBody,
  readResponse,
  betas,
  requireJson = false,
  scanSucceeded,
  timeoutMs = 25_000,
}) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: 'Use POST' } });
    return;
  }

  if (!authorize(req)) {
    // Generic 401 — no hint about whether the secret was missing,
    // malformed, or wrong. One bit of feedback to the client.
    res.status(401).json({ error: { message: 'Unauthorised' } });
    return;
  }

  // App Attest runs before throttling, because its verified key is the
  // identity the limits are counted against. See `principalFor`.
  //
  // Only rejects in enforce mode; report mode verifies + logs so the
  // rollout can be validated from production logs before anything is
  // blocked. The `attest_required` code tells a genuine client to
  // (re-)register its key rather than treat this as a secret failure;
  // `attest_clock` tells it to correct its clock and keep the key.
  const attest = await checkAppAttest(req, { logLabel });
  if (!attest.ok) {
    res.status(401).json({ error: { message: 'Unauthorised', code: attest.code } });
    return;
  }

  const principal = principalFor(req, attest);

  // A principal in an abuse cooldown is refused before any work.
  if (await isBlocked({ principal })) {
    refuse(res, 'blocked');
    return;
  }

  if (!(await checkRateLimit(principal, logLabel))) {
    // Persistent hammering earns a cooldown; a client that trips the
    // limit occasionally never accumulates enough strikes to notice.
    if (await recordLimitStrike({ principal })) {
      console.warn(`[${logLabel}] principal blocked for repeated limit strikes`);
    }
    refuse(res, 'rate_limited');
    return;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    // Log loudly server-side so the deployer notices, but tell the
    // client a generic "service unavailable" — leaking "proxy not
    // configured" advertises a half-deployed environment.
    console.error(`[${logLabel}] ANTHROPIC_API_KEY missing on this deployment`);
    refuse(res, 'unavailable');
    return;
  }

  // Opt-in, because older app builds on the pass-through routes never
  // promised a content type. A route that owns its prompt knows its
  // only caller sends JSON, so anything else is not the app.
  if (requireJson && !/^application\/json\b/i.test(req.headers['content-type'] || '')) {
    res.status(415).json({ error: { message: 'Unsupported content type' } });
    return;
  }

  const contentLength = parseInt(req.headers['content-length'] || '0', 10);
  const bodyCap = Math.min(
    typeof maxBodyBytes === 'number' && maxBodyBytes > 0 ? maxBodyBytes : MAX_BODY_BYTES,
    MAX_BODY_BYTES
  );
  if (contentLength > bodyCap) {
    res.status(413).json({
      error: { message: 'Request too large; resize before retrying' }
    });
    return;
  }
  // Enforce the cap on the actual parsed body too — a client can omit
  // or understate `content-length` (chunked transfer), which would
  // otherwise let a route-specific tighter cap be bypassed up to the
  // platform's own body limit.
  const parsedBytes = Buffer.byteLength(JSON.stringify(req.body ?? ''), 'utf8');
  if (parsedBytes > bodyCap) {
    res.status(413).json({
      error: { message: 'Request too large; resize before retrying' }
    });
    return;
  }

  // Routes that own their prompt (food-scan) build the whole upstream
  // request server-side from a small app payload; everything else is a
  // sanitised pass-through of the Messages shape the app sends.
  const clean = buildBody
    ? buildBody(req.body)
    : sanitiseBody(req.body, { systemPrefix, allowClientSystem, maxClientSystemChars, shape, maxTokens, thinking });
  if (!clean) {
    res.status(400).json({ error: { message: 'Malformed request body' } });
    return;
  }

  // Charged on the parsed body, never on `content-length`, which a
  // client can omit or understate — and only once the request is known
  // to be well-formed, so a 400 or 413 costs the caller nothing.
  const cost = costForBody(clean, parsedBytes);

  // Per-principal daily ceiling. Without this, one extracted secret
  // can spend the whole shared budget and take every paying user down
  // with it — the global cap alone protects the bill, not the service.
  if (!(await withinDeviceQuota({ principal, cost }))) {
    console.warn(`[${logLabel}] principal exceeded daily quota`);
    refuse(res, 'daily_quota');
    return;
  }

  // Free-tier scan allowance, on routes that pass `scanSucceeded`.
  // Charged after every other refusal so a rejected request never
  // spends a scan, and refunded unless the scan produced a result.
  const scan = scanSucceeded ? await chargeScan(req, { principal, logLabel }) : null;
  if (scan && !scan.allowed) {
    await refundSpend({ principal, cost, budget: false });
    refuse(res, 'scan_quota');
    return;
  }
  let scanSpent = false;

  // Hard spend ceiling, checked last so only requests that would
  // actually reach Anthropic consume budget. Fail closed with the
  // same generic 503 the missing-key path uses — the client treats
  // both as "try later", and the reason stays server-side.
  if (!(await withinDailyBudget({ cost }))) {
    console.error(`[${logLabel}] daily Anthropic budget exhausted or unverifiable`);
    await refundSpend({ principal, cost, budget: false });
    await scan?.refund();
    refuse(res, 'unavailable');
    return;
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const upstream = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        ...(betas?.length ? { 'anthropic-beta': betas.join(',') } : {}),
      },
      body: JSON.stringify(clean),
      signal: controller.signal,
    });

    if (!upstream.ok) {
      // Don't echo Anthropic's response body or status — the body can
      // carry org IDs / model hints, and the exact status (401/429/
      // 529) leaks server-side key state useful for reconnaissance.
      // Collapse every upstream failure into a generic 502; the real
      // status is logged server-side only. Only an overloaded or
      // rate-limited upstream is marked worth the app paying for a
      // second try; anything else fails the same way again.
      console.error(`[${logLabel}] upstream non-2xx`, upstream.status);
      const retryable = upstream.status === 429 || upstream.status >= 500;
      await refundSpend({ principal, cost });
      res.status(502).json({ error: { message: 'Upstream error', ...(retryable && { retryable: true }) } });
      return;
    }

    if (readResponse) {
      const { status, body } = readResponse(await upstream.json());
      scanSpent = Boolean(scanSucceeded?.(status, body));
      res.status(status).json(body);
      return;
    }

    const text = await upstream.text();
    res.status(upstream.status);
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/json');
    res.send(text);
  } catch (err) {
    // No refund on a timeout: Anthropic may still finish, and bill,
    // the generation we stopped waiting for.
    if (err && err.name === 'AbortError') {
      console.error(`[${logLabel}] upstream timeout`);
      res.status(504).json({ error: { message: 'Upstream timeout' } });
      return;
    }
    console.error(`[${logLabel}] fetch failure`, err);
    await refundSpend({ principal, cost });
    res.status(502).json({ error: { message: 'Proxy failure', retryable: true } });
  } finally {
    clearTimeout(timeout);
    if (scan && !scanSpent) await scan.refund();
  }
}
