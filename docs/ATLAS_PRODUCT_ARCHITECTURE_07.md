# ATLAS PRODUCT ARCHITECTURE IMPLEMENTATION REPORT

**Master Implementation 07 — navigation, information architecture, and discoverability.**
Date: 2026-08-30. Implemented on `claude/atlas-codebase-audit-cr7olj` on top of the Wave 1
data-integrity work. Every claim below was verified against the working tree before any edit;
claims that could not be verified are marked **NOT VERIFIED**.

One correction to the brief's premise, stated up front: **no "Recovery-Informed Training
Intelligence" implementation exists in this repository** — there is no training-load, strain,
or readiness engine beyond `RecoveryScoreEngine` (HRV/RHR/sleep) feeding the Today hero trio
and `CoachingMessageEngine`. Phase 5 was therefore executed against the real recovery surfaces,
not the described ones.

---

## Executive Summary

Atlas's five-tab shell was already right; what was wrong was inside the tabs. Today rendered
dose state in five places on one scroll while burying its status trio mid-page and offering
nutrition nothing; the Library (the differentiated protocols surface) hid behind an unlabeled
pill and a Profile card; the Train overview went stale the moment a workout finished and its
"recent workouts" rows never navigated anywhere; onboarding ran a fake 2.6-second "Building
your plan…" animation and collected an email address no code ever read; and every home-screen
widget tap dumped the user on whatever tab was last open.

This pass made the smallest changes that fix those specific problems: Today now reads
**status → recommendation → action → analysis** with one protocols section and a labeled
Manage entry; a compact discover row makes Protocols findable for users who have none; the
Movement card routes to the Train tab, retiring the legacy parallel "Workout Tracker" screen
entirely; Train refreshes live after a finish and its recent rows push the session detail;
onboarding dropped from 18 to 16 pages by deleting the fake progress screen and the dead email
step; widgets got real destinations through a new tested `DeepLinkRouter` and a
finally-registered URL scheme; and the "Connect Apple Health" footer became a button that goes
where connecting actually happens. Four dead view files were deleted. No tab was added, no
feature was removed from reach, and no active-workout, restore, or deep-link flow was touched
destructively.

## Current Architecture (verified before changes)

```
APP (TabView)
├── Today (HomeView — 17 sections)
│     Welcome · ContextRow(cycle pill→Library) · JumpBar(5 chips, 2 = tab dupes)
│     HabitsHero · AtlasScore · NotifBanner · WeeklyHero · Trio · Coaching
│     Goal · OverviewCard · ProtocolScoreCard · DailyPlan · Schedule
│     Wellness · Movement(→legacy WorkoutDetailView) · Timeline · HealthGrid
├── Train (Overview | Exercises | History · ActiveWorkout cover · resume banner)
│     Overview: Start CTA · muscle map · gains · recents(not tappable) · calendar
├── Meals (HomeMealsSection only)
├── Biology (BioAge hero · biomarkers · labs)
├── Habits
├── [sheet] Profile (avatar / toolbar buttons)
└── [fullScreenCover] Library = PeptideListView
      → ProtocolsEntryCard → ProtocolListView (sheet)
      → peptide Database rows → PeptideDetailView
      → AI research chat (toolbar, Pro)
Onboarding: 18 fixed pages incl. buildingPlan(fake) + email(dead)
Deep links: peptidex://dose/<uuid>, peptidex://weekly/current — scheme unregistered
Widgets: NextDose / Compliance / Nutrition — zero deep links
```

## Problems Identified (Phase 1–2 discoverability audit)

| Feature | Location before | Discoverability | Problem |
|---|---|---|---|
| Protocols/Library | Unlabeled cycle pill on Today; Profile card | Poor | Differentiated feature invisible; zero-protocol users had no Today entry at all |
| Today status trio | 8th section, below score card and banner | Poor | "How am I?" answered mid-scroll |
| Dose state | 5 surfaces (pill, overview hero, score card, plan, schedule) | Over-exposed | Same fact restated; scroll fatigue |
| Nutrition on Today | Only inside TodayOverviewCard's 2×2 grid | Poor | Meals is a top-3 daily action with no Today presence hierarchy |
| Legacy Workout Tracker | Pushed from Today's Movement card | Confusing | Parallel training surface disagreeing with Train tab |
| Recent workouts detail | Rows not tappable (destination existed) | Broken promise | Header comment said "tappable into the detail view" |
| Train freshness | Refresh on first appear + pull only | Broken | Post-finish data stale until pull-to-refresh |
| Widgets | No `widgetURL` | Broken expectation | Tap lands anywhere |
| Onboarding | 18 pages, fake progress, dead email capture | Trust + friction | 2.6 s of pretend computation; duplicate contact ask |
| Connect Health prompt | Display-only footer | Dead end | Names the fix, offers no path |

