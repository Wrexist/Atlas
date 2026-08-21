# App Store Review Response — Guideline 2.1 (Information Needed)

This is the complete, ordered checklist for replying to App Review's
Guideline 2.1 information request for **Atlas v1.0.0**. Apple asked for
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

- Account registration / login / **account deletion** (Sign in with Apple is optional in Atlas, but the deletion path must still be shown)
- Paid content / subscription / purchase flows
- User-generated content + reporting/blocking (Atlas has none — say so)
- Every system permission prompt the app can trigger

### How to record (best way)

Use a real iPhone, not the Simulator — Apple explicitly says "physical
device."

1. **Reset app state** so prompts fire fresh:
   - Settings → General → iPhone Storage → Atlas → Offload App
   - Reinstall via TestFlight
2. **Disable "Do Not Disturb"** so notification banners can appear if you demo a reminder.
3. **Start screen recording**: Control Center → Screen Recording (long-press to enable mic if you want voice-over). Recording starts after a 3-second countdown.
4. **Run the script in §1.1.** Aim for 90-180 seconds. App Review prefers brevity over exhaustiveness.
5. **Stop recording**, trim head/tail in Photos (Edit → trim handles), AirDrop to Mac.
6. **Encode for upload**: keep under 250 MB. If you need to compress:
   ```bash
   ffmpeg -i raw.mov -vcodec h264 -crf 24 -preset slow -acodec aac Atlas-review.mp4
   ```
7. **Upload** as a reply attachment in the Resolution Center thread.

### 1.1 Recording script (run in this exact order)

| # | Action | Why it satisfies the reviewer |
|---|---|---|
| 1 | Tap Atlas icon on Home Screen | Proves cold launch on a physical device |
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
| 15 | Profile → Account → **Delete Account** → confirm in the alert | **Account deletion** (mandatory per 5.1.1(v)) |
| 16 | Settings app → Face ID & Passcode → confirm Atlas listed (optional, only if you ship app-lock) | Face ID purpose string |

### 1.2 If a flow does not exist, say so

Atlas has no UGC, no camera, no contacts, no location, no microphone.
Mention this in the Notes (§4) so the reviewer does not look for them.

---

## 2. App purpose, problem solved, value delivered

Paste verbatim into the Notes field:

```
PURPOSE
Atlas is a private, native iOS companion for training, nutrition,
recovery, and (for advanced users) clinician-advised supplementation
protocols. Everything the user logs stays on their device or syncs
through their own iCloud — there is no developer backend, no analytics,
and no tracking.

PROBLEM IT SOLVES
Fitness-focused users juggle separate apps for workout logging, macro
tracking, HRV/sleep analysis, habit streaks, and (for the advanced
audience) peptide protocol compliance. Atlas consolidates all five
surfaces into one private, on-device app with a recovery-first home
screen that ties them together.

VALUE TO THE USER
1. Log workouts in two taps — weight and reps are pre-filled from the
   last session; rest timer fires automatically.
2. Scan meals by barcode (200M+ products) or photo (AI vision).
3. Wake up to a Recovery Score built from HRV, resting heart rate,
   and sleep pulled from Apple Health.
4. Track any habit with a 6-month momentum heatmap and streak counter.
5. For users following clinician-advised protocols: build and log
   peptide/supplement cycles with dose reminders, compliance analytics,
   and a 208-compound research database with citations.
6. Export everything to CSV / JSON for personal records (Atlas Pro).

Atlas is an EDUCATIONAL and TRACKING tool. It does not prescribe,
sell, source, or recommend any compound for human use. The medical
disclaimer is acknowledged during onboarding and visible on every
peptide detail screen.
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
HOW TO REVIEW ATLAS

Sign-in:
• Sign in with Apple is optional. On the sign-in screen, tap "Continue
  without an account" — every feature works without an account.
• If you do sign in, Profile → Account exposes both "Sign Out"
  (clears the cached Apple ID identifier from the iOS Keychain on this
  device) and "Delete Account" (irreversibly erases all protocols,
  dose entries, and profile data, and removes the Apple ID linkage —
  Guideline 5.1.1(v) compliant).

HealthKit:
• HealthKit is requested ONLY when you tap "Connect Health" in the
  Profile tab. It is never asked automatically. Atlas is read-only
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
```

> **Status of these instructions vs. the codebase:**
> Delete Account ships in this build (`AccountSection.swift` →
> `AuthService.deleteAccount()`, calling `SwiftDataRepository.deleteAll()`
> + Keychain wipe; CloudKit propagation handled by SwiftData).
> A demo-data loader was **not** added — the recording in §1 logs
> doses live, so the reviewer doesn't need one. If you later add one,
> document the path here before re-pasting.

### 3.3 Implementation checklist for §3.2 to be true

- [ ] Verify "Continue without an account" is visible and unconditional on the sign-in screen (file: `Peptide/Features/Auth/`).
- [x] **Delete Account shipped.** `AccountSection.swift` exposes a destructive Delete Account button under the Sign Out button when the user is signed in. Confirms via `.alert`, then `AuthService.deleteAccount()` wipes SwiftData (`SwiftDataRepository.deleteAll()`) and Keychain. SwiftData propagates the delete to the user's private CloudKit zone. There is no developer-operated backend, so no server-side token revocation is needed; users can revoke at appleid.apple.com if they wish.
- [ ] Confirm "Restore Purchases" button is present on the paywall and on the post-purchase failure path.

---

## 4. External services / tools / platforms

This is the question the reviewer most often re-asks if the answer is
vague. Be exhaustive. Paste verbatim:

