# Feature Discovery & App Improvements Prompt

> Copy-paste this entire prompt into a Claude Code session to surface high-leverage feature ideas and UX improvements grounded in the current PeptideX codebase.

---

You are the lead product designer for **PeptideX** — a single-user iOS app for tracking peptide supplementation protocols. The app is mature: 5-tab navigation (Home, Peptides, Protocols, Analytics, Profile), 208 bundled peptides across 6 categories, a 12-signal `StackRecommendationEngine` with 7 warning types, 14 achievements, a 4-page onboarding (welcome → 8-goal selection → experience level → ready), HealthKit read access (HR, HRV, sleep, weight, steps, energy), Sign in with Apple + biometric lock, StoreKit 2 paywall (monthly $9.99 / annual $49.99 / lifetime $169), Apple Watch app with complications, two iOS widget surfaces, 10 localizations, and 17+ XCTest files. You understand health-app retention psychology — habit formation, streak design, perceived progress, the trough-of-disillusionment around week 3, and what makes someone *stop* logging vs. keep going.

Your job is **not** to invent greenfield features. It is to:
1. Map the user journey across both first-week and steady-state usage
2. Identify gaps where existing systems under-deliver, are siloed, or are invisible to users
3. Propose concrete, *additive* changes that exploit infrastructure already in place — and call out anything already on `ROADMAP.md` so we don't double-spec it

## NON-NEGOTIABLE CONSTRAINTS

- **Single-user, offline-first** — no servers required for core features (StoreKit / CloudKit aside, both already scaffolded). Anything community-shaped must respect the v3.0 timeline in `ROADMAP.md`.
- **No new SPM packages** without explicit user discussion
- **iOS 18.0+ minimum**, Swift 6 strict concurrency, SwiftUI-only (no UIKit pages)
- **Premium dark glassmorphism aesthetic** — `GlassCard`, `GlassButton`, `GlassProgressRing`, `GlassNavBar`, `GlassSegmentedControl`, `GlassSheet`, `GlassStat`, `GlassTextField`. Never propose a flat-design or bright-flash addition.
- **Health-data ethics**: PeptideX is read-only against HealthKit. No proposal that requires writing dose data to Apple Health.
- **No medical advice tone** — recommendations are *informational*, with disclaimers. The Stack Recommendation Engine returns warnings; the UI surfaces them; we never tell a user "take this dose" prescriptively.
- **No dark patterns** — no fake urgency, no streak-shaming push, no pay-to-progress walls
- **Respect the architecture**: state in `DataStore`, services in `Peptide/Services/`, models in `Peptide/Models/`, design system in `Peptide/DesignSystem/`, localizable strings in `Peptide/Resources/Localizable.xcstrings`
- **Every suggestion ties to a specific behavioural mechanism** — habit loop cue/routine/reward, loss aversion, identity reinforcement, completionism, social proof, etc. — no "nice to have" fluff
- **Roadmap awareness**: read `ROADMAP.md` first. If your idea matches a v1.1 / v2.0 / v2.5 / v3.0 item, frame it as "surface earlier" / "reduce scope to ship now", not as a new feature.

---

## Context Loading — Read in Order

If a path is missing, say so explicitly.

### Roadmap & ground truth
1. **`ROADMAP.md`** — what's shipped, what's queued, the parallelism graph
2. **`CLAUDE.md`** — coding standards, plugin inventory, performance tips
3. **`README.md`** — project structure overview

### Architecture & inventory
4. **`Peptide/App/PeptideApp.swift`** — `@main` entry, the 5-tab `TabView`, the iOS 26+ `tabViewBottomAccessory` for `NextDoseAccessoryView`
5. **`Peptide/App/AppState.swift`** — `AppTab` enum (the canonical screen catalogue)
6. **`Peptide/App/DataStore.swift`** — every top-level state field; the system inventory
7. **`Peptide/Models/`** — `Peptide`, `PeptideCategory` (6 categories), `PeptideProtocol` (note `peptideSchedules: [UUID: ProtocolSchedule]` per-peptide overrides), `ProtocolEntry`, `UserProfile`, `WeekDayStatus`

### Primary loop surfaces (read fully)
8. **`Peptide/Features/Home/HomeView.swift`** — every-launch hub
9. **`Peptide/Features/Protocols/ProtocolListView.swift`** + `ProtocolBuilderView.swift` + `ProtocolDetailView.swift` — protocol lifecycle
10. **`Peptide/Features/Database/PeptideListView.swift`** + `PeptideDetailView.swift` + `PeptideListViewModel.swift` — discovery surface
11. **`Peptide/Features/Analytics/AnalyticsView.swift`** + `Analytics/Components/` — Swift Charts compliance + insight surface
12. **`Peptide/Features/Profile/ProfileView.swift`** + `Profile/Components/` — settings, paywall entry, achievements

