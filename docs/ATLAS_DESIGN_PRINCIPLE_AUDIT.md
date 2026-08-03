# Atlas — design-principle audit

What this is: Atlas measured against the four design resources named for
this review, rule by rule, with the measurement and where it is enforced.
Every number here is reproducible from the two checkers in `scripts/`.

Reproduce:

```sh
python3 scripts/design-lint.py --all     # 16 rules, gates CI
python3 scripts/contrast-check.py        # 244 colour pairs, gates CI
```

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
| R2 | No glow | **enforced** | `design-lint: glow` — a coloured shadow at radius ≥10 behind a *glyph*. Two neon halos found and removed. Tinted elevation under a filled shape is a deliberate system and is exempt. |
| R3 | No `transition: all` | **enforced** | `design-lint: untargeted-animation` — the SwiftUI analogue is `.animation(x)` without a `value:`, which animates every change in the subtree. |
| R4 | Kill visual monotony | **open** | Not statically checkable. Squint test needs renders. |
| R5 | No placeholder text | **enforced** | `design-lint: placeholder-copy` — lorem ipsum, "coming soon", "TBD". Zero hits. |
| R6 | Contain stacking contexts | **pass** | 4 `zIndex` calls, values 1–3, no arms race. SwiftUI scopes z-order to the container, so the CSS failure mode does not arise. |
| R7 | No pure black on pure white | **enforced** | `design-lint: pure-neutral`. Light surface is `#F4F4F7`, dark is `#101013`, ink-on-accent is `#FCFCFD`. Zero pure neutrals. |
| R8 | Space on a scale | **enforced** | `design-lint: off-grid-spacing`, 8-point grid plus 2/4/6 for optical insets. |
| R9 | Type does the work | **enforced** | Six-step scale (`AppFont.Scale`), lint-enforced; three emphasis weights over the default; tabular figures on every animated numeral (`monospacedDigit`). |
| R10 | Pick an elevation language | **enforced** | `design-lint: stacked-glass` — 25 surfaces were stacking two glass materials outside the primitives; all fixed. |
| R11 | Design every state | **partial** | 20 empty states, 10 with a CTA (2 added this pass); of the 10 without, 8 are error / not-found / success states where no CTA applies. Loading and error states exist per async surface but are not machine-checked. |
| R12 | Motion is physics | **enforced** | `design-lint: motion` (no short decorative loops) and `design-lint: unguarded-loop` (a `repeatForever` in a file that never reads `accessibilityReduceMotion` fails the build). Eight loops across six views were fixed this pass. |

## 2. ceorkm/mobile-app-ui-design

| Rule | Status | Measurement |
|------|--------|-------------|
| One font family | **pass** | System font only; `.rounded` design on numerals. |
| Max 4 sizes / ≤3 weights | **partial** | Weights: 3 emphasis (semibold 285 / heavy 149 / bold 87) over the default — compliant. Sizes: six steps below display, one more than the rule's four. Held deliberately: a health app renders badge, caption and body in the same row constantly, and the 30 sizes this replaced is the failure the rule is actually aimed at. |
| Monospace for large numbers | **pass** | All display-size stat numerals carry `monospacedDigit()`. The exceptions are non-numeric (`"You're set, {name}"`) or fixed-canvas share cards. |
| 60/30/10 colour | **open — off target** | 671 accent references: 281 ink, 202 tint/wash, 101 palette/other, 58 control tint, 16 solid fill, 13 stroke. Roughly **27% against a ~10% target**. This is the largest open design finding. Thinning it is per-site judgement — which of 280 accent glyphs carry state and which are decoration is not decidable from source. |
| 8-point grid | **enforced** | `design-lint: off-grid-spacing`. |
| Relationship-based spacing | **open** | Needs renders. |
| 44×44pt tap targets | **enforced** | `design-lint: hit-target`; nine sub-44pt controls found and fixed. |
| Contrast ratios | **enforced** | `contrast-check`, 244 pairs at WCAG AA, both schemes × five themes, plus `design-lint: accent-gradient-fill` for gradient fills the pair-checker cannot resolve. |
| Empty / error / loading / success states | **partial** | See R11. |
| Thumb-zone CTAs | **open** | Needs renders. |
| Soft, background-tinted shadows | **pass** | Shadows resolve through `AppShadow`; the glow rule catches the harsh case. |

## 3. anthropics/skills → frontend-design

Installed at `~/.claude/skills/frontend-design/`. It is a posture ("make
deliberate, opinionated choices; take one real aesthetic risk"), not a
checklist, so there is nothing to measure. Applied as the standing lens on
this branch: the Liquid Glass surface language, the tuned near-neutrals,
and the five-theme ramp are the app's non-default choices.

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

1. **Accent at ~27% against a 10% target** (60/30/10). 280 accent-coloured
   glyphs. The single biggest lever on "does this read as premium", and the
   one that most needs a rendered screen to act on safely.
2. **~70 remaining gradient fills** (R1) are illustrations, chart strokes and
   ambient backdrops. Whether each is artwork or decoration turns on seeing
   it. The decorative-on-controls case — the one R1 is actually aimed at —
   is fixed and lint-enforced.
3. **Display numerals ignore Dynamic Type.** The 16 sites above 24pt use
   `Font.system(size:)` directly. At Accessibility XXXL body text grows
   past some of them and the hierarchy inverts.
   `AppFont.scaled(_:relativeTo:)` is the fix; capping growth without the
   XXXL screenshots risks truncation instead.
4. **Visual monotony, thumb zone, relationship spacing** (R4 and friends) —
   blocked on renders.
5. **Two empty states still tell without showing**: `WorkoutHistoryView`
   ("once you finish your first session…") and `DailyPlanCard` ("add a
   protocol…"). Both need a callback threaded from a parent, which is why
   they were left when the two self-contained ones were fixed.