```
EXTERNAL SERVICES USED BY PEPTIDEX

Atlas has NO developer-operated backend. No analytics SDKs, no
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

Atlas is functionally identical in every region where it is offered.
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
whether the developer is licensed/authorized. Atlas positions itself
as **educational and tracking only**, which is the established pattern
that does not require credentials. Paste verbatim:

```
REGULATED-INDUSTRY POSTURE

Atlas is a tracker and educational reference, not a medical device,
not a pharmacy, not a telehealth service, and not a marketplace. It
does not prescribe, diagnose, treat, sell, source, or recommend any
compound for human use. Many compounds in the database are explicitly
labeled as research chemicals not approved for human use, and the app
shows this disclaimer:

  "Atlas is an educational and tracking tool. It is not a medical
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

- [ ] Subscription **title** for each tier (Atlas Pro Monthly / Annual / Lifetime)
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
| `NSFaceIDUsageDescription` | "Atlas uses Face ID to protect your peptide protocols and health information." | ✅ Reason given. Could mention the example ("for example, when opening the app after backgrounding"). Optional polish. |
| `NSHealthShareUsageDescription` | "Atlas reads heart rate, HRV, resting heart rate, body mass, steps, and active energy from Apple Health to correlate your peptide protocols with biometric trends. All analysis happens on your device — nothing is sent off the device." | ✅ Excellent — explicit metrics, explicit purpose, on-device guarantee. |

Notification permission has no plist key (it's prompted via
`UNUserNotificationCenter`) but the in-app pre-prompt should explain
**why**: "Atlas uses notifications to remind you of scheduled doses
and let you log them with one tap." Verify this string exists in the
auth flow.

If you add any new permission later (camera for QR import, contacts,
location), the purpose string MUST follow the pattern: **what + why +
example**, e.g. "Atlas uses your camera to scan barcode peptide
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
Atlas is a fitness, nutrition, and recovery tracking app — no
developer backend, no third-party SDKs, and no external AI services.
Every feature runs on the user's device. Sign-in is optional, so no
demo credentials are required; the recording demonstrates this by
tapping "Continue without an account" at launch.

— The Atlas team
support@peptidesai.com
```

---

## 10. Guideline 3.1.2 — Terms of Use (EULA) link  *(build 1.2.0 (135))*

### What Apple said

> The submission offers auto-renewable subscriptions but does not include
> a functional link to the Terms of Use (EULA) in the app's metadata.

This is a **metadata** rejection, not a binary one. Nothing in the app is
wrong — the paywall (`PaywallView.swift`) and the onboarding trial offer
(`TrialOfferView.swift`) already link to Apple's standard EULA and to the
privacy policy, and the auto-renew disclosure sheet already states price,
period, and how to cancel. What was missing is the same EULA link in the
**App Description**, which is the field Apple means by "metadata."

### Why it happened

App Store Connect has no "Terms of Use" URL field. The
App Information → License Agreement field only accepts a **custom** EULA.
Atlas uses Apple's **standard** EULA, and Apple's rule for that case is:
put the link in the App Description. The description had the pricing and
the trial lengths but no links.

### The fix (no new build required)

1. **App Store Connect → your app → the rejected 1.2.0 version →
   Description.** Replace the description with the copy in
   `APP_STORE_METADATA.md` → *Description*. It now ends with:

   ```
   SUBSCRIPTION TERMS
   Atlas Pro Monthly ($9.99, renews monthly) and Atlas Pro Annual ($49.99, renews
   yearly) are auto-renewable. Atlas Pro Lifetime ($169) is a one-time purchase and
   does not renew. Payment is charged to your Apple Account at confirmation.
   Subscriptions renew unless auto-renew is turned off at least 24 hours before the
   period ends. Manage or cancel in Settings > Apple Account > Subscriptions.
   Unused free-trial time is forfeited on purchase.

   Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
   Privacy Policy: https://wrexist.github.io/Peptide-ai/privacy.html
   ```

   Paste the URLs as **plain text** — App Store Connect linkifies them.
   Do not shorten, redirect, or wrap them in markup; a redirect is the
   most common cause of a repeat 3.1.2 rejection.

2. **Leave App Information → License Agreement on the standard EULA.**
   Do not paste a custom agreement — a custom EULA has to be reviewed and
   must then be the thing you link to, which is more surface to get wrong.

3. **Confirm the Privacy Policy URL** is still
   `https://wrexist.github.io/Peptide-ai/privacy.html` and returns 200.

4. **Save**, then reply in the Resolution Center with §10.1 and click
   **Submit for Review** on the same build. No new binary, no new build
   number.

### 10.1 Resolution Center reply

```
Hello App Review,

Thank you for the note. We have added a functional link to the Terms of
Use (EULA) to the app's metadata.

The App Description now ends with a SUBSCRIPTION TERMS section stating the
subscription title, length, and price for each auto-renewable product,
followed by:

Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://wrexist.github.io/Peptide-ai/privacy.html

Atlas uses Apple's standard EULA, so the link points to Apple's standard
Terms of Use as described in Schedule 1. Both links are also present and
tappable inside the app on the subscription purchase screen and on the
onboarding trial offer, alongside the auto-renewal disclosure.

No binary changes were needed, so we have resubmitted the same build for
review.

— The Atlas team
support@peptidesai.com
```

### 10.2 Verify before resubmitting

- [ ] `curl -sI https://www.apple.com/legal/internet-services/itunes/dev/stdeula/ | head -1` → 200
- [ ] `curl -sI https://wrexist.github.io/Peptide-ai/privacy.html | head -1` → 200
- [ ] Description saved and under 4 000 characters (it is 3 888)
- [ ] Both URLs render as tappable links in the App Store Connect preview
- [ ] Every localization of the description carries the same two links —
      a localization missing them re-triggers 3.1.2
- [ ] Promotional Text was **not** used for the links (it is not part of
      the description Apple checks)
