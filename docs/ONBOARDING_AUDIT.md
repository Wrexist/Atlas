# Atlas / PeptideX Onboarding Audit

Branch: `claude/audit-onboarding-experience-LEVSs`

A complete audit of the new-user onboarding experience and a prioritized
list of everything to change to make it genuinely best-in-class. Three
independent audit passes were combined: structural flow, missing app
features, and conversion patterns vs. leading iOS health/fitness apps.

---

## TL;DR — the five things bleeding the most value

1. **There is no paywall in onboarding.** `TrialOfferView.swift` is a
   polished, animated, StoreKit-wired 3-day-trial paywall and the flow
   never instantiates it. `OnboardingView.swift:253-255` simply sets
   `hasCompleted = true` and dumps users into the app for free. Single
   biggest revenue leak in the codebase.
2. **~10 finished onboarding components are dead code.** `TrialOfferView`,
   `ReviewPromptPage`, `RecommendationsPage`, `EmailCapturePage`,
   `CreatorAttributionPage`, `ThemeChoicePage`, `AddMedicationPreviewPage`,
   `ConsistencyChart`, `NotificationPreviewCard`, `WelcomeFeatureBadge` —
   all built, all unused. The 17-page flow described in `HANDOFF.md`
   covered all of these; the training pivot rewrote the flow and forgot
   to re-attach them.
3. **The brand identity is incoherent.** README/CLAUDE.md/ROADMAP/HANDOFF
   describe a peptide protocol tracker; onboarding sells "Train. Eat.
   Recover." with zero mention of peptides, vials, doses, or stacks.
   New users finish onboarding then land on Library/Protocols/Biology
   tabs that they were never told existed.
4. **No social proof, no projection moment, no "wow" calculation.** No
   testimonials, no "10k+ users", no Apple-Health-unlocks-this preview,
   no "by Aug 12 you'll be at 180 lb" projection chart (Cal AI's
   signature). The entire flow asks but never gives.
5. **Permissions are blunt system prompts.** No notification preview
   before the OS dialog; no Health-data preview explaining what
   Recovery / HRV / Bio Age unlocks. Industry best-practice doubles
   permission grant-rate by previewing value first.

---

## Current 14-page flow (what ships today)

`Peptide/Features/Onboarding/OnboardingView.swift` (1106 lines)

| # | Step | Notes |
|---|------|-------|
| 0 | Welcome | "Train. Eat. Recover." — contradicts the actual app (no Eat/Recover tabs) |
| 1 | Value proof | 4 generic bullets, no imagery, no social proof |
| 2 | Name | Single text field |
| 3 | Primary goal | 6 training-only goals — no sleep, recovery, anti-aging, GLP-1 fat loss, hair/skin |
| 4 | Experience | beginner / intermediate / advanced |
| 5 | Body metrics | height + weight + age + sex on one scroll |
| 6 | Schedule | days per week + day picker + time slot |
| 7 | Equipment | grid of gear types |
| 8 | "Try a set" demo | Strongest screen — emotional peak, then squandered |
| 9 | With/Without Atlas comparison | Anticlimactic after the demo |
| 10 | Program preview | Names like "5/3/1" / "PPL" — no proof these `Program` objects exist in the codebase |
| 11 | Nutrition targets | DailyTargetsPage computed from body metrics |
| 12 | Permissions | Health + Notifications, raw system prompts, no previews |
| 13 | Ready | Summary, then **straight into the app — no paywall** |

---

## Critical gaps (must-fix to compete)

### C1. Wire the paywall

**File:** `OnboardingView.swift:253-255` and `Components/TrialOfferView.swift`

`TrialOfferView` already does StoreKit, intro-offer detection, error
handling, animated sparkles, terms/privacy links. Wire it as a full-
screen cover after `readyStep` so the first session monetizes. Without
this, monetization depends entirely on a post-onboarding upsell that
50%+ of users will never see.

