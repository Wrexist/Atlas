# Atlas — design-principle audit

What this is: Atlas measured against the four design resources named for
this review, rule by rule, with the measurement and where it is enforced.
Every number here is reproducible from the two checkers in `scripts/`.

Reproduce:

```sh
python3 scripts/design-lint.py --all     # 17 rules, gates CI on errors
python3 scripts/contrast-check.py        # 244 colour pairs, gates CI
```

Current state: **0 errors, 7 warnings** — all 7 are R2 accent halos, listed
below. Errors gate the build; warnings do not.

**The limit of this document.** Nothing here has been rendered. These four
resources split cleanly into rules that are arithmetic (contrast, spacing
multiples, weight counts, tap targets) and rules that need eyes (visual
monotony, thumb zone, whether a gradient is brand or decoration). The
arithmetic half is measured and CI-enforced below. The rest is listed as
open with the measurement that would settle it, and needs the
**Screenshots** workflow (Actions → Screenshots → Run workflow) or a
simulator.

---

## 1. tommyjepsen/awesome-ux-skills — the 12 craft rules

| # | Rule | Status | Evidence |
|---|------|--------|----------|
| R1 | No gradients | **partial — enforced where it bites** | 84 gradient sites classified by what they fill: 53 surface fills, 20 illustration/other, 6 ring or chart strokes, 3 overlay masks. The rule's actual target — a fade applied to buttons and pills alike — was **6 CTA capsules** filling with `[accentPrimary → accentLight]`; all now flat `accentFill`, which also fixed a 1.3–3.7:1 contrast failure the token checker could not see (see below). Gradient-filled *text* was 2 sites: the promo numeral (flattened) and the "Atlas" wordmark (R1's explicit brand exception, kept). `design-lint: accent-gradient-fill` holds the line. The remaining fills are illustrations, charts and ambient backdrops — classifying those still needs renders. |
| R2 | No glow | **reported, 7 open** | The rule claimed a clean bill it could not deliver: it matched only literal `.shadow(color:)`, so it never saw `AppShadow.accentGlow` — the token the glows actually use — and it skipped any glow anchored to a `.stroke()` rather than a fill. Both holes are fixed, and **7 accent halos** now surface: the `MetricRing` `glow: true` arc and its callers, the onboarding hero icon, the scanner reticle, the share card. They are left in place deliberately — a glowing recovery ring is the idiom in this category (Whoop, Oura) and the codebase opts into it per call site — but they are warnings on the record now rather than invisible. A render settles whether they read as emphasis or as neon. |
| R3 | No `transition: all` | **enforced** | `design-lint: untargeted-animation` — the SwiftUI analogue is `.animation(x)` without a `value:`, which animates every change in the subtree. |
| R4 | Kill visual monotony | **open** | Not statically checkable. Squint test needs renders. |
| R5 | No placeholder text | **enforced** | `design-lint: placeholder-copy` — lorem ipsum, "coming soon", "TBD". Zero hits. |
| R6 | Contain stacking contexts | **pass** | 4 `zIndex` calls, values 1–3, no arms race. SwiftUI scopes z-order to the container, so the CSS failure mode does not arise. |
| R7 | No pure black on pure white | **enforced** | `design-lint: pure-neutral`. Light surface is `#F4F4F7`, dark is `#101013`, ink-on-accent is `#FCFCFD`. Zero pure neutrals. |
| R8 | Space on a scale | **enforced** | `design-lint: off-grid-spacing`, 8-point grid plus 2/4/6 for optical insets. |
| R9 | Type does the work | **enforced** | Six-step scale (`AppFont.Scale`), lint-enforced; three emphasis weights over the default; tabular figures on every animated numeral (`monospacedDigit`). |
| R10 | Pick an elevation language | **enforced** | `design-lint: stacked-glass` — 25 surfaces were stacking two glass materials outside the primitives; all fixed. |
| R11 | Design every state | **pass on empty states** | 20 empty states, 12 with a CTA (4 added this pass). The 8 without are error, not-found and success states where a CTA would be noise. No empty state now asks the user to do something without offering it. Loading and error states exist per async surface but are not machine-checked. |
| R12 | Motion is physics | **enforced** | `design-lint: motion` (no short decorative loops) and `design-lint: unguarded-loop` (a `repeatForever` in a file that never reads `accessibilityReduceMotion` fails the build). Eight loops across six views were fixed this pass. |

