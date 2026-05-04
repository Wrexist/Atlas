# App Store Review Response — Guideline 2.1 (Information Needed)

This is the complete, ordered checklist for replying to App Review's
Guideline 2.1 information request for **PeptideX v1.0.0**. Apple asked for
six items plus addressed five "common issues." Each section below maps
**what to deliver**, **how to produce it the best way**, and (where
applicable) **ready-to-paste copy** for the Notes field in App Store
Connect → App Review Information.

> Companion docs: `APP_STORE_METADATA.md` (already-prepared listing copy)
> and `TESTFLIGHT_SETUP.md` (build pipeline). This file only covers the
> 2.1 reply.

---

## 0. Where each item goes in App Store Connect

| Apple's ask | Field in App Store Connect |
|---|---|
| 1. Screen recording | Reply to the message thread → attach `.mov`/`.mp4` |
| 2. Purpose / problem / value | Notes for App Review |
| 3. Reviewer instructions + creds | Sign-In Information + Notes |
| 4. External services list | Notes |
| 5. Regional differences | Notes |
| 6. Regulated-industry docs | Notes (+ attach if requested) |

Everything in §2-§6 lives in the **Notes** field and should also be saved
in this repo so future submissions reuse the same text.

---

## 1. Screen recording on a physical device

### What Apple wants
A single capture, started from app launch, walking the typical user flow
through the **core features**, plus every flow they specifically called
out:

- Account registration / login / **account deletion** (Sign in with Apple is optional in PeptideX, but the deletion path must still be shown)
- Paid content / subscription / purchase flows
- User-generated content + reporting/blocking (PeptideX has none — say so)
- Every system permission prompt the app can trigger

### How to record (best way)

Use a real iPhone, not the Simulator — Apple explicitly says "physical
device."

1. **Reset app state** so prompts fire fresh:
   - Settings → General → iPhone Storage → PeptideX → Offload App
   - Reinstall via TestFlight
2. **Disable "Do Not Disturb"** so notification banners can appear if you demo a reminder.
3. **Start screen recording**: Control Center → Screen Recording (long-press to enable mic if you want voice-over). Recording starts after a 3-second countdown.
4. **Run the script in §1.1.** Aim for 90-180 seconds. App Review prefers brevity over exhaustiveness.
5. **Stop recording**, trim head/tail in Photos (Edit → trim handles), AirDrop to Mac.
6. **Encode for upload**: keep under 250 MB. If you need to compress:
   ```bash
   ffmpeg -i raw.mov -vcodec h264 -crf 24 -preset slow -acodec aac PeptideX-review.mp4
   ```
7. **Upload** as a reply attachment in the Resolution Center thread.

### 1.1 Recording script (run in this exact order)

