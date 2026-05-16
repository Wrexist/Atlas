/**
 * Vercel proxy route for Atlas's AI weekly summary. Bypasses
 * the shared `forwardToAnthropic` helper because this endpoint owns
 * the system prompt and applies Anthropic prompt caching to the
 * cacheable prefix — 90 %+ cost reduction once the cache warms.
 *
 * iOS env vars (Info.plist or scheme env):
 *   WEEKLY_SUMMARY_ENDPOINT = https://<deploy>/api/weekly-summary
 *   WEEKLY_SUMMARY_SECRET   = the PROXY_SHARED_SECRET value
 *
 * Payload from the iOS client: `{ aggregate: WeeklyAggregate }`.
 * The aggregate is anonymized — no peptide names, no UUIDs, no raw
 * dates beyond `weekStart`. See `Peptide/Models/WeeklySummary.swift`
 * for the full privacy contract.
 *
 * Returns: `{ text: string, generatedAt: ISOString }`.
 */
import { timingSafeEqual } from 'node:crypto';
import { clientKey } from './_lib/anthropic-proxy.js';

const MODEL = 'claude-sonnet-4-6';
const MAX_TOKENS = 360; // ~280 words; 150 ideal, 200 hard ceiling
const PROXY_HEADER = 'x-peptide-proxy';

const SYSTEM_PROMPT = [
  "You are Atlas's weekly coach. Summarize the user's last 7 days in 2-3 short paragraphs, ~150 words total.",
  "",
  "Tone: honest, encouraging, never alarmist. Personal but not familiar — like a thoughtful coach, not a friend.",
  "",
  "Rules:",
  "• Never make medical claims. Avoid: \"should\", \"must\", \"proven\", \"treat\", \"cure\", \"diagnose\", \"prescribe\".",
  "• Don't speculate on causation. Say \"trended with\" or \"alongside\", never \"caused\" or \"because of\".",
  "• If a stat is missing or marked null, don't mention it — never invent data.",
  "• No peptide names, dosages, or protocol specifics — the aggregate doesn't carry them, and you must not guess.",
  "• Use the numbers provided verbatim. If compliance was 86 %, say 86 %, not \"strong\" or \"most\".",
  "",
  "Structure:",
  "1. One sentence opener: how the week went overall.",
  "2. 2-3 specific observations grounded in the numbers (compliance pct, streak length, check-in averages, HRV delta if present).",
  "3. One forward-looking line for next week — encouraging, not prescriptive.",
  "",
  "Output: plain text, no markdown, no bullet points, no headings. The iOS card renders the paragraphs as-is."
].join("\n");

function constantTimeEquals(a, b) {
  const aBuf = Buffer.from(a, 'utf8');
  const bBuf = Buffer.from(b, 'utf8');
  if (aBuf.length !== bBuf.length) {
    // Run a same-length compare on a self-pair so the timing cost
    // doesn't telegraph "wrong length". Then reject the mismatch.
    timingSafeEqual(aBuf, aBuf);
    return false;
  }
  return timingSafeEqual(aBuf, bBuf);
}

function authorize(req) {
  const expected = process.env.PROXY_SHARED_SECRET;
  if (!expected) return false; // fail closed when env is missing
  const provided = req.headers[PROXY_HEADER];
  if (typeof provided !== 'string' || provided.length === 0) return false;
  return constantTimeEquals(provided, expected);
}

// Per-IP token bucket. Weekly summaries fire at most once per week
// per user, so 4/min is generous — anything higher than a handful is
// retry-loop noise or abuse.
const buckets = new Map();
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const RATE_LIMIT_RPM = parseInt(process.env.WEEKLY_RPM || '6', 10);

// `clientKey` lives in `_lib/anthropic-proxy.js` so all three routes share
// the same Vercel-aware (un-spoofable) IP derivation.

