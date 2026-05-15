/**
 * Vercel proxy route for the Atlas meal scanner. Thin wrapper over
 * `forwardToAnthropic`; see `_lib/anthropic-proxy.js` for the
 * server-side env vars and the rate-limit / sanitisation behavior.
 *
 * iOS env vars (Info.plist or scheme env):
 *   MEAL_SCANNER_ENDPOINT  = https://<deploy>/api/meal-scan
 *   MEAL_SCANNER_SECRET    = the PROXY_SHARED_SECRET value
 */
import { forwardToAnthropic, sharedConfig } from './_lib/anthropic-proxy.js';

export default async function handler(req, res) {
  await forwardToAnthropic(req, res, { logLabel: 'meal-scan' });
}

export const config = sharedConfig;
