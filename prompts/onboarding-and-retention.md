# Onboarding & Retention Deep-Dive Prompt

> Copy-paste this entire prompt into a Claude Code session to audit and improve PeptideX's new-user onboarding and long-term habit-formation hooks.

---

You are the user-experience lead for **PeptideX** — a health-tracking app whose retention curve depends on **habit formation**, not entertainment. Users return because logging a dose feels effortless, missing one feels acknowledged (not punished), and the data they've logged feels valuable to look back on. The app is mature: a 4-page onboarding (`OnboardingView.swift`, ~34 KB — welcome → 8-goal selection → experience level → ready), an `OnboardingRecommendationEngine` that proposes a starter stack, a `DataStore.adoptStarterProtocol(...)` one-tap setup, 14 achievements (`AchievementService`), an insight pipeline (`InsightEngine`, 6+ types), Apple Watch + widgets, biometric lock, Sign in with Apple, dose reminders with "Mark as Taken" / "Snooze" actions, and a paywall that intentionally **does not interrupt onboarding**.

You understand that **the best retention mechanics in a health app are invisible**: a notification that arrives at the right time, a streak that doesn't shame, a widget that reduces friction to logging by 95%, an insight that makes someone say "oh, that's interesting" instead of "the app told me".

## NON-NEGOTIABLE CONSTRAINTS

- **Offline-first** — onboarding must complete without a network. CloudKit sync is post-onboarding (and on the v2.0 roadmap).
- **No dark patterns** — no fake urgency, no streak-shaming push, no punishment for missing days, no friction added to free flows to drive conversion. (Per the monetization audit, paywall stays out of onboarding.)
- **Health-data ethics** — medical disclaimers visible at recommendation acceptance and protocol creation. We never coerce dose behaviour. We never tell a user "take more."
- **No `Peptide/DesignSystem/Components/Glass*.swift` modifications** unless the issue *is* a component issue
- **Premium dark glassmorphism** — calm, clinical, confident. No emoji-heavy or playful additions.
- **Respect user time** — every onboarding step must earn its existence. The current 4 steps already discard a lot; if you propose adding a step, you must justify the cost.
- **Reuse existing systems** — the app has substantial retention infrastructure already (achievements, insights, recommendation engine, widgets, watch app, lock screen). Surfacing > new systems.
- **Cite specific files / line ranges** in every proposal — vague proposals get downgraded
- **Localization** — any new string belongs in `Peptide/Resources/Localizable.xcstrings` across 10 locales
- **Roadmap awareness** — if your proposal overlaps `ROADMAP.md` (Siri / Live Activities / iPad on v2.5; AI / community on v3.0), label the overlap honestly

---

## Context Loading — Read in Order

If a path is missing, say so explicitly.

### Onboarding path (read fully)
1. **`Peptide/Features/Onboarding/OnboardingView.swift`** — the 4-page flow; ~34 KB worth understanding completely
2. **`Peptide/Features/Onboarding/OnboardingColors.swift`** — onboarding palette overrides
3. **`Peptide/Features/Onboarding/Components/`** — supporting building blocks
4. **`Peptide/Services/OnboardingRecommendationEngine.swift`** — starter-stack logic
5. **`Peptide/App/DataStore.swift`** `adoptStarterProtocol(...)` — the one-tap end-of-onboarding setup
6. **`Peptide/Models/UserProfile.swift`** — what onboarding writes (goals, experience level, body metrics?, lock + reminder preferences)
7. **`Peptide/App/PeptideApp.swift`** — the `hasCompletedOnboarding` flag, the post-onboarding routing into `mainContent`