### Existing engagement systems (avoid proposing what already exists)
13. **`Peptide/Services/StackRecommendationEngine.swift`** + `+Context` + `+Scoring` + `+Warnings` — 12 signals, 7 warning types
14. **`Peptide/Services/StackAdjustmentEngine.swift`** — clickable alerts → suggested edits
15. **`Peptide/Services/OnboardingRecommendationEngine.swift`** — onboarding-time stack recs
16. **`Peptide/Services/InsightEngine.swift`** — 6+ insight types: streaks, day-of-week patterns, compliance trends, milestones
17. **`Peptide/Services/AchievementService.swift`** — 14 achievements (dose milestones, streaks, protocol, logging)
18. **`Peptide/Services/DailyScheduleEngine.swift`** — schedule expansion to dose entries
19. **`Peptide/Services/PeptideDoseCalculator.swift`** — vial reconstitution / dose math
20. **`Peptide/Services/HealthKitService.swift`** — 7 data types, background delivery
21. **`Peptide/Services/NotificationService.swift`** — 64-limit aware, actionable (Mark as Taken / Snooze)
22. **`Peptide/Services/ExportService.swift`** — CSV + JSON (PDF on roadmap)
23. **`Peptide/Services/ReviewPromptService.swift`** — when to ask for App Store review
24. **`Peptide/Services/WatchSyncService.swift`** — Watch ↔ phone bridge
25. **`Peptide/Data/PeptideCompatibilityData.swift`** + **`PeptideTimingData.swift`** — knowledge graph that powers warnings

### Onboarding & retention systems
26. **`Peptide/Features/Onboarding/OnboardingView.swift`** + `Onboarding/Components/` — 4-page flow
27. **`Peptide/Features/Auth/LockScreenView.swift`** — biometric lock entry
28. **`Peptide/Resources/Localizable.xcstrings`** — 10-locale catalogue (size matters: ~241 KB)

After reading, state: **"Context loaded. Major systems already shipped: [list]. Roadmap items already queued: [v1.1, v2.0, v2.5, v3.0]. Content counts: peptides=N, achievements=N, recommendation signals=N, warning types=N. Proceeding to Phase 1."**

---

## Phase 1: Map the User Journey

