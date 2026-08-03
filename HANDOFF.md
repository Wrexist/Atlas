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
  thirteen rules SwiftLint can't see. Running it found 25 surfaces still
  stacking two glass materials outside the primitives, two neon halos,
  nine sub-44pt controls, and five rows VoiceOver read as eight stops —
  all fixed. It sits at **zero errors and zero warnings**. Getting there
  meant finding the glow rule blind three separate times — to
  `AppShadow.accentGlow`, to stroke-anchored shadows, and finally to a
  blurred coloured disc stacked behind a medallion, which is a halo built
  from a shape rather than a shadow. Twelve halos in total, including
  `MetricRing`'s `glow` parameter, which is now deleted rather than
  defaulted off. `scripts/test_design_lint.py` pins all three forms.
- **Light mode is no longer optional per screen.** 44 shipping views —
  every sheet, both editors, the paywall, onboarding — pinned
  `.preferredColorScheme(.dark)` on their own root. That was invisible
  until this branch made light mode real, at which point picking Light
  would have turned the tabs light and left every sheet dark. All 44 are
  gone and a `forced-color-scheme` lint rule keeps the literal out of
  shipping code (previews are blanked before rules run).
- **Contrast is measured, not assumed.** `scripts/contrast-check.py`
  reads the hex literals out of `ColorTheme.swift` / `AppTheme.swift`
  and holds all 244 ink/surface pairs to WCAG 2.1 AA, in both schemes and
  all five themes. It found 30 failures, two of them structural: the
  Graphite ramp pinned its ink stops to one value and sat at 1.8:1 on the
  dark background, and `onAccent` was printed on `accentPrimary` — a stop
  tuned as *ink*, so near-white on it was 2.5:1 on the lock screen's
  unlock button. Filled accent surfaces now use `AppColor.accentFill`.
  It gates CI at zero failures.
- **Training weights honour the unit setting.** `SetEntry.weightKg` is
  documented as canonical kilograms the UI converts on read and write;
  the Train feature never did the conversion, so an imperial user typing
  225 stored 225 kg. The conversion now lives on `MeasurementUnit` and
  retired the `2.20462` literal that six other files had each copied.

### Read this before picking the branch up

**There is no compile verification.** The session that produced these
changes had no Xcode, and the Swift toolchain download is blocked by the
environment's proxy allowlist, so this was not a matter of not trying.
Every changed file was parsed with `tree-sitter-swift` (the only 5 parse
errors in the repo are pre-existing grammar limitations, byte-identical to
the base commit) and every changed API's call sites had their argument
labels checked against the declaration. That catches syntax and
signatures, not types. Build first.

**One part of this repo is genuinely tested: the proxy.** `server/` has 48
Node tests covering the rate limiter, the per-device quota, App Attest and
the CBOR decoder, and they *execute* — no Xcode needed. All 48 pass. That
is worth knowing precisely because nothing on the Swift side can say the
same.

**Run `scripts/check.sh` before you push.** It is every check that works
without Xcode — the design system, the 244 colour pairs, SwiftLint if it is
installed, the bundled dataset, the 48 proxy tests, and the four App Store
screen sets — in one command, exiting non-zero on failure so it works as a `pre-push` hook. It
exists because of the next paragraph: with CI down, these checks run only if
a human runs them.

**CI has not run since 2026-06-20 — check this first.** Every push to this
branch creates a workflow run that immediately reports `startup_failure`,
with no workflow name and `path: BuildFailed` (35 of them so far). All six
files in `.github/workflows/` parse as valid YAML and none but `release.yml`
(tags only) even triggers on a branch push, so the cause is not in the repo.
The last run of any workflow that *succeeded* was 2026-06-20, six weeks ago,
across a period of active development. That pattern — runs failing before a
job starts, no name resolved — is what GitHub does when Actions cannot start
on a repository at all, most commonly a spending limit on a private repo or
a disabled-Actions policy. Until that is resolved, no CI check on this branch
means anything, including the two checkers added here.

