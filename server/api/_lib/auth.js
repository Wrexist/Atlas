/**
 * Shared-secret client auth used by every proxy route. The iOS app
 * echoes the secret as the `X-Peptide-Proxy` header; the compare is
 * constant-time and fails closed when no secret is configured.
 *
 * Zero-downtime rotation: set `PROXY_SHARED_SECRET_NEXT` to the new
 * value (both are now accepted), ship client builds carrying it,
 * and once old builds have aged out promote it to
 * `PROXY_SHARED_SECRET` and clear the `_NEXT` slot.
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
  const provided = req.headers['x-peptide-proxy'];
  if (typeof provided !== 'string' || provided.length === 0) return false;
  const current = process.env.PROXY_SHARED_SECRET;
  if (!current) return false; // fail closed when env is missing
  if (constantTimeEquals(provided, current)) return true;
  const next = process.env.PROXY_SHARED_SECRET_NEXT;
  return typeof next === 'string' && next.length > 0 && constantTimeEquals(provided, next);
}