Suggested copy variant for an audience this opinionated: "Start your
3-day free trial. Then $9.99/mo." Anchor against annual ($49.99 = ~58%
saving) and lifetime ($169) tiers — `TrialOfferView` currently only
shows monthly, missing the anchoring lift.

### C2. Resolve the peptide vs training identity gap

**Files:** `OnboardingView.swift:6-11` (intentional comment), `README.md`,
`CLAUDE.md`, `Features/Library/`, `Features/Protocols/`,
`Features/Biology/`, `Features/Labs/`

Either:
- **(A) Re-introduce peptides honestly.** Add one teaser slide between
  Goal and Experience: "Atlas also tracks peptide cycles, bloodwork, and
  bio-age. Tap to enable." Cheap to add, preserves the training-first
  feel, surfaces the half of the app that's currently undiscoverable.
  Recommended.
- **(B) Stay training-pure.** Hide Library/Protocols/Biology/Labs/
  CommunityStacks behind a "More" tab or settings toggle. Trim the
  bundled peptide DB from the default install. Hostile to existing
  brand recognition; only do this if you're rebranding fully.

The status quo (peptide tracker that hides peptides from new users)
orphans ~60% of the shipped feature surface.

### C3. Social proof anywhere in the flow

**File:** `Components/ReviewPromptPage.swift` (unused) — has "+10,000
users" pill + two starred testimonials.

Add as a screen between Welcome (0) and Name (2), OR collapse a 1-line
proof strip ("★★★★★ 4.9 · 12k+ lifters") under the welcome headline
at `OnboardingView.swift:294`.

### C4. Medical/safety disclaimer step

App handles injectable peptides. `RecommendationsPage.swift:72-94` has
the "Atlas does not recommend, prescribe, or calculate doses" notice
baked in. Surface this once during onboarding — table-stakes for App
Review and for trust.

### C5. Sign in with Apple

**Files:** none exist for this; ROADMAP v2.0 item 4.3 plans it.

Without an account there's no cloud sync, no referrals, no abandoned-
onboarding retargeting, no email recovery. Even a single "Continue with
Apple" tap after Welcome unlocks all of these later. Industry standard
for any subscription health app.

---

## Conversion losses (revenue impact)

### CL1. Notification permission has no preview

`OnboardingView.swift:1049-1059`. `NotificationPreviewCard.swift` is a
ready-made lock-screen mock for exactly this purpose. Add a screen
showing the mock notification first, then the OS dialog on the next
tap. Bumps grant-rate ~20-30% on every comparable app.

### CL2. Health permission has no value preview

`OnboardingView.swift:969-975` says "enrich your insights" — vague.
Should preview the Recovery ring, HRV trend chart, and Bio Age dial
that HealthKit data unlocks.

### CL3. No personalized projection moment

