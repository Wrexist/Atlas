# PeptideX Roadmap

## Current State (v1.0.0)

PeptideX is a native iOS SwiftUI app for tracking peptide supplementation protocols. The UI is complete -- glassmorphism design system, 5-tab navigation (Home, Peptides, Protocols, Analytics, Profile), 14 peptides across 6 categories, protocol builder, compliance charts, streak tracking, and CI/CD to TestFlight.

**What's missing:** All data is in-memory mock data. No persistence, no backend, no auth, no notifications, no HealthKit, no tests, no onboarding. The app looks production-ready but is functionally a prototype.

---

## Phase 0 -- Foundation & Testing (v1.0.1)

> Make the codebase testable and serializable before adding features.

| # | Feature | Description |
|---|---------|-------------|
| 0.1 | **Codable conformance** | Add `Codable` to all models (`Peptide`, `ResearchLink`, `ProtocolSchedule`, `PeptideProtocol`, `ProtocolEntry`, `UserProfile`) -- required for persistence, sync, and export |
| 0.2 | **DataService protocol** | Extract `DataServiceProtocol` from `DataStore` to decouple business logic from UI concerns (haptics, animations). Enables test doubles |
| 0.3 | **Unit test target** | Add `PeptideTests` to `project.yml`. Cover streak calculation, compliance computation, trend analysis, entry generation. Target 80% on DataStore logic. Run tests in CI |
| 0.4 | **UI test target** | Add `PeptideUITests`. Smoke tests: app launch, tab navigation, protocol creation flow |
| 0.5 | **SwiftLint** | Add linter config, enforce in CI |

---

## Phase 1 -- Data Persistence (v1.1.0)

> Data survives app restart. The app becomes actually useful.

| # | Feature | Description |
|---|---------|-------------|
| 1.1 | **SwiftData integration** | `@Model` classes in `Peptide/Persistence/`. `ModelContainer` in app entry. Migrate `DataStore` to read/write from `ModelContext` |
| 1.2 | **Mock data migration** | First-launch detection: "Start fresh" or "Import sample data". Gate mock data behind `#if DEBUG` |
| 1.3 | **Bundled peptide JSON** | Export peptide reference database to `peptides.json`. Enables future remote updates without app release |
| 1.4 | **UserDefaults for prefs** | `@AppStorage` for onboarding flag, appearance, lightweight settings. SwiftData for user-created data only |

---

## Phase 2 -- Onboarding & Authentication (v1.2.0)

> First-run experience and optional account creation.

| # | Feature | Description |
|---|---------|-------------|
| 2.1 | **Onboarding flow** | 4-5 screen paged flow: welcome, goal selection, experience level, feature tour, optional Health connect. Gated by `@AppStorage("hasCompletedOnboarding")` |
| 2.2 | **Sign in with Apple** | `AuthenticationServices`. Store identifier in Keychain. Fully optional -- app works without sign-in. Required for cloud sync |
| 2.3 | **Biometric app lock** | Optional Face ID / Touch ID via `LocalAuthentication`. Toggle in Profile. Protects health data |

---

## Phase 3 -- Notifications & Core Experience (v1.3.0)

> Active assistant that reminds users and captures richer dose data. Highest-impact retention feature.

| # | Feature | Description |
|---|---------|-------------|
| 3.1 | **Dose reminders** | `UNUserNotificationCenter` scheduling from protocol times. Actionable: "Mark as taken" from notification. Reschedule on protocol changes. Handle 64-notification limit |
| 3.2 | **Rich dose logging** | Expand `ProtocolEntry` with `actualDose`, `actualTime`, `injectionSite`, `notes`. Quick-log (swipe) + detailed sheet. Injection site picker for rotation tracking |
| 3.3 | **Protocol editing** | `ProtocolBuilderView` edit mode for existing protocols. Changes apply forward; history preserved |
| 3.4 | **Improved dashboard** | "Upcoming" section with countdown timers. Weekly mini-calendar. Streak milestones (7, 30, 60, 90 days) |
| 3.5 | **Schedule conflict detection** | Warn when two peptides overlap in timing. Suggest 15-30 min offsets |

---

## Phase 4 -- HealthKit & Advanced Analytics (v1.4.0)

> Connect to Apple Health and provide meaningful insights beyond compliance %.

| # | Feature | Description |
|---|---------|-------------|
| 4.1 | **HealthKit integration** | Read HRV, resting HR, sleep, body weight, activity. Map to peptide categories (recovery -> HRV, growth -> sleep/weight, cognitive -> sleep quality, metabolic -> weight/energy). Background delivery |
| 4.2 | **Enhanced analytics** | Swift Charts. Per-protocol analytics. Calendar heatmap. Body metrics overlay on protocol timeline. Cycle comparison |
| 4.3 | **Protocol insights** | Local insight engine: "You miss evening doses on Fridays", "Compliance drops after week 6". Cards on Home + Analytics |
| 4.4 | **Data export** | CSV protocol history. PDF analytics report. JSON full backup. Share sheet |

---

## Phase 5 -- Apple Ecosystem (v2.0.0)

> Meet users on wrist, home screen, and lock screen.

