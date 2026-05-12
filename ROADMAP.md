# PeptideX Roadmap

## Current State

PeptideX is a native iOS SwiftUI app for tracking peptide supplementation protocols with grounded AI assistance — barcode scanning, photo meal estimation, multi-turn research chat, and HealthKit-correlated analytics. iOS 18+, Swift 6.0, SwiftData (CloudKit-backed). 5-tab navigation, companion Watch app, two widget targets, Live Activities, and CI/CD to TestFlight via Fastlane.

### What's shipped

| Area | Status | Details |
|------|--------|---------|
| **UI/UX** | Complete | Glassmorphism design system, dark mode, haptic feedback, scale-press affordances |
| **Peptide database** | Complete | 208 peptides across 6 categories, bundled JSON, research links |
| **Protocol management** | Complete | Create, edit, pause, complete protocols with schedule builder and per-peptide overrides |
| **Dose tracking** | Complete | Daily entries, toggle completion, rich logging (actual dose, time, injection site, notes) |
| **Lifestyle tab** | Complete | Macro rings, weight sparkline + log, workout log, progress-photo capture |
| **Meal scanner — photo** | Complete | Claude vision via Vercel proxy; macro estimate with confidence and clamping |
| **Meal scanner — barcode** | Complete | DataScanner viewfinder, Open Food Facts lookup, portion picker, recently-scanned grid, edit-before-log override, Undo via `.logged` phase |
| **AI research assistant** | Complete | Multi-turn chat via Vercel proxy with substring-RAG over the bundled database |
| **Recommendation engine** | Complete | 12 scoring signals, 7 warning types, validated stacks |
| **Insight engine** | Complete | Streaks, day-of-week patterns, compliance trends, milestone insights; unified streak math with `DataStore.currentStreak` |
| **Notifications** | Complete | Dose reminders, actionable (Mark as Taken / Snooze), 64-limit handling, per-timeslot consolidation |
| **Widgets** | Complete | iOS small + medium (next dose, compliance ring + schedule), watchOS widgets, real data via App Groups |
| **Live Activities** | Complete | Dose-window Dynamic Island + lock-screen UI |
| **Watch app** | Complete | Reads via App Group, sends mark-complete / mark-incomplete back via WCSession |
| **Achievements** | Complete | 14 achievements (dose milestones, streaks, protocol, logging), toast notifications |
| **Export** | Complete | CSV + JSON full backup via share sheet |
| **Onboarding** | Complete | 17-page flow: review prompt → creator code → email → paywall → theme → add-medication → ready |
| **HealthKit** | Complete | Reads 7 data types (HR, HRV, sleep, weight, steps, energy); observer-based background delivery wired (`UIBackgroundModes=[processing]`) |
| **Persistence** | Complete | SwiftData @Model classes, CloudKit-backed private container with local + in-memory fallbacks |
| **StoreKit 2** | Complete | Monthly + annual + lifetime, paywall, transaction verification, restore purchases, intro-offer eligibility |
| **AI proxy** | Complete | Vercel deployment with shared-secret auth, per-IP rate limit, body sanitisation, model allowlist, max_tokens hardcap |
| **Sharing** | Complete | Cycle-share card (1080×1920) with Day-7/30/complete prompts and privacy detail toggle |
| **Siri shortcuts** | Complete | AppIntents bundle including "Log my BPC-157" and "What are my macros today?" |
| **Testing** | ~40 test files | Network services (MockURLProtocol), data integrity, recommendation/insight engines, persistence round-trip, schedule cadence, achievement service, etc. |
| **CI/CD** | Complete | XcodeGen, SwiftLint, build + test in GitHub Actions (macos-15 pinned), TestFlight via Fastlane, binary-size delta gate |

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
| 4.1 | **Protocol templates** | 2-3 days | Community-shared protocol configs. Browse by category/goal. Ratings and Staff Picks. _v1: bundled curated stacks (`community-stacks.json`) ship today; user-published stacks need a backend with moderation._ |
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

### PeptideX Pro ($9.99/mo, $49.99/yr, or $169 lifetime)

> Items marked _(planned)_ are scheduled for the indicated milestone and are
> not part of the current v1.x build. The paywall does not advertise them.

- Unlimited protocols
- Full analytics + HealthKit correlation + export
- AI insights + recommendations _(planned, v3.0)_
- All widgets + Apple Watch _(Watch planned, v2.5)_
- Cloud sync + backup _(planned, v2.0)_
- Community features + templates _(planned, v3.0)_
- 7-day free trial (monthly), 14-day (annual)
