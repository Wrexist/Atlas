/**
 * Shared proxy logic for every Atlas → Anthropic route. Holds the
 * server-side API key, authenticates clients via a shared secret,
 * sanitises the request body, throttles per IP, and forwards to
 * `api.anthropic.com/v1/messages`. The iOS client never sees the
 * upstream Anthropic key.
 *
 * Routes (meal-scan, ai-research) thin-wrap `forwardToAnthropic` so
 * adding the next defense (App Attest) is a one-place change.
 *
 * Env vars (set on the Vercel deployment):
 *   ANTHROPIC_API_KEY    — server-side Anthropic key.
 *   PROXY_SHARED_SECRET  — random 32+ byte string the iOS client
 *                          echoes as `X-Peptide-Proxy`.
 *   ALLOWED_MODELS       — comma-separated Anthropic model IDs.
 *                          Default: claude-sonnet-4-6.
 *   RATE_LIMIT_RPM       — per-IP requests per minute per route.
 *                          Default 20.
 *   UPSTASH_REDIS_REST_URL / UPSTASH_REDIS_REST_TOKEN
 *                        — optional Redis backing so the limits hold
 *                          across all instances (see _lib/rate-limit.js).
 *   ANTHROPIC_DAILY_REQUEST_BUDGET
 *                        — optional hard cap on upstream requests per
 *                          UTC day across all routes; 503 once spent.
 *   APP_ATTEST_MODE / APP_ATTEST_APP_ID
 *                        — App Attest assertion gate; see
 *                          _lib/app-attest.js for modes and rollout.
 *
 * iOS clients pull the proxy URL and the matching secret from
 * Info.plist (or scheme env): `MEAL_SCANNER_ENDPOINT` +
 * `MEAL_SCANNER_SECRET`, and `AI_RESEARCH_ENDPOINT` +
 * `AI_RESEARCH_SECRET`. The same `PROXY_SHARED_SECRET` server-side
 * value goes into both client secrets.
 */
import { checkAppAttest } from './app-attest.js';
import { authorize } from './auth.js';
import { allowRate, withinDailyBudget } from './rate-limit.js';

const DEFAULT_ALLOWED_MODEL = 'claude-sonnet-4-6';
const MAX_TOKENS_HARDCAP = 800;
// Cap large enough for the AI research multi-turn chat flow (history +
// new turn). 4 was too small — the third user turn already produced 5
// messages and the proxy rejected it.
const MAX_MESSAGES = 40;
// Absolute body-size ceiling. Each route can pass a tighter
// `maxBodyBytes` to `forwardToAnthropic` — meal-scan needs ~5 MB for
// a JPEG payload, ai-research is text-only and ~64 KB is plenty.
const MAX_BODY_BYTES = 7 * 1024 * 1024;

