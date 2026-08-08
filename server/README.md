# Atlas Vercel proxy

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

| Route                        | Purpose                            | iOS service           |
| ---------------------------- | ---------------------------------- | --------------------- |
| `POST /api/meal-scan`        | Meal photo → macros (Claude vision)| MealScannerService    |
| `POST /api/ai-research`      | Multi-turn research chat           | AIResearchService     |
| `POST /api/weekly-summary`   | AI weekly recap (prompt-cached)    | WeeklySummaryService  |
| `GET/POST /api/attest-register` | App Attest key registration     | AppAttestService      |

The AI routes share `_lib/anthropic-proxy.js` — auth, per-IP rate
limit, App Attest gate, body sanitisation, model allowlist, and the
forward to `api.anthropic.com/v1/messages` live there.

## Deploy

1. `npm i -g vercel` if you don't have the CLI.
2. From this directory: `vercel deploy --prod`.
3. In the Vercel dashboard for the project, set environment variables:
   - `ANTHROPIC_API_KEY` — your real Anthropic key.
   - `PROXY_SHARED_SECRET` — a long random string,
     `openssl rand -hex 32` is fine.
   - Optional:
     - `ALLOWED_MODELS` — comma-separated Anthropic model IDs.
       Defaults to `claude-sonnet-5,claude-sonnet-4-6`.
       **If you set this, list every model the app sends.** The meal
       scanner asks for `claude-sonnet-5`; ai-research and
       weekly-summary ask for `claude-sonnet-4-6`. A model that isn't
       on the list is rewritten to the first entry rather than
       rejected, so an incomplete list looks like it works and just
       quietly serves the wrong model. Existing deployments pinned to
       `claude-sonnet-4-6` keep scanning on 4.6 until this is updated.
     - `RATE_LIMIT_RPM` — per-IP request cap per minute per route.
       Default 20 (`WEEKLY_RPM`, default 6, for weekly-summary).
     - `UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN` — add the
       Upstash Redis integration from the Vercel Marketplace and these
       are injected automatically; rate limits and the daily budget
       then hold across all instances instead of per warm lambda.
       The legacy `KV_REST_API_URL` / `KV_REST_API_TOKEN` names work
       too. Unset → per-instance in-memory limiting (the old behavior).
     - `ANTHROPIC_DAILY_REQUEST_BUDGET` — hard cap on upstream
       Anthropic requests per UTC day across **all** routes combined.
       Once spent, routes return 503 until midnight UTC. Unset → no
       budget. Size it from real traffic, e.g. DAU × expected
       calls/user × safety factor.
     - `PROXY_SHARED_SECRET_NEXT` — staged secret for zero-downtime
       rotation: set it, ship client builds carrying it, then promote
       it to `PROXY_SHARED_SECRET` and clear this slot.
     - `APP_ATTEST_APP_ID` (`<TeamID>.<BundleID>`) +
       `APP_ATTEST_MODE` (`off` | `report` | `enforce`, default
       `report`) — App Attest assertion gate; requires Redis. See
       the rollout section below before touching `enforce`.
       `APP_ATTEST_ALLOW_DEVELOPMENT=1` admits Xcode-run builds in
       enforce mode; `ATTEST_RPM` caps registrations (default 5/min).
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
  the env var is unset; dual-slot (`_NEXT`) rotation.
- **App Attest** (`_lib/app-attest.js`): per-install Secure Enclave
  key attested against Apple's pinned root; per-request assertions
  with a strictly-increasing counter. In enforce mode an extracted
  shared secret is no longer sufficient to relay to Anthropic.
- **Per-principal rate limit**, 20 req/min default per route
  (`RATE_LIMIT_RPM`), backed by Upstash Redis when configured (global
  across instances); falls back to in-memory per warm instance.
- **Per-principal daily quota** (`DEVICE_DAILY_QUOTA`, default 300).
  The control that keeps one abuser from taking everyone down: without
  it, a single scripted client can spend the whole shared budget and
  every paying user gets 503s for the rest of the day.
- **Abuse cooldown** (`ABUSE_STRIKES` / `ABUSE_BLOCK_SECONDS`,
  defaults 20 per hour / 900s). A limited client that keeps retrying
  is still making 28,800 requests a day; after enough refusals the
  principal is blocked outright. Well-behaved clients never
  accumulate strikes.
- **Daily spend budget** (`ANTHROPIC_DAILY_REQUEST_BUDGET`) across all
  routes — 503 once spent. Counts **cost units**, not requests: one
  unit per 256 KB of payload, so a 5 MB meal-scan image costs ~20× a
  chat turn, which is roughly how Anthropic bills it.
  **Fails closed** when Redis is configured but unreachable — a spend
  ceiling that silently stops applying during an outage isn't a
  ceiling. `BUDGET_FAIL_OPEN=1` opts out.
- **Body sanitisation**: only `model`, `max_tokens`, `messages`, and
  optional `system` are forwarded; everything else is stripped so a
  compromised client can't smuggle alternate prompts or `tools`.
- **Model allowlist**: anything outside `ALLOWED_MODELS` is rewritten
  to the first allowed model — caps your spend per call.
- **`max_tokens` hard cap** at 800.
- **`messages` length cap** at 40 (covers the multi-turn chat
  history without giving an attacker unbounded prompts).
- **Body-size cap** at 7 MB, plus a 5 MB iOS-side guard.

## App Attest rollout

Verification ships **report-only by default** — it logs
`app-attest ok/report` lines without ever rejecting. Flip
`APP_ATTEST_MODE=enforce` only after ALL of:

1. The embedded Apple root in `_lib/app-attest.js` is byte-diffed
   against `https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem`
   (it was embedded offline; the unit test pins subject + validity
   but only a diff proves identity).
2. Redis (Upstash) is provisioned — key records live there.
3. A TestFlight build with `APP_ATTEST_ENDPOINT`/`APP_ATTEST_SECRET`
   in Info.plist shows successful registrations AND
   `app-attest ok (counter n)` lines in production logs. The
   verification logic is tested against synthetic openssl-minted
   fixtures, not yet a real device blob — the report phase is what
   validates it against Apple's real formats.

iOS client config: `APP_ATTEST_ENDPOINT` = the attest-register URL,
`APP_ATTEST_SECRET` = the `PROXY_SHARED_SECRET` value (inject via CI
like the other endpoint/secret pairs). Without them the client sends
no assertion headers and report mode just logs their absence.

### What counts as a "principal"

Every limit above is counted per principal: **the verified App Attest
key ID when one is present, otherwise the client IP**.

This is why enforcing App Attest matters beyond authentication. A
client IP is not an identity — mobile carriers rotate it per request
and a VPN makes it free to change, so an IP-keyed quota is a speed
bump for anyone deliberately working around it. An attested key is one
physical install and can't be rotated without re-attesting to Apple,
which is what makes a real per-user quota possible.

Until `APP_ATTEST_MODE=enforce`, limits fall back to IP. The quota and
cooldown still bound casual abuse and accidental retry storms, and the
global budget still bounds the bill — but the per-user ceiling is only
as strong as the identity underneath it.

## Known follow-ups

- **CORS / Origin** allowlist as defense in depth.
- **Per-principal spend attribution** from Anthropic's `usage` in the
  response, rather than the payload-size proxy `requestCost` uses.
  Would let the quota track real tokens instead of bytes.

## Tests

`npm test` (Node 18+, no dependencies) runs the limiter and
handler-wiring suites under `test/`.

## Body shape

The proxy is a sanitised forward to `api.anthropic.com/v1/messages`:

```json
{
  "model": "claude-sonnet-5",
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
