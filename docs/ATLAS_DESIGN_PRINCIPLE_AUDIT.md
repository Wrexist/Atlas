# Atlas — design-principle audit

What this is: Atlas measured against the four design resources named for
this review, rule by rule, with the measurement and where it is enforced.
Every number here is reproducible from the two checkers in `scripts/`.

Reproduce:

```sh
python3 scripts/design-lint.py --all     # 19 rules, gates CI on errors
python3 scripts/contrast-check.py        # 244 colour pairs, gates CI
```

Current state: **0 errors, 0 warnings**.

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
| R1 | No gradients | **decorative use removed; brand ramp kept under the rule's own exception** | Two rounds. First the 6 CTA capsules filling with `[accentPrimary → accentLight]`, which were also a contrast failure. Then the idiom that is R1's actual definition — *"the default move when a colour decision hasn't been made"* — a gradient from a colour **into itself** at lower opacity. Five of those; four were soft shading on medallions and chips and are now flat. What remains is deliberate: the accent ramp between two *different* brand stops (R1 exempts a gradient that is the brand), gradients fading to `opacity(0)` which are area fills under chart lines, the muscle map's anatomical belly shading, scrim masks, and the fixed export canvas. |
| R2 | No glow | **enforced, 0 open** | You asked for these 12 rules enforced; I kept 7 halos on my own judgement that a glowing ring is the category idiom. That was substituting taste for your instruction. All are gone: `MetricRing` lost its `glow` parameter entirely (an API offering a banned effect is the wrong shape), and 5 more turned up in a *third* form the rule still could not see — a blurred coloured disc stacked behind a medallion, a halo built from a shape rather than a shadow. The rule now catches all three forms and has tests for each. Data-encoding glow stays: the muscle-map heat halo *is* the activation reading, and the share card's 180px backdrop wash is scene lighting on a fixed export canvas. |
| R3 | No `transition: all` | **enforced, both clauses** | The SwiftUI analogue of `transition: all` is `.animation(x)` with no `value:` — that half was already covered. The other half of the rule, *"explicit durations and easings"*, was not: nine sites used a bare `withAnimation { }`, taking SwiftUI's default rather than naming the motion, which is the same "author didn't decide how fast" the rule is about. All nine now use an `AppAnimation` constant. `design-lint: unnamed-motion` covers it. |
| R4 | Kill visual monotony | **measured, still needs eyes** | Not "unmeasurable" as first claimed — the squint test has a proxy: largest type on a screen ÷ median type. Onboarding scores 3.5–4.3x (a clear focal element); `PeptideListView` scores **1.17x** (17pt vs 14pt median), `HabitsView` 1.33x, `ProtocolBuilderView` 1.42x. But the metric cannot tell "flat because nobody made a choice" from "flat because it is a list" — and those three lowest scorers are a searchable database list, a habit list and a form, which are *correctly* flat. Acting on the number alone would damage them. Recorded as a ranked candidate list for whoever has a simulator. |
| R5 | No placeholder text | **enforced, both clauses** | Lorem/"coming soon"/TBD: zero hits, as before. The rule's *second* clause — "never use a placeholder as an input's only label" — had never been checked. Ten inputs failed it: six numeric fields across the weight, workout, nutrition-target and macro sheets announced themselves to VoiceOver as **"0, text field"**, and the custom-peptide form introduced its Name field as *"e.g., Selank"*. In each case the real label sat beside the field in a separate `Text` the field never inherits. All ten now carry `.accessibilityLabel`; `design-lint: placeholder-as-label` holds the line. |
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
| R9 type scale | 33 distinct sizes, 7.0pt–73.3pt | **fixed** — snapped onto the app's own six-step `AppFont.Scale` (8/11/13/16/20/24pt), largest move 2.0pt, plus four untouched hero numerals |
| R8 8-point grid | 26 off-grid values, 153 source uses | **fixed** — snapped to the 4pt half-grid, largest move 2.0pt; 19 sub-1.5pt optical nudges remain, which the app's own rule also permits |

The type scale was the same failure the app itself already fixed — 30 point
sizes collapsed onto six — and the marketing deck simply never had that
pass. It now uses the *same* scale as the app, which is the point: the
screenshots and the product finally agree about what a caption is. 125
declarations moved, none by more than 2.0pt, and all four sets were
re-rendered and inspected.

The grid went the same way, once it was clear the render-and-look loop
made it checkable rather than hopeful: 153 source values snapped to the 4pt
half-grid, largest move 2.0pt, every screen re-rendered and inspected. What
remains off-grid is 19 nudges of 1pt or less, which is the same optical
allowance `design-lint` grants the app.

The primary CTA and the "BEST VALUE" chip also carried a gradient *and* a
coloured drop shadow — R1 and R2 on the one element both rules name. Both
are flat now with neutral elevation, matching the `accentFill` call already
made in the app.

**This surface is done.** Contrast, weights, type scale, grid, and the
control treatments are all measured, fixed, re-rendered and looked at. The
only reported failure left across all four sets is one verified false
positive.

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
