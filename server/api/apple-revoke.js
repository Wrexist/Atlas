/**
 * Sign in with Apple token revocation, required when a user deletes
 * their account (App Store Guideline 5.1.1(v)).
 *
 *   POST /api/apple-revoke   { authorizationCode }
 *
 * The app obtains a fresh authorization code by re-running Sign in with
 * Apple at deletion time. This route exchanges it for a refresh token
 * and immediately revokes that token, which removes Atlas from the
 * user's "Apps Using Apple ID" list. Nothing is stored.
 *
 * Env vars:
 *   APPLE_TEAM_ID      — developer team ID (JWT issuer).
 *   APPLE_KEY_ID       — ID of the Sign in with Apple private key.
 *   APPLE_PRIVATE_KEY  — that key's .p8 contents (PEM, `\n` escapes ok).
 *   APPLE_CLIENT_ID    — the app's bundle ID.
 *   REVOKE_RPM         — per-IP requests per minute. Default 5.
 * Missing configuration answers 503 so the app can fall back to telling
 * the user to revoke access in Settings.
 */
import { createPrivateKey, sign } from 'node:crypto';
import { clientKey } from './_lib/anthropic-proxy.js';
import { authorize } from './_lib/auth.js';
import { allowRate } from './_lib/rate-limit.js';

const APPLE_AUTH = 'https://appleid.apple.com';
const MAX_CODE_LENGTH = 1024;

function appleConfig() {
  const teamId = process.env.APPLE_TEAM_ID;
  const keyId = process.env.APPLE_KEY_ID;
  const privateKey = process.env.APPLE_PRIVATE_KEY;
  const clientId = process.env.APPLE_CLIENT_ID;
  if (!teamId || !keyId || !privateKey || !clientId) return null;
  return { teamId, keyId, privateKey: privateKey.replace(/\\n/g, '\n'), clientId };
}

const base64url = (value) => Buffer.from(value).toString('base64url');

/** ES256 client secret Apple requires on its token and revoke endpoints. */
export function clientSecret({ teamId, keyId, privateKey, clientId }, now = Date.now()) {
  const iat = Math.floor(now / 1000);
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: keyId }));
  const payload = base64url(JSON.stringify({
    iss: teamId,
    iat,
    exp: iat + 300,
    aud: APPLE_AUTH,
    sub: clientId,
  }));
  const signingInput = `${header}.${payload}`;
  const signature = sign('sha256', Buffer.from(signingInput), {
    key: createPrivateKey(privateKey),
    dsaEncoding: 'ieee-p1363',
  });
  return `${signingInput}.${signature.toString('base64url')}`;
}

async function postForm(path, fields) {
  return fetch(`${APPLE_AUTH}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields).toString(),
  });
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: 'Use POST' } });
    return;
  }
  if (!authorize(req)) {
    res.status(401).json({ error: { message: 'Unauthorised' } });
    return;
  }
  const limit = parseInt(process.env.REVOKE_RPM || '5', 10);
  if (!(await allowRate({ name: 'apple-revoke', key: clientKey(req), limit, windowSeconds: 60 }))) {
    res.status(429).json({ error: { message: 'Too many requests' } });
    return;
  }

  const code = req.body?.authorizationCode;
  if (typeof code !== 'string' || code.length === 0 || code.length > MAX_CODE_LENGTH) {
    res.status(400).json({ error: { message: 'Malformed request body' } });
    return;
  }

  const config = appleConfig();
  if (!config) {
    console.error('[apple-revoke] Sign in with Apple key not configured');
    res.status(503).json({ error: { message: 'Service unavailable' } });
    return;
  }

  try {
    const secret = clientSecret(config);
    const exchange = await postForm('/auth/token', {
      client_id: config.clientId,
      client_secret: secret,
      code,
      grant_type: 'authorization_code',
    });
    if (!exchange.ok) {
      console.warn(`[apple-revoke] code exchange failed: ${exchange.status}`);
      res.status(502).json({ error: { message: 'Revocation failed' } });
      return;
    }
    const tokens = await exchange.json();
    const token = tokens.refresh_token ?? tokens.access_token;
    const hint = tokens.refresh_token ? 'refresh_token' : 'access_token';
    const revoke = await postForm('/auth/revoke', {
      client_id: config.clientId,
      client_secret: secret,
      token,
      token_type_hint: hint,
    });
    if (!revoke.ok) {
      console.warn(`[apple-revoke] revoke failed: ${revoke.status}`);
      res.status(502).json({ error: { message: 'Revocation failed' } });
      return;
    }
    res.status(204).send('');
  } catch (error) {
    console.error(`[apple-revoke] ${error.message}`);
    res.status(502).json({ error: { message: 'Revocation failed' } });
  }
}
