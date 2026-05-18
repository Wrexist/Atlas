# Atlas Roadmap

## Current State

Atlas is a native iOS SwiftUI health & fitness app — workout
tracking with rest timer and PR detection, nutrition via barcode +
photo meal scanning, biology (HRV / RHR / sleep / recovery score /
lab panels), habits with streak tracking, and an AI research chat.
For advanced users, a peptide-protocol tracker rides alongside the
fitness surfaces — the legacy peptide name lives on in the bundle
ID and StoreKit product IDs (`com.peptidesai.app`) so existing
subscribers keep working through the rebrand. iOS 18+, Swift 6.0,
SwiftData (CloudKit-backed). 5-tab navigation, companion Watch
app, two widget targets, Live Activities, biometric lock, and
CI/CD to TestFlight via Fastlane.

### What's shipped

| Area | Status | Details |
|------|--------|---------|
| **UI/UX** | Complete | Glass material design, dark mode, haptic feedback, scale-press affordances, Bevel-style hero rings + coaching + Health Monitor grid + context pills + sync toast |
| **Today screen** | Complete | WelcomeHeader → context pills → quick-jump chip bar → hero metric trio → coaching → meals/wellness/movement → Health Monitor grid → daily insight |
| **Peptide database** | Complete | 208 peptides across 6 categories, bundled JSON, research links |
| **Protocol management** | Complete | Create, edit, pause, complete protocols with schedule builder and per-peptide overrides |
| **Dose tracking** | Complete | Daily entries, toggle completion, rich logging (actual dose, time, injection site, notes) |
| **Hero metric trio** | Complete | Adherence / Recovery / Sleep rings at top of Today, Bevel-inspired |
| **Recovery score engine** | Complete | Composite 0–100 from HRV + Sleep + RHR with redistributed-weight partial-data handling; 17 unit tests |
| **Coaching messages** | Complete | Priority cascade (welcome → connect-health → recovery state → short sleep → catch-up → on-track) under hero trio; 9 unit tests |
| **Health Monitor grid** | Complete | HRV / RHR / Sleep biometric cards with personal-range envelopes (p10–p90 over 21 days); 7 unit tests |
| **Vial visual system** | Complete | Category-driven CompoundVial (cap finish per category, hue offsets per compound, no more gray fallback); migrated across 5 surfaces; 7 unit tests |
| **Today jump-bar** | Complete | Pill row chips (Doses / Meals / Wellness / Movement / Insights) with scroll-to-section + Insights-tab jump + quick-log dialog |
| **Lifestyle tab** | Complete | Macro rings, weight sparkline + log, workout log, progress-photo capture |
| **Meal scanner — photo + live camera** | Complete | Claude vision via Vercel proxy; macro estimate with confidence and clamping; "Take photo" + "Choose from library" dual-button picker; rear camera via CameraPicker |
| **Meal scanner — barcode** | Complete | DataScanner viewfinder, Open Food Facts lookup with 502/503/504 retry-with-backoff, portion picker, recently-scanned grid, edit-before-log override, Undo via `.logged` phase |
| **AI research assistant** | Complete | Multi-turn chat via Vercel proxy with substring-RAG over the bundled database |
| **Recommendation engine** | Complete | 12 scoring signals, 7 warning types, validated stacks |
| **Insight engine** | Complete | Streaks, day-of-week patterns, compliance trends, milestone insights; unified streak math with `DataStore.currentStreak` |
| **Smart cycle planner** | Complete | 5 suggestion kinds (shorten, shift, wrap-up, off-cycle, pause); confidence-scored; surfaces ≥medium picks on Home |
| **Notifications** | Complete | Dose reminders, actionable (Mark as Taken / Snooze), 64-limit handling, per-timeslot consolidation |
| **Widgets** | Complete | iOS small + medium (next dose, compliance ring + schedule), watchOS widgets, real data via App Groups |
| **Live Activities** | Complete | Dose-window Dynamic Island + lock-screen UI with category-aware tint |
| **Watch app** | Scaffold | Reads via App Group, sends mark-complete / mark-incomplete back via WCSession; **needs manual Xcode build verification** |
| **Achievements** | Complete | 14 achievements (dose milestones, streaks, protocol, logging), toast notifications |
| **Export** | CSV + JSON | PDF planned (see v1.1) |
| **Onboarding** | Complete | 17-page flow: review prompt → creator code → email → paywall → theme → add-medication → ready |
| **HealthKit** | Complete | Reads 7 data types (HR, HRV, sleep, weight, steps, energy); observer-based background delivery wired; daily-series helpers for HRV / RHR / Sleep used by Health Monitor grid |
| **Biometric lock** | Complete | LocalAuthentication-backed lock screen with auto-Face-ID on appear, scene-phase re-lock on background, Reduce-Motion respect, haptic feedback, toggle in AppearanceSettings, `NSFaceIDUsageDescription` in project.yml |
| **Persistence** | Complete | SwiftData @Model classes, CloudKit-backed private container with local + in-memory fallbacks |
| **StoreKit 2** | Complete | Monthly + annual + lifetime, paywall, transaction verification, restore purchases, intro-offer eligibility |
| **AI proxy** | Complete | Vercel deployment with shared-secret auth, per-IP rate limit, body sanitisation, model allowlist, max_tokens hardcap |
| **Sharing** | Complete | Cycle-share card (1080×1920) with Day-7/30/complete prompts and privacy detail toggle |
| **Siri shortcuts** | Complete | AppIntents bundle including "Log my BPC-157" and "What are my macros today?" |
| **Premium promo card** | Complete | Cosmic-backdrop reusable component for Pro upsells (used by future Bio Age tab, etc.) |
| **Sync toast** | Complete | Top-of-screen "Sync Complete" pill auto-dismissing after fresh HealthKit pull |
| **Localization** | Complete | 9 locales fully translated (en, es, zh-Hans, ja, de, fr, pt-BR, ko, ru, ar) |
| **Testing** | ~45 test files | Network services (MockURLProtocol), data integrity, recommendation/insight engines, persistence round-trip, schedule cadence, achievement service, vial palette, recovery score, coaching messages, health range percentiles |
| **CI/CD** | Complete | XcodeGen, SwiftLint, build + test in GitHub Actions (macos-15 pinned), TestFlight via Fastlane, binary-size delta gate |

