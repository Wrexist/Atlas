# Atlas Vercel proxy

Vercel serverless function(s) that hold the Anthropic API key
server-side so the iOS app's `MealScannerService`, `AIResearchService`
and `WeeklySummaryService` never embed it in the shipping binary. The client authenticates with a
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
| `POST /api/food-scan`        | Smart scan: photo, barcode product or typed food → items, per-100g nutrition, portion options, price (structured output) | MealScannerService |
| `POST /api/lab-scan`         | Blood-test report photos (1–4 JPEG pages) → transcribed markers, units, reference ranges, draw date (structured output) | LabScanService |
| `POST /api/ai-research`      | Multi-turn research chat           | AIResearchService     |
| `POST /api/weekly-summary`   | AI weekly recap (prompt-cached)    | WeeklySummaryService  |
| `GET/POST /api/attest-register` | App Attest key registration     | AppAttestService      |
| `POST /api/apple-revoke`     | Revoke Sign in with Apple on account deletion | AuthService |

`apple-revoke` needs `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`
(the Sign in with Apple `.p8`, `\n` escapes allowed) and `APPLE_CLIENT_ID`
(the bundle ID); without them it answers 503 and the app tells the user to
remove Atlas under Settings → Apple ID → Sign in with Apple.

meal-scan, food-scan and ai-research share `_lib/anthropic-proxy.js` —
auth, App Attest gate, per-principal limits, body sanitisation, model
allowlist, and the forward to `api.anthropic.com/v1/messages` live
there. weekly-summary owns its prompt and upstream call but uses the
same auth, App Attest gate and limiter.

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
       scanner and ai-research ask for `claude-sonnet-5`; older app
       builds' ai-research still asks for `claude-sonnet-4-6`.
       (weekly-summary picks its own model server-side.) A model that
       isn't on the list is rewritten to the first entry rather than
       rejected, so an incomplete list looks like it works and just
       quietly serves the wrong model. Existing deployments pinned to
       `claude-sonnet-4-6` keep scanning on 4.6 until this is updated.
     - `FOOD_SCAN_MODEL` — model for `/api/food-scan`. Default
       `claude-opus-5-5`. Not subject to `ALLOWED_MODELS`: the app
       never names a model on this route, the server picks it.
       `claude-sonnet-5-5` roughly halves the cost per scan.
     - `FOOD_SCAN_EFFORT` — `low` (default), `medium` or `high`.
     - `LAB_SCAN_MODEL` / `LAB_SCAN_EFFORT` — the same pair for
       `/api/lab-scan`. Defaults `claude-opus-5-5` / `low`.
     - `RATE_LIMIT_RPM` — per-principal request cap per minute per
       route. Default 20 (`WEEKLY_RPM`, default 6, for weekly-summary).
     - `DEVICE_DAILY_QUOTA` — per-principal cost units per UTC day.
       Default 300.
     - `SHARED_IP_LIMIT_SCALE` — multiplier on both limits above for an
       IPv4 principal, which carrier NAT shares across many installs.
       Default 10.
     - `UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN` — add the
       Upstash Redis integration from the Vercel Marketplace and these
       are injected automatically; rate limits and the daily budget
       then hold across all instances instead of per warm lambda.
       The legacy `KV_REST_API_URL` / `KV_REST_API_TOKEN` names work
       too. Unset → per-instance in-memory limiting (the old behavior).
     - `ANTHROPIC_DAILY_REQUEST_BUDGET` — hard cap on upstream
       Anthropic cost units per UTC day across **all** routes combined.
       Once spent, routes return 503 until midnight UTC. Unset → 20 000
       on a Vercel production deployment and no budget elsewhere; `0`
       disables it. Size it from real traffic, e.g. DAU × expected
       units/user × safety factor.
     - `PROXY_SHARED_SECRET_NEXT` — staged secret for zero-downtime
       rotation: set it, ship client builds carrying it, then promote
       it to `PROXY_SHARED_SECRET` and clear this slot.
     - `APP_ATTEST_APP_ID` (`<TeamID>.<BundleID>`) +
       `APP_ATTEST_MODE` (`off` | `report` | `enforce`, default
       `report`) — App Attest assertion gate; requires Redis. See
       the rollout section below before touching `enforce`.
       `APP_ATTEST_ALLOW_DEVELOPMENT=1` admits Xcode-run builds in
       enforce mode. `ATTEST_CHALLENGE_RPM` (default 60) and
       `ATTEST_RPM` (default 30) cap registration challenges and
       submissions per IP per minute; `ATTEST_REGISTRATIONS_PER_DAY`
       (default 10, scaled for IPv4 like the other limits) caps
       successful registrations per IP per UTC day.
     - `FREE_SCANS_PER_WEEK` — server-side free-tier AI meal scans per
       install per ISO week. Default `3`, matching the app's
       `MealScanQuota.freeScansPerWeek` — change both together. `0`
       turns the server check off. Needs the Upstash vars above; see
       "Free scan quota" below.
     - `STOREKIT_BUNDLE_ID` — bundle ID a Pro transaction must carry.
       Default `com.peptidesai.app`; only set it for a different app.
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

