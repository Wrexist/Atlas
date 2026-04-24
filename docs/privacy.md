---
title: Privacy Policy
---

# Privacy Policy — PeptideX

**Effective date:** April 24, 2026
**App:** PeptideX (iOS)
**Developer:** Peptides AI

## Summary

PeptideX is designed to be private by default. All of your data stays on your
device. We do not operate a backend server, do not run analytics, do not use
advertising SDKs, and do not share data with third parties. Nothing you enter
in the app — protocols, doses, journal entries, health metrics, achievements —
leaves your device unless you explicitly export it yourself.

## What data the app handles

### Data stored locally on your device
- **Protocol and dose data** you create (peptide name, dosage, schedule, notes)
- **Usage history** (dose logs, adherence streaks, achievements)
- **Your profile** (optional: display name, goals, preferences)
- **App settings**

This data is stored in your device's local app container using Apple's
standard persistence frameworks and, where applicable, shared with the
PeptideX Widgets extension via an App Group. It is **not** transmitted to
us or anyone else.

### Apple Health (HealthKit) — read-only
With your permission, PeptideX reads the following metrics from Apple Health
to correlate them with your protocol adherence:
- Heart rate and heart rate variability (HRV)
- Sleep analysis
- Active energy, step count, and workout data

PeptideX **does not write to Apple Health.** The `NSHealthUpdateUsageDescription`
permission is requested only because the HealthKit framework requires it; the
app never modifies your health records.

HealthKit data is processed entirely on your device. It is never uploaded, and
it is never combined with any identifier that leaves your device.

You can revoke HealthKit access at any time in **Settings → Privacy &
Security → Health → PeptideX**.

### Sign in with Apple (optional)
If you choose to sign in with Apple, PeptideX stores the opaque Apple user
identifier, and — only when Apple provides them on first sign-in — your name
and relay email, in your device's **Keychain**. These values are used solely
to personalize the app and to detect when you revoke access. They are not
transmitted to us. You can sign out at any time inside the app, and you can
revoke the app's access at any time in **Settings → Apple Account → Sign in
with Apple**.

Using PeptideX does not require signing in. Every feature works without an
account.

### Notifications
PeptideX schedules local dose reminders on your device using iOS's
`UserNotifications` framework. Notification content never leaves your device
and is not delivered through any remote push service.

### Purchases (StoreKit)
Subscriptions and one-time purchases are processed by Apple via StoreKit.
PeptideX receives a purchase receipt from Apple to unlock paid features; it
does not see or store your payment details. Apple's own privacy policy
governs the purchase itself: <https://www.apple.com/legal/privacy/>.

### Biometric authentication (Face ID / Touch ID)
If you enable the app lock, authentication is performed on-device by Apple's
LocalAuthentication framework. PeptideX never receives your biometric data —
only a yes/no result from the system.

## What we do NOT collect

- No analytics, telemetry, or crash reporting SDKs
- No advertising or tracking identifiers (IDFA or otherwise)
- No third-party SDKs that phone home
- No precise or coarse location
- No contacts, photos, microphone, or camera access
- No cloud storage of your protocols or health data (as of version 1.0)

PeptideX's App Privacy manifest (`PrivacyInfo.xcprivacy`) declares
`NSPrivacyTracking = false` and an empty `NSPrivacyCollectedDataTypes` list.

## Data sharing

We do not sell, rent, or share your personal data with third parties. We do
not have the ability to — your data never leaves your device.

## Data export and deletion

- **Export:** you can export your own data at any time as CSV or JSON from
  inside the app (Settings → Export).
- **Deletion:** deleting the app from your device permanently removes all
  PeptideX data stored locally, including your protocol history and cached
  HealthKit correlations. If you signed in with Apple, also revoke app access
  in **Settings → Apple Account → Sign in with Apple** to complete removal of
  the Keychain-stored identifier.

Because we do not operate a server, there is no remote copy of your data for
us to delete.

## Children

PeptideX is not directed at children under 13 and should not be used by them.
The app is intended for adults making informed decisions in consultation with
a qualified healthcare provider.

## Medical disclaimer

PeptideX is an educational and tracking tool. It is **not** a medical device,
and it does not provide medical advice, diagnosis, or treatment. Many
substances referenced in the peptide database are research chemicals not
approved for human use. Always consult a qualified healthcare provider before
starting, changing, or stopping any protocol.

## Your rights (GDPR / UK GDPR / CCPA)

Because all personal data is stored locally on your device and is under your
direct control, you can exercise the following rights at any time by using
the app itself:

- **Access / portability:** export your data via Settings → Export.
- **Rectification:** edit any entry directly in the app.
- **Erasure:** delete entries in the app, or uninstall to remove everything.
- **Withdraw consent:** revoke HealthKit or Sign in with Apple access in iOS
  Settings as described above.

We do not sell personal information as defined by the California Consumer
Privacy Act (CCPA). We do not have a Data Protection Officer because we do
not process personal data on our own systems.

## Security

Data is protected by the standard iOS sandbox and, for credentials, the iOS
Keychain with `kSecAttrAccessibleAfterFirstUnlock`. Enabling Face ID / Touch
ID app lock adds a second barrier. No security measure is perfect; enabling
a device passcode and keeping iOS up to date materially improves protection.

## Changes to this policy

If this policy changes, the effective date above will be updated and the
updated version will be made available at the same URL from which you are
reading this. Material changes will also be surfaced in-app.

## Contact

Questions or privacy requests:

**Peptides AI** — privacy@peptidesai.com

---

*This policy covers PeptideX version 1.0.0 and later.*
