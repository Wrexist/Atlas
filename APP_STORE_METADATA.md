# App Store Connect — Metadata for Atlas v1.0.0

> **Rebrand note.** The legacy product/bundle name remains `PeptideX` /
> `com.peptidesai.app` so the StoreKit products and TestFlight history
> stay intact. User-facing copy throughout this document leads with
> Atlas — a health & fitness app for training, nutrition, recovery, and
> protocol tracking — to match the in-app positioning shipped on the
> rebrand branch. The peptide tracking surface is still present, framed
> as an advanced-user feature alongside training and nutrition rather
> than the headline.

Paste the sections below into the corresponding fields in App Store Connect.
All text respects Apple's current character limits. Placeholders are marked
`<LIKE THIS>` — replace before submitting.

---

## App Information

| Field | Value |
|---|---|
| App Name | `Atlas` *(5 / 30)* |
| Subtitle | `Train, eat, recover, repeat` *(27 / 30)* |
| Primary Category | **Health & Fitness** |
| Secondary Category | **Medical** *(optional — leave blank if you want a lighter review)* |
| Bundle ID | `com.peptidesai.app` |
| SKU | `peptidex-ios-1` |
| Primary Language | English (U.S.) |

## URLs

> **Deploy first:** these URLs return 404 until you enable GitHub Pages in
> the repo (Settings → Pages → deploy from `main` / `/docs`). App Store
> Connect validates the Privacy Policy URL at submission time, so publish the
> site before hitting Submit.
>
> The `docs/` folder ships **pure static HTML** (no Jekyll, no theme, no
> build step). A `.nojekyll` file disables GitHub Pages' Jekyll
> preprocessing so `index.html`, `privacy.html`, and `support.html` are
> served byte-for-byte. URLs end in `.html` exactly as given to App Store
> Connect; there is no permalink rewriting that could move them.

| Field | Value |
|---|---|
| Marketing URL | `https://wrexist.github.io/Peptide-ai/` |
| Privacy Policy URL | `https://wrexist.github.io/Peptide-ai/privacy.html` |
| Support URL | `https://wrexist.github.io/Peptide-ai/support.html` |

*(If you later move to a custom domain, swap all three.)*

---

## Promotional Text *(170 char limit — can be updated without review)*

```
Train, log your meals, watch recovery climb. Atlas pulls workouts,
nutrition, and biology into one private, on-device companion. Pro
unlocks more.
```
*(165 / 170)*

---

## Description *(4000 char limit)*

```
Atlas is a private, native iOS companion for training, nutrition, recovery,
and (for the advanced user) supplementation protocols. Everything you log
stays on your device or syncs through your own iCloud — there is no
backend, no analytics, and no tracking.

TRAIN
• Log every set with weight, reps, RPE, rest timer, and the previous
  session pre-filled so you can focus on lifting
• Library of common exercises plus custom lifts you build yourself
• Per-muscle heatmap of the week's training volume
• Personal records detected automatically and surfaced after the workout
• Full session history with month-grouped browsing
• Calendar that respects your locale's first day of the week

NUTRITION
• Barcode scanner backed by Open Food Facts (200 million+ products)
• Photo-based meal scanner powered by on-server vision (your photo is
  analyzed and discarded; nothing is stored remotely)
• Custom-food library plus quick re-log of recent meals
• Daily calorie + macro rings, with TDEE derived from your activity level
• Per-meal history grouped by breakfast, lunch, dinner, snack
• Optional one-way write to Apple Health for the meals you log

BIOLOGY & RECOVERY
• Recovery score that combines HRV, RHR, and sleep into a single number
• Trend cards for weight, body fat, waist, blood pressure, and any lab
  panel you enter (testosterone, ferritin, vitamin D, lipids, more)
• Daily check-in for biology metrics with editable history
• Compatible with Apple Health for the metrics it tracks; everything
  manual otherwise

HABITS
• Build streaks for the small things — drink water, stretch, walk
• Daily, weekday-specific, or times-per-week schedules
• Heatmap of the last six months so you can see momentum at a glance
• Optional reminders that fire when you set a time on the habit

PEPTIDE PROTOCOL TRACKING (ADVANCED)
For users already following peptide protocols on the advice of a qualified
clinician, Atlas keeps the research library and protocol tracker that
shipped with the original release:
• 208 peptides across six categories with research citations
• Up to 3 active protocols on the free tier, unlimited with Atlas Pro
• Dose logging with time, site, and free-form notes
• Local dose reminders with Mark-as-Taken and Snooze actions

ATLAS DOES NOT prescribe, recommend, or calculate doses for any compound.
Every peptide value is labeled as reported in the literature with
citations on each detail page. Always consult a qualified clinician before
starting, changing, or stopping any protocol.

ATLAS PRO — UNLOCKED BY SUBSCRIPTION OR LIFETIME PURCHASE
Pro is offered as a monthly auto-renewing subscription, an annual
auto-renewing subscription, or a one-time lifetime purchase. A 3-day free
trial is available on monthly and a 14-day free trial on annual. Cancel
anytime in your Apple ID settings.
• Unlimited protocols (Atlas Pro — subscription required)
• Full Biology tab including body fat, waist, blood pressure, lab panels (Atlas Pro — subscription required)
• AI research assistant with peptide-database RAG (Atlas Pro — subscription required)
• Cloud sync across all your devices (Atlas Pro — subscription required)
• Every Home Screen widget plus Apple Watch (Atlas Pro — subscription required)
• CSV and JSON data export (Atlas Pro — subscription required)

PRIVATE BY DEFAULT
• No analytics, no trackers, no advertising SDKs
• All your data stored locally on-device
• Optional Sign in with Apple, stored only in the iOS Keychain
• Privacy manifest declares zero collected data types

IMPORTANT — MEDICAL DISCLAIMER
Atlas is an educational reference and self-tracking journal. It is not a
medical device and does not provide medical advice, diagnosis, treatment,
dose recommendations, or dose calculations. Always consult a qualified,
licensed healthcare provider before starting, changing, or stopping any
training, nutrition, supplement, or peptide protocol.
```

