/**
 * App Attest key registration. One-time per install:
 *
 *   GET  /api/attest-register            → { challengeId, challenge }
 *   POST /api/attest-register
 *        { keyId, challengeId, attestation }   (all base64)
 *
 * The challenge is single-use (GETDEL) with a 5-minute TTL, so a
 * captured attestation can't be re-registered. Both verbs sit behind
 * the same shared-secret auth and per-IP rate limit as the AI
 * routes; a successful POST stores the credential public key in
 * Redis for `checkAppAttest` to verify per-request assertions
 * against.
 *
 * Env vars: APP_ATTEST_APP_ID (required), Redis pair (required —
 * key records must survive cold starts), ATTEST_RPM (default 5).
 */
import { randomBytes } from 'node:crypto';
import { clientKey } from './_lib/anthropic-proxy.js';
import { storeAttestKey, verifyAttestation } from './_lib/app-attest.js';
import { authorize } from './_lib/auth.js';
import { allowRate } from './_lib/rate-limit.js';
import { redisConfigured, redisPipeline } from './_lib/redis.js';

const CHALLENGE_TTL_SECONDS = 300;
const MAX_BODY_BYTES = 32 * 1024; // a real attestation is ~5.5 KB
const challengeSlot = (id) => `attest:challenge:${id}`;

function checkRateLimit(req) {
  const limit = parseInt(process.env.ATTEST_RPM || '5', 10);
  return allowRate({ name: 'attest-register', key: clientKey(req), limit, windowSeconds: 60 });
}

async function issueChallenge(res) {
  const challengeId = randomBytes(16).toString('hex');
  const challenge = randomBytes(32);
  const results = await redisPipeline([
    ['SET', challengeSlot(challengeId), challenge.toString('base64'), 'EX', String(CHALLENGE_TTL_SECONDS), 'NX'],
  ]);
  if (results?.[0]?.result !== 'OK') {
    res.status(503).json({ error: { message: 'Service unavailable' } });
    return;
  }
  res.status(200).json({ challengeId, challenge: challenge.toString('base64') });
}

async function consumeChallenge(challengeId) {
  const results = await redisPipeline([['GETDEL', challengeSlot(challengeId)]]);
  const raw = results?.[0]?.result;
  return typeof raw === 'string' ? Buffer.from(raw, 'base64') : null;
}

async function register(req, res) {
  const parsedBytes = Buffer.byteLength(JSON.stringify(req.body ?? ''), 'utf8');
  if (parsedBytes > MAX_BODY_BYTES) {
    res.status(413).json({ error: { message: 'Request too large' } });
    return;
  }

  const { keyId, challengeId, attestation } = req.body ?? {};
  if (typeof keyId !== 'string' || typeof challengeId !== 'string' || typeof attestation !== 'string'
      || !/^[0-9a-f]{32}$/.test(challengeId)) {
    res.status(400).json({ error: { message: 'Malformed registration' } });
    return;
  }
  const keyIdBytes = Buffer.from(keyId, 'base64');
  if (keyIdBytes.length !== 32) {
    res.status(400).json({ error: { message: 'Malformed registration' } });
    return;
  }

  const challenge = await consumeChallenge(challengeId);
  if (!challenge) {
    res.status(400).json({ error: { message: 'Registration failed' } });
    return;
  }

  try {
    const { publicKeyPem, environment } = verifyAttestation({
      attestation: Buffer.from(attestation, 'base64'),
      keyId: keyIdBytes,
      challenge,
      appId: process.env.APP_ATTEST_APP_ID,
    });
    const stored = await storeAttestKey(keyId, {
      publicKeyPem,
      counter: 0,
      environment,
      createdAt: new Date().toISOString(),
    });
    if (!stored) {
      res.status(503).json({ error: { message: 'Service unavailable' } });
      return;
    }
    console.log(`[attest-register] key registered (${environment})`);
    res.status(200).json({ registered: true });
  } catch (err) {
    // One generic failure for every verification miss — the precise
    // reason is for our logs, not for whoever is probing the check.
    console.warn('[attest-register] attestation rejected:', err?.message);
    res.status(400).json({ error: { message: 'Registration failed' } });
  }
}

export default async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.status(405).json({ error: { message: 'Use GET or POST' } });
    return;
  }
  if (!authorize(req)) {
    res.status(401).json({ error: { message: 'Unauthorised' } });
    return;
  }
  if (!(await checkRateLimit(req))) {
    res.status(429).json({ error: { message: 'Too many requests' } });
    return;
  }
  if (!process.env.APP_ATTEST_APP_ID || !redisConfigured()) {
    // Without an app ID there is nothing to verify against; without
    // Redis a stored key wouldn't survive the next cold start.
    console.error('[attest-register] APP_ATTEST_APP_ID and Redis are required');
    res.status(503).json({ error: { message: 'Service unavailable' } });
    return;
  }

  if (req.method === 'GET') await issueChallenge(res);
  else await register(req, res);
}

export const config = {
  api: {
    bodyParser: {
      sizeLimit: '32kb',
    },
  },
};
