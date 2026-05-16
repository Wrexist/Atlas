/**
 * Shared proxy logic for every Atlas → Anthropic route. Holds the
 * server-side API key, authenticates clients via a shared secret,
 * sanitises the request body, throttles per IP, and forwards to
 * `api.anthropic.com/v1/messages`. The iOS client never sees the
 * upstream Anthropic key.
 *
 * Routes (meal-scan, ai-research) thin-wrap `forwardToAnthropic` so
 * adding the next defense (App Attest, Vercel KV-backed limits) is a
 * one-place change.
 *
 * Env vars (set on the Vercel deployment):
 *   ANTHROPIC_API_KEY    — server-side Anthropic key.
 *   PROXY_SHARED_SECRET  — random 32+ byte string the iOS client
 *                          echoes as `X-Peptide-Proxy`.
 *   ALLOWED_MODELS       — comma-separated Anthropic model IDs.
 *                          Default: claude-sonnet-4-6.
 *   RATE_LIMIT_RPM       — per-IP requests per minute. Default 20.
 *
 * iOS clients pull the proxy URL and the matching secret from
 * Info.plist (or scheme env): `MEAL_SCANNER_ENDPOINT` +
 * `MEAL_SCANNER_SECRET`, and `AI_RESEARCH_ENDPOINT` +
 * `AI_RESEARCH_SECRET`. The same `PROXY_SHARED_SECRET` server-side
 * value goes into both client secrets.
 */
import { timingSafeEqual } from 'node:crypto';

// In-memory token bucket keyed by client IP. Persists across warm
// invocations of the same Vercel instance; cold starts reset state,
// which is acceptable for a soft cap. For a hard cap, swap in Upstash
// / Edge Config.
const buckets = new Map();
const RATE_LIMIT_WINDOW_MS = 60 * 1000;

const DEFAULT_ALLOWED_MODEL = 'claude-sonnet-4-6';
const MAX_TOKENS_HARDCAP = 800;
// Cap large enough for the AI research multi-turn chat flow (history +
// new turn). 4 was too small — the third user turn already produced 5
// messages and the proxy rejected it.
const MAX_MESSAGES = 40;
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

function checkRateLimit(req) {
  const limit = parseInt(process.env.RATE_LIMIT_RPM || '20', 10);
  if (!Number.isFinite(limit) || limit <= 0) return true;
  const key = clientKey(req);
  const now = Date.now();
  const bucket = buckets.get(key);
  if (!bucket || now - bucket.start > RATE_LIMIT_WINDOW_MS) {
    buckets.set(key, { start: now, count: 1 });
    return true;
  }
  bucket.count += 1;
  return bucket.count <= limit;
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

function constantTimeEquals(a, b) {
  // Pad to equal length first — timingSafeEqual throws on mismatched
  // lengths, which is itself a timing leak. The padded compare runs
  // for the same time as a real one, then we reject the mismatch.
  const aBuf = Buffer.from(a, 'utf8');
  const bBuf = Buffer.from(b, 'utf8');
  if (aBuf.length !== bBuf.length) {
    timingSafeEqual(aBuf, aBuf);
    return false;
  }
  return timingSafeEqual(aBuf, bBuf);
}

function authorize(req) {
  const expected = process.env.PROXY_SHARED_SECRET;
  if (!expected) return false; // fail closed when env is missing
  const provided = req.headers['x-peptide-proxy'];
  if (typeof provided !== 'string' || provided.length === 0) return false;
  return constantTimeEquals(provided, expected);
}

export async function forwardToAnthropic(req, res, { logLabel, systemPrefix, allowClientSystem }) {
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

  if (!checkRateLimit(req)) {
    res.status(429).json({ error: { message: 'Too many requests' } });
    return;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: { message: 'Proxy not configured' } });
    return;
  }

  const contentLength = parseInt(req.headers['content-length'] || '0', 10);
  if (contentLength > MAX_BODY_BYTES) {
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

  try {
    const upstream = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(clean),
    });

    if (!upstream.ok) {
      // Don't echo Anthropic's response body — it can carry org IDs,
      // model availability hints, and request metadata useful for
      // reconnaissance.
      console.error(`[${logLabel}] upstream non-2xx`, upstream.status);
      res.status(upstream.status).json({
        error: { message: 'Upstream error', status: upstream.status }
      });
      return;
    }

    const text = await upstream.text();
    res.status(upstream.status);
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/json');
    res.send(text);
  } catch (err) {
    console.error(`[${logLabel}] fetch failure`, err);
    res.status(502).json({ error: { message: 'Proxy failure' } });
  }
}

export const sharedConfig = {
  api: {
    bodyParser: {
      sizeLimit: '7mb',
    },
  },
};
