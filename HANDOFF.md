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
- **A six-step type scale.** The app had thirty distinct point sizes,
  thirteen inside a 12pt band. Below the display range there are now six
  (`AppFont.Scale`), lint-enforced. 393 call sites moved, all by ≤2pt.
- **A design checker that gates CI.** `scripts/design-lint.py` covers
  eleven rules SwiftLint can't see. Running it found 25 surfaces still
  stacking two glass materials outside the primitives, two neon halos,
  nine sub-44pt controls, and five rows VoiceOver read as eight stops —
  all fixed. It's at zero errors and zero warnings; keep it there rather
  than growing the exemption lists.

### Read this before picking the branch up

**There is no compile verification.** The session that produced these
changes had no Xcode, and the Swift toolchain download is blocked by the
environment's proxy allowlist, so this was not a matter of not trying.
Every changed file was parsed with `tree-sitter-swift` (the only 5 parse
errors in the repo are pre-existing grammar limitations, byte-identical to
the base commit) and every changed API's call sites had their argument
labels checked against the declaration. That catches syntax and
signatures, not types. Build first.

**Nothing has been seen rendered.** No simulator, no screenshots. The
design work is correct by construction and by static check; it has not
been looked at. The type-scale collapse is the change most in need of a
visual pass — 393 sites moved by 1–2pt, and while the moves are mostly
downward (shrinking text can't truncate), dense rows are worth a look.

`OneRedOak/claude-code-workflows → design-review` was read and is the
right tool for this loop, but it drives a browser through Playwright MCP;
it has no path to a native iOS view. Its Phase 3–4 checklist (visual
polish, WCAG 2.1 AA) is what `scripts/design-lint.py` now covers
statically. The rendered-screen half of that loop still needs a human
with a simulator.

**Two things were proven un-doable here, not assumed.** The `@MainActor`
conversion of `ThemeManager` was measured, not guessed: 231 reads of the
ThemeManager-backed `AppColor` accessors sit outside an obviously isolated
context, so the isolation propagates far past what inspection can verify.
Both it and `LocalizationManager` now enforce the invariant at runtime
(`assertMainActor()`, debug-only) so a stray background write traps with a
stack trace instead of silently racing the `@Observable` registrar — the
audit's own second option, and what makes their `@unchecked Sendable`
honest. Do the type-level conversion when you have a compiler and delete
the assertions.

Separately, a signature checker was built to find the `PeptideTests`
compile backlog statically. It works for initializers (zero mismatches
once memberwise inits are modelled) but not for method calls: without
receiver-type resolution, `Calendar.date(byAdding:)` is indistinguishable
from an app-target `date(...)`, and the noise floor swamps the signal.
That backlog needs a type checker.

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
