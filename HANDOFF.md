# Atlas — handoff

## Current in-flight state

Branch: `claude/sleepy-babbage-fjf6gh`, on top of `main` at PR #178.

This branch is the September 2026 audit and the fixes that came out of it:
App Review and privacy compliance, proxy spend controls, correctness and
performance fixes, and revenue work (contextual paywalls, metered AI meal
scans, trial reminders, billing-retry banner, offer codes, win-back offer,
review prompts). `docs/ATLAS_AUDIT_2026_09.md` is the full record of what
was found, what changed, and what still needs a decision or credentials.

**Nothing on this branch has been compiled locally.** It was written in a
container with no Swift toolchain. The proxy suite (`cd server && npm
test`) and every `scripts/` gate pass; the Swift is only proven by
`build-check` on a non-draft PR. Open the PR and read that run before
anything else.

**Nothing has been seen rendered.** Device QA still owed: the paywall and
trial-offer footers (taller now, 44 pt targets), the AI consent sheet, the
meal-scan quota caption, the Delete All Data alert, and the reconstitution
calculator on an iPhone SE and a Pro Max, plus Dynamic Type and VoiceOver.

**Needs App Store Connect / Vercel / GitHub, not code:**
- Vercel: confirm `ANTHROPIC_DAILY_REQUEST_BUDGET` (production now defaults
  to 20 000 units when unset) and that Upstash Redis is configured.
- GitHub secrets: `APP_ATTEST_ENDPOINT`, `APP_ATTEST_SECRET`; then ship,
  watch for `app-attest ok` in logs, and set `APP_ATTEST_MODE=enforce`.
- App Store Connect: one-week intro offer on both subscriptions; rank Annual
  above Monthly in the group; decide on Family Sharing; create creator
  offer codes and win-back offers; review screenshot slot 8 (the privacy
  screen now shows an AI card).

## Before merging branch work

1. `xcodegen generate`, then a clean build for an iOS 18+ simulator.
2. Fix the remaining `PeptideTests` compile errors and re-enable the CI
   step; run the suite.
3. Verify Liquid Glass surfaces on an iOS 26 simulator/device — the design
   work cannot be validated on older OSes.
4. Check the app in **all three** display modes. Light mode has never been
   run; the tokens are correct by construction, but no screen has been seen
   in it.

## Project basics

- Product: **Atlas** (iOS health & fitness). Repo / Xcode targets are
  named `Peptide` for legacy reasons — see the "Naming" section of
  [`README.md`](README.md).
- iOS 18+, Swift 6.0, SwiftUI, SwiftData (CloudKit-backed). Companion
  Watch app, two widget targets, Live Activities.
- Persistence runs through `SwiftDataRepository` (the JSON
  `PersistenceService` is retained only for custom peptides and
  widget snapshots).
- The Anthropic key lives in the Vercel proxy under `server/`; the iOS
  binary never ships one.
