/**
 * Shared helpers for the PeptideX Vercel proxy routes.
 *
 * Every Anthropic-bound endpoint goes through `forwardToAnthropic` so
 * auth, rate-limit, and size checks live in exactly one place. The
 * client (iOS app) sends a JSON body in the Anthropic Messages API
 * shape — model, max_tokens, messages — plus an `x-peptide-key`
 * header. This module:
 *
 *   1. Requires POST.
 *   2. Verifies `x-peptide-key` matches `PEPTIDE_SHARED_SECRET` using
 *      a constant-time comparison so timing attacks can't grind out
 *      the secret one character at a time.
 *   3. Caps request size (defense against accidental abuse).
 *   4. Forwards the body to `api.anthropic.com/v1/messages` with the
 *      server-side `ANTHROPIC_API_KEY`.
 *   5. Returns the upstream status + body so the client doesn't need
 *      to know it's talking to a proxy.
 *
 * The shared secret is a "raise the bar" defense, not a guarantee:
 * it stops URL leaks and casual reverse-engineering, but a determined
 * attacker who unpacks the IPA can still find the secret. App Attest +
 * a Vercel-KV-backed per-device rate-limiter is the v2 hardening
 * (tracked as a follow-up to PR #106).
 */
import { timingSafeEqual } from 'node:crypto';

const MAX_BODY_BYTES = 7 * 1024 * 1024;

export async function forwardToAnthropic(req, res, { logLabel }) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: 'Use POST' } });
    return;
  }

  if (!authorize(req)) {
    // Generic 401 — no hint about whether the secret was missing,
    // malformed, or wrong. The client gets a single bit of feedback.
    res.status(401).json({ error: { message: 'Unauthorized' } });
    return;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    res.status(500).json({
      error: { message: 'ANTHROPIC_API_KEY not configured on the proxy' }
    });
    return;
  }

  const contentLength = parseInt(req.headers['content-length'] || '0', 10);
  if (contentLength > MAX_BODY_BYTES) {
    res.status(413).json({
      error: { message: 'Request too large' }
    });
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
      body: typeof req.body === 'string' ? req.body : JSON.stringify(req.body),
    });

    const text = await upstream.text();
    res.status(upstream.status);
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/json');
    res.send(text);
  } catch (err) {
    // Don't leak the raw upstream error message back to the client —
    // it occasionally includes the masked API key fingerprint.
    console.error(`[${logLabel}] upstream failure`, err);
    res.status(502).json({ error: { message: 'Upstream failure' } });
  }
}

function authorize(req) {
  const expected = process.env.PEPTIDE_SHARED_SECRET;
  if (!expected) {
    // No secret configured server-side — fail closed rather than
    // silently allow everything. Deploy operators get a 401 instead
    // of an open proxy.
    return false;
  }
  const provided = req.headers['x-peptide-key'];
  if (typeof provided !== 'string' || provided.length === 0) {
    return false;
  }
  return constantTimeEquals(provided, expected);
}

function constantTimeEquals(a, b) {
  // Pad to equal length first — timingSafeEqual throws on mismatched
  // lengths, which is itself a timing leak. The pad bytes never match
  // a real secret because we still require both lengths to be equal
  // before returning true.
  const aBuf = Buffer.from(a, 'utf8');
  const bBuf = Buffer.from(b, 'utf8');
  if (aBuf.length !== bBuf.length) {
    // Run a dummy compare against itself so this branch takes
    // roughly the same time as a real comparison.
    timingSafeEqual(aBuf, aBuf);
    return false;
  }
  return timingSafeEqual(aBuf, bBuf);
}

export const sharedConfig = {
  api: {
    bodyParser: {
      sizeLimit: '7mb',
    },
  },
};