---

## Keywords *(100 char limit — comma-separated, NO spaces after commas)*

```
workout,nutrition,macros,recovery,hrv,sleep,habits,barcode,peptide,protocol,journal,wellness
```
*(95 / 100 — leads with the fitness/nutrition surface to broaden discovery, keeps peptide/protocol so the existing audience still matches)*

More technical alternative (narrower audience, higher intent):
```
peptide,protocol,tracker,bpc157,tb500,biohack,supplement,injection,dose,reminder,hrv,analytics
```

---

## "What's New in This Version" *(4000 char limit)*

```
Welcome to Atlas 1.0.

This release pulls everything we've built into one health & fitness
companion — and keeps it private by default.

TRAIN
• Full workout logging with sets, reps, RPE, and a rest timer that wakes
  you with a local notification when the break is over
• Per-muscle weekly volume heatmap
• Automatic personal-record detection (incl. bodyweight rep PRs)
• Searchable exercise library + custom lifts
• Month-grouped workout history

NUTRITION
• Open Food Facts barcode scanner with a 60-minute duplicate guard
• Photo-based meal scanner; review and edit before saving
• Daily calorie + macro targets derived from your activity level
• Per-meal history grouped by breakfast, lunch, dinner, snack
• Optional one-way write to Apple Health

BIOLOGY & RECOVERY
• Recovery score combining HRV, RHR, and sleep
• Trend cards for weight, body fat, waist, blood pressure, and any lab
  panel you enter
• Daily check-in with editable history

HABITS
• Streak tracking with daily, weekday, or times-per-week schedules
• Six-month heatmap for each habit
• Optional reminders on the days the habit is due

PEPTIDE TRACKING (FOR ADVANCED USERS)
• 208 peptides with research citations
• Up to 3 active protocols on the free tier
• Dose logging + local reminders with Mark-as-Taken / Snooze
• Atlas does not prescribe, recommend, or calculate doses

ATLAS PRO (subscription or lifetime purchase required):
• Unlimited protocols
• Full Biology tab (body composition + lab panels)
• AI research assistant with peptide-database RAG
• Cloud sync across devices
• Every Home Screen widget plus Apple Watch
• CSV and JSON data export
• 3-day trial on monthly, 14-day trial on annual, or one-time lifetime

Private by default: no backend, no analytics, no third-party SDKs.

Atlas is an educational reference and self-tracking journal — it does
not recommend doses, diagnose, or replace a clinician. Always consult a
qualified healthcare provider.

Thanks for trying Atlas. Send feedback to support@peptidesai.com — we
read everything.
```

---