| # | Action | Why it satisfies the reviewer |
|---|---|---|
| 1 | Tap PeptideX icon on Home Screen | Proves cold launch on a physical device |
| 2 | Step through the 4 onboarding screens, accept the medical disclaimer | Shows safety messaging up front |
| 3 | On the sign-in screen, tap **"Continue without an account"** | Demonstrates that account is optional |
| 4 | Land on Today tab — point out next-dose card and compliance ring | Core feature |
| 5 | Open the Peptide database, search "BPC", open the detail screen | Core feature |
| 6 | Tap "Add to Protocol" → build a 5-day protocol → save | Core feature |
| 7 | Today tab → log a dose (amount, site, notes) | Core feature |
| 8 | Allow the **Notifications** permission prompt when it appears | Sensitive permission |
| 9 | Open Analytics → show heatmap, streak, day-of-week chart | Core feature |
| 10 | Profile → "Connect Health" → allow **HealthKit** read access | Sensitive permission + read-only confirmation |
| 11 | Back to Analytics → show HRV/sleep correlation populated | Proves HealthKit integration works |
| 12 | Profile → Upgrade → show the paywall (Monthly / Annual / Lifetime), point out trial length, Terms, Privacy links | Subscription flow |
| 13 | Tap a plan → cancel the StoreKit sheet (don't actually buy) | Demonstrates the paywall, no charge |
| 14 | Profile → Sign in with Apple → complete sign-in | Optional registration |
| 15 | Profile → Account → **Delete Account** → confirm | **Account deletion** (mandatory per 5.1.1(v)) |
| 16 | Settings app → Face ID & Passcode → confirm PeptideX listed (optional, only if you ship app-lock) | Face ID purpose string |

### 1.2 If a flow does not exist, say so

PeptideX has no UGC, no camera, no contacts, no location, no microphone.
Mention this in the Notes (§4) so the reviewer does not look for them.

---

## 2. App purpose, problem solved, value delivered

Paste verbatim into the Notes field:

```
PURPOSE
PeptideX is a private, on-device tracker for people who already follow
peptide supplementation protocols on the advice of a clinician or
qualified practitioner. The app helps them schedule doses, log what they
actually took, see compliance over time, and (optionally) correlate
adherence with biometric trends from Apple Health.

PROBLEM IT SOLVES
People who run multi-week peptide cycles typically track them in
spreadsheets, paper notebooks, or generic reminder apps that lack any
domain awareness (no concept of injection sites, cycle pauses,
stacking, or compliance scoring). PeptideX consolidates protocol design,
dose logging, reminders, and analytics into one purpose-built tool.

VALUE TO THE USER
1. Build flexible daily/weekly/cycled protocols in a structured editor.
2. Log doses with site, time, amount, and free-form notes.
3. Receive rich local notifications with "Mark as Taken" / "Snooze."
4. See compliance analytics (streaks, heatmap, trend lines).
5. Optionally overlay HealthKit signals (HR, HRV, sleep, activity) to
   spot correlations — entirely on-device.
6. Export everything to CSV / JSON / PDF for personal records.

PeptideX is an EDUCATIONAL and TRACKING tool. It does not prescribe,
sell, source, or recommend any compound for human use. The medical
disclaimer is shown during onboarding and on every peptide detail
screen.
```

---

## 3. Reviewer instructions + credentials

### 3.1 Sign-In Information section

Sign in with Apple is **optional** — the reviewer can skip it and still
exercise every feature. Therefore in App Store Connect:

- Sign-In required: **No** (uncheck the box)
- Provide a one-line reminder in Notes (below)

> If, for any reason, Apple insists on a credential, create a test Apple
> ID specifically for App Review and include the email / password in
> Sign-In Information. Do not reuse a personal Apple ID.

### 3.2 Reviewer instruction copy (paste into Notes)

```
HOW TO REVIEW PEPTIDEX

Sign-in:
• Sign in with Apple is optional. On the sign-in screen, tap "Continue
  without an account" — every feature works without an account.
• If you do sign in, account deletion is at Profile → Account →
  Delete Account.

HealthKit:
• HealthKit is requested ONLY when you tap "Connect Health" in the
  Profile tab. It is never asked automatically. PeptideX is read-only
  against Apple Health (NSHealthShareUsageDescription only;
  NSHealthUpdateUsageDescription is intentionally absent in Info.plist).
• Denying HealthKit hides the correlation card. No other feature is
  blocked.

Notifications:
• Asked the first time you save a protocol with a reminder. Denying
  notifications disables reminders only; nothing else is blocked.

Subscriptions:
• Profile → Upgrade opens the paywall. Sandbox accounts work without
  additional setup. Trial lengths: Monthly 3 days, Annual 14 days,
  Lifetime is a one-time non-consumable.
• Restoring purchases: Profile → Upgrade → "Restore Purchases."

Demo data:
• A "Load sample data" affordance is in Profile → Developer Options
  (visible in TestFlight builds) so the reviewer can see analytics
  without running a multi-day protocol. Tap it to populate 14 days of
  realistic dose history.
```

### 3.3 Implementation checklist for §3.2 to be true

- [ ] Verify "Continue without an account" is visible and unconditional on the sign-in screen (file: `Peptide/Features/Auth/`)
- [ ] Verify Account Deletion exists and works for Sign-in-with-Apple users (Apple Guideline 5.1.1(v) **mandatory**). Path: Profile → Account → Delete Account. Must:
  - Revoke the Apple ID token via `ASAuthorizationAppleIDProvider.credentialState`
  - Wipe SwiftData / UserDefaults / Keychain entries
  - Delete the user's private CloudKit zone
- [ ] Confirm "Load sample data" exists or add it. If you add it, gate behind `#if DEBUG || TESTFLIGHT` so it doesn't ship to production users.
- [ ] Confirm "Restore Purchases" button is present on the paywall and on the post-purchase failure path.

---

## 4. External services / tools / platforms

This is the question the reviewer most often re-asks if the answer is
vague. Be exhaustive. Paste verbatim:

```
EXTERNAL SERVICES USED BY PEPTIDEX

PeptideX has NO developer-operated backend. No analytics SDKs, no
crash reporters, no advertising identifiers, no third-party AI APIs,
no remote config. The full list of external systems the app talks to:

1. Apple StoreKit 2 — in-app purchases (Monthly, Annual, Lifetime).
   Used for purchase, restore, transaction verification.

2. Sign in with Apple (optional) — authentication only. Identifier
   and cached email/name stored in iOS Keychain. No external user
   directory of our own.

3. Apple HealthKit (optional, read-only) — heart rate, HRV, resting
   heart rate, body mass, step count, active energy. Read on-device
   only; never transmitted off the device.

4. Apple CloudKit (private database, optional) — used as a sync
   backend if the user is signed into iCloud. Per Apple's privacy-
   manifest spec, the developer cannot read the user's private
   CloudKit zone, so this is not "collected data."

5. Apple Push Notification Service — NOT USED. All reminders are
   local notifications scheduled on-device via UNUserNotificationCenter.

"AI Insights" clarification:
The "AI insights" feature advertised on the paywall is a deterministic,
on-device rule engine (InsightEngine / StackRecommendationEngine /
OnboardingRecommendationEngine in the source). It does NOT call any
external LLM or AI service. No data leaves the device for AI processing.

Static educational content shipped in the binary:
The 208-peptide database is a bundled JSON file
(Peptide/Resources/peptides.json). It is read-only reference content
and does not contact any server.

External marketing / support sites (NOT used by the app at runtime,
listed for completeness because the App Store listing links to them):
• Marketing: https://wrexist.github.io/Peptide-ai/
• Privacy:   https://wrexist.github.io/Peptide-ai/privacy.html
• Support:   https://wrexist.github.io/Peptide-ai/support.html
```

### 4.1 Verify the claim before sending

- [ ] `git grep -n "URLSession\|URLRequest\|Alamofire\|fetch(" Peptide/` returns nothing outside StoreKit / SwiftUI internals.
- [ ] `git grep -nE "OpenAI|Anthropic|Firebase|Sentry|AppsFlyer|Amplitude|Segment|Mixpanel|GoogleService"` returns zero matches.
- [ ] `git grep -n "advertisingIdentifier\|ASIdentifierManager"` returns zero matches.

---

## 5. Regional differences

Paste verbatim:

```
REGIONAL AVAILABILITY

PeptideX is functionally identical in every region where it is offered.
There is no geo-fenced content, no country-specific feature, and no
region-specific pricing tier beyond Apple's standard auto-localization
of subscription prices.

The app is localized to: English, Spanish, Simplified Chinese, Japanese,
German, French, Brazilian Portuguese, Korean, Russian, and Arabic.
Localization is purely UI string translation; it does not change feature
availability.

The peptide reference content is the same across all regions. The
in-app medical disclaimer is shown to every user regardless of region.
```

### 5.1 If you choose to restrict territories

If you decide to block a country (e.g. Russia, China) for legal
reasons, **do it in App Store Connect → Pricing and Availability**, not
inside the app. The Notes should still reflect the truth, so update the
text above to list excluded territories.

---

## 6. Regulated-industry posture

Peptides are a sensitive category. App Review will sometimes ask
whether the developer is licensed/authorized. PeptideX positions itself
as **educational and tracking only**, which is the established pattern
that does not require credentials. Paste verbatim:

```
REGULATED-INDUSTRY POSTURE

PeptideX is a tracker and educational reference, not a medical device,
not a pharmacy, not a telehealth service, and not a marketplace. It
does not prescribe, diagnose, treat, sell, source, or recommend any
compound for human use. Many compounds in the database are explicitly
labeled as research chemicals not approved for human use, and the app
shows this disclaimer:

  "PeptideX is an educational and tracking tool. It is not a medical
   device and does not provide medical advice, diagnosis, or
   treatment. Many substances referenced are research chemicals not
   approved for human use. Always consult a qualified healthcare
   provider before starting, changing, or stopping any protocol."

This disclaimer appears:
• During onboarding (the user must acknowledge it to proceed)
• On every peptide detail screen
• In the App Store description

Because the app does not provide regulated services (pharmacy,
prescribing, diagnosis), no professional credentials apply. If App
Review determines additional documentation is required for the
educational reference content, we will provide source citations for
each peptide entry on request — every entry already carries a research
link in the bundled data.
```

### 6.1 Proactive hardening (do these regardless)

- [ ] Verify the medical disclaimer is shown on **first launch** and is **dismissible only after explicit acknowledgement** (a tap, not a swipe).
- [ ] Verify every peptide detail view shows the disclaimer above the fold.
- [ ] Confirm no peptide detail screen contains language like "buy", "order", "vendor", "source", "purchase from."
- [ ] Confirm the app does not link out to any vendor / reseller. Research-paper links to PubMed / NIH / journals are fine.
- [ ] Add the App Store description's medical disclaimer paragraph (already in `APP_STORE_METADATA.md` lines 109-114) to the on-device About screen too, so a reviewer can find it in-app without leaving the app.

---

## 7. Address the 5 "common issues" Apple flagged

Apple's rejection email lists these as preventative reminders. Tick each
before resubmitting, even though they aren't formal rejections.

### 7.1 (2.1) Bugs and crashes — physical-device sanity check

- [ ] Install the TestFlight build on **at least one iPhone and one iPad** you actually own.
- [ ] Run the §1.1 script end-to-end on each. Watch for:
  - Permission prompt copy renders correctly (not truncated)
  - Notifications fire when scheduled
  - HealthKit data populates within 5 seconds of granting access
  - Paywall renders all three products with localized prices
  - Widgets refresh after a dose log
- [ ] Inspect crash logs in Xcode → Window → Devices & Simulators → View Device Logs. Zero crashes in your test session.

### 7.2 (2.1) Accessing the app — credentials

Already covered in §3. Sign-in is optional, so no credentials are
required. State this explicitly so the reviewer does not assume it was
forgotten.

### 7.3 (2.3.3) Screenshots — show the app in use

- [ ] Audit the screenshots in App Store Connect against `APP_STORE_METADATA.md` §"Screenshots required" (lines 308-331). Required: Today, Database, Protocol Builder, Analytics, HealthKit Correlation, Widgets, Paywall.
- [ ] **No splash screens.** **No login screens.** **No bare title art.** Every screenshot must show actual feature UI with realistic data populated.
- [ ] Verify both 6.9" iPhone (1320 × 2868) and 13" iPad (2064 × 2752) sets are uploaded.

### 7.4 (3.1.2) Subscription information

The paywall must clearly display, on the same screen as the buy buttons:

- [ ] Subscription **title** for each tier (PeptideX Pro Monthly / Annual / Lifetime)
- [ ] Subscription **length** (monthly, annual, lifetime)
- [ ] Subscription **price** (auto-localized via StoreKit)
- [ ] Auto-renew disclosure (Apple's standard wording)
- [ ] Link to Terms of Use (Apple's standard EULA URL is acceptable: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)
- [ ] Link to Privacy Policy (https://wrexist.github.io/Peptide-ai/privacy.html)

Reviewer-friendly addition: also surface the same disclosure on the
**onboarding trial offer** screen if there is one (`TrialOfferView.swift`
already does this per the metadata doc, but verify visually).

### 7.5 (5.1.1) Purpose strings

Open `Peptide/Resources/Info.plist` and confirm each purpose string
includes both **why** and a **concrete example**. Current state:

| Key | Current value | Verdict |
|---|---|---|
| `NSFaceIDUsageDescription` | "PeptideX uses Face ID to protect your peptide protocols and health information." | ✅ Reason given. Could mention the example ("for example, when opening the app after backgrounding"). Optional polish. |
| `NSHealthShareUsageDescription` | "PeptideX reads heart rate, HRV, resting heart rate, body mass, steps, and active energy from Apple Health to correlate your peptide protocols with biometric trends. All analysis happens on your device — nothing is sent off the device." | ✅ Excellent — explicit metrics, explicit purpose, on-device guarantee. |

Notification permission has no plist key (it's prompted via
`UNUserNotificationCenter`) but the in-app pre-prompt should explain
**why**: "PeptideX uses notifications to remind you of scheduled doses
and let you log them with one tap." Verify this string exists in the
auth flow.

If you add any new permission later (camera for QR import, contacts,
location), the purpose string MUST follow the pattern: **what + why +
example**, e.g. "PeptideX uses your camera to scan barcode peptide
labels — for example, to auto-fill an entry instead of typing it."

---

## 8. Final pre-submit checklist (do not skip)

```
[ ] Recording captured on a real iPhone, under 3 minutes
[ ] Recording shows: launch, onboarding, skip sign-in, log dose,
    analytics, HealthKit grant, paywall, sign in with Apple, account
    deletion
[ ] Notes field in App Store Connect contains §2-§6 verbatim
[ ] Sign-In Information section: "Sign-in required" unchecked
[ ] Demo data toggle exists (or sample state is pre-loaded)
[ ] Account deletion path tested end-to-end (token revoke + data wipe)
[ ] All purpose strings audited per §7.5
[ ] Screenshots audited per §7.3
[ ] Paywall disclosure audited per §7.4
[ ] Privacy / Support / Marketing URLs return HTTP/2 200
    (run the curl block in APP_STORE_METADATA.md §"Quick URL verification")
[ ] Reply posted in Resolution Center with the recording attached and
    the §2-§6 text quoted
[ ] APP_STORE_METADATA.md "Notes for App Review" updated to match the
    new version of §2-§6 above (so the next submission ships with the
    same text already in place)
```

---

## 9. Suggested reply message (top of the Resolution Center thread)

Paste this as the first paragraph of the reply, then attach the
recording, then quote §2-§6.

```
Hello App Review,

Thank you for the detailed feedback. Below is the requested
information; the §1 screen recording is attached to this reply.
PeptideX has no developer backend, no third-party SDKs, and no
external AI services — every feature listed below runs on the user's
device. Sign-in is optional, so no demo credentials are required to
exercise the full feature set; the recording demonstrates this by
tapping "Continue without an account" at launch.

— The PeptideX team
support@peptidesai.com
```
