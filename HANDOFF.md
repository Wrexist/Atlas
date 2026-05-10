# PeptideX overnight handoff — branch `claude/add-review-prompt-onboarding-H4SD6`

This doc captures everything done overnight on the v2.0+ roadmap pass,
plus the items that genuinely require a human-in-the-loop session
(Apple Developer config, real-device testing, new Xcode targets) and
can't be safely landed from a headless coding session.

## TL;DR — branch state

19 commits since `288e5a4`. The flow now ships with:

- 17-page onboarding (review prompt → creator code → email capture → paywall → theme → add-medication → ready)
- New Lifestyle tab (meal scanner with Claude Vision, weight tracking with sparkline + log sheet, real progress photo capture, real workout logging, daily macro rings)
- Track tab (the renamed Protocols surface) with monthly calendar — both Schedule mode (per-day dose dots) and Cycle mode (per-week colored bands across active protocols), plus the per-day detail panel and a compound filter shelf
- Vial illustration component used in 5 surfaces (Home shelf, onboarding preview, calendar detail panel, dose card thumbnails, ShareCardSheet)
- Cycle-share card (1080×1920 Stories format) with Day-7/30/complete trigger prompts and a privacy detail toggle
- Rebuilt PaywallView with the Vercel-deployed creator-code attribution banner
- Marketing landing page rebuild
- AI research assistant chat (Claude Sonnet 4.6 with substring-RAG over the bundled peptide database)
- AppIntents bundle with 5 Siri shortcuts including parameterized "Log my BPC-157" and "What are my macros today?"
- Smart cycle planner card on Home (5 suggestion kinds: shorten, shift, wrap-up, off-cycle, pause)
- Live Activities for in-progress dose windows with Dynamic Island + lock-screen UIs

Plus the audit-pass bug fixes (timezone-correct macro day buckets, weight trend window, onboarding back-button stranding, calendar dot dedup, vial surface clip, etc) and a real Vercel proxy for the meal scanner so the API key never ships in the binary.

---

## What you need to do before merging

### 1. Local Xcode build

I can't run `xcodebuild` from this environment, so nothing is compile-verified. Do a clean build:

