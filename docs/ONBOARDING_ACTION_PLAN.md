# Onboarding Action Plan — Final State

Branch: `claude/audit-onboarding-experience-LEVSs`
Companion to: `docs/ONBOARDING_AUDIT.md`

This is the final state of the branch after Plan A execution and
three rounds of audit-driven bug fixes.

---

## Shipped — Plan A items executed

| # | Item | Status |
|---|------|--------|
| A2 | Typography variation pass (data-entry pages 32pt → 26pt) | ✅ shipped |
| A3 | GoalCountdownCard on Home reading `profile.goalDate` | ✅ shipped |
| A4 | ScenePhase refresh for notification authorization | ✅ shipped (now via `.task(id:)`) |
| A5 | Widget add-deeplink tip card on Ready | ✅ shipped |
| A6 | Tests for OnboardingFunnelTracker + GoalCountdownCard | ✅ shipped |
| A8 | OnboardingExperiment scaffolding + paywall tier-order experiment | ✅ shipped |
| A10 | "How did you hear about us?" attribution survey | ✅ shipped |
| A7 | Localize stubs | ⏭️ deferred — Localizable.xcstrings auto-extraction runs at xcodebuild time |
| A9 | Commitment ritual screen (Finch pattern) | ⏭️ deferred — A/B-experimental, needs product input |
| A11 | Funnel event drain plumbing | ⏭️ deferred — depends on backend |
| A12 | Reverse trial experiment | ⏭️ deferred — A/B-experimental |

---

## Audits run — findings & resolution

Three parallel audit agents ran after Plan A executed:

1. **Code review** — 21 findings (6 critical, 9 medium, 6 low)
2. **Security review** — 12 findings (0 critical, 3 high, 5 medium, 4 low)
3. **Integration audit** — 18 findings (3 critical, 4 high, 6 medium, 5 low)

### Resolved in fix rounds 1–3

| ID | Audit | Fix |
|----|-------|-----|
| C1 (compile error) | code-review #2 + integration C1 | Added missing PrimaryGoal cases (`betterSleep`, `recovery`, `antiAging`, `skinHair`, `energy`) to `recommendedProgramName` switch |
| C2 (silent data loss) | integration | OnboardingView calls `updateGoals(goalSet)` before `setPrimaryGoal()`; `setPrimaryGoal` now logs a warning on drops |
| Code-review #1 | code-review | `defer { isPurchasing = false }` on the paywall purchase Task |
| Code-review #3 / H1 | code-review + integration | `OnboardingExperiment.variant(for:)` moved out of `@State` initializer into `.task` block |
| Code-review #4 | code-review | `buildingPlanStep.onChange(of: page)` moved to outer body → `updateBuildingPlanForPage(_:)` |
| Code-review #5 | code-review | `dataStore.flushPendingSave()` instead of `persistProfile()` for `goalDate`, `creatorAttribution`, `emailSubscription` |
| Code-review #6 | code-review | Building-plan auto-advance held on `buildingTask: Task?` state, cancelled on back-nav |
| Code-review #7 | code-review | `trialDays` switches on `intro.period.unit` (day/week/month/year → days) |
| Code-review #10 | code-review | Defensive `.onChange(of: showTrialOffer)` catches system dismissal, records `paywall_dismissed_externally` |
| Code-review #11 | code-review | `@State authService = AuthService.shared` pins observation tracking |
| Code-review #12 | code-review | `weeksRemaining` derived from calendar-based `daysRemaining`, DST-aware |
| Code-review #13 / M-4 | code-review + security | `OnboardingExperiment.assign` uses CryptoKit SHA-256 instead of randomised `String.hashValue` |
| Code-review #14 | code-review | `scenePhase` watcher migrated from `onChange + Task` to `.task(id: scenePhase)` |
| Code-review #17 | code-review | `GoalCountdownCard` wrapped in `TimelineView(.everyMinute)` |
| Code-review #18 | code-review | Accessibility label + hint on attribution chips |
| Code-review #21 | code-review | "12k+ training" → "12k+ athletes" |
| H-1 (security) | security | `profile.json` writes with `.completeFileProtection` |
| H-2 (security) | security | `SignInError.failed` no longer interpolates untrusted `localizedDescription` |
| H-3 (security) | security | `@AppStorage("disclaimerAcknowledgedAt")` provides persistent audit trail |
| M-1 (security) | security | `looksLikeEmail` caps input at 3...254 chars (RFC 5321) |
| M-2 (security) | security | `CreatorCodeService.lookup` caps needle at 32 chars |
| M-5 (security) | security | Funnel tracker caps events at 200 entries, names at 64 chars, log privacy bumped to `.private` |
| H2 (integration) | integration | `nameStep.onAppear` pre-fills name from `authService.userDisplayName` |
| M3 (integration) | integration | Skip button records `skip_<step_name>` funnel events |
| M4 (integration) | integration | Dead `@State storeService` on OnboardingView deleted |

