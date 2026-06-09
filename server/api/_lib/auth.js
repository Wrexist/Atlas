/**
 * Shared-secret client auth used by every proxy route. The iOS app
 * echoes `PROXY_SHARED_SECRET` as the `X-Peptide-Proxy` header; the
 * compare is constant-time and fails closed when the env var is
 * unset.
 */
import { timingSafeEqual } from 'node:crypto';

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

export function authorize(req) {
  const expected = process.env.PROXY_SHARED_SECRET;
  if (!expected) return false; // fail closed when env is missing
  const provided = req.headers['x-peptide-proxy'];
  if (typeof provided !== 'string' || provided.length === 0) return false;
  return constantTimeEquals(provided, expected);
}