## 2. ceorkm/mobile-app-ui-design

| Rule | Status | Measurement |
|------|--------|-------------|
| One font family | **pass** | System font only; `.rounded` design on numerals. |
| Max 4 sizes / ≤3 weights | **partial** | Weights: 3 emphasis (semibold 285 / heavy 149 / bold 87) over the default — compliant. Sizes: six steps below display, one more than the rule's four. Held deliberately: a health app renders badge, caption and body in the same row constantly, and the 30 sizes this replaced is the failure the rule is actually aimed at. |
| Monospace for large numbers | **pass** | All display-size stat numerals carry `monospacedDigit()`. The exceptions are non-numeric (`"You're set, {name}"`) or fixed-canvas share cards. |
| 60/30/10 colour | **partial — the decidable half is done** | The rule's own definition (accent = CTAs, key indicators, icons; text hierarchy from *neutral* opacity) makes the split decidable after all. Classifying the 281 accent ink sites: **136 icons** and **26 CTA labels** are legitimate by the rule, **40 values/indicators** are legitimate, and **25 were static literal labels** — uppercase eyebrows ("WHAT THIS TRACKS", "YOUR INVENTORY"), help copy and unit suffixes, which the rule says come from neutral opacity. 19 moved to `textSecondary`; 6 kept as genuine indicators or Peak-End moments (`PRO` badges, "Achievement Unlocked!", "New personal best!"). 671 → 645 references. What remains — 202 tint/wash fills at low opacity — is what the rule explicitly *encourages* ("accent at 5% opacity for subtle card highlights"), so the raw reference count overstates the surface. The true painted-area ratio still needs a render. |
| 8-point grid | **enforced** | `design-lint: off-grid-spacing`. |
| Relationship-based spacing | **open** | Needs renders. |
| 44×44pt tap targets | **enforced** | `design-lint: hit-target`; nine sub-44pt controls found and fixed. |
| Contrast ratios | **enforced** | `contrast-check`, 244 pairs at WCAG AA, both schemes × five themes, plus `design-lint: accent-gradient-fill` for gradient fills the pair-checker cannot resolve. |
| Empty / error / loading / success states | **partial** | See R11. |
| Thumb-zone CTAs | **open** | Needs renders. |
| Soft, background-tinted shadows | **pass** | Shadows resolve through `AppShadow`; the glow rule catches the harsh case. |

## 2b. The App Store screens, measured

The iOS app cannot be rendered here, but `marketing/app-store/` can — it is
HTML through Playwright, and Chromium is available. That makes it the one
surface where the craft rules could be *measured* rather than inferred.
Numbers below are from `craft.mjs`-style instrumentation over all 8 phone
screens at their real 3x canvas.

| Rule | Measured | Status |
|------|----------|--------|
| Contrast (AA) | 5 real failures, incl. the medical disclaimer at 2.6:1 and subscription terms at 3.4:1 | **fixed**, all 4 sets clean |
| R2/R1 on controls | the primary CTA matched no CSS rule at all — browser-default 16px on a 3x canvas = 5.3pt | **fixed** |
| Weights | 6 distinct (400/500/600/700/800/900) | **fixed** — folded to 3 emphasis + default |
| R9 type scale | **33 distinct sizes**, from 7.0pt to 73.3pt | **open** |
| R8 8-point grid | **29 distinct off-grid values across 530 uses** — 3.7pt, 6.0pt, 10.7pt, 6.7pt, 9.3pt lead | **open** |

The last two are real and large. They are the same failure the app itself
already went through and fixed — 30 point sizes collapsed onto a six-step
scale, seven weights onto three — and the marketing deck simply never had
that pass. 33 sizes is the single clearest reason these screens read as
assembled rather than designed.

They are left open deliberately: collapsing 33 sizes onto 5 and re-flowing
530 spacing values is a redesign of assets that are about to ship, not a
bug fix, and it is the author's call rather than a reviewer's. Every number
here is reproducible, and the render-and-look loop exists now, so it is a
contained job for whoever takes it.

