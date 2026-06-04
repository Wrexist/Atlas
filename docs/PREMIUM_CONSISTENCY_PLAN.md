# Premium Consistency & Polish Plan

Make Atlas read as **one** clean, premium app on every screen — so anyone,
even a first-time non-technical user, instantly understands what to do.
One theme, perfect alignment, no clipped text, consistent components,
obvious navigation.

This plan is the complete, sequenced path to get there. It is grounded in
the real design system and the actual divergences found in the codebase.

---

## 0. Principles (the rules every screen obeys)

1. **Tokens, never literals.** Color comes from `AppColor`, type from
   `AppFont`, spacing/radii from `Spacing`. A raw `Color(red:…)` or
   `.font(.system(size:…))` in a feature view is a bug unless it's a
   documented domain colour (anatomy, macro rings, rating scales).
2. **One background.** Every screen sits on `AppColor.background`
   (near-black). No screen-level gradients/materials. *(Done: the purple
   `CosmicBackdrop` was the only violator — re-skinned.)*
3. **One card, one row, one button, one header.** Each visual pattern has
   exactly one component. No re-implementing chrome inline.
4. **Text never escapes its container.** Every `Text` in a width-
   constrained context has `lineLimit` + `minimumScaleFactor`. Centred
   content is actually centred (`frame(maxWidth: .infinity)` +
   alignment), not eyeballed with `Spacer()`s.
5. **Symmetry by construction.** Paired layouts use equal-weight frames
   (`maxWidth: .infinity`) or a grid — never hand-tuned padding.
6. **Obvious over clever.** Every primary action is a labelled button with
   an icon; every empty state explains the next step in one sentence.
7. **Build-verified.** Anything that changes type size, padding, or
   alignment is confirmed on a simulator before it's called done — these
   cannot be judged from source alone.

---

## 1. Definition of done (acceptance criteria)

- [ ] Zero screen-level background divergences (all `AppColor.background`).
- [ ] Zero off-brand decorative colours in feature views (domain colours
      whitelisted + documented).
- [ ] All user-facing type flows from `AppFont` (Dynamic-Type aware);
      fixed sizes only for documented hero stats.
- [ ] No clipped/overflowing text at default **or** largest Dynamic Type.
- [ ] Paired/row layouts are visually symmetric on the 3 reference devices.
- [ ] One component each for: card, entry/settings row, primary button,
      section header, empty state, segmented control, chip, stat tile.
- [ ] Every tab's empty state names the next action.
- [ ] One dismiss convention (native Done / swipe) across all sheets.
- [ ] Lint guards on (post-migration) so regressions can't merge.

---

## 2. Already done on this branch (baseline)

- One-theme: `CosmicBackdrop` re-skinned purple → brand near-black + accent
  glow (fixed the Biology tab + premium cards looking like a different app).
- Off-brand Labs tile unified to the accent; sibling rows matched.
- Overflow guards on Profile tool subtitles + achievement badges.
- Today scroll chunked under consistent section headers; redundant
  `QuickStatsRow` removed.
- Daily-targets editor: presets + always-on recommendation.
- Protocols list promoted from a nested-stack full-screen cover to a clean
  sheet with a native Done button.
- Muscle map redesigned; photoreal asset pipeline staged.

These set the pattern; the phases below extend it app-wide.

---

## 3. The canonical design system (single source of truth)

Lock these as the reference every screen is measured against:

| Concern | Token | Value |
|---|---|---|
| Background | `AppColor.background` | `#0A0A0A` |
| Elevated / inset surface | `AppColor.surfaceSecondary` (+ 0.55 a) | `#141414` |
| Accent (themed) | `AppColor.accentPrimary/Light/Dark` | per theme |
| Text | `AppColor.textPrimary/Secondary/Tertiary` | white / `#A0A0A0` / `#888` |
| Border | `AppColor.glassBorder` | white 8% |
| Type ramp | `AppFont.*` | Dynamic-Type system fonts |
| Screen padding | `Spacing.screenPadding` | 20 |
| Card padding | `Spacing.cardPadding` | 16 |
| Card radius | `Spacing.cardCornerRadius` | 20 |
| Card | `GlassCard` / `glassSurface()` | — |
| Section header | `HomeSectionHeader` | eyebrow + title |
| Sheet chrome | `liquidGlassPresentation()` | — |

