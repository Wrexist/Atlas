# Atlas audit — September 2026

Four parallel audits of `main` at `2a4ae11` (PR #178): correctness and
crashes, security and privacy, user-facing UX / accessibility / App Review,
and build / CI / tests / performance. Every finding below was confirmed by
reading the code. Nothing here was seen rendered: this pass had no Mac, no
simulator and no Swift toolchain, so every Swift change relies on CI's
`build-check` to prove it compiles.

Baseline before any change: `scripts/check.sh --quick` green (design lint
0/0, store metadata, copy claims, 208-entry dataset), proxy tests 50/50.

## Fixed on `claude/sleepy-babbage-fjf6gh`

| Area | Fix |
|---|---|
| Privacy / 5.1.3 | AI weekly recap now defaults **off** (it sends HRV to Anthropic; Info.plist and privacy.html already promised opt-in). The toggle names the recipient. |
| Privacy / 5.1.2(i) | One-time consent sheet naming Anthropic before the first research-chat message or before the camera/library opens for a meal scan; revocable in Profile › About › Privacy at a glance. |
| App Review 1.4.1 / 2.3.1 | The 12 bundled "Community Stacks" credited invented doctors ("Dr. M. Reyes, MD"), showed invented popularity scores and made efficacy claims. They are now "Atlas Editorial" research summaries with hedged wording, no scores, a disclaimer at "Use this stack", and the library is renamed "Stack Library". |
| App Review 1.4.1 | Calendar showed the database research range as the user's scheduled dose when none was set; now "Dose not set". |
| App Review 3.1.2(c) | Yearly plan headlined the per-month figure; the billed amount ($49.99/yr) now leads on both `PaywallView` and `TrialOfferView`. |
| App Review / IAP | `TrialOfferView` had no Restore Purchases; added. Onboarding skips the trial offer for existing subscribers. Paywall shows a retry state when products fail to load instead of an empty list. Inline auto-renew price and 24-hour cancellation line on the paywall. 44 pt hit targets on Restore / Terms / Privacy / Maybe later. |
| Store copy | `APP_STORE_METADATA.md` claimed "All on your device" and "No backend" while AI features use the proxy. Reworded; stated character count updated (3 940 / 4 000). |
| Onboarding bug | Swiping forward skipped `primaryAction()`, so name, goal and nutrition targets were never saved. Forward swipes are now blocked on every page. Outcome-promise headlines softened; sample Health values labelled "Example". |
| UX bug | Language picker offered 10 languages but only English ships; Arabic flipped the app RTL with English text. Picker now lists only bundled languages (hidden while that's just English) and a stale saved choice is dropped. |
| UX / honesty | Creator-program application only saved locally yet promised a reply in 5 business days. Hidden unless `AffiliateIntakeEndpoint` is configured. |
| UX | Today timeline forced 24-hour time; now follows the device's 12/24-hour setting. |
| Copy | Delete-account warning now lists workouts, meals and photos (which it does erase); privacy screen no longer implies free exports. |
| Security | Proxy rebuilds every content part from allow-listed fields and rejects `url` image sources (a 1 KB body could make Anthropic fetch large images for one quota unit). Two new tests; 52/52 pass. |
| Security | CSV exports neutralise leading `= + - @` (formula injection via Open Food Facts / AI meal names). |
| Security | Meal-scan retry now signs each attempt with a fresh App Attest assertion (the reused one would 401 under enforce). |
| Privacy manifests | `1C8F.1` app-group UserDefaults reason added to app, widgets and watch; watch widgets got a manifest (ITMS-91053). Unused `healthkit.background-delivery` entitlement removed. |
| CI | Screenshots workflow (the exit-70 failure) and the UI-tests step pick the simulator by UDID instead of `name=…,OS=latest`; the `simulator` input reaches the shell through `env`. |

## Second pass (same branch)

Everything the first pass left as "needs a decision" that code could settle
was done, plus revenue and core-loop work:

- **Spend and abuse:** production daily budget defaults to 20 000 units;
  cost is the larger of bytes and estimated tokens; meal-scan accepts only
  one photo plus prompt; enforce-mode App Attest refuses on missing config;
  TestFlight injects App Attest keys when the secrets exist.
- **Privacy / compliance:** weekly recaps (HRV) moved out of iCloud to a
  device-only file; the recap is reset off once for profiles that never
  chose it; Delete All Data for every user (also clears backups, exports
  and in-memory state); Sign in with Apple revocation on account deletion
  (`/api/apple-revoke` + client flow); photos and backups use complete file
  protection; "not retained" claims replaced with what Atlas can promise;
  reconstitution calculator extracted to a tested engine with neutral UI;
  meal capture time from EXIF, Photos permission string dropped; store copy
  Pro list now matches what is actually gated.
- **Revenue:** paywall sources with contextual headlines and per-source
  events; offer-code redemption; restore feedback; no hard-coded US prices
  on the trial offer; trial-ends-in-2-days reminder; billing-retry banner;
  3 free AI meal scans a week then Pro; one-time trial re-offer after
  engagement; review prompts after a PR or the third workout; `atlas://pro`;
  a research-assistant row on Today.
- **Training:** keyboard Done and scroll-dismiss, per-exercise and default
  rest times, previous set per row with tap-to-fill, set haptic, confirm
  before removing logged sets, minimize a workout, confirm before replacing
  one, effort + note on finish, warm-up marking, delete / repeat / save-as-
  routine for past workouts, recent exercises and multi-select, plate
  calculator.
- **Nutrition:** day switcher (backfill any day, photo scans included),
  numeric macro fields and portion chips, Log again and recent meals, water
  undo and exact metric water.
- **Today / Biology / Profile:** training-first layout for people without
  protocols, Labs entry, pull-to-refresh and Connect Health, Training
  settings section.
- **Quality:** Dynamic Type for badges and stats, VoiceOver cleanup, 44 pt
  targets; ~17.6 s of test sleeps removed and midnight/DST/month-boundary
  flakes pinned; streak-freeze month bug fixed; logo shipped at drawn size;
  `SWIFT_STRICT_CONCURRENCY: targeted`; redundant CI job removed.

## Still open

- **Credentials / dashboards:** Vercel `ANTHROPIC_DAILY_REQUEST_BUDGET`
  (confirm), Upstash Redis, `APPLE_TEAM_ID` / `APPLE_KEY_ID` /
  `APPLE_PRIVATE_KEY` / `APPLE_CLIENT_ID`; GitHub secrets
  `APP_ATTEST_ENDPOINT`/`SECRET`, `APPLE_REVOKE_ENDPOINT`/`SECRET`; then
  `APP_ATTEST_MODE=enforce`. App Store Connect: one-week intro offer on both
  plans, rank Annual above Monthly, Family Sharing decision, creator offer
  codes, win-back offers.
- **Business decisions:** creator codes naming real-looking influencers
  (`CreatorCodeService.swift`) need signed agreements or neutral codes;
  `support@peptidesai.com` and the `/Peptide-ai/` privacy URL; whether the
  App Privacy label still holds given Anthropic's API retention terms.
- **Engineering:** Swift 6 language mode (warnings now visible); CloudKit
  silent-push sync (`remote-notification` + `aps-environment`, needs the
  provisioning profile); Release-config compile on PRs; one version scheme;
  localization beyond English; the scan quota is client-side only (a
  reinstall resets it) until the proxy can verify entitlements.

## Still needs a device

Everything visual: iPhone SE / Pro Max layout of the changed paywall and trial
offer footers (now taller with 44 pt targets), Dynamic Type, VoiceOver, the
consent sheet, Sandbox purchase + restore, and the App Store Connect
one-week intro offer on both subscriptions.
