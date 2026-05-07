# App Store Connect — Metadata for PeptideX v1.0.0

Paste the sections below into the corresponding fields in App Store Connect.
All text respects Apple's current character limits. Placeholders are marked
`<LIKE THIS>` — replace before submitting.

---

## App Information

| Field | Value |
|---|---|
| App Name | `PeptideX` *(12 / 30)* |
| Subtitle | `Peptide protocol tracker` *(24 / 30)* |
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
Educational peptide reference and on-device dose journal. Read research,
log what you take, see your compliance. Pro unlocks more (subscription).
```
*(141 / 170)*

---

## Description *(4000 char limit)*

```
PeptideX is a private, native iOS educational reference and self-tracking
journal for people who already follow peptide supplementation protocols on
the advice of a qualified clinician. Look up published research, build a
schedule you input yourself, log what you actually take, and see your
adherence over time — all stored on your device.

PeptideX does NOT prescribe, recommend, or calculate doses. Every value is
labeled as reported in the research literature with citations on each
peptide page. Always consult a qualified clinician before starting,
changing, or stopping any protocol.

INCLUDED FOR EVERY USER (FREE)
• Browse 208 peptides across six categories with full research citations
• Build up to 3 active protocols with flexible daily, weekly, or cycled schedules
• Log each dose with the amount, time, injection site, and free-form notes
• Pause and resume cycles without losing history
• Local dose reminders on your iPhone (Mark as Taken / Snooze actions)
• Read-only Apple Health integration for HR, HRV, sleep, activity
• Basic compliance analytics — streaks, weekly heatmap, day-of-week patterns
• Compliance widget on your Home Screen
• 14 achievements across dose milestones, streaks, and logging consistency
• Add your own custom peptides
• Sign in with Apple (optional)

PEPTIDEX PRO — UNLOCKED BY SUBSCRIPTION OR LIFETIME PURCHASE
Every feature listed below requires PeptideX Pro. Pro is offered as a
monthly auto-renewing subscription, an annual auto-renewing subscription,
or a one-time lifetime purchase. A 3-day free trial is available on monthly
and a 14-day free trial on annual. Cancel anytime in your Apple ID
settings.
• Unlimited protocols (PeptideX Pro — subscription required)
• Full analytics with HealthKit correlation (PeptideX Pro — subscription required)
• AI insights and smart suggestions (PeptideX Pro — subscription required)
• Cloud sync across all your devices (PeptideX Pro — subscription required)
• Every Home Screen widget plus Apple Watch (PeptideX Pro — subscription required)
• CSV and JSON data export (PeptideX Pro — subscription required)

PRIVATE BY DEFAULT
• No analytics, no trackers, no advertising SDKs
• All your data stored locally on-device
• Optional Sign in with Apple, stored only in the iOS Keychain
• Privacy manifest declares zero collected data types

IMPORTANT — MEDICAL DISCLAIMER
PeptideX is an educational reference and self-tracking journal. It is not a
medical device and does not provide medical advice, diagnosis, treatment,
dose recommendations, or dose calculations. Information about peptides is
summarized from published research with citations on each peptide page.
Many substances referenced are research chemicals not approved for human
use in many jurisdictions. Always consult a qualified, licensed healthcare
provider before starting, changing, or stopping any protocol.
```

---

## Keywords *(100 char limit — comma-separated, NO spaces after commas)*

```
peptide,protocol,tracker,bpc,health,fitness,supplement,reminder,dose,hrv,sleep,compliance
```
*(91 / 100 — balances general health/fitness discovery with peptide-specific terms)*

More technical alternative (narrower audience, higher intent):
```
peptide,protocol,tracker,bpc157,tb500,biohack,supplement,injection,dose,reminder,hrv,analytics
```

---

## "What's New in This Version" *(4000 char limit)*

```
Welcome to PeptideX 1.0.

Version 1.0 ships the full v1 experience.

Included for every user (free):
• 208 peptides across six categories, fully searchable, with research citations
• Up to 3 protocols with flexible schedules
• Dose logging with site, time, and notes
• Local dose reminders with Mark as Taken / Snooze
• Read-only HealthKit correlation (HR, HRV, sleep, activity)
• Compliance widget for your Home Screen
• Basic analytics: streaks, heatmap, day-of-week
• 14 achievements
• Optional Sign in with Apple

PeptideX Pro features (subscription or lifetime purchase required):
• Unlimited protocols
• Full analytics with HealthKit correlation
• AI insights and smart suggestions
• Cloud sync across devices
• Every Home Screen widget plus Apple Watch
• CSV and JSON data export
• 3-day free trial on monthly, 14-day free trial on annual, or one-time lifetime

