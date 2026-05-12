/**
 * Vercel proxy route for the PeptideX meal scanner. Holds the
 * Anthropic API key server-side and forwards the client's image →
 * macros request, so the key never lands in the shipping iOS binary.
 *
 * Deploy:
 *   1. `vercel deploy` this directory.
 *   2. Set env vars on the deployment:
 *        ANTHROPIC_API_KEY      — your Anthropic key
 *        PEPTIDE_SHARED_SECRET  — a random 32+ byte string the iOS
 *                                 client must echo as x-peptide-key
 *   3. In the iOS app's Info.plist (or scheme env), set:
 *        MEAL_SCANNER_ENDPOINT       = https://<deploy>/api/meal-scan
 *        MEAL_SCANNER_SHARED_SECRET  = <same string as above>
 *
 * The body shape is identical to api.anthropic.com/v1/messages —
 * model, max_tokens, messages — so this is a 1:1 forward.
 */
import { forwardToAnthropic, sharedConfig } from './_lib/anthropic-proxy.js';

export default async function handler(req, res) {
  await forwardToAnthropic(req, res, { logLabel: 'meal-scan' });
}

export const config = sharedConfig;
