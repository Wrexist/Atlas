/**
 * Vercel route for Atlas's lab-report scanner: up to four photos of a
 * blood-test report come back as transcribed markers (name, value,
 * unit, reference range, draw date) for the app to map onto its own
 * marker catalog and show for review. The prompt and JSON schema live
 * server-side in `_lib/lab-scan.js`; auth, App Attest, limits, budget
 * and the upstream call are the shared `forwardToAnthropic` path.
 *
 * The iOS app derives this URL from `MEAL_SCANNER_ENDPOINT` (same
 * deployment, `lab-scan` in place of `meal-scan`).
 */
import { forwardToAnthropic } from './_lib/anthropic-proxy.js';
import { buildLabScanRequest, readLabScanResult, LAB_SCAN_BETAS } from './_lib/lab-scan.js';

export default async function handler(req, res) {
  await forwardToAnthropic(req, res, {
    logLabel: 'lab-scan',
    buildBody: buildLabScanRequest,
    readResponse: readLabScanResult,
    betas: LAB_SCAN_BETAS,
    requireJson: true,
    // Several dense pages take longer than one plate; vercel.json's
    // maxDuration covers this.
    timeoutMs: 55_000,
  });
}
