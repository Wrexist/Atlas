# PeptideX Vercel proxy

Vercel serverless function(s) that hold the Anthropic API key
server-side so the iOS app's `MealScannerService` and `AIResearchService`
never embed it in the shipping binary. The client authenticates with a
shared secret (`X-Peptide-Proxy` header).

## Why

Embedding `ANTHROPIC_API_KEY` in the iOS binary — even through an
xcconfig — means anyone unzipping the IPA recovers the key. The proxy
holds the key, the client holds a rotatable shared secret, and the
real Anthropic API is reached one hop away.

## Routes

| Route                   | Purpose                            | iOS service           |
| ----------------------- | ---------------------------------- | --------------------- |
| `POST /api/meal-scan`   | Meal photo → macros (Claude vision)| MealScannerService    |
| `POST /api/ai-research` | Multi-turn research chat           | AIResearchService     |

Both routes share `_lib/anthropic-proxy.js` — auth, per-IP rate limit,
body sanitisation, model allowlist, and forward to
`api.anthropic.com/v1/messages` live there.

## Deploy

1. `npm i -g vercel` if you don't have the CLI.
2. From this directory: `vercel deploy --prod`.
3. In the Vercel dashboard for the project, set environment variables:
   - `ANTHROPIC_API_KEY` — your real Anthropic key.
   - `PROXY_SHARED_SECRET` — a long random string,
     `openssl rand -hex 32` is fine.
   - Optional:
     - `ALLOWED_MODELS` — comma-separated Anthropic model IDs.
       Defaults to `claude-sonnet-4-6`.
     - `RATE_LIMIT_RPM` — per-IP request cap per minute. Default 20.
4. Note the deploy URL (e.g. `https://peptidex-proxy.vercel.app`).

## Wire the iOS app

Either add the values directly to `Peptide/Resources/Info.plist`, or
(recommended) keep them out of source control via a gitignored
`Secrets.xcconfig` and reference `$(MEAL_SCANNER_ENDPOINT)` etc. from
Info.plist:

```xml
<key>MEAL_SCANNER_ENDPOINT</key>
<string>https://peptidex-proxy.vercel.app/api/meal-scan</string>
<key>MEAL_SCANNER_SECRET</key>
<string>$(PROXY_SHARED_SECRET)</string>

<key>AI_RESEARCH_ENDPOINT</key>
<string>https://peptidex-proxy.vercel.app/api/ai-research</string>
<key>AI_RESEARCH_SECRET</key>
<string>$(PROXY_SHARED_SECRET)</string>
```

The iOS services throw `proxyNotConfigured` if either side is missing —
no silent fallback that could send the photo to a half-configured
endpoint.

## Defenses (current)

- **Shared-secret auth**, constant-time compared, fails closed when
  the env var is unset.
- **Per-IP token bucket**, 20 req/min default, in-memory across warm
  invocations. Cold-start resets are acceptable for a soft cap.
- **Body sanitisation**: only `model`, `max_tokens`, `messages`, and
  optional `system` are forwarded; everything else is stripped so a
  compromised client can't smuggle alternate prompts or `tools`.
- **Model allowlist**: anything outside `ALLOWED_MODELS` is rewritten
  to the first allowed model — caps your spend per call.
- **`max_tokens` hard cap** at 800.
- **`messages` length cap** at 40 (covers the multi-turn chat
  history without giving an attacker unbounded prompts).
- **Body-size cap** at 7 MB, plus a 5 MB iOS-side guard.

## Known follow-ups

- **App Attest / DeviceCheck** assertion verification per request (so
  even a leaked shared secret isn't enough — the request also has to
  come from a real, current build).
- **Vercel KV** or Upstash-backed rate limit (cross-instance, durable).
- **CORS / Origin** allowlist as defense in depth.

## Body shape

The proxy is a sanitised forward to `api.anthropic.com/v1/messages`:

```json
{
  "model": "claude-sonnet-4-6",
  "max_tokens": 400,
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": "..." } },
        { "type": "text", "text": "Identify the meal..." }
      ]
    }
  ]
}
```

The proxy adds `x-api-key` + `anthropic-version` and forwards.