```bash
xcodegen generate
xcodebuild build -scheme Peptide -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

Likely places to inspect first if anything fails:
- `Peptide/Services/MealScannerService.swift` and `AIResearchService.swift` — the JSON payload uses `as [String: Any]` casts in dictionary literals; if Swift 6 strict concurrency complains, an explicit `let payload: [String: Any] = [...]` annotation at the call site fixes it.
- `Peptide/Features/Home/HomeView.swift` — the milestone-prompt sheet uses `liquidGlassPresentation(detents:)`; that variant might not exist in your liquid-glass extension. If so, drop the `(detents:)` argument.
- `Peptide/Services/DoseLiveActivityService.swift` — `Color.cgColor` returns `CGColor?`; verify the cast on iOS 16.

### 2. Deploy the Vercel meal-scanner proxy

The proxy lives in `/server/` as a deployable Vercel project. Steps in `server/README.md`:

```bash
cd server
vercel deploy --prod
# In Vercel dashboard, set ANTHROPIC_API_KEY env var
```

Then add to `Peptide/Resources/Info.plist`:

```xml
<key>MEAL_SCANNER_ENDPOINT</key>
<string>https://your-deploy.vercel.app/api/meal-scan</string>
<key>AI_RESEARCH_ENDPOINT</key>
<string>https://your-deploy.vercel.app/api/meal-scan</string>
```

(The same proxy serves both surfaces — the body shape is identical.)

### 3. Live Activities entitlement

`project.yml` now declares `NSSupportsLiveActivities: true`, but the entitlement also needs to be present in your Apple Developer App ID config. Check Apple Developer → Identifiers → `com.peptidesai.app` → make sure "Live Activities" is in the supported capabilities. The certificate / provisioning profile should refresh automatically after enabling.

### 4. App Store Connect promo offers (optional)

The creator-code banner on the rebuilt PaywallView shows `"X% off applied — thanks to [creator]!"` but the actual price modification is **not wired** — the existing StoreKit flow runs whatever intro offer you've configured in App Store Connect. To make the discount real, either:

- **Cleanest**: configure App Store Connect promotional offers per `discountPercent` value and pass them to `Product.PurchaseOption.promotionalOffer(...)` from `StoreService.purchase`. Requires server-side promo-offer signature signing.
- **Quickest**: change the banner copy to "Code applied — thanks to [creator]!" so it's not making a price-change claim until the backend lands.

### 5. AppIntents may need a quick re-import

The `LogSpecificPeptideIntent` parameter syntax `\(\.$peptideName)` requires the Xcode AppIntents extractor to re-scan. After the next build, open Xcode → File → Packages → Reset Package Caches if Siri can't find the new shortcut.

---

## What landed overnight (commits `478d859` through HEAD)

### Server-side proxy (`/server/`) — closes audit follow-up

- `server/api/meal-scan.js` — Vercel serverless function holding the API key
- `server/vercel.json` + `server/package.json` + `server/README.md` — deployable as a standalone Vercel project (doesn't disturb the existing `docs/` landing-page deploy)

### v3.0.2 — AI research assistant

- `Peptide/Services/AIResearchService.swift` — Claude Sonnet 4.6 client. Substring-RAG: scans the user's question + recent transcript for peptide names against the bundled 208-entry database, injects up to 4 matching entries' description / dosage / half-life / mechanism / contraindications / citations into the system prompt
- `Peptide/Features/AIResearch/AIResearchView.swift` — chat UI: disclaimer banner, suggested prompts, streaming spinner, selectable bubbles
- Pro-gated entry point on Database tab toolbar (`PeptideListView.sidebarToolbar`); free tier sees the paywall

### v2.5.2 — AppIntents extension (existing intents preserved)

- `LogSpecificPeptideIntent` — parameterized "Log my [name]" matches against active stack
- `TodayMacrosIntent` — "What are my macros today?" surfaces calorie + protein totals via Siri
- `IntentDataSnapshot` extended to read `profile.dailyConsumption` with the same timezone-pinned ISO key the live app uses

### v3.3 — Smart cycle planner

- `Peptide/Services/SmartCyclePlanner.swift` — 5 suggestion kinds:
  - `shortenNextCycle(currentWeeks:suggestedWeeks:)` — when second-half compliance is materially worse than first-half
  - `shiftDoseTime(from:to:)` — when one preferred time slot has ≥25% lower adherence
  - `cycleWrappingUp(daysRemaining:)` — last 5 days of the cycle window
  - `offCycleReady(daysSinceLast:)` — completed protocol past its rest window
  - `considerPausing(daysIdle:)` — active protocol with no completed entries in 7+ days
- Confidence-scored, ordered highest-first, hidden from UI below `.medium`
- `Peptide/Features/Home/Components/SmartCyclePlannerCard.swift` surfaces ≥medium picks on Home, capped at 3

### v2.5.3 — Live Activities for in-progress dose windows

- `Shared/DoseWindowAttributes.swift` — `ActivityAttributes` (entry id, peptide abbreviation, dose display, tint hex) + `ContentState` (dose time, completed flag). Lives in `/Shared` so both targets see it
- `PeptideWidgets/DoseWindowLiveActivity.swift` — lock-screen + Dynamic Island (compact / expanded / minimal) presentations. Countdown via `Text(_:style:.timer)` so iOS auto-tweens without per-second push updates
- `Peptide/Services/DoseLiveActivityService.swift` — start/update/end controller. Active window = 30 min before → 90 min after `doseTime`. Reconciliation runs on `.active` scenePhase transition (`PeptideApp`); explicit `markCompleted(_:)` on `DataStore.toggleEntry` when the user logs a dose
- `Peptide/Services/Logger.swift` — new `AppLog.live` category for ActivityKit failures
- `project.yml` — `NSSupportsLiveActivities: true`

### Localization (already shipped)

- `Peptide/Resources/Localizable.xcstrings` is already 9875 lines, fully translated for all 9 declared locales (en, es, zh-Hans, ja, de, fr, pt-BR, ko, ru, ar). No action needed beyond running the standard `xcodebuild -exportLocalizations` if you add new source-language strings later.

### Accessibility additions

- `MealScanBanner` and `MacroSummaryRow` quick-add water buttons gained explicit accessibility labels + button traits
- Existing accessibility coverage is broad — `CalendarMonthView`, `CycleCardView`, `VialIllustration`, all the chip rows in the body-stats picker — and was already in good shape

### Performance audit — no changes needed

`PeptideListView` already uses `LazyVStack` for the 208-entry peptide grid. Other `ForEach` sites iterate small bounded collections (active protocols ≤ 5, today's entries ≤ ~10, warning peptides ≤ 4) so converting them to lazy variants would be premature.

---

## What I deliberately did NOT ship overnight, with reasons

These items are on the v2.0+ roadmap but cannot be safely landed from a headless coding session — they require Apple Developer dashboard config, real-device testing, new Xcode targets, or backend deployment access.

### v2.1 — SwiftData migration (DEFERRED)

The codebase already has a `SwiftDataRepository` (visible in `IntentDataSnapshot.load`) but the live `DataStore` still reads via JSON `PersistenceService`. The migration itself is data-sensitive (one wrong move loses every existing user's protocols and entries) and demands real-device migration testing across the install-base. I won't touch this without manual verification at every step.

**Recommended path**: feature-flag the SwiftData read path, ship it as opt-in for one TestFlight cycle, then promote to default once the migration is proven idempotent.

### v2.3 — CloudKit sync (DEFERRED)

The entitlements file already has `iCloud.com.peptidesai.app` declared, so the Apple Developer side is ready. What's missing is the `CKSyncEngine` plumbing on top of SwiftData. Same dependency-on-SwiftData blocker as v2.1, plus this needs real-device testing across two signed-in iCloud accounts to verify conflict resolution.

### v2.5.1 — Apple Watch app (PARTIALLY SHIPPED, NEEDS COMPLETION)

`/PeptideWatch/` and `/PeptideWatchWidgets/` directories already exist and the project.yml has Watch targets declared. I didn't touch them because the existing scaffold may already be functional and I can't verify Watch builds from here. **Worth a manual review pass**: open the project in Xcode, build the Watch target, see what's missing.

### v3.4 — iPad optimization (LARGELY SHIPPED)

`PeptideListView` already branches on `horizontalSizeClass` and renders `NavigationSplitView` on iPad regular vs `NavigationStack` on iPhone. The pattern is in place and just needs the same treatment applied to other tab views (Home, Lifestyle, Profile) — fairly mechanical work that benefits from running it on a real iPad to tune column widths.

### v4.4 — Community features (DEFERRED)

The bundled `community-stacks.json` ships curated stacks today (`CommunityStackService` is wired). User-published stacks need a backend with moderation — a meaningful product-and-infra project, not a one-night code change.

### v5.4 — macOS Catalyst (DEFERRED)

Adding a Catalyst target requires `project.yml` changes I can't verify, plus extensive UI testing for keyboard/mouse interaction. Fundamentally a multi-day pass.

### v5.5 — visionOS (DEFERRED)

Same reason as Catalyst — needs a new target and design pass for spatial UI.

### App Store Connect promotional offers (DEFERRED)

The creator-code attribution banner shows the discount % but no actual price modification happens. Wiring this requires App Store Connect promo offer config + server-side signed JWT for the offer (see `Product.PurchaseOption.promotionalOffer`). Cleanest as a focused 1-day pass once the proxy is deployed.

---

## Test coverage added overnight

| File | What it covers |
|------|----------------|
| `CycleBandsTests` | 5 tests: empty/inactive/paused exclusion, window overlap, completed-protocol exclusion, multi-protocol stacking |
| `VialInventoryTests` | 5 tests: zero entries → full vial, linear drain, vial-boundary refill, modulo wrap past first vial, floor clamp |
| `CycleMilestoneServiceTests` | 10 tests: eligibility ladder, suppression isolation, paused-skip, ordering tiebreak, re-prompt prevention |
| `LifestyleDataStoreTests` | Extended with workout-mutator tests: sort order, delete-by-id, day-isolated `workoutSummary` |

The new `AIResearchService`, `SmartCyclePlanner`, and `DoseLiveActivityService` don't have dedicated test files yet — `SmartCyclePlanner` is the easiest to test (pure functions over inputs); `AIResearchService` and `DoseLiveActivityService` need network-mock and ActivityKit-mock infrastructure that's outside this branch's scope. Worth a follow-up.

---

## One last caveat

Nothing in these 19 commits is compile-verified. The audit-pass code-reviewer agent flagged a couple of API-version edge cases (`ImageRenderer.proposedSize` setter is iOS 17+) that are worth confirming on the iOS 18 deployment target before merging. A clean Xcode build should surface anything that needs to be patched in under an hour.

Sleep well — code's ready when you are.
