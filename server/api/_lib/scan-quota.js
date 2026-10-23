/**
 * Server-side free-tier scan allowance. The app keeps its own weekly
 * counter for instant UI, but that lives in UserDefaults and resets on
 * reinstall; this counter is keyed on a per-install ID the app keeps in
 * the Keychain (which survives deletion), so the proxy is the authority.
 *
 * Only requests the app marks `X-Atlas-Scan-Metered: 1` are counted —
 * the same scans the local counter meters (meal photos and described
 * meals; barcode and package reads are always free). Pro users send
 * their StoreKit signed transaction in `X-Atlas-Entitlement` and skip
 * the count once it verifies.
 *
 * Headers read:
 *   X-Atlas-Scan-Metered  — `1` on a scan that spends the allowance.
 *   X-Atlas-Install-Id    — Keychain UUID; falls back to the request
 *                           principal (attest key or IP) when absent.
 *   X-Atlas-Scan-Week     — the app's ISO week (`2026-W43`) in the
 *                           user's time zone, so both counters turn over
 *                           at the same local Monday midnight. Honoured
 *                           only within ±14h of UTC; else the UTC week.
 *   X-Atlas-Entitlement   — StoreKit JWS; see storekit-jws.js.
 *
 * Env vars:
 *   FREE_SCANS_PER_WEEK — allowance; default 3 (MealScanQuota.freeScansPerWeek).
 *                         0 disables the server check.
 *   UPSTASH_REDIS_REST_URL / _TOKEN — the counter store (see redis.js).
 *
 * **Fails open.** With no Redis configured, or Redis unreachable, every
 * scan is allowed: this is a product allowance, not a spend ceiling (the
 * global budget in rate-limit.js is that), and blocking paying-intent
 * users on an outage is worse than a few free scans.
 */
import { redisConfigured, redisPipeline } from './redis.js';
import { verifyProTransaction } from './storekit-jws.js';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const WEEK_PATTERN = /^\d{4}-W\d{2}$/;
const MAX_ZONE_OFFSET_MS = 14 * 60 * 60 * 1000;
// A week key is read for one week; two keep it past any time-zone skew.
const KEY_TTL_SECONDS = 14 * 24 * 60 * 60;

const ALLOW = Object.freeze({ allowed: true, refund: async () => {} });

/** ISO-8601 week of `date` in UTC, formatted like the app (`2026-W03`). */
export function isoWeek(date) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const weekday = d.getUTCDay() || 7;
  // The Thursday of this week decides which year the week belongs to.
  d.setUTCDate(d.getUTCDate() + 4 - weekday);
  const yearStart = Date.UTC(d.getUTCFullYear(), 0, 1);
  const week = Math.ceil(((d - yearStart) / 86_400_000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

/**
 * The week to count against: the client's local week when it is one
 * some time zone could be in right now, else the UTC week. A client can
 * at most pick the neighbouring week near a boundary.
 */
export function quotaWeek(claimed, now = Date.now()) {
  if (typeof claimed === 'string' && WEEK_PATTERN.test(claimed)) {
    const plausible = [now - MAX_ZONE_OFFSET_MS, now, now + MAX_ZONE_OFFSET_MS]
      .map((t) => isoWeek(new Date(t)));
    if (plausible.includes(claimed)) return claimed;
  }
  return isoWeek(new Date(now));
}

function weeklyLimit() {
  const parsed = parseInt(process.env.FREE_SCANS_PER_WEEK ?? '', 10);
  return Number.isFinite(parsed) ? parsed : 3;
}

/**
 * Whether the request carries a StoreKit Pro transaction that verifies.
 * Also the server-side gate on Pro-only routes (`requirePro` in
 * anthropic-proxy.js).
 */
export function hasVerifiedPro(req, logLabel) {
  const jws = req.headers['x-atlas-entitlement'];
  if (!jws) return false;
  try {
    verifyProTransaction(String(jws));
    return true;
  } catch (err) {
    console.warn(`[${logLabel}] entitlement rejected: ${err.storeKit ? err.message : 'verification error'}`);
    return false;
  }
}

/**
 * Spends one free scan for this install. Returns `{ allowed, refund }`;
 * call `refund()` when the scan did not produce a result, so — like the
 * app's counter — only successful scans are spent.
 */
export async function chargeScan(req, { principal, logLabel, now = Date.now() }) {
  if (req.headers['x-atlas-scan-metered'] !== '1') return ALLOW;
  const limit = weeklyLimit();
  if (limit <= 0 || !redisConfigured()) return ALLOW;
  if (hasVerifiedPro(req, logLabel)) return ALLOW;

  const installId = String(req.headers['x-atlas-install-id'] ?? '');
  const subject = UUID_PATTERN.test(installId) ? `i:${installId.toLowerCase()}` : principal;
  const key = `scanq:${subject}:${quotaWeek(req.headers['x-atlas-scan-week'], now)}`;

  const results = await redisPipeline([
    ['INCR', key],
    ['EXPIRE', key, String(KEY_TTL_SECONDS)],
  ]);
  const count = results?.[0]?.result;
  if (typeof count !== 'number') return ALLOW;

  const refund = async () => {
    await redisPipeline([['DECR', key]]);
  };
  if (count > limit) {
    await refund();
    return { allowed: false, refund: async () => {} };
  }
  return { allowed: true, refund };
}
