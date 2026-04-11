# PeptideX Product Roadmap

## Current State (v1.0 MVP)

PeptideX is a SwiftUI iOS app for peptide therapy protocol management with a custom Liquid Glass design system.

**Shipped features:**
- Dashboard with today's schedule, compliance score, and quick stats
- Peptide database (14 peptides across 6 categories with dosage info and research links)
- Protocol management (create, view active/paused/completed protocols)
- Analytics (compliance charts, weekly dose breakdown, streak tracking)
- User profile with goals and settings
- Dark mode Liquid Glass UI (19 reusable components)

**Current limitations:**
- All data is mock (no persistence between sessions)
- Protocol builder UI exists but doesn't save
- No notifications or reminders
- No HealthKit integration
- No authentication or cloud sync

---

## Phase 1: Foundation — Local Persistence
*Goal: Make the app functional with real data that persists.*

### 1.1 SwiftData Integration
- Add `@Model` to `PeptideProtocol`, `ProtocolEntry`, and `UserProfile`
- Create `ModelContainer` configuration in app entry point
- Migrate ViewModels from mock data to `@Query` / `ModelContext`

### 1.2 Protocol Builder Persistence
- Wire "Create Protocol" button to save via `ModelContext.insert()`
- Add validation (name required, at least 1 peptide, at least 1 day)
- Make protocol list reactive to SwiftData changes

### 1.3 Dose Logging
- Persist completion state when toggling doses in Today's Schedule
- Track timestamps for dose completions
- Calculate real compliance scores from persisted entries

### 1.4 "Add to Protocol" Flow
- Wire the button in peptide detail view
- Create protocol selector sheet
- Update protocol's peptide list in SwiftData

### 1.5 Onboarding Flow
- 3-4 screen onboarding (welcome, goal selection, name entry)
- Create user profile on completion
- Use `@AppStorage("hasCompletedOnboarding")` for first-launch detection

---

## Phase 2: Engagement — Notifications & Real Analytics
*Goal: Keep users engaged and provide meaningful insights.*

### 2.1 Local Notifications
- Request notification permissions during onboarding
- Schedule dose reminders based on protocol times
- Cancel/reschedule when protocols change
- Deep link notification taps to relevant protocol

### 2.2 Real Analytics
- Replace mock chart data with SwiftData queries
- Aggregate real `ProtocolEntry` data by time range
- Calculate true streaks from consecutive completion days
- Show real trend indicators (week-over-week compliance change)

### 2.3 Protocol Lifecycle
- Pause/resume active protocols
- Edit existing protocols (modify schedule, add/remove peptides)
- Auto-complete protocols when cycle end date passes
- Duplicate protocols ("start another cycle")

### 2.4 Data Export
- Export protocol history as CSV
- Generate compliance report PDF
- Use `ShareLink` with `Transferable` conformance

---

## Phase 3: Health Integration — HealthKit & Insights
*Goal: Connect peptide tracking to measurable health outcomes.*

### 3.1 HealthKit Integration
- Wire "Connect Apple Health" button in profile
- Read: heart rate, HRV, sleep analysis, activity energy
- Display health metrics alongside protocol data
- Correlate compliance with health metric trends

### 3.2 Insights Engine
- Auto-generate insights: "Your HRV improved 15% since starting Recovery Stack"
- Surface correlation between compliance and health changes
- Add insights card to Home dashboard

### 3.3 iOS Widgets
- Next dose widget (time, peptide name, dosage)
- Today's progress widget (completion ring)
- Streak counter widget
- Lock Screen widget support

---

## Phase 4: Cloud — Backend & Sync
*Goal: Enable multi-device access and data safety.*

### 4.1 Authentication
- Sign in with Apple (primary)
- Email/password fallback
- Keychain token storage

### 4.2 Cloud Sync
- CloudKit integration for automatic sync
- Offline-first: SwiftData remains source of truth
- Background sync with conflict resolution
- Multi-device support (iPhone, iPad)

### 4.3 Remote Peptide Database
- Move peptide data to remotely updateable source
- Add new peptides without app updates
- Versioned database with delta updates

---

## Phase 5: Scale — Premium Features
*Goal: Expand platform reach and monetization.*

### 5.1 Apple Watch Companion
- Today's schedule with completion toggles
- Complication showing next dose time
- Haptic dose reminders

### 5.2 iPad Optimization
- Adaptive layouts with `NavigationSplitView`
- Side-by-side protocol comparison
- Enhanced analytics with larger chart views

### 5.3 Subscription Model (StoreKit 2)
- **Free tier:** Basic tracking, 1 active protocol, 7-day analytics
- **Premium:** Unlimited protocols, full analytics, HealthKit, cloud sync, widgets
- Family sharing support

### 5.4 Advanced Features
- Photo logging (injection site tracking)
- Blood work result tracking and trends
- Peptide interaction checker
- AI-powered protocol recommendations
- Community protocol templates (anonymized sharing)

---

## Phase 6: Production Hardening — Ongoing
*Goal: Ship with confidence and maintain quality.*

### 6.1 Testing
- Unit tests for all ViewModels and business logic
- UI tests for critical flows (onboarding, protocol creation, dose logging)
- Snapshot tests for design system components

### 6.2 Observability
- Privacy-focused analytics (TelemetryDeck or PostHog)
- Crash reporting (Sentry)
- Performance monitoring

### 6.3 Accessibility
- VoiceOver audit on all screens
- Dynamic Type support verification
- Reduced Motion support (disable animations)
- Color contrast verification

### 6.4 Localization
- Extract all strings to `Localizable.strings`
- Priority markets: English, Spanish, German, Japanese
- RTL layout support