Frequency classification (Phase 2): **Daily** = Today, Train, Meals, dose schedule, habits.
**Frequent** = Biology, weekly recap, protocol management. **Occasional** = Library database,
AI chat, labs, backup/export. **Reference** = peptide detail pages, muscle history, PRs.
The five tabs match the Daily set plus Biology — no tab changes warranted.

## Target Architecture (Phase 3, as shipped)

```
TODAY  = command center: status → recommendation → action → analysis
  1 Welcome · 2 JumpBar(3 scroll chips + Log) · 3 NotifBanner(situational)
  4 "At a glance" trio (STATUS) · 5 CoachingCard (RECOMMENDATION)
  6 WeeklyHero(weekend) · 7 HabitsHero (ACTION)
  8 Protocols: header+Manage→Library · DailyPlan · Schedule
      └ zero protocols → ProtocolsDiscoverRow → Library
  9 Wellness · 10 Movement(→Train tab)
  11 Overview(lifestyle) · 12 Goal · 13 AtlasScore · 14 Timeline · 15 HealthGrid  (ANALYSIS)
TRAIN  = start/resume + live-refreshing overview; recents → session detail
MEALS / BIOLOGY / HABITS unchanged
LIBRARY unchanged internally; entries now labeled (Manage, discover row, Profile)
```

Phase 5 answers: the **one most important action** is contextual — the next pending dose for
protocol users, today's habit ring otherwise; the **second** is Start Workout (one tab away,
top CTA); **hidden until requested** — timeline, health grid, goal countdown, score detail,
weekly-strip analytics (now only in the adherence detail sheet).

## Navigation Changes
- Jump bar chips reduced 5 → 3; the Meals/Biology chips duplicated the tab bar and are gone.
- `DeepLinkRouter` (AppState.swift) replaces the inline `onOpenURL` switch; new hosts
  `today`, `train`, `meals` join `dose`/`weekly`; unknown input mutates nothing.
- `peptidex` registered in `CFBundleURLTypes` (project.yml + Info.plist) — widget links never
  needed it, but notification/Shortcuts links do.

## Features Moved
- Hero trio + coaching: mid-scroll → top (status/recommendation).
- AtlasScoreCard, GoalCountdownCard, TodayOverviewCard: upper scroll → analysis zone.
- Library entry: unlabeled pill → labeled "Manage" on the Protocols header + discover row.

## Features Merged
- Today's protocol surfaces: context pill + score card + plan + schedule → one headed section
  (plan + schedule retained; they are complementary — timing/conflicts vs. toggle list).

## Features Removed (with dead files deleted)
- `TodayContextRow.swift` — duplicated the date rendered one line above it.
- `ProtocolScoreCard.swift` — restated the trio's adherence ring; weekly analytics live in
  the adherence detail sheet.
- `WorkoutDetailView.swift` + `WorkoutLogSheet.swift` — the legacy "Workout Tracker" and its
  note-string quick log; the Movement card was its only presenter. `DataStore.logWorkout`
  stays (tested service API; Siri intents unaffected — verified no intent uses these views).
- Onboarding `buildingPlan` + `email` pages and `EmailCapturePage.swift` (below).

## Today / Train Changes
Covered above; additionally TrainOverviewView now recomputes on `dataStore.revision`
(`recordWorkoutFinished` bumps it precisely for this) and recent-workout rows are
`NavigationLink(value: .workoutDetail(id))` into the already-declared destination.

## Protocol Discoverability (Phase 4 decision)
Contextual entry + integrated Today section, **not** primary navigation: protocol users see
the section daily with a labeled Manage entry; non-protocol users see one quiet discover row
("Protocols — track compounds, doses, and cycles") that vanishes once a protocol exists.
Promoting Library to a tab was rejected — it would re-lead the app with the advanced feature
the store positioning deliberately demotes.

## Progress Architecture (Phase 7)
Action and analysis are now physically separated on Today (sections 1–10 vs 11–15). Deeper
consolidation (one Progress destination unifying AtlasProgressView, workout history, recovery
trends, and habit analytics) is **deferred** — it needs design work that shouldn't ship blind;
see Deferred Improvements.

## Empty State Improvements (Phase 11 audit result)
Audited: Train overview/history (actionable ✓), Habits (best-in-app ✓), ProtocolList (✓),
Meals cards (pickers always visible ✓), Today day-0 (gating ✓ — and now shows the discover
row instead of nothing protocol-shaped). Fixed the one dead end: the trio's "Connect Apple
Health" footer is now a tappable row (chevron, combined a11y label + hint) opening Profile,
where `HealthConnectionCard` lives. Biology still lacks its own connect-Health CTA —
deferred, noted below.

## Onboarding Improvements (Phases 14–16)
- **Fake progress removed** (Phase 15): `buildingPlan` was a 1.2 s ring + 1.4 s sleep with
  zero computation — nutrition targets are written on the projection step's Continue, training
  prefs earlier still. Deleted outright; the Ready page remains the honest transition.
