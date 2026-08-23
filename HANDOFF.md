# Atlas — handoff

## Current in-flight state

Branch: `claude/paywall-ux-messaging-v1ut4w`, merged into `main` as PR #161.

This branch rebuilt the in-app paywall (`PaywallView`) and the onboarding
trial offer (`TrialOfferView`) for the 7-day-trial launch: both
subscriptions moved from a 3-day monthly / 14-day annual split to a single
`P7D` intro offer, `Products.storekit` and `APP_STORE_METADATA.md` were
updated to match, and `StoreService` grew an eligibility layer
(`isEligibleForTrial`, `redeemableTrialDays(for:)`) so the "free" copy on
both screens stops being true the instant either subscription's trial is
redeemed — monthly and annual share one subscription group, so redeeming
either burns both. The buy button now lives in a `pinnedFooter` (never
scrolls) and states what it charges on its second line, formatted through
the product's own currency style rather than a hard-coded `$`.

Unlike the audit work this document used to describe, this branch was
actually compiled: PR #161's `build-check` ran a real `xcodebuild build`
plus `-only-testing:PeptideTests` on a macOS runner and both succeeded — 79
tests, zero failures. `proxy-checks` ran the three gates that matter for a
store launch — `design-lint.py --all`, `check-store-metadata.py`,
`contrast-check.py` — and all three passed on the merge commit. So the code
compiles and the automated gates are clean; what CI cannot tell anyone is
whether the screen looks right on a real phone.

**Nothing has been seen rendered.** Every "does it fit on an iPhone SE",
"does Dynamic Type clip it", "does VoiceOver read the button correctly"
question from the original brief is still open, because answering it needs
a simulator or device and this pass had neither. The `Screenshots` workflow
(Actions → Screenshots → Run workflow) can render the app in demo mode on a
macOS runner without a local Mac, but its one run to date (Aug 9, on an
older commit, predating this branch) failed with exit code 70 — that
failure is unrelated to the paywall and hasn't been re-investigated here.

**The trial length is not actually 7 days for a real user yet.** The
`.storekit` file only controls the Simulator; App Store Connect has its own,
separate introductory-offer configuration for
`com.peptidesai.app.pro.monthly` and `com.peptidesai.app.pro.annual`, and
nobody has confirmed on screen that both are set to the one-week offer
(App Store Connect has no literal "7 days" option — one week is the
equivalent, and the app converts week→days for display). Until that's set
and confirmed, the code is ready but the actual subscriber offer hasn't
moved.

**Sandbox purchase testing has not run.** The one behavior that would catch
a real bug — a returning subscriber who already redeemed a trial seeing
`Unlock Atlas Pro` at full price instead of a second "free" offer — only
shows up on a real device against a fresh Sandbox Apple ID.
`StoreServiceTests` covers the equivalent logic against `SKTestSession`,
including `test_redeemableTrialDays_isNil_onceTheTrialIsRedeemed`, and that
test passed in CI, but a passing unit test and a correct on-device purchase
flow are not the same claim.

**Two small things fell out of a code read, not a build, so treat them as
leads rather than confirmed bugs.** `TrialOfferView.swift`'s file-header
comment still describes "the 3-day free trial" — stale from before this
branch, harmless since it's only a comment, but worth fixing in the next
pass that touches this file. And the two paywalls disagree on when to show
a "SAVE X%" badge: `PaywallView` suppresses it below a 5% saving,
`TrialOfferView` shows any positive number — probably not intentional, not
verified against design intent.

The repo's SwiftLint pass also surfaces about ten pre-existing
colon/brace/comma findings in `VialPalette.swift`, `Haptics.swift`, and
`ShimmerModifier.swift` — all three untouched by this branch, and
`pr-checks.yml` already documents why they're deliberately out of scope for
a feature PR (`--strict` is withheld from the SwiftLint step for exactly
this reason, pending a dedicated cleanup pass). They are not part of what
this branch needs fixed, and folding them into a paywall commit would break
the one-logical-change rule this repo otherwise holds to.

Everything after "compiles and passes CI" — device QA on an iPhone SE and a
16 Pro Max, the App Store Connect trial-duration change, Sandbox purchase
testing, the slot-8 paywall screenshot, and the pre-submission checklist —
is still open, and needs a Mac with Xcode plus App Store Connect access
that neither this pass nor the one before it had.

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