| # | Feature | Description |
|---|---------|-------------|
| 5.1 | **iOS Widgets** | Small (next dose), Medium (today's schedule), Large (weekly chart), Lock screen (score ring + next dose). Interactive: mark dose from widget. Live Activity for dose windows |
| 5.2 | **Apple Watch app** | Today's doses with tap-to-complete. Complication for next dose. Haptic reminder at dose time |
| 5.3 | **Siri & Shortcuts** | `AppIntents`: "Log my BPC-157", "What's my next dose?", "How's my compliance?" |
| 5.4 | **iPad optimization** | `NavigationSplitView` sidebar. Multi-column layouts. Wider charts |

---

## Phase 6 -- Backend & Community (v2.5.0)

> Connected experience with cloud sync and social features.

| # | Feature | Description |
|---|---------|-------------|
| 6.1 | **CloudKit backend** | Private database for user data. `CKSyncEngine` for auto sync + conflict resolution. Offline-first. Sync status indicator |
| 6.2 | **Cloud backup & restore** | Automatic iCloud backup. Restore on new device. Requires Sign in with Apple |
| 6.3 | **Protocol templates** | Community-shared protocol configs. Browse by category. "Use this template". Rating/popularity. Staff Picks |
| 6.4 | **Community features** | Anonymous compliance leaderboards (opt-in). Protocol reviews. Discussion threads per peptide |
| 6.5 | **Remote push notifications** | APNs for community activity, template recommendations. Digest preferences |

---

## Phase 7 -- AI Features (v3.0.0)

> Intelligent, personalized guidance. Differentiator from generic trackers.

| # | Feature | Description |
|---|---------|-------------|
| 7.1 | **Protocol recommendations** | Core ML: goals + compliance rates -> ranked suggestions. "Suggested for you" on Home. Entirely on-device |
| 7.2 | **AI research assistant** | On-device LLM (Apple Intelligence / Foundation Models). RAG over peptide database. Chat interface. Sourced answers. Medical disclaimers |
| 7.3 | **Smart cycle planning** | Analyze past compliance patterns and durations. Suggest optimal cycle length and timing. Calendar integration |
| 7.4 | **Anomaly detection** | Flag compliance drops, missed dose clusters. HealthKit correlation ("HRV dropped 20%"). All on-device |

---

## Phase 8 -- Monetization (v3.1.0)

> Sustainable freemium model.

### Free Tier
- Up to 3 active protocols
- Full peptide database
- Basic analytics (weekly view)
- Local persistence
- Dose reminders
- 1 widget

### PeptideX Pro
- Unlimited protocols
- Full analytics + HealthKit correlation + export
- AI research assistant + recommendations
- All widgets + Apple Watch
- Cloud sync + backup
- Community features + templates
- **Monthly $6.99 / Annual $49.99 (~40% savings)**
- 7-day free trial (monthly), 14-day (annual)

| # | Feature | Description |
|---|---------|-------------|
| 8.1 | **StoreKit 2** | `SubscriptionStoreView` paywall. `Transaction.currentEntitlements`. Family Sharing |
| 8.2 | **Soft paywalls** | Glass-styled "Upgrade" preview cards. Never paywall reminders or basic tracking |
| 8.3 | **Restore purchases** | Profile button. Auto-restore on new device |

---

## Phase 9 -- Growth & Polish (v3.5.0+)

| # | Feature | Description |
|---|---------|-------------|
| 9.1 | **App Store optimization** | Screenshots, preview video, keywords. Localization: Spanish, Portuguese, German, Japanese |
| 9.2 | **Referral system** | Share protocol as deep link. "Invite a friend" with shared trial extension |
| 9.3 | **Accessibility** | Full VoiceOver. Dynamic Type. Reduce Motion. High Contrast for glassmorphism |
| 9.4 | **Gamification** | Badges: "First Protocol", "7-Day Streak", "30-Day Streak", "Perfect Week", "100 Doses". Celebration animations |
| 9.5 | **Performance** | Lazy loading. Pagination. < 1s cold start |

---

## Phase 10 -- Long-Term Vision (v4.0.0+)

| # | Feature | Description |
|---|---------|-------------|
| 10.1 | **Multi-platform** | macOS via Mac Catalyst. visionOS spatial health dashboard |
| 10.2 | **Provider portal** | Web dashboard for practitioners to view patient compliance (with consent). HIPAA considerations |
| 10.3 | **Source verification** | QR scanning for peptide vial verification. Certificate of analysis storage |
| 10.4 | **Advanced biometrics** | Oura Ring, Whoop, Eight Sleep integration. Anonymized community health trends |
| 10.5 | **Regulatory** | GDPR export/deletion. CCPA compliance. Health data policies |

---

## Phase Dependencies

```
Phase 0 (Foundation)
  |
Phase 1 (Persistence)
  |
  +---> Phase 2 (Onboarding/Auth)  -----> Phase 6 (Backend/Community)
  |                                              |
  +---> Phase 3 (Notifications/Core) --+---> Phase 5 (Ecosystem) ---+
  |                                    |                             |
  +---> Phase 4 (HealthKit/Analytics) -+---> Phase 7 (AI) -----> Phase 8 (Monetization)
                                                                     |
                                                              Phase 9 (Growth)
                                                                     |
                                                              Phase 10 (Vision)
```

**Parallelism:** Phases 2, 3, 4 run in parallel after Phase 1. Phases 5, 7 run in parallel. Phase 8 ships after Phases 3-5 provide enough premium value.
