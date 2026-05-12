/**
 * Vercel proxy route for the PeptideX AI research assistant. Same
 * shape and protections as the meal-scan route — see meal-scan.js
 * for deploy steps.
 *
 * iOS env vars:
 *   AI_RESEARCH_ENDPOINT       = https://<deploy>/api/ai-research
 *   AI_RESEARCH_SHARED_SECRET  = <same PEPTIDE_SHARED_SECRET>
 */
import { forwardToAnthropic, sharedConfig } from './_lib/anthropic-proxy.js';

export default async function handler(req, res) {
  await forwardToAnthropic(req, res, { logLabel: 'ai-research' });
}

export const config = sharedConfig;