## Age Rating

Recommended: **17+**

Apple's questionnaire answers:

| Question | Answer |
|---|---|
| Unrestricted Web Access | No |
| Gambling | No |
| Contests | No |
| Medical/Treatment Information | **Frequent/Intense** *(the app centers on dosing and protocols)* |
| Drug, Alcohol, or Tobacco Use or References | **Infrequent/Mild** *(references peptides and research chemicals)* |
| Sexual Content, Nudity, Violence, Profanity, Horror | None |
| User-Generated Content | No |

Medical/Treatment + references typically yields a **17+** rating, which is
appropriate for this audience and avoids back-and-forth with App Review.

---

## App Privacy (Privacy Nutrition Label)

Your `PrivacyInfo.xcprivacy` already declares this, but App Store Connect
will ask again. Answers:

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No** |
| Tracking (ATT)? | **No** |

Since the answer is "No", no data categories need to be disclosed.

If Apple's review pushes back because HealthKit is listed as an entitlement:
HealthKit data is **read and used on-device only** and is **not collected**
per Apple's definition (it is not transmitted off the device, not linked to
an identity, and not used for tracking). You can reiterate this in the
review notes.

### Privacy manifest coverage

Each distributable binary in this project ships its own
`PrivacyInfo.xcprivacy` (Apple now requires one per target):

| Target | File | Declared APIs |
|---|---|---|
| Peptide (main app) | `Peptide/Resources/PrivacyInfo.xcprivacy` | `UserDefaults` reason `CA92.1` (same-app access — used by `@AppStorage`, `AchievementService`, `LocalizationManager`, `ReviewPromptService`, `AppTheme`) |
| PeptideWidgets | `PeptideWidgets/PrivacyInfo.xcprivacy` | None (file IO only via App Group container) |
| PeptideWatch | `PeptideWatch/PrivacyInfo.xcprivacy` | None (file IO only via App Group container) |

### Why no other Required Reason APIs are declared

The audit at v1.0 verified the codebase touches none of:

- `NSPrivacyAccessedAPICategoryFileTimestamp` — no `creationDate` /
  `modificationDate` / `attributesOfItem` lookups.
- `NSPrivacyAccessedAPICategorySystemBootTime` — no `systemUptime` /
  `mach_absolute_time` / `kern.boottime`.
- `NSPrivacyAccessedAPICategoryDiskSpace` — no
  `volumeAvailableCapacity*` queries.
- `NSPrivacyAccessedAPICategoryActiveKeyboards` — no `activeInputModes`
  reads.

Re-run the audit before each release if persistence, file IO, or
performance-monitoring code lands.

### Why `NSPrivacyCollectedDataTypes` is empty

Atlas has **no developer backend** — all user data either:

1. Stays in `UserDefaults` / SwiftData on-device, or
2. Syncs through the user's **private** CloudKit database (Apple's
   definition of "collected" excludes data the developer cannot access),
   or
3. Lives in the **Keychain** (Sign in with Apple identifier + cached
   email/name).

No `URLSession` calls, no third-party SDKs (Firebase / Sentry /
AppsFlyer / etc.), no analytics pipeline. Code search for
`URLSession`, `URLRequest`, `import Firebase`, `ASIdentifierManager`,
`advertisingIdentifier` returned zero hits at v1.0.

---

## Export Compliance

`ITSAppUsesNonExemptEncryption = false` is already set in `project.yml`.
App Store Connect will not ask further questions.

---

## Review Information

### Sign-in credentials
*(Provide only if the reviewer must sign in. Atlas works without sign-in,
so this is optional. If you leave it off, add a line to Notes explaining
"Sign in with Apple is optional — every feature works without an account.")*

### Contact Information
- First name: `<YOUR FIRST NAME>`
- Last name: `<YOUR LAST NAME>`
- Phone: `<YOUR PHONE>`
- Email: `review@peptidesai.com` *(create or forward this)*

### Notes for App Review

