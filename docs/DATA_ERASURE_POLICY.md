# Atlas data-erasure policy

What "delete my data" means in Atlas, artifact by artifact. This is the
contract `AuthService.deleteAccount()` implements and the checklist any
future storage surface must be added to.

## Erased on account deletion (`AuthService.deleteAccount()`)

| Artifact | Where | How |
|---|---|---|
| SwiftData store (protocols, entries, profile, workouts, routines, custom exercises, personal records) | App container + user's private CloudKit zone | `SwiftDataRepository.deleteAll()`; CloudKit mirrors the deletions when sync is active |
| Legacy JSON (`protocols.json`, `entries.json`, `profile.json`) | Documents | `PersistenceService.clearAll()` |
| Archived migration safety nets (`*.migrated`) | Documents | `PersistenceService.clearAll()` — these carry name, email, body metrics, weight history |
| Custom peptides (`custom-peptides.json`) | Documents | `PersistenceService.clearAll()` |
| Widget snapshot (`widget-data.json`) | App Group container | `PersistenceService.clearAll()` |
| Progress photos | Documents/ProgressPhotos | `ProgressPhotoStorage.deleteAll()` |
| Scanned lab reports | Documents/LabReports | `LabReportStorage.deleteAll()` |
| Apple ID linkage (keychain email/name/identifier) | Keychain | `signOut()` |
| Pending and delivered reminders | Notification Center | `NotificationService.cancelAll()` |
| Recently scanned products | Caches | `BarcodeProductCache.clear()` |
| Custom foods and recipes in system search | CoreSpotlight index | `FoodSpotlightService.removeAll()` |
| AI data-sharing consent (chat and coach summary) | UserDefaults | `AIDataConsent.revoke()` — the next scan or question asks again |
| Onboarding funnel snapshot (step times, events, attribution channel) | UserDefaults | `OnboardingFunnelTracker.eraseAll()` |
| Onboarding training-experience answer | UserDefaults (`experienceLevel`) | removed in `eraseAllLocalData()` |

## Retained deliberately

- **HealthKit samples** the app wrote (workouts, nutrition). Health data
  belongs to the user's Health app and outlives any single app's account;
  Apple's own guidance treats Health as user-controlled storage, and users
  routinely expect workouts to survive an app's removal. Deleting them
  silently would destroy data the user may consider theirs. The user can
  remove Atlas-written samples in Health → Profile → Apps → Atlas →
  Delete All Data. If product ever wants in-app deletion, it must be a
  separate, explicit opt-in at deletion time — never automatic.
- **Medical-disclaimer acknowledgment** (`disclaimerAcknowledgedAt`). A
  timestamp that the user accepted the disclaimer, with no health or
  personal data in it; it is the record that the safety note was shown,
  so it outlives an erase.
- **iCloud backups** of the device are Apple-managed; files deleted above
  disappear from future backups.

## Retention of migration archives (no account deletion)

`*.migrated` files exist only after a **verified** migration (counts +
IDs checked; see `MigrationService.verificationFailure`). They are kept
`PersistenceService.archivedLegacyRetentionDays` (90) days as a rollback
safety net, then removed by `cleanUpExpiredArchivedLegacyFiles()` on
launch. Cleanup touches archive filenames only and can never delete a
live `.json` source file.
