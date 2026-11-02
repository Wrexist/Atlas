/**
 * Vercel route for Atlas's fridge scan: one photo of a fridge, a shelf
 * or a shopping haul comes back as the groceries in it, each with the
 * box it sits in so the app can cut it out. The prompt and JSON schema
 * live server-side in `_lib/fridge-scan.js`; auth, App Attest, limits,
 * budget and the upstream call are the shared `forwardToAnthropic` path.
 *
 * The iOS app derives this URL from `MEAL_SCANNER_ENDPOINT` (same
 * deployment, `fridge-scan` in place of `meal-scan`).
 */
import { forwardToAnthropic } from './_lib/anthropic-proxy.js';
import {
  buildFridgeScanRequest, readFridgeScanResult, isFridgeScanHit, FRIDGE_SCAN_BETAS,
} from './_lib/fridge-scan.js';

export default async function handler(req, res) {
  await forwardToAnthropic(req, res, {
    logLabel: 'fridge-scan',
    buildBody: buildFridgeScanRequest,
    readResponse: readFridgeScanResult,
    betas: FRIDGE_SCAN_BETAS,
    requireJson: true,
    // A whole fridge costs one of the free weekly scans, like a table.
    scanSucceeded: isFridgeScanHit,
    // A packed fridge is a long list; vercel.json's maxDuration covers this.
    timeoutMs: 55_000,
  });
}
