# App Store Connect — Atlas v1.0.0

> **Rebrand note.** Bundle ID and StoreKit product IDs keep the legacy
> `com.peptidesai.app` prefix so existing TestFlight history and
> subscriber records stay intact. Every user-visible string uses **Atlas**.

---

## App Information

| Field | Value |
|---|---|
| **App Name** | `Atlas: Fitness & Recovery` *(25 / 30)* |
| **Subtitle** | `Workout Log, Macros & Habits` *(28 / 30)* |
| **Primary Category** | Health & Fitness |
| **Secondary Category** | Sports |
| **Bundle ID** | `com.peptidesai.app` |
| **SKU** | `peptidex-ios-1` |
| **Primary Language** | English (U.S.) |

> **Why this name + subtitle combination:**
> Apple's algorithm treats the Name and Subtitle fields as searchable.
> "Atlas: Fitness & Recovery" captures *fitness* and *recovery* — two
> high-volume, conversion-intent terms. The subtitle adds *workout log*
> (a high-intent compound phrase), *macros*, and *habits* — covering
> training, nutrition, and behavior tracking without any overlap.
> The keyword field then fills in terms not already covered.

---

## URLs

> Deploy GitHub Pages before submitting — App Store Connect validates
> the Privacy Policy URL at submission time.
>
> The `docs/` folder ships pure static HTML (no Jekyll, no build step).
> A `.nojekyll` file disables Jekyll preprocessing so files are served
> byte-for-byte. URLs include `.html` exactly as given below.

| Field | Value |
|---|---|
| Marketing URL | `https://wrexist.github.io/Peptide-ai/` |
| Privacy Policy URL | `https://wrexist.github.io/Peptide-ai/privacy.html` |
| Support URL | `https://wrexist.github.io/Peptide-ai/support.html` |

```bash
# Verify before submitting — each must return HTTP/2 200
curl -sI https://wrexist.github.io/Peptide-ai/             | head -1
curl -sI https://wrexist.github.io/Peptide-ai/privacy.html | head -1
curl -sI https://wrexist.github.io/Peptide-ai/support.html | head -1
```

---

## Promotional Text *(170 chars — update anytime without a new build)*

```
Free to start. Log workouts in 2 taps, scan meals by photo, and wake up to a
Recovery Score built from your HRV and sleep. No ads. No tracking.
```
*(147 / 170)*

> Swap this out for launch events, seasonal campaigns, or new-feature
> announcements without needing a build review. Keep the hook punchy
> and lead with a free-tier action so the preview isn't gated.

---

## Keywords *(100 char limit — comma-separated, NO spaces after commas)*

```
calorie counter,gym,nutrition,hrv,sleep,supplement,peptide,strength,protein,food,biohacker
```
*(90 / 100)*

> **ASO rationale — no keyword is wasted:**
> The Name field already indexes *atlas*, *fitness*, *recovery*.
> The Subtitle field already indexes *workout*, *log*, *macros*, *habits*.
> The keyword field adds ten distinct search intents that are NOT
> covered above:
>
> | Term | Why it's here |
> |---|---|
> | `calorie counter` | Top-5 most-searched nutrition term on App Store |
> | `gym` | Highest-volume single-word fitness intent |
> | `nutrition` | Broad nutrition discovery (distinct from *macros*) |
> | `hrv` | High-intent recovery/biohacker audience; low competition |
> | `sleep` | Cross-sell from Sleep category searches |
> | `supplement` | Bridges general supplement trackers to the protocol feature |
> | `peptide` | Exact-match for the advanced audience; near-zero competition |
> | `strength` | Differentiates from cardio/yoga apps; weight-training intent |
> | `protein` | High-volume macro-tracking sub-term |
> | `food` | Catches food-diary and food-log queries |
> | `biohacker` | Premium niche; converts at high rate for Pro tier |

---

## Description *(4000 char limit)*