function checkRateLimit(req) {
  if (!Number.isFinite(RATE_LIMIT_RPM) || RATE_LIMIT_RPM <= 0) return true;
  const key = clientKey(req);
  const now = Date.now();
  const bucket = buckets.get(key);
  if (!bucket || now - bucket.start > RATE_LIMIT_WINDOW_MS) {
    buckets.set(key, { start: now, count: 1 });
    return true;
  }
  bucket.count += 1;
  return bucket.count <= RATE_LIMIT_RPM;
}

/**
 * Light schema check on the aggregate. Belt-and-suspenders over the
 * iOS encoder — guards against bad data poisoning the prompt and
 * blowing up the token count.
 */
function validateAggregate(agg) {
  if (!agg || typeof agg !== 'object') return false;
  if (typeof agg.weekStart !== 'string' || agg.weekStart.length > 16) return false;
  const c = agg.compliance;
  if (!c || typeof c !== 'object') return false;
  if (typeof c.completed !== 'number' || typeof c.total !== 'number') return false;
  if (c.total > 200) return false; // a week can't exceed this; reject blatant noise
  return true;
}

function buildUserPrompt(aggregate) {
  // Pretty-printed JSON is what the model reads best. Stays
  // deterministic per aggregate so identical aggregates (rare but
  // possible) hit any downstream caching cleanly.
  return [
    "Here is the user's aggregate for the past week. Write the summary.",
    "",
    "```json",
    JSON.stringify(aggregate, null, 2),
    "```"
  ].join("\n");
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: 'Use POST' } });
    return;
  }

  if (!authorize(req)) {
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

  const aggregate = req.body?.aggregate;
  if (!validateAggregate(aggregate)) {
    res.status(400).json({ error: { message: 'Malformed aggregate' } });
    return;
  }

  // System content blocks with cache_control on the static prompt
  // → first call warms the cache, every subsequent call hits a 90 %
  // discount on those tokens. The aggregate goes in the user
  // message, never the system block.
  const body = {
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system: [
      {
        type: 'text',
        text: SYSTEM_PROMPT,
        cache_control: { type: 'ephemeral' }
      }
    ],
    messages: [
      {
        role: 'user',
        content: buildUserPrompt(aggregate)
      }
    ]
  };

  try {
    const upstream = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        // Prompt-caching beta header — required for cache_control
        // blocks to apply. Pin the date so a future beta cycle that
        // changes semantics doesn't silently break.
        'anthropic-beta': 'prompt-caching-2024-07-31'
      },
      body: JSON.stringify(body)
    });

    if (!upstream.ok) {
      console.error('[weekly-summary] upstream non-2xx', upstream.status);
      res.status(upstream.status).json({
        error: { message: 'Upstream error', status: upstream.status }
      });
      return;
    }

    const data = await upstream.json();
    // Anthropic's response shape: content is an array of typed
    // blocks. We expect a single text block; concatenate defensively.
    const text = Array.isArray(data.content)
      ? data.content
          .filter((b) => b && b.type === 'text' && typeof b.text === 'string')
          .map((b) => b.text)
          .join('\n\n')
          .trim()
      : '';

    if (!text) {
      console.error('[weekly-summary] empty text in response');
      res.status(502).json({ error: { message: 'Empty response from model' } });
      return;
    }

    // Optional cache-hit telemetry — Anthropic returns
    // `usage.cache_read_input_tokens` and
    // `usage.cache_creation_input_tokens`. Log only the counts.
    if (data?.usage) {
      console.log(
        '[weekly-summary] usage',
        JSON.stringify({
          input: data.usage.input_tokens ?? 0,
          output: data.usage.output_tokens ?? 0,
          cacheRead: data.usage.cache_read_input_tokens ?? 0,
          cacheCreation: data.usage.cache_creation_input_tokens ?? 0
        })
      );
    }

    res.status(200).json({
      text,
      generatedAt: new Date().toISOString()
    });
  } catch (err) {
    console.error('[weekly-summary] fetch failure', err);
    res.status(502).json({ error: { message: 'Proxy failure' } });
  }
}

export const config = {
  api: {
    bodyParser: {
      sizeLimit: '64kb' // aggregate is tiny; nothing larger is legitimate
    }
  }
};