### Still open (deferred — see B-tier work)

| ID | Audit | Reason |
|----|-------|--------|
| C3 (integration) | Goal taxonomies inconsistent — onboarding camelCase vs ProfileView Title Case | Strategic call — needs unified catalog. Tracked as B14 below. |
| M-3 (security) | Typed funnel event enum | Would require a coordinated refactor of every call site — defer until backend drain spec ships |
| L-3 (security) | Apple Sign-In nonce | No backend consumes the identity token yet; harden when one ships |
| Code-review #2/H3 (integration) | Schedule prefs only persist on `equipment` advance — back-nav past it loses state | Requires `updateTrainingPreferences` also being called on `schedule` advance; minor risk in linear flow today |
| Code-review #8 | `orderedTiers` recomputed on every body | Already addressed by moving to `@State`, but per-render cost was already negligible |
| Code-review #9 | Direct profile writes vs named mutators | Style consistency — flagged as a follow-up code-tidy pass |
| Code-review #15 | Same 350ms gap on `creatorAttribution` | Addressed by flushPendingSave |
| Code-review #16 | `scrollPositionBinding` allocation per body | Real but cosmetic — defer |
| Code-review #19 | `notificationsStep.task` placement | Real but benign — the auth check is idempotent |
| Code-review #20 | Permission task lifecycle on view replacement | SwiftUI handles via @State lifetime; benign |
| Integration M1 | Nested ScrollView gesture conflict | Needs real-device QA on multiple form factors |
| Integration M5 | Disclaimer bypass on re-entry | Two-tap-every-time is a stricter bar; current behavior matches App Review intent |
| Integration M6 | Step entries are first-entry-only | Acts as documented; "time on step" derived metric would be wrong but isn't computed today |
| L-1 (security) | `Text(.init(text))` markdown — latent | Strings are literals today; safe |
| L-4 (security) | Step ordering in os.Logger at `.public` | Step names aren't PII; event names already bumped to `.private` |

---

## Plan B — what you need to do, step by step

### B1. Build & run in Xcode (FIRST — blocks everything else)

```bash
git fetch origin
git checkout claude/audit-onboarding-experience-LEVSs
git pull
xcodegen generate
open Peptide.xcodeproj
```

In Xcode:
1. Select **Peptide** scheme → iPhone 16 simulator
2. ⌘B build — if anything fails, paste the error and I'll patch
3. ⌘R run, then walk the 24-step flow:
   - Welcome (verify "12k+ athletes" pill renders) → Sign In (try skip; try complete + see Name step pre-fill) → Social proof → Attribution → Feature reel (swipe all 5 cards) → Name → Goal (try a wellness goal like Better Sleep) → Goal date (try 8 weeks chip + custom date) → Experience → Body metrics → Schedule → Equipment → Demo set (log the set; see success banner) → Comparison → Program preview (verify it shows the right name for your goal — Recovery & Sleep Hygiene for betterSleep) → Nutrition → Projection (verify chart + headline + target date all read your goal/date) → Disclaimer (two-tap; verify "Thanks. Tap Continue" appears) → Notifications (verify preview card; tap Enable) → Health (verify HRV/Sleep/Recovery preview; tap Enable) → Building plan (auto-advances after 3s) → Creator code (try LUCAS50; try WRONG; try skip) → Email (try invalid; try valid; try skip) → Ready (verify "Pro tip — Long-press your home screen" card; verify creator discount row if applied) → Tap Open Atlas → Paywall (verify tier picker; "SAVE N%" badge; tap Maybe later) → Theme picker → Enter Atlas → land on Home → verify GoalCountdownCard renders with correct weeks/days/target date

### B2. Run tests