```
Thank you for reviewing Atlas.

• Sign in with Apple is optional. Every feature works without an account —
  you can skip sign-in on the onboarding screen.
• HealthKit permission is requested from the Profile tab: tap "Connect
  Health" in the Health Connection card. It is NOT requested automatically
  from the Analytics tab. Denying access does not disable any feature; it
  only hides the HealthKit correlation section.
• Atlas reads six biometrics from Apple Health (heart rate, HRV, resting
  HR, body mass, step count, active energy) for recovery correlation. It
  also optionally WRITES the meals you log (dietaryEnergyConsumed,
  dietaryProtein, dietaryCarbohydrates, dietaryFatTotal) so nutrition
  shows up in Apple Health alongside everything else. Both
  NSHealthShareUsageDescription and NSHealthUpdateUsageDescription are
  declared in Info.plist with strings that describe their use. Writing is
  off by default and toggled by the user from Profile → Apple Health.
• The peptide database is educational, and the broader app frames itself as
  a fitness companion (training, nutrition, recovery) with peptide tracking
  as one of several surfaces. The in-app medical disclaimer is surfaced in
  onboarding and on every peptide detail screen. Peptides are referenced
  as research chemicals; Atlas does not sell, prescribe, or source any
  compound.
• Subscriptions are standard StoreKit 2 auto-renewable in-app purchases;
  Lifetime is a non-consumable in-app purchase. Sandbox accounts work
  without additional setup. Full data export (CSV / JSON / PDF) is a Pro
  feature; uninstalling the app removes all local data regardless of
  subscription status.
• No backend of our own, no analytics, no third-party SDKs. Network use is
  limited to Apple's StoreKit and (optionally) Sign in with Apple. Each
  distributable binary (main app, widget extension, watch app) ships its
  own PrivacyInfo.xcprivacy declaring NSPrivacyTracking=false and an empty
  collected-data-types array.
• User data either stays on-device (UserDefaults / SwiftData / Keychain) or
  syncs through the user's *private* CloudKit database, which Apple's
  privacy-manifest spec excludes from "collected data" because the
  developer cannot access it.
• The paywall (Profile → Upgrade) and the onboarding trial offer both
  display the auto-renew disclosure inline and link to Terms of Use
  (Apple's standard EULA) and the Privacy Policy at
  https://wrexist.github.io/Peptide-ai/privacy.html.

Support contact: support@peptidesai.com
```

---

## Screenshots required

iOS requires at least the following (take in Simulator with
`xcrun simctl io <device> screenshot`):

| Device class | Size | Count |
|---|---|---|
| iPhone 6.9" (iPhone 16 Pro Max) | 1320 × 2868 | 3–10 |
| iPhone 6.5" (iPhone 11 Pro Max) | 1242 × 2688 | 3–10 *(legacy fallback, optional if 6.9" provided)* |
| iPad Pro 13" (M4) | 2064 × 2752 | 3–10 *(required since you target iPad)* |

Suggested screen order (per device) — leads with the broad fitness
surface, keeps the peptide tracker visible since it's still a real
audience hook:

1. **Home / Today view** — recovery score, next workout, today's macros
2. **Active workout / set logging** — sets with rest timer
3. **Meals tab** — macro rings + per-meal history
4. **Biology tab** — recovery score, weight trend, lab panels (Atlas Pro)
5. **Habits** — streak heatmap + chip row
6. **Peptide library + protocol detail** — research citations + adherence ring
7. **Widgets on Home Screen** — small + medium (marketing shot)
8. **Paywall** — clean pricing page with Yearly / Monthly / Lifetime

### Apple Guideline 2.3.2 — paid-feature labeling on screenshots

Apple's most recent rejection cited the screenshots and description for
referencing paid content (Atlas Pro features, advanced analytics, cloud
sync, AI insights, full export, all widgets, Apple Watch) without
indicating that a purchase is required.

Before resubmitting:

- **Caption every screenshot that depicts a Pro-only feature** with the
  literal text `Atlas Pro — subscription required`. Paid features in
  this app are: unlimited protocols, body-composition + lab biomarkers
  in the Biology tab, the AI research assistant, cloud sync, every Home
  Screen widget, Apple Watch app, and CSV/JSON export.
- **Free-tier features that should NOT carry the Pro label**: workout
  logging with rest timer + PR detection, meal logging via barcode /
  photo / manual, the four free biomarker baselines (weight, HRV, RHR,
  sleep), habit streak tracking, protocol building (up to 3 active),
  dose logging, local dose reminders, the basic compliance widget, and
  the educational peptide library with citations.
- The paywall screenshot (slot 8) must remain in the screenshot set and
  display the auto-renew disclosure plus Terms / Privacy links so the
  reviewer can see them at a glance.