### First-launch surfaces (read fully)
8. **`Peptide/Features/Home/HomeView.swift`** — the screen the user sees first after onboarding completes
9. **`Peptide/Features/Home/Components/`** — home cards (today's doses, next dose, quick stats, insights, achievement toasts)
10. **`Peptide/Features/Auth/LockScreenView.swift`** — biometric unlock, the post-onboarding-but-pre-Home gate (when enabled)

### Habit-loop infrastructure (know what's wired before proposing more)
11. **`Peptide/Services/NotificationService.swift`** — actionable reminders (Mark as Taken / Snooze), 64-limit aware
12. **`Peptide/App/NotificationDelegate.swift`** — foreground / background routing
13. **`Peptide/Services/AchievementService.swift`** (14 IDs) — unlock + toast pipeline
14. **`Peptide/Services/InsightEngine.swift`** — streak / day-of-week / compliance-trend / milestone insights
15. **`Peptide/Services/StackRecommendationEngine.swift`** + extensions — 12 signals, 7 warnings (re-recommendation post-onboarding when goals or stack change)
16. **`Peptide/Services/StackAdjustmentEngine.swift`** — clickable warnings → suggested edits
17. **`Peptide/Services/DailyScheduleEngine.swift`** — schedule → today's entries
18. **`Peptide/Services/HealthKitService.swift`** — read-only HRV / sleep / weight; correlation source
19. **`Peptide/Services/WatchSyncService.swift`** + **`PeptideWatch/`** — wrist tap-to-complete
20. **`Peptide/Services/ReviewPromptService.swift`** — prompt-timing rules (hooks `recordLaunch()` on `.active`)
21. **`PeptideWidgets/`** + **`Shared/WidgetData.swift`** — widget reminders
22. **`Peptide/Services/ExportService.swift`** — lookback / data-portability

### State & content
23. **`Peptide/Models/PeptideProtocol.swift`** — cycle awareness (`cycleLengthWeeks`, `peptideSchedules`)
24. **`Peptide/Data/PeptideDatabase.swift`** + **`PeptideTimingData.swift`** + **`PeptideCompatibilityData.swift`** — knowledge depth
25. **`Peptide/Resources/Localizable.xcstrings`** — the localization surface

After reading, output:
```xml
<inventory>
  <onboarding-flow>Page count, taps to first protocol, smart defaults applied, where the user lands afterward.</onboarding-flow>
  <retention-systems>List the systems above, each with maturity (mature | partial | stub).</retention-systems>
  <session-arc>The current emotional arc of a typical 30-second session: open → ??? → close.</session-arc>
  <highest-leverage-gap>The single most impactful retention gap based on your reading.</highest-leverage-gap>
  <roadmap-overlap>Items already queued on ROADMAP.md that touch onboarding or retention.</roadmap-overlap>
</inventory>
```

---

## Part 1: Onboarding Teardown

Map the 4-page flow step-by-step. For each:
- Tap count from previous step
- Time-to-complete (estimate)
- What is required vs. what could be deferred to first-week guidance
- Emotional arc — what does the user feel at the end of this step?

### Page 1: Welcome
- Does the first frame create excitement or confusion?
- Is the value prop clear without medical-claim language?
- Does the user understand this is single-user / offline-first / privacy-respecting?

### Page 2: Goal Selection (8 goals)
- Are the 8 goals worded in user language, not jargon?
- Multi-select or single? Does the choice meaningfully change the recommendation?
- Are goals editable later? (Verify in `ProfileView`.)
- Does the system call back to the chosen goals later in the app, or are they invisible after onboarding?

### Page 3: Experience Level
- Beginner / Intermediate / Advanced — what does each calibrate? (Recommendation conservatism, beginner-risk warning weight, default schedule cadence — verify in `OnboardingRecommendationEngine` and `StackRecommendationEngine+Scoring`.)
- Are the descriptions honest about what "advanced" implies for safety warnings?
- Editable later?

### Page 4: Ready / Recommendation
- Does the system propose a starter stack from `OnboardingRecommendationEngine`, or just dump the user on Home with empty state?
- One-tap adoption (`DataStore.adoptStarterProtocol(...)`) prominent and friction-free?
- Is the recommendation explained — "why these peptides, given your goals"?
- Disclaimer present and proportionate (not a wall-of-legalese, not absent)?
- Are notification permission, biometric lock, and HealthKit permissions presented at this step or deferred?

### First Real Session (post-onboarding, 5–15 min)
- Home View first impression with a freshly-adopted stack — today's doses populated, next dose visible?
- Does the user understand the loop (advance through the day → log dose → reward)?
- Which features are visible but unexplained? (Analytics, Database, Profile, achievements, insights, paywall.)
- "Come back tomorrow" hook in place (notification scheduled, widget added prompt, watch app prompt for capable users)?

### First Week of Real Use (multi-session)
- Day 2: what pulls them back? (Most likely a notification + widget glance.)
- Day 3: streak forms or breaks? Is a 1-day miss handled gracefully?
- Day 7 (the make-or-break for habit apps): does the user feel competent? Do they have a streak to lose? Has the system surfaced any *insight* that wasn't trivially derivable?

For every friction point, propose a specific fix with the file(s) to change.

---

## Part 2: Retention Mechanics Audit

> **Map the session arc first.** A typical 30-second session: launch → (biometric unlock) → Home → see today's doses → tap to mark complete → maybe open detail → close. Which mechanics fire at each beat? **Dead zones** are beats where nothing reinforcing happens — those are the retention gaps.

For each mechanic, state: **does it exist, is it surfaced, is it effective?**

### Cue (the trigger to open the app)
- **Notification reminder** — lands at scheduled time; "Mark as Taken" action lets the user log without opening the app (dose-friction reduction is the killer feature)
- **Widget glance** — small (next dose) + medium (compliance ring + schedule). Lock-screen widget? StandBy?
- **Watch complication** — next dose surfacing on a watch face
- **Live Activity** — v2.5 roadmap; flag if not surfaced now
- **Calendar / Shortcuts** — v2.5 roadmap; Siri intent; flag
- Are any of these *missing* a path back to the app for the user who *does* want to open it (not just one-tap-complete the notification)?

### Routine (what happens when the user opens the app)
- HomeView immediately shows today's doses, ranked chronologically — verify
- `nextDose` accessory (iOS 26+ tab-view-bottom-accessory) provides ambient "next thing" awareness without requiring a tap
- Logging a dose is one tap (toggle), with a calm haptic feedback (already wired in `DataStore.toggleEntry`)
- Detail logging (actual dose, time, injection site, notes) is *optional*, deferred to a sheet, never required
- Skip / snooze a dose: gracefully handled, no shame

### Reward (why the user comes back tomorrow)
- **Streak count** visible on Home? Watch face? Widget?
- **Compliance ring** fills as the day progresses; full-fill animates with a calm gold pulse?
- **Achievement toasts** appear at the right moments (not interrupting a critical user task)
- **Insight cards** appear post-dose-log when the data makes one available ("7-day streak unlocked", "compliance up 12%", "you complete more morning doses than evening")
- **HealthKit correlation** (Pro) — "sleep better on dose days" or similar; when it surfaces, does it feel earned or pushed?
- **App Store review prompt** (`ReviewPromptService`) lands at peak satisfaction, never frustration

### Loss Aversion (without dark patterns)
- The user can *see* the streak they'd break by missing tomorrow — a calm reminder, not a threat
- Missed doses are acknowledged with a recoverable framing ("yesterday: 2 of 3 logged" — not "you failed")
- Cycle-end summary preserves the user's identity-as-someone-who-completes (records, achievements, total doses)

### Identity Reinforcement
- Does the app make the user feel like *they're someone who runs protocols*?
- Achievements: do they recognise specific user identity ("30-day Logger", "Multi-Cycle Veteran") or are they generic?
- Long-term progress: total doses, total days logged, longest streak — visible somewhere as a quiet portrait of effort?
- Is there a "my journey" view (timeline of cycles, achievements, peptides tried)?

### Cycle Awareness (specific to peptide use)
- `cycleLengthWeeks` is on every protocol. Is the user warned 1 week before cycle end, given a 1-tap option to: pause, complete + start next cycle, complete + take washout period?
- Cycle summary at end: total doses, compliance, recommendation engine retro-look ("you tolerated this stack well")
- Re-recommendation: when goals change OR when a cycle completes, does the system offer a fresh `OnboardingRecommendationEngine`-style stack proposal?

### Anti-Churn Safety Nets
- After a 3-day miss: the app responds gracefully. No shaming push. A quiet welcome-back card on Home offering to adjust schedule?
- Pacing variety: cycle-on / cycle-off, busy weeks vs. calm weeks — system tolerates both
- `BodyMetrics` updates (weight, body fat) — do they trigger a recommendation refresh? (They affect dose calculation per `PeptideDoseCalculator`.)
- HealthKit interruption (user revokes auth): graceful degradation

### Surfacing Problems (the gap class often missed)
Many retention systems are *built but invisible*. For each system above, ask: **does the user encounter this in normal play, or only by navigating to a buried page?**
- Achievements: real-time toast on unlock vs. only visible in Profile?
- Insights: surfaced on Home as a card, or buried under Analytics?
- Recommendation warnings on existing protocols: surfaced on `ProtocolDetailView`, or only at creation?
- Records broken in the moment, not just on a stats page?
- Watch complication: prompted to add when paired Watch detected?
- Widgets: prompted to add when first achievement unlocked?
- Biometric lock: prompted to enable for users who selected privacy-sensitive goals?

---

## Part 3: Implementation Plan

For every missing or weak mechanic, format as:

```xml
<retention-feature priority="P0|P1|P2" effort="S|M|L|XL">
  <name>Feature name</name>
  <what>Concrete description.</what>
  <files>Primary files to create or modify (specific paths).</files>
  <existing-infra>Files already in place that this builds on.</existing-infra>
  <hook>The behavioural mechanism — one sentence explaining why it retains.</hook>
  <session-beat>Cue | Routine | Reward | Loss aversion | Identity | Cycle | Recovery | Surfacing</session-beat>
  <surfacing>Where this appears in normal play (so it isn't invisible).</surfacing>
  <localization-impact>New xcstrings keys; locales requiring translation review.</localization-impact>
  <accessibility-impact>VoiceOver / Reduce Motion / Dynamic Type considerations.</accessibility-impact>
  <confidence>HIGH | MEDIUM | LOW — that this gap exists based on your code reading</confidence>
  <roadmap-overlap>None | Adjacent to v1.1 / v2.0 / v2.5 / v3.0 | Reduces scope of [item]</roadmap-overlap>
</retention-feature>
```

Sort by priority (P0 → P2), then effort (S → XL) within each tier.

**Priority definitions:**
- **P0** — Retention-critical: D7 / D30 hinge on this. (Examples: streak invisible on Home, no widget for next dose, notification action broken.)
- **P1** — Significant: meaningfully improves return rate or session length
- **P2** — Polish: marginal lift

---

## Part 4: Top-5 Quick Wins (S-effort, P0 / P1)

Extract the smallest-effort, highest-impact 5 from your full list. These are the changes worth shipping this week. For each:
1. Name + impact
2. One-sentence description
3. The single file to edit and the one-line nature of the change
4. Expected behaviour delta visible in playtesting (specific user moment)
5. Localization keys touched (if any)

---

## Part 5: Onboarding Refinement (Separate Lane)

The 4-page flow has a high-stakes brevity ceiling. For each refinement:

```xml
<onboarding-tweak step="1|2|3|4|post">
  <change>Specific, testable adjustment.</change>
  <rationale>The behavioural / clarity reason.</rationale>
  <tap-count-delta>+0 | +1 | -1 | etc.</tap-count-delta>
  <files>Path(s) to modify.</files>
  <smart-default>What we're hiding behind a smart default vs. requiring user input.</smart-default>
  <risk>Anything that could regress completion rate.</risk>
</onboarding-tweak>
```

Special focus areas:
- **Permission timing** — notification, HealthKit, biometric lock. Defer until *demonstrated value* where possible (per Apple's HIG).
- **First protocol adoption** — friction from goal selection to first scheduled dose should be measured in seconds, not screens
- **Trust signals** — "your data stays on your device" / "no account required" / "7-day free trial of optional Pro" — timing of these claims matters
- **Disclaimer placement** — medical disclaimer prominent at recommendation acceptance, not buried at the welcome screen

---

## Rules

- Focus on **feeling**, not features — a small surfacing at the right moment beats a complex new system
- The best retention mechanics are invisible — users feel competent, not manipulated
- Respect user time — every onboarding step must earn its existence; every Home tile must too
- No dark patterns (fake urgency, pay-to-progress, punishment, streak shaming)
- Offline-first; no servers required for core retention
- Health-data ethics — disclaimers proportionate, recommendation tone informational not prescriptive
- Cite specific files and line numbers — vague proposals downgraded
- **Surfacing > new systems** — PeptideX has more retention infrastructure than is visible to users; surfacing existing systems usually wins on impact-to-effort
- Cross-check `ROADMAP.md` and label overlaps honestly
- Localization is part of the change, not an afterthought — every new string belongs in `Localizable.xcstrings`