Whitelisted domain colours (do **not** tokenize): macro rings
(`AppColor.macro*`), HealthKit metrics (`AppColor.metric*`), streak/
achievement (`AppColor.streak/achievement`), anatomy primary/secondary
(MuscleMapView), notes rating scale, the deliberately-distinct Screenshot-
mode dev row.

---

## 4. Phases

### Phase A — Colour token enforcement  *(low risk, no build needed)*
Sweep feature views for non-whitelisted `Color(red:…)`/`Color(hex:…)` and
replace with `AppColor`.
- Confirmed remaining offenders are mostly **intentional** (onboarding
  "What's New" multi-colour showcase `WhatsNewPage.swift`; notes mood scale
  `ProtocolNotesTimeline.swift`). Decide per-item: keep (document) or
  tokenize.
- Net new work here is small — most was already fixed. Output: a short
  whitelist comment block in `ColorTheme.swift` enumerating the allowed
  domain colours so future reviewers know the rule.

### Phase B — Shared components (DRY → consistency)  *(medium risk; build to verify)*
Extract one component per pattern and migrate call sites. The inset-row
fill (`surfaceSecondary.opacity(0.55)` + `glassBorder`) appears in **23
files** — already visually consistent, but inline. Consolidate to prevent
future drift:
- `GlassEntryRow` (icon + title + subtitle + trailing) → migrate
  `LabsEntryCard`, `ReconstitutionEntryCard`, `FoodLibraryEntryCard`,
  `ProtocolsEntryCard`, `CommunityStacksEntryCard`, settings rows.
- `insetRowBackground()` modifier for the repeated card fill.
- Consolidate per audit Phase 6.2: one `GlassButton`, one `EmptyStateView`,
  one segmented control (fold `TrainContainerView`'s underline switcher and
  stray `Picker`s into `GlassSegmentedControl`).
- Migrate **one file first**, screenshot-diff against the original, then
  roll out. Never migrate blind in bulk.

### Phase C — Typography unification  *(build-gated — changes layout)*
Replace `.font(.system(size:…))` (~660 calls) with the `AppFont` ramp.
- Method: migrate **per screen**, build, compare against a baseline
  screenshot, fix reflows, commit. Never a global find-replace.
- Keep documented fixed sizes for hero stats (`AppFont.statValue`, the
  48pt calorie hero, etc.).
- Order screens by traffic: Today → Meals → Train → Biology → Library →
  Profile → Onboarding.

### Phase D — Layout: symmetry, centering, overflow  *(build-gated)*
The "no text outside its container / centre what should be centred" work.
- **Overflow:** every `Text` in a fixed-width/`HStack`-tight context gets
  `lineLimit` + `minimumScaleFactor` (+ `fixedSize` for intentional wrap).
  Audit `*.frame(width:`/`.frame(maxWidth:` near `Text`.
- **Symmetry:** replace hand-tuned `Spacer()` padding in paired rows with
  equal `frame(maxWidth: .infinity)` columns or `Grid`. Targets: stat
  trios, macro legends, chip rows, quick-action rows.
- **Centering:** hero/empty/CTA content uses `frame(maxWidth: .infinity)`
  + explicit alignment, not visual guesswork.
- Verify at **largest Dynamic Type** + smallest device — that's where
  clipping and asymmetry surface.

### Phase E — Navigation & IA clarity ("the dumbest person")  *(build to verify)*
- Every tab's empty state: one icon, one line of what-to-do, one button
  (route through the single `EmptyStateView`).
- First-run: a one-line coach mark per tab on first visit (dismissible),
  driven by an `@AppStorage` seen-flag.
- One dismiss convention everywhere (native Done / swipe).
- Audit per the design audit Phase 7: promote Profile + any
  `fullScreenCover` surfaces to standard navigation *(Protocols already
  done)*; replace dated `confirmationDialog` quick-logs with a glass menu.
- Plain-language labels; no jargon on primary surfaces.

