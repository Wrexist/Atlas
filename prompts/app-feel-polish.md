# App Feel & Polish Prompt

> Copy-paste this entire prompt into a Claude Code session to find and implement micro-interactions, animations, and feedback that make PeptideX feel premium, calm, and trustworthy.

---

You are the motion and haptics lead for **PeptideX** — a SwiftUI iOS 18+ health-tracking app with a dark glassmorphism design system, gold accent (`AppColor.accentPrimary`), and a 5-tab structure. The aesthetic is **clinical-premium**: restrained, confident, never playful or bright. Mid-range iPhones (iPhone 12 and up) must hit 60fps; 120Hz ProMotion devices should feel buttery. Animate only `transform` (`scale`, `offset`, `rotationEffect`) and `opacity` — never animate layout properties (`frame`, `padding`, `Spacer().frame()`) on the hot path. Polish compounds: an app that feels great to *use* is one users return to without thinking.

## NON-NEGOTIABLE CONSTRAINTS

- **Animate only transform & opacity** in high-frequency surfaces (Home, today's doses, list rows). Layout-driving animations (e.g. expanding cards) are acceptable only on user-initiated taps with `transaction.disablesAnimations = false` and short duration.
- **Never block input** — use `Animation.smooth` / `.snappy` / `.spring(response:dampingFraction:)`; default to interruptible. Do not gate user actions behind animations.
- **Use what's already installed**: SwiftUI native (`withAnimation`, `Animation`, `matchedGeometryEffect`, `phaseAnimator`, `keyframeAnimator`, `Transition`, `ContentTransition.numericText`), `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` (already invoked from `DataStore`), `WidgetKit` reload via `WidgetCenter`. **No new SPM packages — no Lottie, no Pop, no Rive.**
- **Duration discipline**: micro-interactions 120–250ms, transitions 250–400ms, celebrations 400–800ms, achievement reveals up to 1.2s. Never longer.
- **60fps on iPhone 12; 120fps target on ProMotion**. No heavy `Canvas` or `TimelineView`-driven loops outside celebrations.
- **Glassmorphism preserved**: `GlassCard`, `GlassButton`, `GlassNavBar`, `GlassProgressRing`, `GlassSegmentedControl`, `GlassSheet`, `GlassStat`, `GlassTextField` are the building blocks. Don't reinvent.
- **Dark mode is forced** (`.preferredColorScheme(.dark)` at root). Don't propose light-mode-specific polish.
- **Don't over-animate** — if everything moves, nothing stands out. Reserve motion for moments that matter (logged dose, streak unlock, recommendation accept, achievement, paywall confirm).
- **Respect Reduce Motion**: every non-critical animation must check `@Environment(\.accessibilityReduceMotion)` and degrade to fade or no-op.
- **Respect `profile.hapticFeedbackEnabled`** — `DataStore` already gates haptics on this. Any new call site must do the same. Use the existing pattern (`if profile.hapticFeedbackEnabled { ... }`), don't bypass.
- **Health-adjacent app**: avoid celebratory excess on serious moments. Logging a missed dose should feel calm and acknowledging, not punishing. A pause-protocol confirm should feel deliberate, not regretful.

---

## Existing Animation & Haptics Infrastructure (Read First)

If a path is missing, say so explicitly.

### Animation primitives in use
1. **`Peptide/DesignSystem/Animations/AnimationConstants.swift`** — canonical durations, springs, easing. Use these constants; don't redefine.
2. **`Peptide/DesignSystem/Animations/StaggerHelper.swift`** — list-stagger pattern for first-mount
3. **`Peptide/DesignSystem/Theme/`** — `AppColor`, `AppFont`, `Spacing` (these compose the visual rhythm — read but don't modify)

### Glass component library (the design vocabulary)
4. **`Peptide/DesignSystem/Components/GlassCard.swift`** — default container; observe its press/tap state
5. **`Peptide/DesignSystem/Components/GlassButton.swift`** — tappable surface; press state
6. **`Peptide/DesignSystem/Components/GlassProgressRing.swift`** — the compliance ring; the most-watched animation in the app
7. **`Peptide/DesignSystem/Components/GlassSegmentedControl.swift`** — tab-within-page selection
8. **`Peptide/DesignSystem/Components/GlassSheet.swift`** — modal entry/exit
9. **`Peptide/DesignSystem/Components/GlassStat.swift`** — numeric-display tile (use `ContentTransition.numericText` for changes)
10. **`Peptide/DesignSystem/Components/GlassTextField.swift`** + **`GlassNavBar.swift`** + **`PeptideCategoryBadge.swift`** + **`ExpandableText.swift`**

### Haptic call sites (already wired in `DataStore`)
- `addProtocol`, `addCustomPeptide`, `addPeptide(toProtocolId:)` → `.success` notification haptic
- `toggleEntry` → `.light` impact (becoming complete) / `.soft` impact (becoming incomplete)
- `setPeptideSchedule` → `.light` impact
- All gated on `profile.hapticFeedbackEnabled`

### High-traffic surfaces (audit fully)
11. **`Peptide/Features/Home/HomeView.swift`** — every-launch hub; today's doses, next-dose card, quick stats
12. **`Peptide/Features/Home/Components/`** — hub building blocks
13. **`Peptide/Features/Protocols/ProtocolListView.swift`** + `ProtocolBuilderView.swift` + `ProtocolDetailView.swift` — high-frequency edit surface
14. **`Peptide/Features/Database/PeptideListView.swift`** + `PeptideDetailView.swift` — search & discovery
15. **`Peptide/Features/Analytics/AnalyticsView.swift`** + `Analytics/Components/` — Swift Charts surfaces
16. **`Peptide/Features/Profile/ProfileView.swift`** + `Profile/Components/` — settings & paywall entry
17. **`Peptide/Features/Onboarding/OnboardingView.swift`** — first-impression peak
18. **`Peptide/Features/Auth/LockScreenView.swift`** — biometric unlock peak
19. **`Peptide/App/PeptideApp.swift`** — the iOS 26+ `tabViewBottomAccessory` (`NextDoseAccessoryView`) is a key polish surface

### Watch & widgets (reduced motion budget)
20. **`PeptideWidgets/`** + **`PeptideWatch/`** + **`PeptideWatchWidgets/`** + **`Shared/WidgetData.swift`** + **`Shared/WatchData.swift`**

After reading, state: **"Context loaded. Existing animation tokens: [list from AnimationConstants]. Existing haptic call sites: [count by category]. Highest-polish surface: [view]. Lowest-polish surface: [view]. Proceeding to audit."**

---

## Audit Every Interaction (across five dimensions)

Walk every page and component. For each user-triggered interaction, evaluate:

### 1. Feedback & Response
- Every tap → immediate visual + (where appropriate) haptic feedback?
- Loading states present where work is async (HealthKit auth, StoreKit purchase, CSV/JSON export, CloudKit sync, large list cold-load)?
- State changes celebrated **proportionally** to importance? (Toggling a single dose entry ≠ unlocking a 30-day streak ≠ buying Pro lifetime.)
- Destructive actions weighted appropriately? (Delete protocol, cancel subscription, sign out, disable biometric lock.)
- Logged-but-late doses feel acknowledged, not graded?

### 2. Transitions & Flow
- Page transitions feel spatial (back gestures land where you'd expect)?
- Modals (`GlassSheet`) animate in/out, never pop?
- Tab switches preserve scroll position where it makes sense?
- `matchedGeometryEffect` opportunities (e.g. peptide card → detail hero, today's dose → log sheet)?
- The iOS 26+ `tabViewBottomAccessory` (`NextDoseAccessoryView`) transitions between "next dose" and "all completed" smoothly?

### 3. Visual Rhythm
- Numeric changes use `ContentTransition.numericText` (compliance %, streak count, days logged, total doses)?
- List items stagger in (`StaggerHelper`) on first mount, not all-at-once?
- Chart axis transitions (`AnalyticsView`) animate value changes, not just initial draw?
- Empty states designed (icon + copy + suggested CTA) not blank?
- New items in lists (just-created protocol, just-logged dose) get a subtle highlight on entry?

### 4. Micro-Rewards
- The `GlassProgressRing` celebrates fill-to-100% (subtle gold pulse, success haptic) — verify and replicate the pattern for streak milestones?
- Streak count increments — number rolls up, not pops?
- Achievement unlock — calm gold flash + numeric haptic, not fireworks?
- Compliance trend turning positive after a slump — surfaced with a single "trending up" indicator, not a confetti shower?
- HealthKit correlation insights ("sleep was better on dose days") — quiet revelation moments, not push-dialog interruptions?

### 5. Haptic Coverage
Apple's haptic taxonomy maps as follows for PeptideX:
- **`.light` impact**: list selection, toggle, segment switch, slider tick, tab switch
- **`.soft` impact**: undo / un-toggle, secondary action, schedule edit
- **`.medium` impact**: open detail sheet, save form, accept recommendation
- **`.heavy` impact**: reserved — use only for rare, weighty actions (delete protocol, cancel subscription)
- **`.success` notification**: dose logged, protocol created, achievement unlocked, purchase confirmed, biometric unlock success
- **`.warning` notification**: notification overflow detected, recommendation engine flagged a high-severity warning, dose missed for a critical-time peptide
- **`.error` notification**: purchase failed, restore failed, save failure with `lastError` set, biometric unlock denied
- Are haptics overused? (Tapping every nav row is fatigue.) Are they consistently gated on `profile.hapticFeedbackEnabled`?

---

## Emotional Context Ranking

> **Reason about emotional context before scoring.** A success haptic on a logged dose ≠ a success haptic on a paywall confirm. The same animation lands differently depending on stakes. Classify each finding:
> - **Navigation tap** — low feel-impact ceiling
> - **Routine action** (toggle dose, edit schedule) — low–medium ceiling
> - **Decision moment** (accept recommendation, save protocol, start cycle) — medium ceiling
> - **Positive milestone** (streak, achievement, compliance high) — high ceiling
> - **Negative event** (missed dose, recommendation warning, purchase failure) — high ceiling, **but** the response must feel calm and respectful, not punitive
> - **First impression** (onboarding, first launch, biometric unlock) — highest ceiling
> - **Health-data moment** (HealthKit correlation, body-metrics save, export) — medium-high, requires gravity not whimsy

---

## Output: Ranked Issue List

```xml
<feel-issue rank="N">
  <interaction>Specific user action (e.g., "tap to toggle a dose entry on HomeView")</interaction>
  <surface>Page or component (file path)</surface>
  <current-experience>What happens now — be specific</current-experience>
  <target-experience>What it should feel like — describe sensation, duration, haptic, transition</target-experience>
  <implementation>Specific SwiftUI animation / transition / haptic call (1–3 lines pseudocode), citing AnimationConstants tokens where applicable</implementation>
  <effort>S (a few lines) | M (new animation token or transition) | L (new component or refactor)</effort>
  <feel-impact>Low | Medium | High</feel-impact>
  <emotional-context>Navigation | Routine | Decision | Positive milestone | Negative event | First impression | Health-data</emotional-context>
  <reduce-motion-fallback>How this degrades when accessibilityReduceMotion is true</reduce-motion-fallback>
  <risk>Anything that could regress 60fps, block input, conflict with existing haptic call sites, or break dark glassmorphism</risk>
</feel-issue>
```

Sort by: `feel-impact` (High → Low), then `effort` (S → L), then `emotional-context` (First impression / Positive / Negative > Decision > Routine / Navigation).

---

## Pre-Implementation Phase Gate

Before writing a single line, state these checks explicitly:

1. ✅ Audited `HomeView`, `ProtocolListView`/`ProtocolBuilderView`/`ProtocolDetailView`, `PeptideListView`/`PeptideDetailView`, `AnalyticsView`, `OnboardingView`, `LockScreenView` (highest-traffic & first-impression surfaces)
2. ✅ All top-15 candidates use only SwiftUI native APIs + `UIFeedbackGenerator` — no new packages
3. ✅ All proposed animations animate only `transform` / `opacity` in hot paths (or are user-initiated and brief)
4. ✅ All durations within budget (250 micro / 400 transition / 800 celebration / 1200 reveal)
5. ✅ Every animation has a `accessibilityReduceMotion` fallback
6. ✅ Every new haptic site goes through `profile.hapticFeedbackEnabled` gating
7. ✅ No top-3 item touches StoreKit catalogue, `MigrationService`, or the recommendation engine warning pipeline
8. ✅ Dark glassmorphism preserved — no new bright accents introduced
9. ✅ Health-adjacent gravity preserved — negative events feel calm, not punitive

---

## Implementation

Work the top-15 list in order. Smallest effort first within each impact tier (S → M → L). For each:

1. Read the target file (if not loaded)
2. Make the focused change — never refactor surrounding code
3. State: `"Implemented [N]: [interaction]. Change: [what was added]. Effort: [S/M/L]. Touched: [file:line]."`

After all implementations, smoke-test:

```
xcodebuild build -scheme Peptide -destination 'platform=iOS Simulator,name=iPhone 16'
```

Manually verify in the simulator at iPhone 16 (390pt) and iPhone SE 3rd gen (375pt) widths. Report any frame drops or interruption issues. Run `swiftlint --strict` before marking done.

---

## Rules

- Animations must be performant — `transform` and `opacity` on hot paths; layout animations only on user-initiated, brief taps
- Use SwiftUI native + `UIFeedbackGenerator` — no new packages
- Durations: 120–250 micro / 250–400 transition / 400–800 celebration / up to 1200 reveal
- Never block input — every animation interruptible
- 60fps on iPhone 12; 120fps on ProMotion
- Don't over-animate — restraint is the aesthetic
- Respect `accessibilityReduceMotion` and `profile.hapticFeedbackEnabled` (the latter is already gated by `DataStore`; just keep the pattern)
- Health-app gravity — calm acknowledgement on negative events, never punitive
- Don't modify `Peptide/DesignSystem/Components/Glass*.swift` unless the polish issue *is* a component issue — prefer call-site changes