---

## Next: v1.1.0 — Reliability & polish

> Lock down what's there. Pure trust-and-stability work.

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 1.1 | **Crash reporting** | 1 day | Sentry or MetricKit for TestFlight crash visibility. Currently flying blind |
| 1.2 | **PDF export** | Half day | Add PDF report generation to existing export service (CSV + JSON already work) |
| 1.3 | **Watch app verification** | 1–2 days | The scaffold exists; needs Xcode build + complication + manual dose-toggle round-trip on real hardware |
| 1.4 | **Smooth-everywhere animation pass** | 1 day | Spring transitions on every section reveal, haptic on ring tap / chip tap / pill expansion, no instant cuts |
| 1.5 | **Today reorder polish** | Half day | Audit redundancy between HeroMetricTrio and TodayOverviewCard (both currently show adherence in a ring); consolidate TodayOverviewCard's ring section once the trio proves out in TestFlight |

---

## v1.2.0 — Bevel-style depth

> Continue the redesign — adds the missing two pieces that turn Today from "dashboard" into "intelligent home screen".

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 2.1 | **Today timeline** | 2 days | Chronological vertical list of today's events (doses + meals + check-ins + workouts + sleep) merged from 4 stores into one sorted feed |
| 2.2 | **Date scrubber** | 2 days | Tap the date pill → date picker → render Today's snapshot for any historical day. Requires HomeView to support past-state rendering |
| 2.3 | **Edit Home customization** | 1 day | Section visibility toggles in Profile → Customize Today, with drag-to-reorder; stored on `UserProfile.todaySectionOrder: [SectionID]` |
| 2.4 | **MetricRing consolidation** | 1 day | Migrate `GlassProgressRing` and `SegmentedCalorieRing` to the unified `MetricRing` primitive; port the celebration-at-100% animation in once, not twice |
| 2.5 | **Hero detail sheets** | 1 day | Tap any of the trio's rings → expanded sheet (HRV trend, sleep stages, today's dose timeline) |

---

## v1.3.0 — Biology tab (signature feature)

> New tab. Atlas's unique angle on Bevel's biological-age model: a peptide tracker that *explains* what's moving the markers.

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 3.1 | **Tab restructure** | Half day | Today / Stack / Insights / Biology / Profile (merges Library + Protocols under "Stack" with internal tabs) |
| 3.2 | **Performance Age engine** | 3 days | Pure-function bio-age estimate from HRV + RHR + sleep + weight trend + lab markers; confidence-gated UI (hide if confidence < 60%) |
| 3.3 | **Biomarker trend cards** | 2 days | 90-day charts for HRV / RHR / Sleep efficiency on the Biology tab |
| 3.4 | **Lab photo OCR ingestion** | 3 days | Snap bloodwork PDF → Claude vision extracts markers → writes to existing Labs feature |
| 3.5 | **Stack-effectiveness score** | 2 days | Atlas-unique: map each lab marker movement to active compounds in the cycle; surfaces "BPC-157 may be helping your IGF-1 trend" |