- **Contact capture** (Phase 16): three asks existed — optional Sign in with Apple (relay
  email, Keychain), creator code, and an email step whose `EmailSubscription` was never sent
  or read by any code. The email step is deleted (model kept for decode compatibility);
  sign-in and creator code (monetization attribution, skippable) remain. 18 → 16 pages.
- Resume safety: stored `lastPage` 16/17 now fails the existing bounds check → fresh start;
  14/15 resume at creator-code/ready. No step-order tests existed to break (verified).

## Deep Link Changes
`DeepLinkRouter` + hosts above; widgets: NextDose & Compliance → `peptidex://today`,
Nutrition → `peptidex://meals`; Live Activity's `dose/<uuid>` untouched. Cold launch works
via `onOpenURL` on the scene; unknown links fail silently by design.

## Accessibility Changes
Discover row and connect-Health footer: combined elements, labels, hints, ≥44pt hit areas;
recent-workout rows combine children; jump-bar semantics unchanged. All design-lint a11y
rules pass (0/0).

## Tests Added / Updated
- **Added** `DeepLinkRouterTests` (7 tests): every host, garbled-UUID rejection without state
  mutation, unknown host/scheme ignored.
- **Updated** `ActiveSectionPickerTests` to the surviving three anchors (same logic pinned).
- Pre-existing suites re-checked for breakage: Onboarding trackers/experiment (step-order
  agnostic — verified), TodayOverviewSnapshotTests (component untouched), UI tests (tab
  reachability only — unaffected).

## Tests Passing
Local (this container has no macOS toolchain): `design-lint.py --all` 0/0,
`check-copy-claims.py` ✓, `check-store-metadata.py` ✓. Compile + full 1,000+-test suite runs
in CI on the PR (`build-check`); **CI is the compile/test gate for the Swift changes**.

## Files Changed
Modified: HomeView, TodayJumpBar, HeroMetricTrio, HomeMovementSection, TrainOverviewView,
OnboardingView, AppState, PeptideApp, PeptideWidgets, project.yml, Info.plist,
ActiveSectionPickerTests, minor comment fixes (MetricRing, TodayOverviewCard).
Added: ProtocolsDiscoverRow, DeepLinkRouterTests, this report.
Deleted: TodayContextRow, ProtocolScoreCard, WorkoutDetailView, WorkoutLogSheet,
EmailCapturePage.

## Migration Risks
- Mid-onboarding users on stale `lastPage` indices: bounded by the existing range check;
  worst case is restarting a flow they hadn't finished.
- Muscle-memory: users who used the cycle pill now use Manage/discover row — same one-tap
  depth, now labeled.
- The removed quick-log workout path (`WorkoutLogSheet`) wrote note-string sessions; existing
  such sessions still render everywhere (timeline/history tolerate empty-exercise sessions).

## Remaining UX Risks
- Layout on device is unverified — nothing in this environment renders SwiftUI. The
  Screenshots workflow or a device pass should eyeball Today's new order (esp. day-0 and
  protocol-user variants), the Manage header, and the discover row.
- TodayOverviewCard still contains a next-dose hero (now the second dose surface). Kept
  deliberately: it is the analysis zone's tap-to-log shortcut; if it reads as duplication on
  device, drop the hero strip inside the component next.

## Deferred Improvements
- Unified Progress destination (merge AtlasProgressView + history + trends).
- Routines/templates UI (dead store from the audit — Build Next item, not an IA fix).
- Biology-tab connect-Health CTA; Biology/Today HealthMonitorGrid ownership decision.
- Widget dose rows deep-linking to a specific entry (needs an id in `WidgetDoseSlot`).
- Renaming "Library" (tests well as "Protocols & research"?) — copy decision for the owner.

## Phase-24 Before / After
BEFORE: open → scroll past score/banner/goal/overview to find status → dose state five times
→ Movement leads to a second workout app → widgets land anywhere → 18-page onboarding with a
fake computation.
AFTER: open → status trio + one recommendation above the fold → single dose section with
labeled management → Movement lands on Train → every widget lands on its subject → 16 honest
pages. Destinations removed: 2 jump chips, 1 legacy screen, 2 onboarding pages. Added: 1
discover row (conditional). Nothing hidden that wasn't a duplicate.

## Final Product Test
- **Can a new user understand what Atlas is for?** Mostly — Today now leads with status and
  habits, and Protocols introduces itself; onboarding is shorter and honest. The remaining gap
  is copy, not structure.
- **Can a daily user immediately see what to do?** Yes — trio, coaching line, habit ring, dose
  section, in that order; Start Workout is one tab away at the top.
- **Can a user find the differentiated features without searching?** Yes — Protocols is
  labeled on Today in both user states; AI research remains one hop inside Library (adequate
  for its Pro/occasional cadence).
- **Does every primary destination have a clear purpose?** Yes — Today acts, Train starts,
  Meals logs, Biology explains, Habits sustains; the Library is the advanced surface, and no
  destination duplicates another anymore.