function getAllowedModels() {
  const raw = process.env.ALLOWED_MODELS;
  if (!raw) return [DEFAULT_ALLOWED_MODEL];
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

// Scoped per route (logLabel) so a meal-scan burst can't starve
// ai-research — the same isolation the old per-lambda Maps had by
// accident of deployment topology.
function checkRateLimit(req, logLabel) {
  const limit = parseInt(process.env.RATE_LIMIT_RPM || '20', 10);
  return allowRate({ name: logLabel, key: clientKey(req), limit, windowSeconds: 60 });
}

// Anthropic accepts content parts of these typed shapes. Anything else
// (tool_use, tool_result, document, ...) is rejected so a tampered
// client can't reach features the app doesn't ship — and so the proxy
// surface only exposes what the iOS code actually sends.
const ALLOWED_CONTENT_TYPES = new Set(['text', 'image']);

function sanitiseContent(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return null;
  const parts = [];
  for (const part of content) {
    if (!part || typeof part !== 'object') return null;
    if (!ALLOWED_CONTENT_TYPES.has(part.type)) return null;
    parts.push(part);
  }
  return parts;
}

function sanitiseBody(raw, options) {
  if (!raw || typeof raw !== 'object') return null;
  const allowedModels = getAllowedModels();
  const model = typeof raw.model === 'string' && allowedModels.includes(raw.model)
    ? raw.model
    : allowedModels[0];

  const maxTokensRaw = Number(raw.max_tokens);
  const max_tokens = Number.isFinite(maxTokensRaw) && maxTokensRaw > 0
    ? Math.min(Math.floor(maxTokensRaw), MAX_TOKENS_HARDCAP)
    : MAX_TOKENS_HARDCAP;

  if (!Array.isArray(raw.messages) || raw.messages.length === 0) return null;
  if (raw.messages.length > MAX_MESSAGES) return null;

  const messages = raw.messages.map((m) => {
    if (!m || (m.role !== 'user' && m.role !== 'assistant')) return null;
    const content = sanitiseContent(m.content);
    if (content === null) return null;
    return { role: m.role, content };
  });
  if (messages.some((m) => m === null)) return null;

  const out = { model, max_tokens, messages };

  // System-prompt handling. Routes that don't expect a client system
  // (`allowClientSystem: false`) drop any client-supplied value
  // entirely. Routes that do still always get the pinned safety
  // prefix prepended, so an injected client system can extend the
  // grounding but never override it.
  const allowClientSystem = options?.allowClientSystem !== false;
  const pinnedPrefix = typeof options?.systemPrefix === 'string' ? options.systemPrefix : '';
  const clientSystem = allowClientSystem && typeof raw.system === 'string'
    ? raw.system.slice(0, 4000)
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
  maxBodyBytes,
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

  if (!(await checkRateLimit(req, logLabel))) {
    res.status(429).json({ error: { message: 'Too many requests' } });
    return;
  }

  // App Attest gate (see _lib/app-attest.js). Only rejects in
  // enforce mode; report mode verifies + logs so the rollout can be
  // validated from production logs before anything is blocked. The
  // `attest_required` code tells a genuine client to (re-)register
  // its key rather than treat this as a secret failure.
  const attest = await checkAppAttest(req, { logLabel });
  if (!attest.ok) {
    res.status(401).json({ error: { message: 'Unauthorised', code: 'attest_required' } });
    return;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    // Log loudly server-side so the deployer notices, but tell the
    // client a generic "service unavailable" — leaking "proxy not
    // configured" advertises a half-deployed environment.
    console.error(`[${logLabel}] ANTHROPIC_API_KEY missing on this deployment`);
    res.status(503).json({ error: { message: 'Service unavailable' } });
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
  // global 7 MB bodyParser limit.
  const parsedBytes = Buffer.byteLength(JSON.stringify(req.body ?? ''), 'utf8');
  if (parsedBytes > bodyCap) {
    res.status(413).json({
      error: { message: 'Request too large; resize before retrying' }
    });
    return;
  }

  const clean = sanitiseBody(req.body, { systemPrefix, allowClientSystem });
  if (!clean) {
    res.status(400).json({ error: { message: 'Malformed request body' } });
    return;
  }

  // Hard spend ceiling, checked last so only requests that would
  // actually reach Anthropic consume budget. Fail closed with the
  // same generic 503 the missing-key path uses — the client treats
  // both as "try later", and the reason stays server-side.
  if (!(await withinDailyBudget())) {
    console.error(`[${logLabel}] daily Anthropic request budget exhausted`);
    res.status(503).json({ error: { message: 'Service unavailable' } });
    return;
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);
  try {
    const upstream = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(clean),
      signal: controller.signal,
    });

    if (!upstream.ok) {
      // Don't echo Anthropic's response body or status — the body can
      // carry org IDs / model hints, and the exact status (401/429/
      // 529) leaks server-side key state useful for reconnaissance.
      // Collapse every upstream failure into a generic 502; the real
      // status is logged server-side only.
      console.error(`[${logLabel}] upstream non-2xx`, upstream.status);
      res.status(502).json({ error: { message: 'Upstream error' } });
      return;
    }

    const text = await upstream.text();
    res.status(upstream.status);
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/json');
    res.send(text);
  } catch (err) {
    if (err && err.name === 'AbortError') {
      console.error(`[${logLabel}] upstream timeout`);
      res.status(504).json({ error: { message: 'Upstream timeout' } });
      return;
    }
    console.error(`[${logLabel}] fetch failure`, err);
    res.status(502).json({ error: { message: 'Proxy failure' } });
  } finally {
    clearTimeout(timeout);
  }
}

export const sharedConfig = {
  api: {
    bodyParser: {
      sizeLimit: '7mb',
    },
  },
};