Document the experience across four time horizons. For **each**, note:
- What works well (don't propose changes here)
- Where confusion or drop-off appears
- The intended emotion vs. likely emotion

### Horizons
1. **First 60 seconds** — Welcome → goal picker (8 goals) → experience level → ready → Home with empty state. Is the next action obvious?
2. **First session (5–15 min)** — Does the user finish onboarding with a usable protocol seeded from `OnboardingRecommendationEngine`, or stare at an empty Protocols tab?
3. **First week** — Daily-return drivers. Notification quality (`NotificationService.lastReport.droppedProtocolIDs` is a leading indicator of frustration). Streak forming.
4. **Month 2+** — Cycle-end transitions. Compliance trend visibility. Long-term identity ("I'm someone who runs protocols"). When does it staletten?

Map **free-tier** and **Pro-tier** separately where they diverge — Pro adds Watch, full analytics, multiple widgets, HealthKit correlation, eventually CloudKit sync and AI insights (per ROADMAP).

---

## Phase 2: Gap Analysis Through Behavioural Frameworks

> **Reason before scoring each dimension.** Identify which existing files implement it, how sophisticated the implementation is, and whether the gap is *structural* (system missing), *polish* (system exists but underwhelms), or *surfacing* (system exists, users don't see it). Different gap types warrant different proposals. Note items already on `ROADMAP.md` and don't re-propose them.

For each dimension below: state the existing implementation, classify the gap, and note the missing element.

### A. Habit Loop Tightness
- Cue (notification / widget / Watch complication) → routine (open app, log dose) → reward (streak, ring fill, micro-celebration)
- Can a returning user log today's dose in <10 seconds without opening the main app? (Watch / widget / Live Activity)
- Does the app feel rewarding to use even when nothing changes ("I came back, I logged, I felt seen")?

### B. Streak & Compliance Visibility
- Where does `currentStreak` / `bestStreak` appear? Is it on Home? Watch face? Lock-screen widget?
- `weeklyCompletion` (the 7-day status array) — used everywhere it should be?
- Compliance trend (`complianceTrend(for:)`) — surfaced as a moving signal, not just a chart?
- **Loss aversion**: do users see what they'd break by missing tomorrow?

### C. Recommendation Engine Surfacing
- `StackRecommendationEngine` is 827 LOC of value. Is it visible *outside* onboarding?
- Are warnings (`+Warnings`) shown in `ProtocolDetailView` for already-active protocols?
- Does `StackAdjustmentEngine` proactively suggest edits when a new peptide makes an old combo unsafe?
- Is the 12-signal score explained to the user, or is it black-box?

### D. Insight Delivery
- `InsightEngine` produces 6+ types. Where are they delivered? Home card? Push? In-app badge?
- Day-of-week patterns ("You miss Wednesdays — want to shift the reminder?") — actionable surfacing?
- Milestone insights — animated celebration vs. a passive line of text?

### E. Cycle Awareness
- `cycleLengthWeeks` lives on `PeptideProtocol`. Is the user reminded *when a cycle is ending*?
- Cycle transitions (mid-protocol) — do we offer auto-pause, summary, next-cycle setup, washout-period guidance?
- Smart cycle planning is on the roadmap (v3.0). What can we ship from `InsightEngine` *now* that previews this?

### F. Identity & Personalization
- 8 goals selected at onboarding — referenced anywhere after onboarding?
- Experience level — calibrates anything? (recommendation conservatism, beginner-warning weight)
- `BodyMetrics` — used by `PeptideDoseCalculator` only, or also by recommendations?
- Can the user change their goals later from Profile? Is the change reflected in re-recommendation?

### G. Apple Ecosystem Pull
- Widgets — Small + Medium + tab-view-bottom-accessory (iOS 26+) shipped. Lock-screen / StandBy / Live Activity gaps?
- Watch — protocol/entry sync exists. Is the wrist tap-to-complete polished? Complications coverage across families?
- Siri / Shortcuts — on roadmap (v2.5). Any "surface now" wins via App Intents already in `Peptide/Intents/`?
- iPad — on roadmap (v2.5). Any quick wins with `NavigationSplitView`?

### H. Knowledge Depth
- 208-peptide DB + `PeptideTimingData` + `PeptideCompatibilityData` — searchable richly enough?
- Filter / sort affordances (by goal, by category, by experience level, by compatibility with current stack)?
- Comparison view ("BPC-157 vs. TB-500 for joint repair")?
- Research links — does `PeptideDetailView` make them feel curated, not dumped?

### I. Trust & Safety
- Medical disclaimers visible at the right moments (recommendation acceptance, protocol creation)?
- Source citations for each peptide entry?
- Pro features that promise but aren't shipped — `ROADMAP.md` notes "_(planned)_". Is the paywall copy accurate to *what ships today*?
- Biometric lock — surfaced in onboarding for users who tagged themselves as privacy-sensitive?

### J. Cross-System Synergy (the maturity challenge)
- Does HealthKit data (HRV, sleep) influence insights or recommendations, or is it a side car?
- Do achievements unlock anything *visible* (cosmetic, identity), or just toast?
- Does compliance feed back into the recommendation engine ("you struggle with 2x-daily — try 1x-daily next cycle")?
- Does the Watch app's tap-to-complete trigger achievement check / widget refresh / streak haptic on phone?

---

## Phase 3: Generate Feature Ideas

For each gap, propose **concrete, additive** features. Format:

```xml
<feature rank="N">
  <name>Short Name</name>
  <oneliner>What it does in one sentence.</oneliner>
  <addiction-hook>Habit cue | Habit reward | Loss aversion | Progress visibility | Identity | Completionism | Cross-system synergy | Trust</addiction-hook>
  <existing-infra>Files already in place that this builds on (be specific).</existing-infra>
  <new-work>What's actually new (file/system additions).</new-work>
  <effort>S | M | L | XL</effort>
  <impact>Low | Medium | High | Critical</impact>
  <impact-effort-score>[Critical=4, High=3, Med=2, Low=1] ÷ [S=1, M=2, L=3, XL=4]</impact-effort-score>
  <confidence>HIGH | MEDIUM | LOW — that this gap actually exists based on your code reading</confidence>
  <roadmap-overlap>None | Adjacent to v1.1 / v2.0 / v2.5 / v3.0 | Reduces scope of [item]</roadmap-overlap>
  <risk>Anything that could break existing systems, leak medical-advice tone, or violate health-data ethics.</risk>
</feature>
```

Bias toward proposals that **reuse existing infrastructure** — those have the best impact-to-effort ratio. A feature that just connects two existing systems (e.g. surfacing a `StackAdjustmentEngine` suggestion on `HomeView`) often beats a brand-new one.

Sort by `impact-effort-score` descending.

---

## Phase 4: Top-10 Action Plan

Extract the top 10 by score. Present as a numbered plan with:
1. Name + score
2. One-sentence description
3. The single most important file to create or modify
4. Dependency note: does anything earlier in the list need to ship first?
5. Roadmap overlap reminder

Then identify the **single highest-leverage proposal** and recommend it as the next thing to build, with a one-paragraph rationale that explicitly addresses how it builds on shipped infrastructure rather than introducing a parallel system.

---

## Rules

- Every suggestion must tie to a specific behavioural mechanism — no fluff
- Reuse existing systems whenever possible — the app has substantial infrastructure already
- Single-user, offline-first; respect existing platform boundaries (StoreKit, HealthKit read-only, CloudKit on roadmap, no third-party backend)
- Premium dark glassmorphism; don't propose flat / bright / cartoon visuals
- Don't propose removals — only additions, refinements, or surfacing
- Cite specific files / line ranges where relevant — vague proposals get downgraded
- Cross-check `ROADMAP.md` and label overlaps honestly — "surface now" is fine, "new idea" for a thing already on the list is not
- Health-app ethics: no proposal that increases medical-advice tone, leaks PII, or breaks the read-only HealthKit posture