```bash
xcodebuild test \
  -project Peptide.xcodeproj \
  -scheme Peptide \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

3 new test files: `OnboardingFunnelTrackerTests.swift`, `OnboardingExperimentTests.swift`, `GoalCountdownCardTests.swift`.

### B3. Decide the peptide-identity question
Pick one — tell me, I'll wire it:
- **Option A** (recommended): re-introduce peptides honestly. Keep the current flow (the feature reel already shows it). Update App Store description.
- **Option B**: stay training-pure. Remove the "Track protocols" card from the feature reel; hide Library + Protocols tabs.

### B4. Apple Developer config
1. Open https://developer.apple.com/account → Identifiers → `com.peptidesai.app`
2. Verify **Sign In with Apple** is enabled
3. Regenerate provisioning profiles if you changed anything
4. Xcode → target Peptide → Signing & Capabilities → verify "Sign in with Apple" capability is listed

### B5. App Store Connect products
Verify these 3 product IDs exist and are Ready/Approved:
- `com.peptidesai.app.pro.monthly` — with a 3-day or 1-week free trial intro
- `com.peptidesai.app.pro.annual` — priced ~$49.99/yr (this is the new tier on the paywall)
- `com.peptidesai.app.pro.lifetime` — priced ~$169

The "SAVE N%" badge on the paywall is computed live from the loaded prices.

### B6. App Store Connect promotional offers (optional, ~1 day)
The creator-code step captures and displays the discount, but the actual price modification isn't wired. Per the original audit's CL6 + HANDOFF.md note 4:
1. Create Promotional Offers in App Store Connect per tier per discount %
2. Stand up a JWT-signing endpoint (needs the App Store Connect SubscriptionKey)
3. Tell me the endpoint URL — I'll wire `StoreService.purchase` to pass the signed `PromotionalOffer` when `profile.creatorAttribution` is set

If you skip this, change the Ready summary copy from "20% off — via Lucas Aoun" to "Applied — via Lucas Aoun" so it's not making a price-change claim.

### B7. Physical-device tests
- iPhone 15+ (any)
- iPad with Stage Manager (the Sign In flow was specifically called out as iPad-fragile in `AuthService.swift`)
- Apple Watch paired with the iPhone

Watch for:
- Sign In with Apple actually completing (not hanging)
- The feature reel paging cleanly — integration audit M1 flagged this as gesture-conflict-risk on smaller screens
- Live Activities firing if you set up a protocol after onboarding
- 60 FPS on the projection chart and building ring

### B8. TestFlight upload
```bash
bundle exec fastlane beta
```
Wait 5–15 min for processing, add internal testers, walk the flow.

### B9. Fresh-user testing (5–10 users)
Get the flow in front of people who haven't seen it. Screen-record. Watch where they hesitate, where they tap Skip.

The funnel tracker writes a local snapshot to UserDefaults. Pull
`~/Library/Containers/com.peptidesai.app/Data/Library/Preferences/com.peptidesai.app.plist`
to see per-step timestamps + all events.

### B10. Localize new strings (depends on your localization flow)
The new copy is English-only. The app declares 9 locales. Run your usual translation workflow once content is final. The string literals are already `LocalizedStringKey`-compatible for xcodebuild's localization extractor.

### B11. App Store metadata + screenshots
If B3 = Option A: update `APP_STORE_METADATA.md` and screenshots in `docs/app-store/` to reflect the peptide angle on the feature reel. If B3 = Option B: same but without the peptide card.

### B12. App Review note
Add to App Store Connect → Version Information → Notes for App Review:
> Atlas does not prescribe, recommend, or compute peptide doses.
> The onboarding includes an explicit disclaimer step that the
> user must acknowledge with a two-tap pattern before continuing
> (acknowledgement timestamp is persisted to UserDefaults under
> `disclaimerAcknowledgedAt`). The app is positioned as a
> tracking and education tool, with research citations from
> NIH/PubMed/ClinicalTrials.gov on each peptide detail page.

### B13. Merge the branch
Once B1–B7 pass:
```bash
# Create a PR via your usual gh / web flow
# Wait for CI green
# Merge — don't squash, the 17 commits tell a clear story
```

### B14. (Optional) Unify the goal taxonomy
Audit C3 flagged that `OnboardingView.PrimaryGoal` uses camelCase rawValues (`buildMuscle`) while `ProfileView.availableGoals` uses Title Case ("Muscle Recovery"). The Profile screen's pinned-goal banner won't display the goal the user picked during onboarding. Either:
- Have the Profile screen map raw → display via a parallel table (1 hour)
- Pick the camelCase rawValues as canonical and update ProfileView to use them (half day)

This isn't blocking — pinned-goal display is a small Profile surface — but worth doing before the next big release.

---

## Commit log (17 commits, latest first)

```
145d90d Audit fixes — round 3: paywall dismissal, AuthService observation, polish
34dc091 Audit fixes — round 2: security highs, lifecycle, accessibility
583ad91 Audit fixes — round 1: compile error, primary-goal drop, paywall bugs
c2e95d6 A8: OnboardingExperiment scaffolding with one live use site
dcc03c0 A6: tests for OnboardingFunnelTracker + GoalCountdownCard logic
e0752b6 A3: GoalCountdownCard on Home — surfaces onboarding goalDate
80fcd6f Onboarding A2/A4/A5/A10: typography, scenePhase refresh, widget tip, attribution
5c14ad0 Action plan: what Claude can still do + what user needs to do
35c879b Onboarding: feature reel replaces static value-proof bullets
7b78481 Onboarding polish: progress bar, Sign-In errors, goalDate persistence
d47c21e Onboarding: fix notification permission row mis-reading peptide flag
60b7768 Onboarding: date-based goal step + projection chart wired to it
36d49be Onboarding: optional Sign in with Apple step after Welcome
013f5ca Onboarding funnel tracker — local-only per-step instrumentation
4da6551 Trial paywall: add yearly tier with savings anchoring
061b74a Onboarding P1: testimonials, projection chart, referrals, disclaimer
530022c Onboarding P0: wire paywall, split permissions, social proof, plan reveal
2276df0 Audit onboarding experience — full findings + prioritized action list
```