**Nothing has been seen rendered — but you can fix that in one click.**
Dispatch the **Screenshots** workflow (Actions → Screenshots → Run
workflow). It now captures every tab in three passes — dark, light, and
Accessibility XXXL — and uploads them as an artifact. Those three are
chosen deliberately: light mode had never been rendered at all, and XXXL
is where the type-scale change would show up as truncation.

It runs on a macOS runner, so it needs no local machine, and it no longer
depends on the `PeptideTests` backlog: it builds the new `PeptideUICapture`
scheme, which compiles the app and the UI tests only. Reviewing those
screenshots is the fastest way to validate this branch.

`OneRedOak/claude-code-workflows → design-review` was read and is the
right tool for this loop, but it drives a browser through Playwright MCP;
it has no path to a native iOS view. Its Phase 3–4 checklist (visual
polish, WCAG 2.1 AA) is what `scripts/design-lint.py` and
`scripts/contrast-check.py` now cover statically. The rendered-screen half
of that loop still needs a human with a simulator.

**Two things were deliberately reported rather than changed**, because
both are judgment calls that need a rendered screen:

1. *Accent is over-spent.* 671 accent references, 280 of them ink —
   roughly 27% of coloured surface against the 60/30/10 target of ~10%.
   Thinning it is per-site taste, not a mechanical edit.
2. *Display numerals don't scale.* The 16 sites above 24pt use
   `Font.system(size:)` and so ignore Dynamic Type entirely; at
   Accessibility XXXL body text grows past some of them and the hierarchy
   inverts. `AppFont.scaled(_:relativeTo:)` fixes it, but capping the
   growth without seeing the XXXL screenshots risks truncation instead.

**What still needs a compiler.** The `PeptideTests` backlog and the
native-chrome migration. Everything else on this branch is either landed
or enforced by a check.

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

**The `PeptideTests` "backlog" was two lines.** The CI comment and this
document both described "a backlog of stale API references and Swift-6
actor-isolation issues". That was never measured. Reading the last
`test-compile` job that actually ran (run 27603514542, Xcode 26.3, June)
shows the build failed on exactly **two** errors, both in one file:

    PeptideTests/AppStateTests.swift:29:30: error: type 'AppTab' has no member 'protocols'
    PeptideTests/AppStateTests.swift:30:44: error: type 'AppTab' has no member 'protocols'

`.protocols` stopped existing when Habits was promoted and Protocols became
the Library modal. Both are fixed on this branch, and the test now also
covers the routing that replaced it.

**The rest of the target was compiled too — by an older run.** `.protocols`
only broke on 2026-06-09, and `test-compile` was added on 06-04, so the runs
in between got past the A–C batch. Run **27013636545** (June 5) reached the
D–P batch and failed on exactly two files:

    DataStoreTests.swift:167:9        'async' call in a function that does not support concurrency
    HealthRangeServiceTests.swift     11x  main actor-isolated ... in a synchronous nonisolated context

`HealthRangeServiceTests` was already fixed on this branch (`@MainActor` on
the class). `DataStoreTests` was not: `toggleHealthConnection()` is
`async -> Bool` and the test called it synchronously, then asserted a flip
that would not have happened in either direction — connecting awaits a real
HealthKit grant a unit test cannot obtain. It now tests the disconnect path,
which is pure state.

So every error any real run has ever reported is now fixed. That is still
not "the target compiles" — a compiler finds the *next* error only once the
previous one is gone, and no run has ever got past these — but the list of
known-outstanding errors is empty for the first time. `test-compile` is
non-gating and runs `build-for-testing`, so the next run says what, if
anything, is behind them.

Two things were checked statically alongside it: every type referenced in
`PeptideTests` resolves against an app-target declaration (784 declarations,
zero unresolved), and no test constructs any of the initialisers changed on
this branch. So the remaining risk is method-signature and inference errors,
not missing symbols.

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
