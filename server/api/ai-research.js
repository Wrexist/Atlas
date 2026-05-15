/**
 * Vercel proxy route for the Atlas AI research assistant. Thin
 * wrapper over `forwardToAnthropic`; see `_lib/anthropic-proxy.js`
 * for the server-side env vars and behavior.
 *
 * iOS env vars (Info.plist or scheme env):
 *   AI_RESEARCH_ENDPOINT = https://<deploy>/api/ai-research
 *   AI_RESEARCH_SECRET   = the PROXY_SHARED_SECRET value (same value
 *                          as MEAL_SCANNER_SECRET — one secret, two
 *                          client env-var slots so each surface can
 *                          point at a different deployment if needed)
 */
import { forwardToAnthropic, sharedConfig } from './_lib/anthropic-proxy.js';

export default async function handler(req, res) {
  await forwardToAnthropic(req, res, { logLabel: 'ai-research' });
}

export const config = sharedConfig;