You collect height/weight/goal/days-per-week but never show a
projection ("by Aug 12 you'll be at 180 lb" / "+4 lb muscle in 12
weeks"). Cal AI / Macrofactor / Rise all insert this chart immediately
before the paywall — it's their #1 conversion lever. Atlas has Swift
Charts already in the codebase.

### CL4. No "Calculating your plan…" loading screen

A 2–4 second animated "personalizing your plan" reveal manufactures
perceived value. Headspace, Cal AI, Rise all use it. Atlas jumps
straight from equipment into the demo with zero theater.

### CL5. No price anchoring

`TrialOfferView.swift:118-120` only shows monthly ($9.99). Show annual
($49.99 ≈ 58% off) and lifetime ($169) tiers with "MOST POPULAR" on
annual. Industry standard is to anchor the higher price first.

### CL6. No scarcity / urgency / creator code

`Components/CreatorAttributionPage.swift` (referral code) ships,
applies a discount, and is **unused**. Wire it before the paywall so a
pre-applied "MARCUS50" code creates urgency on the trial CTA.

### CL7. No email capture for retargeting

`Components/EmailCapturePage.swift` ships and is unused. ~40-60% of
users decline the trial — capture their email before the paywall so
declines still leave a hook for Resend/Loops retargeting.

### CL8. Skip button on every middle page

`OnboardingView.swift:180-187`. Skipping personalization steps poisons
the recommendation engine and removes the sunk-cost commitment that
drives trial conversion. Remove skip on pages 3–7.

### CL9. Goal list is training-only

`OnboardingView.swift:44-77`. For a peptide tracker, missing: better
sleep, fat loss with GLP-1, recovery from injury (BPC-157), anti-
aging, hair/skin (GHK-Cu). Filters the persona to gym bros and loses
the actual buyer.

### CL10. Demo set → comparison → preview → nutrition → permissions

`OnboardingView.swift:115-129`. Five momentum-killers between the
emotional peak (demo) and the paywall. Move the paywall to fire ~1
screen after the demo while the dopamine is hot.

### CL11. No per-step analytics

`hasCompletedOnboarding` is the only completion signal. No
drop-off events per page, so you'll never know where users churn. Even
local-only counters or a `OnboardingFunnelTracker` service would help.

---

## Major app features not introduced in onboarding

A new user finishes onboarding having heard nothing about:

| Feature | File / Service | Why it matters | Suggested onboarding slot |
|---|---|---|---|
| **Peptide library (208 entries)** | `Features/Library/`, `Features/Database/PeptideListView.swift` | Half the product is invisible | Teaser slide after Goal |
| **Meal scanner (Claude vision + barcode)** | `Services/MealScannerService.swift`, `Services/OpenFoodFactsService.swift` | Single most impressive demo in the app | Second interactive demo after the set demo |
| **AI Research chat** | `Features/AIResearch/AIResearchView.swift` | Differentiated; grounded in 208-entry DB | Bullet on value-proof slide |
| **Biology tab / Bio Age** | `Features/Biology/BiologyView.swift`, `Services/BioAgeStateResolver.swift` | Marquee Pro differentiator (ROADMAP v1.3) | Bundle into Health permission ask |
| **Labs OCR ingestion** | `Features/Labs/LabsView.swift` | Snap a bloodwork PDF → Claude extracts markers | Bullet on Biology teaser |
| **Weekly Summary / Insights** | `Services/WeeklySummaryEngine.swift`, `Features/Insights/InsightsView.swift` | Strongest re-engagement loop | Promise during notification opt-in |
| **Apple Watch app** | `PeptideWatch/` | Accessory installs | One-line on Ready |
| **iOS Widgets + Live Activities** | `PeptideWidgets/`, `Shared/DoseWindowAttributes.swift` | Daily-screen real estate | Post-paywall "add widget" deeplink |
| **Achievements (14)** | `Services/AchievementService.swift` | Already mentioned via "celebrate every PR" — sufficient | Keep as-is |
| **Siri shortcuts** | `Intents/PeptideIntents.swift` | "Log my BPC-157" / "What are my macros today?" | Tip card on Ready |
| **Face ID lock** | `Features/Auth/LockScreenView.swift` | Trust anchor for sensitive data | One line near Health permission |
| **Cycle share cards** | `Features/Sharing/CycleCardView.swift` | Re-engagement feature, not a value proof | Skip in onboarding |
| **Smart Cycle Planner** | `Services/SmartCyclePlanner.swift` | Peptide-specific, invisible-quality | Skip in onboarding |
| **Recovery score + Health Monitor** | `Services/RecoveryScoreEngine.swift` | Powers HRV/RHR/Sleep cards | Bundle into Health ask |

---

## UX / polish issues

| # | Issue | Location |
|---|------|----------|
| U1 | Identical font treatment across pages 2,3,4,6,7,10,11 — habituation by page 5 | `OnboardingView.swift` `.system(size: 32, …)` repeated |
| U2 | Body metrics on one big scroll is overwhelming | `OnboardingView.swift:514-520` |
| U3 | Progress dots are functional but cold; no "you're 80% there" counter | `OnboardingView.swift:162-171` |
| U4 | `primaryEnabled` only blocks empty name — user can blow through every other page | `OnboardingView.swift:223-228` |
| U5 | `requestingNotifications` re-uses `doseRemindersEnabled` as the "is on" check — wrong semantic (that flag is for peptide protocol reminders) | `OnboardingView.swift:981` |
| U6 | Welcome is static — no looping hero video / animated reel / App-Store-preview hook | `OnboardingView.swift:283-308` |
| U7 | "Open Atlas" CTA on Ready jumps cold to tab bar — no celebration moment | `OnboardingView.swift:218-219` |
| U8 | No theme picker — users get dark mode forced | `Components/ThemeChoicePage.swift` unused |
| U9 | `recommendedProgramName` returns names ("5/3/1", "PPL") that likely don't exist as actual `Program` entities — unbacked promise | `OnboardingView.swift:900-915` |
| U10 | Permissions step lumps Health + Notifications on one screen — split for higher grant rates | `OnboardingView.swift:967-984` |

---

## Modern best-practice patterns Atlas is missing

Patterns from Cal AI, Rise, Stoic, Finch, Headspace, Strong, Hevy,
Macrofactor, Streaks, Opal, Endel:

1. **Personalized projection chart** — Cal AI's #1 conversion lever
2. **"Calculating your plan…" loading screen** — Headspace / Rise
3. **Two-step notification permission** with preview — Hevy / Streaks
4. **Reverse trial** (start as Pro, downgrade) — Finch
5. **Commitment ritual** ("Promise to yourself") — Finch / Stoic
6. **Date-based goal screen** ("Hit X by [date]") — Macrofactor
7. **"How did you hear about us?" attribution survey** — Cal AI / Opal
8. **Sign in with Apple before paywall** — every subscription app
9. **Apple Editor's Choice / App-of-the-Day badge** — when earned
10. **Widget add-deeplink mid-onboarding** — Streaks / Opal
11. **Looping hero video on welcome** — Calm / Headspace
12. **Scrollable feature reel** as Step 1.5 — Hevy / Strong
13. **Personalized paywall copy** ("Because you train 5×/week and want
    to lose 15 lb…") instead of generic "3 days free"
14. **18–20 personalization questions** — current Atlas asks 8 input
    screens; more questions = higher completion bias = higher trial-
    start rate (counterintuitive but empirically robust up to ~25)
15. **Trial reminder priming** ("We'll remind you 1 day before charge")
    — boosts trust + sometimes reduces fraud chargebacks

---

## Recommended 9-step compressed flow (matches ROADMAP item 5.2)

Goal: ≤9 screens, paywall fires while emotional momentum is hot.

1. **Welcome** — looping hero reel, social-proof strip under headline
2. **What you'll unlock** — scrollable feature reel; peptide angle
   surfaced honestly (one slide for Train, one for Track peptides,
   one for Biology/Labs, one for AI)
3. **Sign in with Apple** (optional skip)
4. **Personalization batch** — combined name + goal (expanded list incl.
   peptide-relevant goals) + body snapshot, paginated within one
   "Tell us about you" container with internal progress
5. **Interactive demo** — "log a set" OR "log a dose" depending on
   whether user opted into peptide track
6. **Permissions, two screens**:
   - 6a. Notification preview (`NotificationPreviewCard`) → OS prompt
   - 6b. Health value preview (Recovery ring mock) → OS prompt
7. **"Building your plan…"** — 3s animated calculation screen
8. **Personalized projection + plan summary** — chart + creator code
   field + email capture
9. **Paywall** (`TrialOfferView` wired with annual/monthly/lifetime
   tiers) → theme picker (`ThemeChoicePage`) → enter app with
   celebration

Items to defer to post-onboarding (surface as Today-screen "finish
setting up" card):
- Schedule (days per week / time of day)
- Equipment access
- Daily nutrition targets fine-tuning

---

## Prioritized action list

### P0 — ship this week (highest ROI per hour)

1. **Wire `TrialOfferView` as the post-Ready step.** ~2 hours.
2. **Add `NotificationPreviewCard` step before the OS notification
   prompt.** ~1 hour.
3. **Add a 3-second "Building your plan…" loading screen** before
   Ready. ~2 hours.
4. **Remove the Skip button on personalization pages (3–7).** ~15 min.
5. **Add social-proof strip** under Welcome headline. ~30 min.
6. **Split the Permissions step** into two screens with value
   previews. ~1 hour.

### P1 — ship this sprint (multi-day investments with clear ROI)

7. **Wire `ReviewPromptPage`** between Welcome and Name. ~1 hour
   (already built).
8. **Wire `CreatorAttributionPage`** before paywall. ~1 hour.
9. **Wire `EmailCapturePage`** before paywall. ~1 hour.
10. **Wire `ThemeChoicePage`** post-paywall. ~30 min.
11. **Add personalized projection chart screen** (Swift Charts) using
    `bodyMetrics` + `primaryGoal` + `daysPerWeek`. ~1 day.
12. **Expand `PrimaryGoal` enum** to include sleep, recovery, fat-loss
    with GLP-1, anti-aging, hair/skin. ~1 hour + copy.
13. **Add medical/safety disclaimer step.** ~30 min.
14. **Annual + lifetime tiers visible on `TrialOfferView`** with
    "MOST POPULAR" anchoring. ~3 hours.
15. **Add Sign in with Apple step.** ~1 day (Keychain identifier
    persistence).

### P2 — ship this quarter (strategic positioning)

16. **Resolve peptide vs training identity** — pick (A) or (B) from
    C2 above. Affects copy, tab bar, App Store positioning.
17. **Per-step funnel analytics** — `OnboardingFunnelTracker` service
    writing per-screen entry/exit events, optionally proxied through
    the existing Vercel function. ~1 day.
18. **Scrollable feature reel** as Step 2. ~2 days.
19. **Date-based goal screen** ("Hit X by [date]") feeding the
    projection chart. ~1 day.
20. **Looping hero video on Welcome.** ~2 days (asset + plumbing).
21. **Widget recommendation deeplink** post-paywall. ~half day.
22. **Trial reminder priming copy + a real local-notif schedule** 1
    day before the trial converts. ~half day.

### P3 — backlog / nice-to-have

23. **Reverse trial experiment** (start as Pro, downgrade at end of
    trial).
24. **"How did you hear about us?" attribution survey.**
25. **Commitment ritual screen** ("Promise to yourself" — Finch
    pattern).
26. **A/B test framework** for onboarding copy and step ordering.

---

## Files referenced

- `Peptide/Features/Onboarding/OnboardingView.swift` (main flow)
- `Peptide/Features/Onboarding/Components/TrialOfferView.swift` (unused)
- `Peptide/Features/Onboarding/Components/ReviewPromptPage.swift` (unused)
- `Peptide/Features/Onboarding/Components/RecommendationsPage.swift` (unused)
- `Peptide/Features/Onboarding/Components/EmailCapturePage.swift` (unused)
- `Peptide/Features/Onboarding/Components/CreatorAttributionPage.swift` (unused)
- `Peptide/Features/Onboarding/Components/ThemeChoicePage.swift` (unused)
- `Peptide/Features/Onboarding/Components/AddMedicationPreviewPage.swift` (unused)
- `Peptide/Features/Onboarding/Components/ConsistencyChart.swift` (unused)
- `Peptide/Features/Onboarding/Components/NotificationPreviewCard.swift` (unused)
- `Peptide/Features/Onboarding/Components/WelcomeFeatureBadge.swift` (unused)
- `Peptide/Features/Profile/Components/PaywallView.swift` (used post-onboarding only)
- `Peptide/App/PeptideApp.swift:60-66` (onboarding entry point)
- `Peptide/Services/StoreService.swift`
- `Peptide/Services/WhatsNewService.swift`
- `ROADMAP.md` items 5.2 and 5.3
- `HANDOFF.md` (describes the older 17-page flow with paywall)
