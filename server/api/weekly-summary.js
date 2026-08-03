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
import { clientKey } from './_lib/anthropic-proxy.js';
import { checkAppAttest } from './_lib/app-attest.js';
import { authorize } from './_lib/auth.js';
import {
  allowRate,
  isBlocked,
  recordLimitStrike,
  requestCost,
  withinDailyBudget,
  withinDeviceQuota,
} from './_lib/rate-limit.js';

const MODEL = 'claude-sonnet-4-6';
const MAX_TOKENS = 360; // ~280 words; 150 ideal, 200 hard ceiling
// Mirrors the bodyParser sizeLimit below; re-checked on the parsed
// body like `_lib/anthropic-proxy.js` does.
const MAX_BODY_BYTES = 64 * 1024;

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

// Per-principal cap via the shared limiter (Redis-backed when
// configured, per-instance memory otherwise). Weekly summaries fire at
// most once per week per user, so 6/min is generous — anything higher
// is retry-loop noise or abuse.
//
// The principal is the verified App Attest key when there is one, else
// the Vercel-derived (un-spoofable) client IP — the same derivation
// all three routes share. See `principalFor` in `_lib/anthropic-proxy.js`
// for why an IP alone is a weak identity.
function principalFor(req, attest) {
  if (attest?.keyId) return `k:${attest.keyId}`;
  return `ip:${clientKey(req)}`;
}

function checkRateLimit(principal, cost) {
  const limit = parseInt(process.env.WEEKLY_RPM || '6', 10);
  return allowRate({ name: 'weekly-summary', key: principal, limit, windowSeconds: 60, cost });
}

/**
 * Rebuilds the aggregate from an explicit allowlist of known fields
 * (see `WeeklyAggregate` in `Peptide/Models/WeeklySummary.swift`) with
 * a per-field type check. Returns null when the required core fields
 * are missing/malformed. Unknown keys — and any free-text a tampered
 * client may have appended — are dropped, so only this bounded shape
 * ever reaches the model prompt: a client cannot smuggle a large
 * adversarial blob into the prompt or inflate the token count.
 */
function asNum(v) {
  return typeof v === 'number' && Number.isFinite(v) ? v : undefined;
}
function asInt(v) {
  const n = asNum(v);
  return n === undefined ? undefined : Math.trunc(n);
}