<key>WEEKLY_SUMMARY_ENDPOINT</key>
<string>https://peptidex-proxy.vercel.app/api/weekly-summary</string>
<key>WEEKLY_SUMMARY_SECRET</key>
<string>$(PROXY_SHARED_SECRET)</string>

<key>APP_ATTEST_ENDPOINT</key>
<string>https://peptidex-proxy.vercel.app/api/attest-register</string>
<key>APP_ATTEST_SECRET</key>
<string>$(PROXY_SHARED_SECRET)</string>

<key>APPLE_REVOKE_ENDPOINT</key>
<string>https://peptidex-proxy.vercel.app/api/apple-revoke</string>
<key>APPLE_REVOKE_SECRET</key>
<string>$(PROXY_SHARED_SECRET)</string>
```

`food-scan` needs no key of its own: the app derives it from
`MEAL_SCANNER_ENDPOINT` (`FOOD_SCAN_ENDPOINT` overrides it).

The iOS services throw `proxyNotConfigured` if either side is missing —
no silent fallback that could send the photo to a half-configured
endpoint.

## Defenses (current)

- **Shared-secret auth**, constant-time compared, fails closed when
  the env var is unset; dual-slot (`_NEXT`) rotation.
- **App Attest** (`_lib/app-attest.js`): per-install Secure Enclave
  key attested against Apple's pinned root; per-request assertions
  whose counter is single-use (so concurrent requests may arrive out
  of order) inside a 5-minute freshness window. In enforce mode an extracted
  shared secret is no longer sufficient to relay to Anthropic.
- **Per-principal rate limit**, 20 requests/min default per route
  (`RATE_LIMIT_RPM`), backed by Upstash Redis when configured (global
  across instances); falls back to in-memory per warm instance.
- **Per-principal daily quota** (`DEVICE_DAILY_QUOTA`, default 300
  cost units). The control that keeps one abuser from taking everyone
  down: without it, a single scripted client can spend the whole
  shared budget and every paying user gets 503s for the rest of the day.
- **Abuse cooldown** (`ABUSE_STRIKES` / `ABUSE_BLOCK_SECONDS`,
  defaults 20 per hour / 900s). A limited client that keeps retrying
  is still making 28,800 requests a day; after enough refusals the
  principal is blocked outright. Well-behaved clients never
  accumulate strikes, and a shared IPv4 principal is never blocked.
  Held in memory when Redis isn't configured.
- **Daily spend budget** (`ANTHROPIC_DAILY_REQUEST_BUDGET`) across all
  routes — 503 once spent. Counts **cost units**, not requests: the
  larger of one unit per 256 KB of body and one per ~4 000 estimated
  tokens (text, ~3 000 per image, plus `max_tokens`, weighted for
  Opus pricing). Charged only for well-formed requests and refunded,
  with the daily quota, when the upstream call fails.
  **Fails closed** when Redis is configured but unreachable — a spend
  ceiling that silently stops applying during an outage isn't a
  ceiling. `BUDGET_FAIL_OPEN=1` opts out.
- **Stable refusal codes**: limit and availability refusals carry
  `error.code` — `rate_limited`, `blocked` and `daily_quota` (429,
  with `Retry-After`), `scan_quota` (429, free weekly scans spent) or
  `unavailable` (503).
- **Free scan quota** (`_lib/scan-quota.js`, `/api/food-scan` only).
  See below.
- **Body sanitisation**: only `model`, `max_tokens`, `messages`, and
  optional `system` are forwarded; everything else is stripped so a
  compromised client can't smuggle alternate prompts or `tools`.
- **Model allowlist**: anything outside `ALLOWED_MODELS` is rewritten
  to the first allowed model — caps your spend per call.
- **`max_tokens` hard cap** at 800 on the pass-through routes;
  food-scan builds its own request with 6 000 (thinking + JSON), and
  weekly-summary uses 500.
- **`messages` length cap** at 40 (covers the multi-turn chat
  history without giving an attacker unbounded prompts).
- **Body-size cap** at 4.4 MB, under the 4.5 MB request payload limit
  Vercel enforces before the handler runs, plus a 3 MB raw-JPEG
  iOS-side guard (~4 MB once base64-encoded).

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
4. The App Store build in users' hands handles `401 attest_clock`: a
   device clock more than 5 minutes off is refused with that code, and
   the app corrects its stamp from the response's `Date` header and
   keeps its key. Older builds treat every 401 as `attest_required`
   and re-register on each request, which never fixes a wrong clock.

iOS client config: `APP_ATTEST_ENDPOINT` = the attest-register URL,
`APP_ATTEST_SECRET` = the `PROXY_SHARED_SECRET` value (inject via CI
like the other endpoint/secret pairs). Without them the client sends
no assertion headers and report mode just logs their absence.

### What counts as a "principal"

Every limit above is counted per principal: **the verified App Attest
key ID when one is present, otherwise the client IP**. An IPv4 address
is often a carrier NAT shared by many installs, so its per-minute and
daily limits are scaled by `SHARED_IP_LIMIT_SCALE` and it is never
abuse-blocked; IPv6 addresses are effectively per device.

This is why enforcing App Attest matters beyond authentication. A
client IP is not an identity — mobile carriers rotate it per request
and a VPN makes it free to change, so an IP-keyed quota is a speed
bump for anyone deliberately working around it. An attested key is one
physical install and can't be rotated without re-attesting to Apple,
which is what makes a real per-user quota possible.

A device can still generate new keys, and each new key starts with a
fresh daily quota. Key records expire after 90 days without use, and
successful registrations are capped per IP per day, but IPs rotate, so
that cap is a speed bump. Apple's App Attest fraud-metric receipt is
the real per-device bound if key minting ever shows up in the logs.

Until `APP_ATTEST_MODE=enforce`, limits fall back to IP. The quota and
cooldown still bound casual abuse and accidental retry storms, and the
global budget still bounds the bill — but the per-user ceiling is only
as strong as the identity underneath it.

## Known follow-ups

- **CORS / Origin** allowlist as defense in depth.
- **Per-principal spend attribution** from Anthropic's `usage` in the
  response, rather than the up-front estimate `costForBody` makes.
  Would let the quota track real tokens instead of an estimate.

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

## Free scan quota

The app gives free users `FREE_SCANS_PER_WEEK` AI meal scans (photo or
described meal) per week and counts them in UserDefaults for instant UI —
which a reinstall wipes. The proxy keeps the authoritative count:

- The app sends `X-Atlas-Scan-Metered: 1` on those scans only (barcode
  and package reads stay free), plus `X-Atlas-Install-Id`, a UUID kept
  in the Keychain so it survives deleting the app, and
  `X-Atlas-Scan-Week`, its local ISO week so both counters turn over at
  the user's Monday midnight.
- Pro users also send `X-Atlas-Entitlement`: the StoreKit 2 signed
  transaction (JWS) of their Pro entitlement. `_lib/storekit-jws.js`
  verifies the x5c chain to Apple Root CA - G3 (pinned by SHA-256
  fingerprint), the ES256 signature, the bundle ID, a Pro product ID,
  no revocation, and expiry (plus Apple's 16-day billing grace). A
  verified Pro request is never counted.
- A free install's fourth scan in the week gets
  `429 { error: { code: "scan_quota" } }` before reaching Anthropic, and
  the app shows its upgrade sheet. A scan that finds no food, fails
  upstream or is refused for another reason is refunded, so — like the
  app — only successful scans count.
- Counters live in Upstash under `scanq:<install>:<week>` (14-day TTL).
  **Fails open**: with no Upstash vars, or Upstash unreachable, every
  scan is allowed. This is a product allowance, not a spend ceiling —
  `ANTHROPIC_DAILY_REQUEST_BUDGET` is that.

`/api/lab-scan` is Pro-only, as it is in the app, and uses the same
check without a free allowance: no `X-Atlas-Entitlement` that verifies
means `403 { error: { code: "pro_required" } }` before any quota or
budget is spent.

The install ID and the metered flag are client-asserted, the same trust
level as the shared secret: they stop a reinstall from resetting the
allowance, not a modified client. App Attest enforce mode is what raises
that bar.
