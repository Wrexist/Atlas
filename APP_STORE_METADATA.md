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

| Field | Value |
|---|---|
| Marketing URL | `https://wrexist.github.io/Peptide-ai/` |
| Privacy Policy URL | `https://wrexist.github.io/Peptide-ai/privacy.html` |
| Support URL | `https://wrexist.github.io/Peptide-ai/support.html` |

*(If you later move to a custom domain, swap all three.)*

---

## Promotional Text *(170 char limit — can be updated without review)*

```
Track every dose, see the patterns behind your compliance, and correlate with
HealthKit — all on-device, with no tracking and no backend.
```
*(162 / 170)*

---

## Description *(4000 char limit)*

```
PeptideX is a private, native iOS app for tracking peptide supplementation
protocols. Build a schedule, log every dose, and see what your adherence
actually looks like week over week — with everything stored on your device.

DESIGNED FOR THE WAY PEOPLE ACTUALLY RUN PROTOCOLS
• Build protocols with flexible daily, weekly, or cycled schedules
• Log each dose with the actual amount, time, injection site, and free-form notes
• Pause and resume cycles without losing history
• 14 achievements across dose milestones, streaks, and logging consistency

208 PEPTIDES, BUNDLED AND SEARCHABLE
• Six categories: healing, metabolic, cognitive, longevity, performance, immune
• Research links on every entry
• Educational content with explicit safety disclaimers — not a prescribing tool

COMPLIANCE ANALYTICS BUILT ON SWIFT CHARTS
• Streaks, weekly heatmap, and trend lines
• Day-of-week patterns so you can see where adherence drifts
• Insight engine highlights milestones, slumps, and positive trends

CORRELATE WITH APPLE HEALTH (OPTIONAL)
• Read-only HealthKit integration for heart rate, HRV, sleep, activity
• See overlap between protocol adherence and the signals you already trust
• PeptideX does not write to Apple Health

ACTIONABLE DOSE REMINDERS
• Rich local notifications with "Mark as Taken" and "Snooze" actions
• Per-time-slot consolidation so you stay under iOS's 64-notification limit
• No remote push — reminders live entirely on your device

HOME SCREEN WIDGETS
• Small: your next dose at a glance
• Medium: today's compliance ring plus schedule

EXPORT WHATEVER YOU NEED
• One-tap CSV export for spreadsheets
• Full JSON backup for portability
• Nothing is ever uploaded unless you choose to share it

PRIVATE BY DEFAULT
• No analytics, no trackers, no advertising SDKs
• All your data stored locally on-device
• Optional Sign in with Apple, stored only in the iOS Keychain
• Privacy manifest declares zero collected data types

PEPTIDEX PRO
Unlock unlimited protocols, full analytics with HealthKit correlation, AI
insights, all Home Screen widgets, and full CSV / JSON / PDF export with a
monthly or annual subscription. A 7-day free trial is available on monthly;
14 days on annual. Cancel anytime in your Apple ID settings.

IMPORTANT — MEDICAL DISCLAIMER
PeptideX is an educational and tracking tool. It is not a medical device and
does not provide medical advice, diagnosis, or treatment. Many substances in
the database are research chemicals not approved for human use. Always
consult a qualified healthcare provider before starting, changing, or
stopping any protocol.
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

Version 1.0 ships the full v1 experience:
• 208 peptides across six categories, fully searchable
• Protocol builder with flexible schedules
• Dose logging with site, time, and notes
• Swift Charts analytics: streaks, heatmap, trends
• Read-only HealthKit correlation (HR, HRV, sleep, activity)
• Home Screen widgets for next dose and compliance ring
• Rich local dose reminders with Mark as Taken / Snooze
• 14 achievements
• CSV and JSON export
• PeptideX Pro subscription with a 7- or 14-day free trial

Private by default: no backend, no analytics, no third-party SDKs.

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
• PeptideX does not write to Apple Health — NSHealthUpdateUsageDescription
  is declared only because the HealthKit framework requires it for any
  HealthKit use.
• The peptide database is educational. The in-app medical disclaimer is
  surfaced in onboarding and on every peptide detail screen. Peptides are
  referenced as research chemicals; PeptideX does not sell, prescribe, or
  source any compound.
• Subscriptions are standard StoreKit 2 auto-renewable in-app purchases.
  Sandbox accounts work without additional setup. Full data export (CSV /
  JSON / PDF) is a Pro feature; uninstalling the app removes all local data
  regardless of subscription status.
• No backend of our own, no analytics, no third-party SDKs. Network use is
  limited to Apple's StoreKit and (optionally) Sign in with Apple. App
  Privacy manifest declares NSPrivacyTracking=false and an empty collected
  data array.

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

Use the 1024×1024 marketing icon already in
`Peptide/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` for the
App Store listing icon.

---

## Subscriptions (In-App Purchases)

| Product | Product ID | Price | Trial |
|---|---|---|---|
| PeptideX Pro — Monthly | `com.peptidesai.app.pro.monthly` | $6.99/mo | 7 days |
| PeptideX Pro — Annual | `com.peptidesai.app.pro.annual` | $49.99/yr | 14 days |

**Subscription group:** `PeptideX Pro`

**Localization (display name and description) for each subscription:**

Monthly:
- Display Name: `PeptideX Pro Monthly`
- Description: `Unlimited protocols, full analytics with HealthKit correlation, AI insights, all widgets, and full CSV/JSON/PDF export. Renews monthly; cancel anytime.`

Annual:
- Display Name: `PeptideX Pro Annual`
- Description: `PeptideX Pro for a full year. Unlimited protocols, full analytics, AI insights, all widgets, full data export. Two months free versus monthly.`

Auto-renewal disclosure (already shown on the in-app paywall) satisfies
Apple's requirement.

---

## Submission pre-flight

Tick off before hitting Submit:

- [ ] GitHub Pages deployed — `https://wrexist.github.io/Peptide-ai/privacy.html` returns **200** (Cayman uses default permalinks, so `.html` is correct — verify with `curl -I` before pasting into App Store Connect; the privacy URL is hard to change after submission)
- [ ] Support URL `/support.html` returns **200**
- [ ] Marketing URL `/` returns **200**
- [ ] Privacy page is publicly accessible (no auth, no JS dependency for content — Apple's review crawler must read it)
- [ ] TestFlight build uploaded and installable
- [ ] Install on a real device — HealthKit, Face ID, paywall, widget all work
- [ ] Screenshots uploaded for 6.9" iPhone + 13" iPad
- [ ] Subscription products approved in App Store Connect
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
