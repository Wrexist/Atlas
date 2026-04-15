# PeptideX Roadmap

## Current State (v1.0.0)

PeptideX is a native iOS SwiftUI app for tracking peptide supplementation protocols. Production-ready with glassmorphism design, 5-tab navigation, 208 bundled peptides, a 12-signal recommendation engine, 14 achievements, StoreKit 2 paywall, and CI/CD to TestFlight.

### What's Shipped

| Area | Status | Details |
|------|--------|---------|
| **UI/UX** | Complete | Glassmorphism design, 5-tab nav, dark mode, haptic feedback |
| **Peptide database** | Complete | 208 peptides across 6 categories, bundled JSON, research links |
| **Protocol management** | Complete | Create, edit, pause, complete protocols with schedule builder |
| **Dose tracking** | Complete | Daily entries, toggle completion, rich logging (actual dose, time, injection site, notes) |
| **Compliance analytics** | Complete | Swift Charts (line, area, heatmap), streaks, weekly calendar, time-range gating |
| **Recommendation engine** | Complete | 827 LOC, 12 scoring signals, 7 warning types, validated stacks |
| **Insight engine** | Complete | 6+ insight types: streaks, day-of-week patterns, compliance trends, milestones |
| **Notifications** | Complete | Dose reminders, actionable (Mark as Taken / Snooze), 64-limit handling, per-timeslot consolidation |
| **Widgets** | Complete | Small (next dose) + Medium (compliance ring + schedule), real data via App Groups |
| **Achievements** | Complete | 14 achievements (dose milestones, streaks, protocol, logging), toast notifications |
| **Export** | Complete | CSV + JSON full backup via share sheet |
| **Onboarding** | Complete | 4-page flow: welcome, goal selection (8 goals), experience level, ready |
| **HealthKit** | On-demand | Reads 7 data types (HR, HRV, sleep, weight, steps, energy). No background delivery |
| **Persistence** | JSON files | PersistenceService writes protocols/entries/profile to Documents. Atomic writes, ISO8601 dates |
| **StoreKit 2** | Complete | Monthly + annual subscriptions, paywall, transaction verification, restore purchases |
| **Testing** | 82 tests | DataStoreTests (20), StackRecommendationEngineTests (39), PersistenceRoundTripTests (23) |
| **CI/CD** | Complete | XcodeGen, SwiftLint, build + test in GitHub Actions, TestFlight via Fastlane |

---

## Next: v1.1.0 — Reliability & Security

> Harden the app for real users. Small effort, high trust impact.

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 1.1 | **Biometric lock** | Hours | Optional Face ID / Touch ID via `LocalAuthentication`. Toggle in Profile settings. Protects health-adjacent data |
| 1.2 | **PDF export** | Hours | Add PDF report generation to existing export service (CSV + JSON already work) |
| 1.3 | **HealthKit background delivery** | 1-2 days | Add `HKObserverQuery` and `enableBackgroundDelivery` so widgets and insights update without opening the app |

---

## v2.0.0 — Data & Sync

> Upgrade persistence and enable multi-device support.

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 2.1 | **SwiftData migration** | 3-5 days | Replace JSON persistence with `@Model` classes. One-time migration from existing JSON files. Enables efficient queries and lightweight migrations |
| 2.2 | **Sign in with Apple** | 1-2 days | `AuthenticationServices`. Store identifier in Keychain. Fully optional — app works without sign-in |
| 2.3 | **CloudKit sync** | 3-5 days | `CKSyncEngine` for automatic sync + conflict resolution. Requires SwiftData. Offline-first with sync status indicator |

---

## v2.5.0 — Apple Ecosystem

> Meet users on wrist, home screen, and via voice.

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 3.1 | **Apple Watch app** | 3-5 days | Today's doses with tap-to-complete. Complication for next dose. Haptic reminder at dose time |
| 3.2 | **Siri & Shortcuts** | 1-2 days | `AppIntents`: "Log my BPC-157", "What's my next dose?", "How's my compliance?" |
| 3.3 | **Live Activities** | 1-2 days | Lock screen dose window countdown. Dynamic Island for active protocol |
| 3.4 | **iPad optimization** | 1-2 days | `NavigationSplitView` sidebar. Multi-column layouts. Wider charts |

---

## v3.0.0 — Community & AI

> Connected experience with social features and intelligent guidance.

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 4.1 | **Protocol templates** | 2-3 days | Community-shared protocol configs. Browse by category/goal. Ratings and Staff Picks |
| 4.2 | **AI research assistant** | 3-5 days | On-device LLM via Apple Intelligence / Foundation Models. RAG over peptide database. Chat interface with sourced answers and medical disclaimers |
| 4.3 | **Smart cycle planning** | 2-3 days | Analyze compliance patterns and durations. Suggest optimal cycle length and timing. Calendar integration |
| 4.4 | **Community features** | 5+ days | Anonymous compliance leaderboards (opt-in). Protocol reviews. Requires backend infrastructure |

---

## v3.5.0+ — Growth & Polish

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 5.1 | **Localization** | 2-3 days | Spanish, Portuguese, German, Japanese |
| 5.2 | **Accessibility** | 1-2 days | Full VoiceOver, Dynamic Type, Reduce Motion, High Contrast |
| 5.3 | **Performance** | 1-2 days | Lazy loading, pagination, < 1s cold start |
| 5.4 | **macOS via Catalyst** | 2-3 days | Desktop version |
| 5.5 | **visionOS** | 3-5 days | Spatial health dashboard |

---

## Phase Dependencies

```
v1.1.0 (Reliability)
  |
v2.0.0 (Data & Sync) ────> v2.5.0 (Ecosystem)
  |                              |
  +── SwiftData ──> CloudKit     +── Watch, Siri, Live Activities
  |
v3.0.0 (Community & AI)
  |
v3.5.0+ (Growth & Polish)
```

**Parallelism:** v1.1.0 items (biometric, PDF, HealthKit background) are independent and can run in parallel. v2.5.0 ecosystem features are independent of v2.0.0 sync features. v3.0.0 AI features are independent of community features.

---

## Monetization (Already Scaffolded)

### Free Tier
- Up to 3 active protocols
- Full peptide database (208 peptides)
- Basic analytics (weekly view)
- Local persistence
- Dose reminders
- 1 widget

### PeptideX Pro ($6.99/mo or $49.99/yr)
- Unlimited protocols
- Full analytics + HealthKit correlation + export
- AI insights + recommendations
- All widgets + Apple Watch
- Cloud sync + backup
- Community features + templates
- 7-day free trial (monthly), 14-day (annual)
