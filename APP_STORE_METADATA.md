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
Welcome to Atlas 1.0.

We rebuilt the whole thing. Training, nutrition, recovery, habits — and the
peptide tracking surface that started it all — pulled into one private,
native iOS app. No backend. No analytics. Your data stays yours.

WHAT'S IN 1.0

WORKOUTS
• Two-tap set logging — pre-filled weight and reps from your last session
• Rest timer with automatic Lock Screen notification
• PR detection for weight, reps, and bodyweight movements
• 200+ exercise library plus custom lifts
• Weekly muscle volume heatmap and month-grouped history

NUTRITION
• Photo meal scanner (AI-powered — photo deleted after analysis)
• Barcode scanner with 200M+ product database
• Daily calorie + macro rings built from your TDEE
• Custom food library and per-meal history

RECOVERY
• Recovery Score combining HRV, resting heart rate, and sleep
• Performance Age metric
• Biomarker trending and lab value tracking
• Full Apple Health integration

HABITS
• Streak tracking with daily, weekday, or times-per-week schedules
• 6-month momentum heatmap per habit
• Optional reminders on habit days

PEPTIDE TRACKING  (Advanced users)
• 208 compounds with research citations
• Up to 3 active protocols on the free tier
• Dose logging + local reminders with Mark-as-Taken / Snooze
• Atlas does not prescribe or recommend doses

ATLAS PRO (subscription or lifetime required)
• Unlimited protocols
• Full Biology tab (body composition + lab panels)
• AI Research assistant
• Apple Watch + all widgets + Live Activities
• Cloud sync and full data export
• 3-day trial (monthly) · 14-day trial (annual) · or one-time lifetime

Private by default — no backend, no analytics, no third-party SDKs.

Atlas is an educational reference and tracking journal. Always consult a
qualified healthcare provider before changing any protocol.

Questions or feedback? support@peptidesai.com — we read everything.
```

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

iOS requires uploads for these device classes (take in Simulator with
`xcrun simctl io <device> screenshot` or on a physical device via Xcode):

| Device class | Pixel size | Required |
|---|---|---|
| iPhone 6.9" (16 Pro Max) | 1320 × 2868 | **Yes** |
| iPhone 6.5" (11 Pro Max) | 1242 × 2688 | Optional fallback |
| iPad Pro 13" (M4) | 2064 × 2752 | **Yes** (if iPad-targeted) |

### Screenshot sequence and captions

Use 6–8 screenshots per device class. Lead with the broad fitness hook;
put peptide protocols mid-sequence; close on the paywall.

**Screenshot 1 — Hero: Recovery Dashboard**
Show: Today tab with Recovery Score ring, HRV/RHR/sleep tiles, next
workout card, and macro summary.
Caption overlay: `Know if you're ready to train.`
Sub-caption: `Recovery Score · HRV · Sleep · Resting HR`
*Free feature — no Pro badge needed.*

**Screenshot 2 — Workouts: Two-Tap Set Logging**
Show: Active workout view with pre-filled weight/reps, rest timer
countdown, and the muscle heatmap peek at the bottom.
Caption overlay: `Log sets faster than any other app.`
Sub-caption: `Pre-filled from last session. Rest timer included.`
*Free feature.*

**Screenshot 3 — Nutrition: Photo + Barcode Scan**
Show: Split composition — barcode scanner on one side, photo scan
result on the other, with macro breakdown visible.
Caption overlay: `Snap a photo. Macros logged instantly.`
Sub-caption: `200M+ products · AI photo scanner · Custom foods`
*Free feature.*

**Screenshot 4 — Recovery: Biology Tab** `Atlas Pro`
Show: Bio Age dial, HRV trend chart, weight/body-fat graph, lab-value
cards (testosterone, vitamin D).
Caption overlay: `Your biology, trending.`
Sub-caption: `Performance Age · Lab panels · Biomarker history`
Badge: `Atlas Pro — subscription required`

**Screenshot 5 — Habits: 6-Month Heatmap**
Show: Habit list with streak counters and a full heatmap below.
Caption overlay: `Build momentum that sticks.`
Sub-caption: `Daily streaks · 6-month heatmap · Smart reminders`
*Free feature.*

**Screenshot 6 — Protocols: Peptide Library** *(Advanced)*
Show: Peptide detail screen with research citations visible and the
dose-log timeline below.
Caption overlay: `208 research-backed compounds.`
Sub-caption: `Dose logging · Cycle calendar · Community stacks`
*Free up to 3 active protocols.*

**Screenshot 7 — Watch + Widgets** `Atlas Pro`
Show: Lock Screen widget showing Recovery Score, Home Screen medium
widget with upcoming doses, Apple Watch face with compliance ring.
Caption overlay: `Always on your wrist and home screen.`
Sub-caption: `Dynamic Island · Live Activities · watchOS app`
Badge: `Atlas Pro — subscription required`

**Screenshot 8 — Paywall: Clean Pricing**
Show: The paywall with Annual / Monthly / Lifetime options, trial
length prominent, auto-renew disclosure visible, Terms + Privacy links.
Caption overlay: `Try free. Upgrade when ready.`
Sub-caption: `14-day free trial on annual · Cancel anytime`
*This screenshot is required by App Review.*

### Guideline 2.3.2 — Pro-feature labeling

Every screenshot depicting a Pro-only feature **must** carry a visible
`Atlas Pro — subscription required` badge or overlay. Pro features:
unlimited protocols, body-composition + lab panels in Biology tab,
AI Research assistant, cloud sync, all Home Screen widgets, Apple Watch
app, Live Activities, and CSV/JSON export.

Free features that must NOT carry a Pro badge: workout logging (rest
timer, PR detection), barcode and photo meal scanning, the four base
biomarkers (weight, HRV, RHR, sleep), habit tracking, up to 3 active
protocols, dose logging, local dose reminders, peptide library browse.

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
