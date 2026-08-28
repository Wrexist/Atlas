# CloudKit multi-device hardware test plan

Repeatable manual pass for everything unit tests cannot verify: real
CloudKit sync between devices. Run before any release that touches
`SwiftDataModels.swift`, `PeptideAtlasSchema.swift`, or
`SwiftDataRepository.swift`.

**Status: NOT VERIFIED ON HARDWARE** for the Data Integrity 04 changes
(profile column split, singleton reconciliation, schema V3). Every item
below must be checked on real devices before those changes are
considered verified.

## Setup

- Device A and Device B, both signed into the same Apple ID, iCloud
  Drive on, Atlas installed from the same build.
- A third "fresh" device (or a reinstall slot) for the new-device case.
- Airplane mode toggles will be used; give each sync step up to a few
  minutes — CloudKit is eventually consistent.

## 1. Basic propagation (A creates → B receives)

On Device A create, then confirm each appears on Device B:

1. A protocol (with schedule) → appears in Protocols on B.
2. Today's dose entry logged complete → completed on B.
3. A workout (2 exercises, a few sets) → appears in Train history on B.
4. A profile change (rename + a habit added + a meal logged) → all on B.

## 2. Concurrent independent edits (the Phase 3 fix)

With both devices online and synced:

1. Within the same minute: Device A logs a **meal**; Device B checks a
   **habit** and logs a **weigh-in**.
2. Wait for sync both ways.
3. PASS: A shows B's habit check + weigh-in; B shows A's meal. Nothing
   reverted. This is the field-level-merge behaviour the profile column
   split exists for — before the split one device's blob silently
   erased the other's.
4. Repeat with: A adds a lab value, B edits nutrition targets.
5. Same-feature conflict (both log a meal): last writer wins **within
   meals only** — the loser's meal may drop (known limitation), but
   habits/labs/etc. must be untouched.

## 3. Simultaneous create / edit / delete

1. Both devices delete the same protocol → it stays deleted, no
   resurrection.
2. A edits a protocol's schedule while B logs one of its doses → both
   changes present after sync.
3. A deletes a workout that set a PR → PR on both devices rolls back
   (Phase 6) after sync + app foreground.

## 4. Duplicate-profile reconciliation (the Phase 8 fix)

1. Put a fresh device in airplane mode, complete onboarding offline
   (creates a local profile row), then reconnect while Device A is
   online with its own profile.
2. Wait for sync, then foreground the app on both devices twice.
3. PASS: both devices converge on one profile (newest `updatedAt`
   wins); no flip-flopping between two profiles across launches; the
   Console shows the "Reconciling N StoredProfile rows" line at most
   once per device.

## 5. Offline / reconnect

1. Device A in airplane mode: log 3 doses, a meal, a habit.
2. Reconnect → everything appears on B exactly once (no duplicates).
3. While A was offline, B logged the same dose entry → after sync both
   devices agree on one completed state.

## 6. Watch duplicate delivery (Phase 1)

1. With poor phone-watch connectivity (phone at edge of range), mark a
   dose complete on the Watch twice in quick succession.
2. PASS: the dose is complete on the phone and stays complete; a
   duplicate delivery never flips it back to incomplete.

## 7. Account switch / reinstall / new device

1. Sign the device into a different iCloud account → previous account's
   data must disappear from the UI (identity-change observer).
2. Sign back in → data returns after sync.
3. Delete and reinstall the app → after first launch + sync, protocols,
   entries, profile (including meals/habits/momentum from the split
   columns), workouts and PRs are all back.
4. Brand-new device, same Apple ID → same result; exactly one profile
   row (case 4).

## 8. Schema upgrade in place

1. Install the **previous** App Store build on Device A with real data.
2. Update to the build under test (TestFlight) without deleting.
3. PASS: launch succeeds (no migration crash), all data present, and a
   subsequent save + sync round-trips to Device B. Legacy-blob data
   (meals/habits logged on the old build) must survive and appear on
   both devices.

## Recording results

Copy this file's checklist into the release notes PR and mark each item
PASS/FAIL with device models + iOS versions. Any FAIL blocks release.