```
Log every set in 2 taps. Snap a photo and Atlas logs the meal. Wake up
to a Recovery Score built from your HRV, sleep, and resting heart rate.

All on your device. No account required. No ads. No tracking.

——

WORKOUTS
Atlas pre-fills your last weight and reps — confirm or adjust and move on.
Rest timer fires automatically and sends a Lock Screen alert when you're ready.
• 200+ exercises plus unlimited custom lifts
• Automatic PR detection — weight, rep, and bodyweight records
• Rest timer with Lock Screen notification
• Weekly muscle volume heatmap by muscle group
• Full workout history with month-grouped browsing and set detail

——

NUTRITION
Snap a photo and Atlas identifies the food. Scan a barcode from 200 million+
products. Either way, macros are logged in seconds.
• AI photo meal scanner — photo analyzed and deleted immediately
• 200M+ product barcode database (Open Food Facts)
• Daily calorie and macro rings with TDEE-based targets
• Custom food library and recipe tracking
• Optional one-way sync to Apple Health

——

RECOVERY
HRV, resting heart rate, and sleep — pulled from Apple Health every morning
and blended into a single Recovery Score. Know whether to push or pull back
before you leave the house.
• Daily Recovery Score (HRV + resting HR + sleep)
• Performance Age metric
• Biomarker trending: weight, body fat, waist, blood pressure
• Lab value tracking: testosterone, vitamin D, lipids, custom panels
• Full Apple Health integration

——

HABITS
Track any daily routine with a 6-month momentum heatmap. Set daily, weekday,
or X-per-week schedules — optional reminders fire on the days they're due.

——

PEPTIDE PROTOCOL TRACKING  (Advanced)
For users following clinician-advised protocols. 208-compound research
database with citations, dose logging, cycle calendar, and community stacks.
• 208 peptides with research citations across 6 categories
• Up to 3 active protocols (free) — unlimited with Atlas Pro
• Dose logging with site, time, and notes
• Community stacks — browse, import, and share protocols

Atlas does not prescribe, recommend, or calculate doses for any compound.
Research and self-tracking only. Medical disclaimer required at first launch.

——

ATLAS PRO
• Unlimited active protocols
• Full Biology tab — body composition + lab panels
• AI Research assistant (RAG-backed peptide database chat)
• Cloud sync across all your devices via iCloud
• Apple Watch companion app
• All Home Screen widgets + Live Activities (Dynamic Island)
• Full data export (CSV and JSON)

Monthly $9.99 · Annual $49.99 (save 58%) · Lifetime $169
Free trial: 3 days (monthly) · 14 days (annual) · Cancel anytime

——

PRIVATE BY DEFAULT
• Zero analytics, trackers, or third-party SDKs
• All data on-device or in your private iCloud — we cannot see it
• No account required — every feature works without signing in
• Privacy manifest: NSPrivacyTracking = false, zero collected data types

——

MEDICAL DISCLAIMER
Atlas is an educational reference and personal tracking journal. It is not a
medical device and does not provide medical advice, diagnose conditions,
recommend doses, or replace a clinician. Always consult a licensed healthcare
provider before starting, changing, or stopping any training, nutrition,
supplement, or peptide protocol.
```

*(3 198 / 4 000 — 802 chars of headroom for future localisation or feature additions)*

---

## "What's New" *(4000 char limit)*

