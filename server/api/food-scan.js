/**
 * Vercel route for Atlas's smart food scanner: meal photos, package
 * photos, barcode products and typed foods all come back in one
 * structured shape (items with per-100g nutrition, portion options
 * suited to the food, price estimates). The prompt and JSON schema live
 * server-side in `_lib/food-scan.js`; auth, limits and the upstream call
 * are the shared `forwardToAnthropic` path.
 *
 * The iOS app derives this URL from `MEAL_SCANNER_ENDPOINT` (same
 * deployment, `food-scan` in place of `meal-scan`) and falls back to
 * the old route when this one is missing.
 */
import { forwardToAnthropic } from './_lib/anthropic-proxy.js';
import { buildFoodScanRequest, readFoodScanResult, isFoodScanHit, FOOD_SCAN_BETAS } from './_lib/food-scan.js';

export default async function handler(req, res) {
  await forwardToAnthropic(req, res, {
    logLabel: 'food-scan',
    buildBody: buildFoodScanRequest,
    readResponse: readFoodScanResult,
    betas: FOOD_SCAN_BETAS,
    // Meal photos and described meals the app marks as metered spend
    // the free weekly allowance; see `_lib/scan-quota.js`.
    scanSucceeded: isFoodScanHit,
    // Opus reading a busy plate can take longer than a pass-through
    // chat turn; the function's maxDuration in vercel.json covers this.
    timeoutMs: 50_000,
  });
}