function sanitiseAggregate(agg) {
  if (!agg || typeof agg !== 'object') return null;
  // Strict ISO-date (no time component). The iOS encoder emits
  // `YYYY-MM-DD` (10 chars); a looser cap let a truncated datetime
  // through which could narrow down the user's timezone if correlated
  // externally.
  if (typeof agg.weekStart !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(agg.weekStart)) return null;

  const c = agg.compliance;
  if (!c || typeof c !== 'object') return null;
  const completed = asInt(c.completed);
  const total = asInt(c.total);
  if (completed === undefined || total === undefined) return null;
  if (total < 0 || total > 200) return null; // a week can't exceed this; reject blatant noise

  const clean = {
    weekStart: agg.weekStart,
    compliance: {
      completed,
      total,
      pct: asNum(c.pct) ?? 0,
      bestDayPct: asNum(c.bestDayPct) ?? 0,
      activeDaysCount: asInt(c.activeDaysCount) ?? 0,
    },
  };

  const s = agg.streak;
  if (s && typeof s === 'object') {
    clean.streak = { current: asInt(s.current) ?? 0, best: asInt(s.best) ?? 0 };
  }

  const o = agg.outcomes;
  if (o && typeof o === 'object') {
    clean.outcomes = {
      energyAvg: asNum(o.energyAvg) ?? 0,
      sleepAvg: asNum(o.sleepAvg) ?? 0,
      recoveryAvg: asNum(o.recoveryAvg) ?? 0,
      moodAvg: asNum(o.moodAvg) ?? 0,
      focusAvg: asNum(o.focusAvg) ?? 0,
      compositeDelta: asNum(o.compositeDelta) ?? 0,
      checkInsCount: asInt(o.checkInsCount) ?? 0,
    };
  }

  const n = agg.nutrition;
  if (n && typeof n === 'object') {
    clean.nutrition = {
      avgCalories: asInt(n.avgCalories) ?? 0,
      targetCalories: asInt(n.targetCalories) ?? 0,
      mealLoggingDays: asInt(n.mealLoggingDays) ?? 0,
      proteinAvgG: asInt(n.proteinAvgG) ?? 0,
      proteinTargetG: asInt(n.proteinTargetG) ?? 0,
    };
  }

  const b = agg.biometrics;
  if (b && typeof b === 'object') {
    const bio = {};
    if (asInt(b.hrvAvg) !== undefined) bio.hrvAvg = asInt(b.hrvAvg);
    if (asInt(b.hrvDelta) !== undefined) bio.hrvDelta = asInt(b.hrvDelta);
    if (asInt(b.rhrAvg) !== undefined) bio.rhrAvg = asInt(b.rhrAvg);
    if (asNum(b.sleepHoursAvg) !== undefined) bio.sleepHoursAvg = asNum(b.sleepHoursAvg);
    clean.biometrics = bio;
  }

  const l = agg.labs;
  if (l && typeof l === 'object' && asInt(l.newPanelsLogged) !== undefined) {
    clean.labs = { newPanelsLogged: asInt(l.newPanelsLogged) };
  }

  if (typeof agg.topInsightCategory === 'string') {
    // Stable category codes are short; cap hard so this can never be
    // a free-text injection vector.
    clean.topInsightCategory = agg.topInsightCategory.slice(0, 64);
  }

  return clean;
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

  // App Attest runs before throttling — its verified key is the identity
  // the limits count against. Same semantics as the main proxy routes.
  const attest = await checkAppAttest(req, { logLabel: 'weekly-summary' });
  if (!attest.ok) {
    res.status(401).json({ error: { message: 'Unauthorised', code: 'attest_required' } });
    return;
  }

  const principal = principalFor(req, attest);
  const cost = requestCost(req);

  if (await isBlocked({ principal })) {
    res.status(429).json({ error: { message: 'Too many requests' } });
    return;
  }

  if (!(await checkRateLimit(principal, cost))) {
    if (await recordLimitStrike({ principal })) {
      console.warn('[weekly-summary] principal blocked for repeated limit strikes');
    }
    res.status(429).json({ error: { message: 'Too many requests' } });
    return;
  }

  if (!(await withinDeviceQuota({ principal, cost }))) {
    console.warn('[weekly-summary] principal exceeded daily quota');
    res.status(429).json({ error: { message: 'Daily limit reached; try again tomorrow' } });
    return;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    console.error('[weekly-summary] ANTHROPIC_API_KEY missing on this deployment');
    res.status(503).json({ error: { message: 'Service unavailable' } });
    return;
  }

  // bodyParser's sizeLimit guards the wire; re-check the parsed body
  // so a chunked request that understates content-length can't slip
  // past it either.
  const parsedBytes = Buffer.byteLength(JSON.stringify(req.body ?? ''), 'utf8');
  if (parsedBytes > MAX_BODY_BYTES) {
    res.status(413).json({ error: { message: 'Request too large' } });
    return;
  }

  const aggregate = sanitiseAggregate(req.body?.aggregate);
  if (!aggregate) {
    res.status(400).json({ error: { message: 'Malformed aggregate' } });
    return;
  }

  // Shared daily spend ceiling across all proxy routes, checked last
  // so only requests that would actually reach Anthropic consume it.
  // Same generic 503 as the missing-key path — reason stays
  // server-side, and the iOS client already falls back deterministically.
  if (!(await withinDailyBudget({ cost }))) {
    console.error('[weekly-summary] daily Anthropic budget exhausted or unverifiable');
    res.status(503).json({ error: { message: 'Service unavailable' } });
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

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);
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
      body: JSON.stringify(body),
      signal: controller.signal
    });

    if (!upstream.ok) {
      // Collapse every upstream failure into a generic 502 — echoing
      // Anthropic's exact status leaks server-side key state. The
      // iOS client has a deterministic offline fallback for any 5xx.
      console.error('[weekly-summary] upstream non-2xx', upstream.status);
      res.status(502).json({ error: { message: 'Upstream error' } });
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
    if (err && err.name === 'AbortError') {
      console.error('[weekly-summary] upstream timeout');
      res.status(504).json({ error: { message: 'Upstream timeout' } });
      return;
    }
    console.error('[weekly-summary] fetch failure', err);
    res.status(502).json({ error: { message: 'Proxy failure' } });
  } finally {
    clearTimeout(timeout);
  }
}

export const config = {
  api: {
    bodyParser: {
      sizeLimit: '64kb' // aggregate is tiny; nothing larger is legitimate
    }
  }
};