## 3. anthropics/skills → frontend-design

Installed at `~/.claude/skills/frontend-design/`. Mostly a posture rather
than a checklist — but running it surfaced one finding sharp enough to
record, and it is not comfortable.

**Atlas's default theme is one of the three looks the skill names as the
current AI-generated default.** Its calibration section lists them
explicitly; the second is *"a near-black background with a single bright
acid-green or vermilion accent."* Atlas ships `#101013` with emerald-500
`#10B981` as the default Emerald theme. That is the pattern, not an
approximation of it.

This is **not** filed as a bug and nothing was changed for it. Rebranding
the default palette is a product and positioning decision, not a craft
defect, and it is not a call to make from inside a review — still less
without ever having seen the app rendered. Two things are worth weighing
against the finding, too: the app ships five ramps rather than one, so the
default is a starting point the user can move off in two taps; and a
near-black surface is a defensible choice for a health app people open at
5am and last thing at night.

What the skill would push toward, if the direction is ever revisited: the
signature should come from somewhere in the subject's own world — recovery,
sleep, load, adaptation — rather than from the accent colour. The Liquid
Glass surface language and the five-ramp system are the app's real
non-default choices; the default accent is the safe one.

The skill's structural rule — *"eyebrows, dividers and labels should encode
something true about the content, not decorate it"* — is what the 60/30/10
pass above acted on independently, and the two agree.

## 4. OneRedOak/claude-code-workflows → design-review

| Phase | Status |
|-------|--------|
| 0 Preparation | n/a |
| 1 Interaction and user flow | **open** — needs a live surface |
| 2 Responsiveness | **partial** — the Screenshots workflow captures Accessibility XXXL, which is where the type-scale change would show as truncation. Not yet run. |
| 3 Visual polish | **covered statically** by `design-lint` |
| 4 Accessibility (WCAG 2.1 AA) | **covered statically** by `contrast-check` + the hit-target, unlabelled-icon and uncombined-row rules |
| 5 Robustness | **open** |
| 6 Code health | covered by SwiftLint + the parse/signature checks |
| 7 Content and console | **open** |

The subagent itself drives a browser through Playwright MCP and has no path
to a native iOS view, so phases 1, 2, 5 and 7 stay open until someone runs
a simulator. Phases 3 and 4 are what the two checkers replicate.

---

## Open findings, ranked

1. **Accent ratio — measured by area, not by reference count.** The
   source-decidable half is fixed (19 static labels moved to neutral). The
   remaining question is what fraction of *painted pixels* is accent, which
   only a render answers. The 202 low-opacity tint/wash fills are sanctioned
   by the rule, so 645 references is not 645 accent-coloured surfaces.
2. **~70 remaining gradient fills** (R1) are illustrations, chart strokes and
   ambient backdrops. Whether each is artwork or decoration turns on seeing
   it. The decorative-on-controls case — the one R1 is actually aimed at —
   is fixed and lint-enforced.
3. ~~Display type ignores Dynamic Type.~~ **Fixed.** The count was 43, not
   the 16 first reported — that figure covered numerals only and missed
   every onboarding headline. All 37 outside the fixed export canvas now use
   `AppFont.scaled(_:relativeTo: .largeTitle)`, which grows them on a
   display curve. The truncation worry that held this back was misplaced:
   without `lineLimit` the text wraps rather than clipping, and the six
   share-card sites that genuinely need a frozen size are exempt by name.
   `design-lint: fixed-font` now covers display text as well as body.
4. **Visual monotony, thumb zone, relationship spacing** (R4 and friends) —
   blocked on renders.
5. ~~Two empty states still tell without showing.~~ **Fixed.**
   `WorkoutHistoryView` needed no parent plumbing after all —
   `startWorkout()` is on the shared session service and
   `TrainContainerView` already presents on `activeSession` appearing.
   `DailyPlanCard` takes an optional `onAddProtocol`, matching its existing
   `onTapDose` shape, wired to the `pendingProtocolList` route Home already
   uses. Every empty state that asks the user to do something now offers a
   way to do it; the 8 without a CTA are error, not-found and success
   states where none applies.