```
PeptideX is now Atlas — rebuilt into a complete health & fitness app.

Everything you used for protocol tracking is still here. On top of it we added training, nutrition, recovery, and a daily momentum system that ties it all together — five tabs in one private app. No backend, no analytics. Your data stays on your device.

——

TRAIN — NEW
Log a set in two taps. Atlas pre-fills your last weight and reps; confirm or adjust and move on. The rest timer fires automatically and drops a Lock Screen alert when you're ready.
• 873-exercise library plus unlimited custom lifts
• Automatic PR detection — weight, rep, and bodyweight records
• Weekly muscle-volume heatmap
• Full history — tap any session for every set, the muscle map, and every PR you hit

——

MEALS — NEW
Three ways to log, all fast. Snap a photo and Atlas identifies each item separately — adjust portions, drop a misfire, save to your library. Scan a barcode from 200M+ products. Or point the camera at a nutrition label and Atlas reads it on-device.
• Daily calorie + macro rings with goal-aware targets
• One-tap "Recommended for you" targets with a live macro preview
• Custom food library and recipes
• Optional one-way sync to Apple Health

——

BIOLOGY — NEW
HRV, resting heart rate, and sleep pulled from Apple Health each morning and blended into one Recovery Score — know whether to push or pull back before you leave the house.
• Biological Age dial (Atlas Pro)
• Biomarker trends: weight, body fat, waist, blood pressure
• Lab tracking: testosterone, vitamin D, lipids, custom panels

——

HABITS — NEW
Track any routine on a 6-month momentum heatmap. Daily, weekday, or X-per-week schedules with reminders on the days they're due. Streak-freeze shields one missed day a month so a single slip doesn't reset you.

——

ATLAS SCORE — NEW
One number for your momentum. Every habit, dose, and meal you log earns points that build your level and tier, Bronze to Diamond. See it on Today, your Profile, and your Apple Watch.

PROGRESS — NEW
Your score trend, current vs. best streaks, and 30-day consistency — framed so you watch the line climb.

ACHIEVEMENTS — NEW
First PR, Perfect Week, dose milestones and more — celebrated the moment you earn them.

——

ALSO NEW
• Rebuilt onboarding with a live workout demo
• Today timeline — doses, meals, check-ins, and workouts in one feed
• Apple Watch complications for Atlas Score and your health & training habits
• Home Screen widgets + Live Activities in the Dynamic Island
• AI Research assistant and AI Weekly Summary (Atlas Pro)

——

PROTOCOL TRACKING (Advanced)
The peptide tools you know, refined: a 208-compound research database with citations, dose logging, a cycle calendar, dose edit/delete, and community stacks. Atlas does not prescribe or recommend doses — research and self-tracking only.

——

STABILITY
Fixes iCloud sync (it was silently falling back to local-only storage), dose duplication on schedule edits, expired Pro entitlements staying active, and achievement toasts dismissing before you saw them — plus a deep correctness and performance pass throughout.

——

PRIVATE BY DEFAULT
No backend. No analytics. No third-party SDKs. Data lives on-device or in your private iCloud — we can't see it. No account required.

Atlas is an educational reference and tracking journal, not medical advice. Always consult a licensed healthcare provider before changing any training, nutrition, supplement, or protocol.

Feedback → support@peptidesai.com
```

*(3 588 / 4 000)*

---

## Age Rating

**Recommended: 17+**

| Question | Answer |
|---|---|
| Unrestricted Web Access | No |
| Gambling | No |
| Contests | No |
| Medical / Treatment Information | **Frequent / Intense** |
| Drug, Alcohol, or Tobacco References | **Infrequent / Mild** |
| Sexual Content, Nudity, Violence, Profanity, Horror | None |
| User-Generated Content | No |

> 17+ is the correct and expected rating for a protocol-tracking app.
> Setting it accurately prevents back-and-forth with App Review and
> signals transparency. Do not attempt to rate it lower.

---

## App Privacy (Privacy Nutrition Label)

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No** |
| Tracking (ATT)? | **No** |

No data categories need to be disclosed. If App Review questions the
HealthKit entitlement: HealthKit data is read and used on-device only —
not transmitted, not linked to an identity, not used for tracking.

### Before configuring any data drain in a shipped build

The dormant drains (`AffiliateIntakeEndpoint`, `OnboardingFunnelEndpoint`
in Info.plist) are host-allowlisted and consent-gated in code, but the
"No data collected" answers above are only true while those keys stay
unset. A build that sets either key MUST first:

1. Update this nutrition label — affiliate intake collects **Name,
   Email Address, Other User Content** (linked to user, App
   Functionality); the funnel drain collects **Product Interaction**
   (not linked, Analytics).
