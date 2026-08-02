# Atlas — handoff

## Current in-flight state

Branch: `claude/app-review-design-polish-s14ish`.

The authoritative remediation plan lives in
[`docs/ATLAS_AUDIT_AND_POLISH_PLAN.md`](docs/ATLAS_AUDIT_AND_POLISH_PLAN.md),
with a second-wave hardening audit in
[`docs/ATLAS_DEEP_AUDIT_II.md`](docs/ATLAS_DEEP_AUDIT_II.md) and a
file-by-file coverage sweep in
[`docs/ATLAS_DEEP_AUDIT_III.md`](docs/ATLAS_DEEP_AUDIT_III.md). Each ends
with an execution log recording what actually landed.

### What this branch changed

- **Light mode is real.** Every `AppColor` surface and ink token resolves
  per trait collection. `DisplayMode` is now Auto / Light / Dark, the
  `.light → .dark` clamp is gone, and Profile → Settings has a live
  appearance picker and a real Metric/Imperial unit picker in place of the
  two static info rows that stood there.
- **Dynamic Type works.** `AppFont.scaled(_:weight:design:)` replaced 737
  fixed `Font.system(size:)` call sites. A `fixed_font_size` SwiftLint rule
  keeps new ones out; `raw_color_literal` does the same for inline colours
  in `Features/`.
- **One button, one glass surface.** `glassControl(_:tint:border:)` makes
  the real iOS 26 material and the legacy recipe mutually exclusive, and
  every `bordered` / `borderedProminent` CTA is now a `GlassButton`.
- **Correctness.** `HomeView` stopped doing a SwiftData fetch and three
  engine passes per render; `PersistenceService` serializes its coders;
  the rest timer no longer ticks at 10Hz all workout; peptide search is
  debounced; Bio Age counts baseline coverage across all three health
  signals; Pro members can manage their subscription in-app.

### Read this before picking the branch up

**There is no compile verification.** The session that produced these
changes had no Xcode. Every changed file was parsed with
`tree-sitter-swift` and every changed API's call sites had their argument
labels checked against the declaration — but that catches syntax and
signatures, not types. Build first.

**CI skips the unit tests.** `.github/workflows/pr-checks.yml` has the
`Unit Tests` step stubbed out with a note that `PeptideTests` doesn't
compile on Xcode 26.3. Two blockers were removed on this branch (a Swift 6
isolation error in `HealthRangeServiceTests` and a stale assertion in
`AppThemeColorTests` that contradicted the shipped default theme), but the
rest of that backlog is still there. Re-enabling that step is the single
highest-value next task — it's why a wrong assertion sat green indefinitely.

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