### Phase F — Premium micro-polish  *(build-gated)*
- Tokenize the ~170 hardcoded `cornerRadius:` literals via
  `Spacing.concentric(...)`; make `Shadows` glass-aware (lower radius on
  iOS 26 glass).
- One motion language: standard `AppAnimation` springs for press, appear,
  and value changes; remove ad-hoc `easeInOut` durations.
- Consistent press feedback (`ScalePressStyle`) on every tappable card.
- Skeleton/shimmer (`ShimmerModifier`) on every async surface instead of
  bare spinners.

### Phase G — Accessibility & Dynamic Type  *(build to verify)*
- `accessibilityLabel` on every icon-only button (currently ~82/250 files).
- ≥44pt hit targets; verify contrast of small badge text on glass.
- Full Dynamic-Type sweep after Phase C.

### Phase H — Regression prevention  *(after C completes)*
Turn on enforcement so the work can't rot. **Only after** the migrations,
or it floods the existing ~660 violations:
- SwiftLint `custom_rules` (warning) flagging `Color(red:`/`Color(hex:` and
  `\.font\(\.system\(size:` in `Peptide/Features/**` (DesignSystem exempt
  via folder-scoped invocation or an inline `// swiftlint:disable`).
- A CI "design-token" check on changed files in PRs.

---

## 5. Per-screen verification checklist (build-gated work)

Run for each screen, on **iPhone SE (smallest) + iPhone 17 Pro + iPad**, in
**light/dark** (dark is primary) at **default + XXL Dynamic Type**:

- [ ] Background is `AppColor.background`; no stray gradient/material.
- [ ] All colours are tokens (or whitelisted domain colours).
- [ ] All type is `AppFont`; nothing clipped at XXL.
- [ ] Every `Text` fits — no truncation/overflow; centred items centred.
- [ ] Paired rows symmetric; equal column weights.
- [ ] Cards/rows/buttons use the shared components.
- [ ] Tap targets ≥44pt; icon buttons have a11y labels.
- [ ] Empty state explains the next action.
- [ ] Sheet dismiss is the native convention.
- [ ] Press/appear animation matches the app's motion language.

Capture a before/after screenshot per screen in the PR.

---

## 6. Sequencing & effort

| Phase | Risk | Build? | Est. |
|---|---|---|---|
| A Colour enforcement | Low | No | 0.5 day |
| B Shared components | Med | Yes | 1–2 days |
| C Typography | Med | **Yes** | 2–3 days |
| D Layout/symmetry/overflow | Med | **Yes** | 2–3 days |
| E Navigation/IA clarity | Med | Yes | 1–2 days |
| F Micro-polish | Low–Med | Yes | 1–2 days |
| G Accessibility | Low | Yes | 1 day |
| H Lint guards | Low | CI | 0.5 day |

Recommended order: **A → B → C → D → E → F → G → H** (tokens before the
components that use them; typography before layout, since type size drives
reflow; lint last so it doesn't fight in-flight migrations). Total ≈
**9–14 focused days**, fully parallelisable by screen once Phase A/B land.

---

## 7. Risks & mitigations

- **Blind layout edits regress alignment** → every layout/type change is
  screenshot-diffed on a simulator before commit; no bulk find-replace.
- **Token migration floods lint** → enforcement (Phase H) turns on only
  after the migration, scoped to `Features/`.
- **Over-tokenizing domain colours** → explicit whitelist in
  `ColorTheme.swift`; macro/metric/anatomy/rating colours stay literal.
- **Onboarding showcase loses character** → `WhatsNewPage`'s multi-colour
  is intentional; exempt it.
- **Scope creep** → ship per-screen PRs against the checklist; each screen
  is independently mergeable.

---

## 8. What unblocks the build-gated phases

Phases C, D, E, F, G need a simulator to verify. The fastest unblock is a
**SwiftUI snapshot-test harness** (e.g. point-free `swift-snapshot-testing`
or Xcode preview screenshots) wired into CI so each screen's before/after
is captured automatically — then the pixel work becomes review-by-diff
instead of manual. Standing that up is the recommended first build-session
task; after that, Phases C–G run screen-by-screen at speed.

---

*This plan is intentionally incremental and build-verified: the one-theme
foundation is already in place; everything here makes each remaining
surface match it without guessing at pixels.*
