/**
 * Vercel serverless proxy for the PeptideX meal scanner.
 *
 * Why this exists: the iOS client at MealScannerService.swift can hit
 * Anthropic's Messages API directly using an API key embedded in the
 * shipping binary, which is unsafe — anyone who jailbreaks an iPhone
 * can extract the key. This function holds the key server-side and
 * forwards a sanitised request so the client never sees it.
 *
 * Deploy:
 *   1. Push this directory to a GitHub repo (or `vercel deploy` it).
 *   2. In the Vercel dashboard, set:
 *        ANTHROPIC_API_KEY  = your Anthropic key
 *        PROXY_SHARED_SECRET = a long random string (e.g. `openssl rand -hex 32`)
 *      Optional:
 *        ALLOWED_MODELS    = comma-separated Anthropic model IDs (default: claude-sonnet-4-6)
 *        RATE_LIMIT_RPM    = per-IP requests per minute (default: 20)
 *   3. Add MEAL_SCANNER_ENDPOINT = https://<your-deploy>.vercel.app/api/meal-scan
 *      and MEAL_SCANNER_SECRET = <same value as PROXY_SHARED_SECRET>
 *      to the iOS app's Info.plist (or scheme env var). The client
 *      sends the secret in the X-Peptide-Proxy header.
 *
 * Body shape: subset of api.anthropic.com/v1/messages — { model,
 * max_tokens, messages }. Unknown top-level keys are stripped so a
 * compromised client can't add `tools`, alternate system prompts, etc.
 */

// In-memory token bucket keyed by client IP. Persists across warm
// invocations of the same Vercel instance; cold starts reset state, which
// is acceptable for a soft cap. For a hard cap, swap in Upstash/Edge
// Config.
const buckets = new Map();
const RATE_LIMIT_WINDOW_MS = 60 * 1000;

const DEFAULT_ALLOWED_MODEL = 'claude-sonnet-4-6';
const MAX_TOKENS_HARDCAP = 600;
const MAX_MESSAGES = 4;

function getAllowedModels() {
  const raw = process.env.ALLOWED_MODELS;
  if (!raw) return [DEFAULT_ALLOWED_MODEL];
  return raw.split(',').map((s) => s.trim()).filter(Boolean);
}

function clientKey(req) {
  // x-forwarded-for can carry a comma-separated chain; the first entry is
  // the original client.
  const forwarded = (req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return forwarded || req.socket?.remoteAddress || 'unknown';
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

function sanitiseBody(raw) {
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

  // Pass messages through but strip unknown fields per item. Anthropic
  // accepts { role, content } where content is a string or an array of
  // typed parts ({ type: "text" | "image", ... }).
  const messages = raw.messages.map((m) => {
    if (!m || (m.role !== 'user' && m.role !== 'assistant')) return null;
    return { role: m.role, content: m.content };
  });
  if (messages.some((m) => m === null)) return null;

  const out = { model, max_tokens, messages };
  if (typeof raw.system === 'string') out.system = raw.system.slice(0, 2000);
  return out;
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: 'Use POST' } });
    return;
  }

  const sharedSecret = process.env.PROXY_SHARED_SECRET;
  if (!sharedSecret) {
    res.status(500).json({ error: { message: 'Proxy not configured' } });
    return;
  }
  const presented = req.headers['x-peptide-proxy'];
  if (typeof presented !== 'string' || presented !== sharedSecret) {
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

  // Defensive size cap — the iOS client compresses to 1024 px max edge
  // at JPEG quality 0.7, which is well under 5 MB even for 12-megapixel
  // originals. Reject anything significantly larger to avoid abuse.
  const contentLength = parseInt(req.headers['content-length'] || '0', 10);
  if (contentLength > 7 * 1024 * 1024) {
    res.status(413).json({
      error: { message: 'Request too large; resize the photo before retrying' }
    });
    return;
  }

  const clean = sanitiseBody(req.body);
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
      // Don't echo Anthropic's response body to the client — it can carry
      // organisation IDs, model availability hints, and request metadata
      // that's useful for reconnaissance.
      console.error('proxy: upstream non-2xx', upstream.status);
      res.status(upstream.status).json({
        error: { message: 'Upstream error', status: upstream.status }
      });
      return;
    }

    const text = await upstream.text();
    res.status(upstream.status);
    const upstreamContentType = upstream.headers.get('content-type') || 'application/json';
    res.setHeader('Content-Type', upstreamContentType);
    res.send(text);
  } catch (err) {
    console.error('proxy: fetch failure', err);
    res.status(502).json({ error: { message: 'Proxy failure' } });
  }
}

export const config = {
  // 1024 px / quality 0.7 JPEGs land around 200-400 KB; allow up to 7 MB
  // to leave headroom for the JSON envelope and base64 expansion.
  api: {
    bodyParser: {
      sizeLimit: '7mb',
    },
  },
};