---

## v2.0.0 — Data & sync

> Multi-device. The #1 thing that converts free → Pro on health apps.

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 4.1 | **SwiftData migration** (feature-flagged) | 3–5 days | Replace JSON persistence with `@Model` classes via opt-in flag for one TestFlight cycle, then promote to default |
| 4.2 | **CloudKit sync** | 3–5 days | `CKSyncEngine` for automatic sync + conflict resolution; requires SwiftData; entitlement already declared |
| 4.3 | **Sign in with Apple** | 1–2 days | `AuthenticationServices`. Identifier in Keychain. Optional — app works without sign-in |
| 4.4 | **iPad pass** | 2 days | `NavigationSplitView` treatment on Home / Lifestyle / Profile (PeptideListView already done) |

---

## v2.5.0 — Growth & retention

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 5.1 | **Promo-offer JWT signing** | 1–2 days | Creator-code banner currently shows a discount that isn't applied; sign promo offers server-side via `Product.PurchaseOption.promotionalOffer` |
| 5.2 | **Onboarding compression** | 2 days | 17 pages → ≤9. Show first-dose value before paywall |
| 5.3 | **Empty-state day 0** | 1 day | First-install dashboard ("0/4, 0%, 0 days") reads as failure; replace with curiosity copy + first-dose preview |
| 5.4 | **Referrals via Universal Links** | 2 days | Share Atlas → personal link → recipient signs in with creator credit |
| 5.5 | **Streak recovery** | 1 day | Streak-freeze Pro perk: 1 per week, auto-applied to a missed day |
| 5.6 | **Share-card formats** | 1 day | Add 1080×1080 (Instagram) and 1200×630 (Twitter) using the existing renderer |

---

## v3.0.0 — Community & AI

> Connected experience with social features and intelligent guidance. Backend-dependent — don't start until v2.0 is solid.

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| 6.1 | **Backend stand-up** | 5 days | Supabase or Cloudflare D1 + Workers. Auth via Sign in with Apple. RLS for templates. Moderation queue |
| 6.2 | **User-published protocol templates** | 3 days | Bundled `community-stacks.json` is curated today; user submission → moderation → publish |
| 6.3 | **Apple Intelligence on-device LLM** | 3 days | Replace cloud Claude for *summarisation* parts of Weekly Summary + insights (iOS 18.2+); cloud Claude stays for meal vision + research chat |
| 6.4 | **Side-effect tracker** | 2 days | Daily check-in extension; correlate with active compounds in Insights |
| 6.5 | **Inter-cycle comparison** | 2 days | "Cycle 2 vs Cycle 1: avg HRV +8ms, weight -2.3kg, sleep efficiency +4%" — one of the highest-value reads in the app |
| 6.6 | **Dose-to-symptom correlation** | 3 days | "Sleep score drops 12% on days you dose CJC-1295 after 6pm"; gated behind `entries.count > 60` |

---

## v3.5.0+ — Platform expansion

> Don't touch until v1.x converts in the App Store.

| # | Feature | Notes |
|---|---------|-------|
| 7.1 | **macOS via Catalyst** | Mostly polish — useful for typing lab values |
| 7.2 | **Web companion (read-only)** | Tiny Next.js app reading via CloudKit server-to-server tokens |
| 7.3 | **visionOS** | Demo-able, not necessarily useful |
| 7.4 | **Android** | Not until iOS hits $20k MRR |

---

## Phase dependencies

```
v1.1 (Reliability)
  │
v1.2 (Bevel-style depth) ─┐
  │                        │
v1.3 (Biology tab)         │
  │                        │
v2.0 (Data & sync) ────────┼─→ v2.5 (Growth & retention)
  │                        │
  └─→ v3.0 (Community & AI)
        │
        └─→ v3.5+ (Platform expansion)
```

---

## Monetization

### Free tier
- Up to 3 active protocols
- Full peptide database (208 peptides)
- Hero metric trio + coaching (basic)
- Health Monitor grid (HRV / RHR / Sleep)
- Basic analytics (weekly view)
- Local persistence
- Dose reminders
- 1 widget

### Atlas Pro ($9.99/mo, $49.99/yr, or $169 lifetime)

- Unlimited protocols
- Full analytics + HealthKit correlation + export
- AI Research chat
- AI weekly summary
- Cycle Card share with health signals
- All widgets + Apple Watch
- Cloud sync + backup _(planned, v2.0)_
- Performance Age + Biology tab _(planned, v1.3)_
- Community features + templates _(planned, v3.0)_
- 7-day free trial (monthly), 14-day (annual)