Private by default: no backend, no analytics, no third-party SDKs.

PeptideX is an educational reference and self-tracking journal — it does
not recommend or calculate doses. Always consult a qualified clinician.

Thanks for trying PeptideX. Send feedback to support@peptidesai.com — we
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

PeptideX has **no developer backend** — all user data either:

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
*(Provide only if the reviewer must sign in. PeptideX works without sign-in,
so this is optional. If you leave it off, add a line to Notes explaining
"Sign in with Apple is optional — every feature works without an account.")*

### Contact Information
- First name: `<YOUR FIRST NAME>`
- Last name: `<YOUR LAST NAME>`
- Phone: `<YOUR PHONE>`
- Email: `review@peptidesai.com` *(create or forward this)*

### Notes for App Review

```
Thank you for reviewing PeptideX.

• Sign in with Apple is optional. Every feature works without an account —
  you can skip sign-in on the onboarding screen.
• HealthKit permission is requested from the Profile tab: tap "Connect
  Health" in the Health Connection card. It is NOT requested automatically
  from the Analytics tab. Denying access does not disable any feature; it
  only hides the HealthKit correlation section.
• PeptideX is read-only against Apple Health. Only
  NSHealthShareUsageDescription is declared in Info.plist;
  NSHealthUpdateUsageDescription is intentionally absent. The
  authorization request is `requestAuthorization(toShare: [], read: ...)`
  in HealthKitService.swift — six metric types are read (heart rate, HRV,
  resting heart rate, body mass, step count, active energy), nothing is
  ever written.
• The peptide database is educational. The in-app medical disclaimer is
  surfaced in onboarding and on every peptide detail screen. Peptides are
  referenced as research chemicals; PeptideX does not sell, prescribe, or
  source any compound.
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

Suggested screen order (per device):

1. **Home / Today view** — next dose, compliance ring
2. **Peptide database** — search and category filter
3. **Protocol builder** — schedule editor
4. **Analytics** — heatmap + streak
5. **HealthKit correlation** — HRV / sleep overlay
6. **Widgets on Home Screen** — small + medium (marketing shot)
7. **Paywall** — clean pricing page

### Apple Guideline 2.3.2 — paid-feature labeling on screenshots

Apple's most recent rejection cited the screenshots and description for
referencing paid content (PeptideX Pro features, advanced analytics, cloud
sync, AI insights, full export, all widgets, Apple Watch) without
indicating that a purchase is required.

Before resubmitting:

- **Caption every screenshot that depicts a Pro-only feature** with the
  literal text `PeptideX Pro — subscription required`. Paid features in
  this app are: unlimited protocols, full analytics with HealthKit
  correlation, AI insights, cloud sync, every Home Screen widget, Apple
  Watch app, and CSV/JSON export.
- **Free-tier features that should NOT carry the Pro label**: protocol
  building (up to 3), dose logging, local dose reminders, the basic
  compliance widget, the educational peptide library with citations, and
  read-only HealthKit correlation visible inside the basic analytics view.
- The paywall screenshot (slot 7) must remain in the screenshot set and
  display the auto-renew disclosure plus Terms / Privacy links so the
  reviewer can see them at a glance.
- If you keep an "AI insights" or "Cloud sync" screenshot, add a visible
  badge or caption overlay reading "PeptideX Pro" so the listing matches
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
| PeptideX Pro — Monthly | `com.peptidesai.app.pro.monthly` | Auto-Renewable | $9.99/mo | 3 days |
| PeptideX Pro — Annual | `com.peptidesai.app.pro.annual` | Auto-Renewable | $49.99/yr | 14 days |
| PeptideX Pro — Lifetime | `com.peptidesai.app.pro.lifetime` | Non-Consumable | $169.00 | — |

**Subscription group:** `PeptideX Pro`

**Localization (display name and description) for each subscription:**

Monthly:
- Display Name: `PeptideX Pro Monthly`
- Description: `Unlimited protocols, full analytics with HealthKit correlation, AI insights, all widgets, and full CSV/JSON/PDF export. Renews monthly; cancel anytime.`

Annual:
- Display Name: `PeptideX Pro Annual`
- Description: `PeptideX Pro for a full year. Unlimited protocols, full analytics, AI insights, all widgets, full data export. Save versus monthly billing.`

Lifetime (non-consumable, listed under In-App Purchases, not Subscriptions):
- Display Name: `PeptideX Pro Lifetime`
- Description: `One-time purchase. Unlock PeptideX Pro forever — unlimited protocols, full analytics, AI insights, all widgets, and full data export. No subscription, no renewals.`

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