2. Update the `PrivacyInfo.xcprivacy` collected-data-types arrays.
3. Update `PrivacySummaryView` ("no backend / data never leaves your
   phone" claims) and the screenshot deck slot that renders it.
4. Update `docs/privacy.html`.

### Privacy manifest coverage

| Target | File | Declared Required-Reason API |
|---|---|---|
| Peptide (main app) | `Peptide/Resources/PrivacyInfo.xcprivacy` | `UserDefaults` → reason `CA92.1` (same-app access) |
| PeptideWidgets | `PeptideWidgets/PrivacyInfo.xcprivacy` | None — file I/O via App Group only |
| PeptideWatch | `PeptideWatch/PrivacyInfo.xcprivacy` | None — file I/O via App Group only |

Re-audit before each release if new persistence, file I/O, or
performance-monitoring code lands.

---

## Export Compliance

`ITSAppUsesNonExemptEncryption = false` is set in `project.yml`.
No further export-compliance questions will be asked.

---

## Subscriptions (In-App Purchases)

| Product | Product ID | Type | Price | Trial |
|---|---|---|---|---|
| Atlas Pro Monthly | `com.peptidesai.app.pro.monthly` | Auto-Renewable | $9.99 / mo | 3 days |
| Atlas Pro Annual | `com.peptidesai.app.pro.annual` | Auto-Renewable | $49.99 / yr | 14 days |
| Atlas Pro Lifetime | `com.peptidesai.app.pro.lifetime` | Non-Consumable | $169.00 | — |

**Subscription group name:** `Atlas Pro`

> Product IDs keep the `com.peptidesai.app` prefix so existing
> subscribers and StoreKit sandbox history are not disrupted.
> Only the display names switch from "PeptideX Pro" to "Atlas Pro".

### Localization copy

**Atlas Pro Monthly**
- Display Name: `Atlas Pro Monthly`
- Description: `Unlimited protocols, full Biology tab (body composition + lab panels), AI Research assistant, Apple Watch, all widgets, and full data export. Renews monthly — cancel anytime in your Apple ID settings.`

**Atlas Pro Annual**
- Display Name: `Atlas Pro Annual`
- Description: `Everything in Atlas Pro for a full year. Unlimited protocols, full Biology, AI Research assistant, Apple Watch, all widgets, full data export. Best value — save 58% vs. monthly.`

**Atlas Pro Lifetime** *(Non-Consumable IAP, not a subscription)*
- Display Name: `Atlas Pro Lifetime`
- Description: `One-time purchase. Unlock Atlas Pro forever — unlimited protocols, full Biology, AI Research assistant, Apple Watch, all widgets, and full data export. No subscription, no renewals.`

---

## Screenshots

> A dedicated Claude prompt for generating polished screenshot mockups is in
> `SCREENSHOT_PROMPT.md`. Paste it into Claude.ai to get a full HTML/CSS
> mockup for each of the 8 slots below.

### Device sizes required

| Device class | Canvas size | Notes |
|---|---|---|
| **iPhone 6.9"** (16 Pro Max) | **1320 × 2868 px** | Required — primary set |
| iPhone 6.5" (11 Pro Max) | 1242 × 2688 px | Optional legacy fallback |
| **iPad Pro 13"** (M4) | **2064 × 2752 px** | Required if iPad-targeted |

Capture with: `xcrun simctl io booted screenshot ~/Desktop/ss-01.png`
or Xcode Device toolbar → Screenshot button on a physical device.

### Overlay anatomy (apply to every screenshot)

```
┌─────────────────────────────────┐
│                                 │
│   [STATUS BAR — real or fake]   │
│                                 │
│   ┌─────────────────────────┐   │
│   │                         │   │
│   │    ACTUAL APP UI        │   │  ← 75–80% of frame height
│   │   (populated with       │   │
│   │    realistic data)      │   │
│   │                         │   │
│   └─────────────────────────┘   │
│                                 │
│   HEADLINE TEXT                 │  ← 32–36pt bold, white
│   Sub-caption line              │  ← 18–20pt regular, 70% white
│   [ATLAS PRO badge if gated]    │  ← pill: accent colour, 14pt
│                                 │
└─────────────────────────────────┘
```

Background: deep charcoal (`#0D0D12`) or the app's own dark gradient.
Font: SF Pro Display (or close equivalent in mockup tools).
Pro badge pill: `#7B5CFF` background, white text, 6pt corner radius.

---

### Screenshot 1 — Today / Recovery Dashboard  *(FREE)*

**What to show**
Today tab fully loaded. Large Recovery Score ring at 78% (green), three
stat tiles below it: HRV 62 ms · RHR 54 bpm · Sleep 7.4 h. Below that,
a workout card ("Push Day · 6 exercises") and a macro ring (1,840 / 2,400
kcal). Status bar: 9:41 AM, full battery/signal.

**App state to set up**
Connect Apple Health test data or manually enter: HRV 62, RHR 54, sleep
7.4 h. Have an active workout template named "Push Day". Log a breakfast
with ~500 kcal earlier in the day.

**Overlay copy**
- Headline: `Know if you're ready to train.`
- Sub-caption: `Recovery Score · HRV · Sleep · Resting HR`
- Pro badge: **none**

**Composition note**
Crop so the Recovery Score ring is the top visual anchor. This is the
first screenshot a browser sees — it must convey "daily intelligence"
at a glance.

---

### Screenshot 2 — Active Workout / Set Logging  *(FREE)*

**What to show**
Active workout view mid-session. Exercise "Bench Press" is selected. The
set row shows: Set 3 · 90 kg · 8 reps (pre-filled from last session in
lighter text). Rest timer circle visible at bottom edge counting 1:24.
Muscle heatmap strip at very bottom showing chest/anterior delt lit up.

**App state to set up**
Start a workout with Bench Press already logged twice (so Set 3 pre-fills
correctly). Do not dismiss the rest timer.

**Overlay copy**
- Headline: `Log sets in 2 taps.`
- Sub-caption: `Pre-filled from last session · Auto rest timer · PR detection`
- Pro badge: **none**

**Composition note**
Show the pre-filled value visually distinct (lighter / ghost text) from
confirmed sets so the "2-tap" hook is obvious without reading the caption.

---

### Screenshot 3 — Meal Scanner: Per-Item Review  *(FREE)*

**What to show**
Photo meal scanner review screen. Detected items: "Chicken breast · 180g
· 297 kcal", "Brown rice · 150g · 195 kcal", "Broccoli · 120g · 41 kcal".
Each item has a portion stepper and a checkmark toggle. "Add 3 items" CTA
button at bottom. Macro breakdown ring visible in the background.

**App state to set up**
Scan a real plate of food with the photo scanner. Alternatively capture
the review UI with realistic mock data already populated.

**Overlay copy**
- Headline: `Snap a photo. Every item logged.`
- Sub-caption: `AI identifies each food · Edit portions · Save to library`
- Pro badge: **none**

**Composition note**
The per-item breakdown is the key differentiator vs. competitors — make
sure at least 2 distinct food items are visible. Show the portion stepper
on at least one item.

---

### Screenshot 4 — Biology Tab: Biological Age  *(ATLAS PRO)*

**What to show**
Biology tab. Bio Age dial front-and-centre showing "28.4" in large
mint-green text (user is chronologically 32 — 3.6 years younger). Delta
badge reads "3.6 years younger". Three driver pills below: "HRV −2.5y /
RHR −1.8y / SLEEP +0.7y". Below the dial, two biomarker rows with
sparklines: HRV trending up (Trending up · 62 ms), RHR steady (Steady ·
54 bpm). Deep cosmic/purple gradient background.

**App state to set up**
Enable Pro in debug settings. Have at least 7 days of HealthKit data
(HRV, RHR, sleep). Profile age: 32. The Bio Age engine will compute the
displayed value from real data.

**Overlay copy**
- Headline: `See your biological age.`
- Sub-caption: `HRV · Sleep · Resting HR · Performance Age`
- Pro badge: `Atlas Pro — subscription required`

**Composition note**
The cosmic background and glowing dial are the visual hook. Frame the
dial as the hero — it should occupy at least 40% of the screenshot
height. This is the biggest Pro conversion screenshot.

---

### Screenshot 5 — Nutrition Targets Editor  *(FREE)*

**What to show**
Nutrition targets editor open. Hero calorie display: "2,340 kcal".
Proportional macro bar below it (protein orange, carbs blue, fat yellow
at roughly 35/45/20 split). "Recommended for you" banner showing
goal-derived suggestion. Three glass input cards: Protein 195g, Carbs
265g, Fat 52g. Goal chip "Build Muscle" lit at the top.

**App state to set up**
Open Profile → Nutrition Targets. Body metrics set (male, 80 kg, 178 cm,
28 y, moderately active, goal: Build Muscle). Tap "Recommended for you"
to populate the values before screenshotting.

**Overlay copy**
- Headline: `Targets built for your goal.`
- Sub-caption: `Goal-aware recommendations · Live macro preview`
- Pro badge: **none**

---

### Screenshot 6 — Habits: 6-Month Heatmap  *(FREE)*

**What to show**
Habits tab with two habits visible. "Morning walk" — 47-day streak,
heatmap below filled 80% green with a few orange/empty gaps. "Cold
shower" — 12-day streak. The 6-month grid is the main visual. Week labels
on the left edge (Mon / Wed / Fri), month labels across the top.

**App state to set up**
Create habits and manually seed 6 months of completion data in the test
device (or use a pre-seeded simulator snapshot). Aim for mostly green
with realistic gaps — perfection looks fake.

**Overlay copy**
- Headline: `Build momentum that sticks.`
- Sub-caption: `Daily streaks · 6-month heatmap · Smart reminders`
- Pro badge: **none**

---

### Screenshot 7 — Protocols: Dose Logging  *(FREE / PRO)*

**What to show**
Protocol detail view. Active protocol "BPC-157 + TB-500" with a compliance
ring at 87%. Today's dose card: "BPC-157 · 250 mcg · 7:30 AM · Sub-Q
abdomen" marked as taken (green checkmark). Timeline below showing 5 days
of dose history. Research citation chip visible at the top.

**App state to set up**
Create a 2-compound protocol with today's dose already logged. This shows
the free tier working without a Pro badge.

**Overlay copy**
- Headline: `Track every protocol. Down to the dose.`
- Sub-caption: `208 compounds · Dose log · Reminders · Community stacks`
- Pro badge: **none** (up to 3 protocols is free)

**Composition note**
Keep the medical disclaimer chip visible somewhere on screen — it signals
to App Review that the disclaimer is in-app, not just in the description.

---

### Screenshot 8 — Paywall  *(REQUIRED BY APP REVIEW)*

**What to show**
Paywall full screen. Three plan rows stacked full-width:
- Annual · $49.99/year · "14-day free trial" · "BEST VALUE" chip
- Monthly · $9.99/month · "3-day free trial"
- Lifetime · $169 · "One-time purchase"

Auto-renew disclosure visible above the CTA. Terms of Use and Privacy
Policy links visible at the bottom. "Atlas Pro" headline at top with 5–6
feature bullets below it.

**App state to set up**
Navigate to Profile → Upgrade. Paywall renders live from StoreKit in
Sandbox — prices auto-populate.

**Overlay copy**
- Headline: `Try free. Upgrade when ready.`
- Sub-caption: `14-day free trial on annual · Cancel anytime in Settings`
- Pro badge: **none** (this IS the paywall screen)

**Critical:** This screenshot is checked by App Review. The disclosure
text, Terms link, and Privacy link must be legible at screenshot size.
Do not crop them out.

---

### Guideline 2.3.2 — Pro-feature labeling checklist

| Screenshot | Pro-gated? | Badge required? |
|---|---|---|
| 1 — Today Dashboard | No | No |
| 2 — Workout Logging | No | No |
| 3 — Meal Scanner | No | No |
| 4 — Biology / Bio Age | **Yes** | **Yes — `Atlas Pro — subscription required`** |
| 5 — Nutrition Targets | No | No |
| 6 — Habits | No | No |
| 7 — Protocols | No (free up to 3) | No |
| 8 — Paywall | n/a — is the paywall | No |

Free features: workout logging (rest timer, PR detection), barcode + photo
meal scanning, four base biomarkers (weight, HRV, RHR, sleep), habit
tracking, up to 3 active protocols, dose logging, local reminders,
peptide library.

Pro features (badge required on screenshots): full Biology tab, body
composition + lab panels, AI Research assistant, cloud sync, Apple Watch,
all Home Screen widgets, Live Activities, CSV/JSON export, unlimited
protocols.

---

## Review Information

### Contact

| Field | Value |
|---|---|
| First name | `<YOUR FIRST NAME>` |
| Last name | `<YOUR LAST NAME>` |
| Phone | `<YOUR PHONE>` |
| Email | `review@peptidesai.com` |

### Notes for App Review

```
Thank you for reviewing Atlas.

SIGN-IN
Sign in with Apple is optional. Every feature works without an account
— tap "Continue without an account" on the onboarding sign-in screen.
If you do sign in: Profile → Account exposes Sign Out and Delete Account.
Delete Account wipes all SwiftData records and the Keychain entry, then
propagates the delete through the user's private CloudKit zone.

HEALTHKIT
HealthKit is requested only when you tap "Connect Health" in the Profile
tab — never automatically. Atlas reads six metrics from Apple Health:
heart rate, HRV, resting heart rate, body mass, step count, active
energy. It optionally writes meal macros (calories, protein, carbs, fat)
if the user enables "Sync to Apple Health" from Profile. Both
NSHealthShareUsageDescription and NSHealthUpdateUsageDescription are
declared in Info.plist with strings describing their exact use.
Denying Health access hides the Recovery correlation section only — no
other feature is blocked.

NOTIFICATIONS
Requested the first time a protocol with a reminder is saved. Denying
disables reminders only; nothing else is blocked.

PEPTIDE CONTENT
The peptide database is educational — 208 compounds with research
citations. Atlas does not sell, prescribe, source, or recommend any
compound. The medical disclaimer is acknowledged during onboarding
(two-tap confirmation, timestamp persisted) and visible on every peptide
detail screen. Peptides are referenced as research chemicals; language
such as "buy," "order," "vendor," or "source" does not appear in the app.

SUBSCRIPTIONS
Profile → Upgrade opens the paywall. Sandbox accounts work without
setup. Trial lengths: Monthly 3 days, Annual 14 days. Lifetime is a
one-time non-consumable IAP. Restore Purchases is on the paywall.
All three products (Monthly, Annual, Lifetime) must be approved in App
Store Connect before submission.

PRIVACY
No developer-operated backend. No analytics SDKs, crash reporters,
advertising identifiers, or third-party AI APIs. Network use is limited
to Apple's own services: StoreKit 2, Sign in with Apple (optional),
HealthKit (read/write, on-device only), CloudKit (user's private zone,
developer cannot access). Each binary ships its own PrivacyInfo.xcprivacy
declaring NSPrivacyTracking = false and an empty collected-data-types array.

Support: support@peptidesai.com
```

---

## Submission Pre-Flight Checklist

Run through every item before hitting Submit in App Store Connect.

**URLs**
- [ ] `https://wrexist.github.io/Peptide-ai/` returns HTTP/2 200
- [ ] `https://wrexist.github.io/Peptide-ai/privacy.html` returns HTTP/2 200 and renders readable text without JavaScript
- [ ] `https://wrexist.github.io/Peptide-ai/support.html` returns HTTP/2 200

**Build & Device**
- [ ] TestFlight build uploaded and installable
- [ ] Cold launch tested on a real iPhone (not Simulator only)
- [ ] HealthKit, paywall, widget, Watch app verified on device
- [ ] Zero crashes in Xcode device logs during the full user flow

**App Store Connect fields**
- [ ] App Name: `Atlas: Fitness & Recovery`
- [ ] Subtitle: `Workout Log, Macros & Habits`
- [ ] Keywords pasted exactly (90 chars, no spaces after commas)
- [ ] Promotional Text pasted (147 chars)
- [ ] Description pasted (~3 198 chars)
- [ ] What's New pasted
- [ ] Age rating set to 17+
- [ ] App Privacy questionnaire: all No
- [ ] Review Notes pasted verbatim from above

**Screenshots**
- [ ] 6–8 screenshots uploaded for 6.9" iPhone (1320 × 2868)
- [ ] 6–8 screenshots uploaded for 13" iPad (2064 × 2752)
- [ ] Every Pro-feature screenshot carries `Atlas Pro — subscription required` badge
- [ ] Paywall screenshot (slot 8) present and shows auto-renew disclosure + Terms + Privacy links
- [ ] No screenshots show a splash, login, or empty state

**IAPs**
- [ ] Atlas Pro Monthly (`com.peptidesai.app.pro.monthly`) — approved, 3-day trial set
- [ ] Atlas Pro Annual (`com.peptidesai.app.pro.annual`) — approved, 14-day trial set
- [ ] Atlas Pro Lifetime (`com.peptidesai.app.pro.lifetime`) — approved
- [ ] Subscription group named `Atlas Pro`

**Final**
- [ ] `review@peptidesai.com` inbox is monitored
- [ ] If rejected: reply in Resolution Center within 24 h to preserve queue position