- If you keep an "AI research" or "Cloud sync" screenshot, add a visible
  badge or caption overlay reading "Atlas Pro" so the listing matches
  what is gated in the binary (`StoreService.canAccessAIFeatures`,
  `canAccessCloudSync`, `canAccessFullAnalytics`, `canAccessExport`,
  `canAccessAllWidgets`).

Use the 1024×1024 marketing icon already in
`Peptide/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` for the
App Store listing icon.

---

## Subscriptions (In-App Purchases)

| Product | Product ID | Type | Price | Trial |
|---|---|---|---|---|
| Atlas Pro — Monthly | `com.peptidesai.app.pro.monthly` | Auto-Renewable | $9.99/mo | 3 days |
| Atlas Pro — Annual | `com.peptidesai.app.pro.annual` | Auto-Renewable | $49.99/yr | 14 days |
| Atlas Pro — Lifetime | `com.peptidesai.app.pro.lifetime` | Non-Consumable | $169.00 | — |

**Subscription group:** `Atlas Pro`

> **Product ID note.** The reverse-DNS product IDs (`com.peptidesai.app.pro.*`)
> stay unchanged so existing subscribers and the StoreKit sandbox
> history continue working. Only the user-facing display names switch
> from "PeptideX Pro" to "Atlas Pro".

**Localization (display name and description) for each subscription:**

Monthly:
- Display Name: `Atlas Pro Monthly`
- Description: `Unlimited protocols, the full Biology tab (body composition + labs), AI research assistant, all widgets, and full CSV/JSON export. Renews monthly; cancel anytime.`

Annual:
- Display Name: `Atlas Pro Annual`
- Description: `Atlas Pro for a full year. Unlimited protocols, full Biology, AI research, all widgets, full data export. Save versus monthly billing.`

Lifetime (non-consumable, listed under In-App Purchases, not Subscriptions):
- Display Name: `Atlas Pro Lifetime`
- Description: `One-time purchase. Unlock Atlas Pro forever — unlimited protocols, full Biology, AI research, all widgets, and full data export. No subscription, no renewals.`

Auto-renewal disclosure (already shown on the in-app paywall) satisfies
Apple's requirement for the auto-renewable subscriptions.

**Introductory offers (configure in App Store Connect → each subscription
→ Subscription Pricing → Introductory Offer):**

- Monthly: 3-day free trial, all eligible territories
- Annual: 14-day free trial, all eligible territories

These mirror the local `Products.storekit` config and what the in-app
paywall surfaces dynamically. If you change a trial length, change all
three (StoreKit config, App Store Connect, screenshot guide §10) in the
same release.

---

## Submission pre-flight

Tick off before hitting Submit:

- [ ] GitHub Pages deployed — `https://wrexist.github.io/Peptide-ai/privacy.html` returns **200** (`.nojekyll` ensures the file is served as-is with no permalink rewriting; verify with `curl -I` before pasting into App Store Connect, since the privacy URL is hard to change after submission)
- [ ] Support URL `/support.html` returns **200**
- [ ] Marketing URL `/` returns **200**
- [ ] Privacy page is publicly accessible (no auth, no JS dependency for content — Apple's review crawler must read it)
- [ ] TestFlight build uploaded and installable
- [ ] Install on a real device — HealthKit, Face ID, paywall, widget all work
- [ ] Screenshots uploaded for 6.9" iPhone + 13" iPad
- [ ] All three IAP products (Monthly, Annual, Lifetime) approved in App Store Connect
- [ ] App Privacy questionnaire answered (all No)
- [ ] Age rating set to 17+
- [ ] Review notes pasted above
- [ ] `review@peptidesai.com` inbox monitored

### Quick URL verification (run after enabling Pages, before Submit)

```bash
# 1. Each must return HTTP/2 200 (not 301/302/404)
curl -sI https://wrexist.github.io/Peptide-ai/           | head -1
curl -sI https://wrexist.github.io/Peptide-ai/privacy.html | head -1
curl -sI https://wrexist.github.io/Peptide-ai/support.html | head -1

# 2. Confirm privacy page is server-rendered (Apple's crawler reads HTML, not JS)
curl -s  https://wrexist.github.io/Peptide-ai/privacy.html | grep -i "privacy policy" | head -3
```

All three URLs returning `HTTP/2 200` and the privacy page producing readable
text without JavaScript = safe to paste the URLs into App Store Connect.
