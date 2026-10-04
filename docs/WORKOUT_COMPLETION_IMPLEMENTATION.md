# Workout completion implementation

Reference: the first, near-black mockup supplied on 2026-10-04. This implementation uses SwiftUI controls and existing Atlas anatomy assets, not a mockup image background.

## Implemented flow

Finish confirmation → durable local repository write → Summary → Exercises / saved-workout editor / Muscle details / This week / Share → Done dismisses the existing workout cover.

| Area | Production implementation |
| --- | --- |
| Summary | Green success check, saved identity/date, actual weekly count, one responsive metrics card, exercise route, compact anatomy/named muscles, inset Done/Share footer |
| Muscle details | Map/list segmented control, catalog roles, named list, distinct contributing-set counts, exercise/set drill-down, mapping explanation and missing-mapping state |
| Exercises | Stable logged-entry order, existing bundled artwork/fallback, completed working sets, applicable volume, all-set detail including excluded warm-ups/incomplete sets |
| Saving | Indeterminate indicator around the actual save, no fake delay/percentages/sync checklist |
| Save error | Honest local-write error, retry using the same candidate identity, return to retained active workout |
| Alternate states | Sub-minute, not tracked, unavailable duration; no supported external volume; unmapped exercises; loading metadata/history failure |
| Weekly progress | Seven real calendar days, completed-workout counts, accessible day labels, conditional recorded volume |
| Share | Clean 3× image rendering, optional workout name/date, no private notes/account/time/location, existing native activity sheet, export/share failure handling |

## Findings and decisions

- iOS 18+, Swift 6, SwiftUI, SwiftData; project generated with XcodeGen. Reuses AppColor/AppFont/Spacing, SF Symbols, ExerciseLibrary, current PR engine and ShareSheet. No dependency, backend or schema migration added.
- Storage is local-first with optional CloudKit mirroring. No per-workout cloud progress or retry API exists; local success is sufficient and no invented sync state is displayed. Workout HealthKit export is not wired.
- Fixed a verified defect: finishing formerly ignored repository commit failure and discarded the active session. The durable method now throws, restores the affected row on failure, and leaves service state active. It rejects the production in-memory fallback as durable storage. In-memory stores remain available for explicitly isolated tests.
- Each active-set mutation already persists its draft. A failed Finish retains that draft; there is no unsupported blanket “your data is safe” promise. Relaunch reads the active row; a committed finish is an existing saved row, never a new ID. A retry keeps the original attempted finish timestamp.
- There was no saved-workout editor. The added value-type draft editor is reachable from Summary, Exercises and history's options menu. Cancel discards the draft; save retains session/entry/set IDs, recalculates PRs and refreshes current recap/widget/watch projections. Previously earned achievement awards remain historical; editing does not award them again or invent revocation behavior. No achievement tiles are shown.
- `WorkoutRecapEngine` is the single derivation used by completion destinations and share. Completed non-warm-up set IDs are distinct. Unused planned entries are excluded. Muscle contributions may overlap, but cannot inflate session working-set counts.
- Canonical kilograms remain unchanged. Older sets retain recorded load × reps. Optional additive JSON metadata explicitly distinguishes combined total, each of a pair (×2), and per-side recorded reps (×1). Equipment names never imply a multiplier. Bodyweight contributes only recorded added external load; assistance, timed and distance sets contribute no invented rep volume. Legacy cardio/stretch entries are not reinterpreted as volume.
- The editor exposes these explicit conventions and timed/distance measurements. The existing active logger retains its rep/load layout, with a small convention label for explicit loads. Reusing paired sets preserves their convention; timed/distance/assisted history does not become a rep/load seed or a rep/load personal record. Zero/bodyweight load is not presented as a misleading zero-volume workout; nil and unsupported totals render as unavailable with an explanation.
- Duration uses persisted end minus start minus accumulated pauses, preserving Atlas's pause-excluding meaning. Invalid/missing timestamps are unavailable. New manual quick logs without duration are explicitly not tracked; ambiguous old zero-duration records stay unavailable.
- Weekly grouping follows the existing start-date convention and `Calendar.current` local week/time zone. Qualifying recaps have a finish and completed working sets, or are saved legacy manual logs without structured exercise data. Summary and weekly chart use the same projection. Manual logs retain their workout count but show “Not logged” for missing set totals. The query is limited to this week and throws on failure rather than fabricating zero. Planning preferences have defaults, not a reliably explicit completion goal; no goal, streak, comparison or record tiles are invented.
- Raw bundled/custom exercise primary/supporting arrays drive mapping. The supplied fixture maps chest, shoulders and triceps; biceps are not invented. Primary wins a mixed-role summary, while drill-down preserves each exercise's role. Anatomy uses existing authored masks on the same 1024×1536 body coordinate system; no arbitrary ellipses or new 3D renderer. Named lists remain available if assets fail.
- Native activity-sheet destinations determine available apps and Save Image. Existing Photos add permission is declared in both Info.plist and XcodeGen configuration. Cancellation is normal; a share error never changes the workout.

## Main files changed

- `Peptide/Features/Train/WorkoutFinishView.swift`
- `Peptide/Features/Train/ActiveWorkoutView.swift`
- `Peptide/Features/Train/WorkoutSessionDetailView.swift`
- `Peptide/Features/Train/Completion/WorkoutRecapComponents.swift`
- `Peptide/Features/Train/Completion/WorkoutRecapDestinations.swift`
- `Peptide/Features/Train/Completion/WorkoutSavedEditor.swift`
- `Peptide/Features/Train/Completion/WorkoutSaveStatusView.swift`
- `Peptide/Features/Train/Completion/WorkoutShareView.swift`
- `Peptide/Services/WorkoutRecapEngine.swift`, `WorkoutRecapStore.swift`, `WorkoutRecapFixture.swift`
- `Peptide/Services/WorkoutEditValidation.swift`
- `Peptide/Services/WorkoutSessionService.swift`, `SwiftDataRepository.swift`, `ScreenshotMode.swift`
- `Peptide/Services/PRDetectionEngine.swift`, `RoutineSeedEngine.swift`, `Peptide/Features/Train/Components/SetEditorRow.swift` (measurement compatibility only; pre-existing animation edits kept separate)
- `Peptide/Models/Training/SetEntry.swift`, `WorkoutFocusState.swift`
- `Peptide/App/DataStore.swift`, `Peptide/DesignSystem/Theme/ColorTheme.swift`
- `Peptide/Features/Profile/Components/ExportSection.swift`, `Peptide/Resources/Info.plist`
- `PeptideTests/WorkoutRecapTests.swift`, `PeptideUITests/ScreenshotTests.swift`
- `project.yml`, `.github/workflows/screenshots.yml`, `scripts/contrast-check.py`

Unrelated pre-existing animation changes are not part of this implementation. The pre-edit finish view was backed up locally at `artifacts/completion-review/WorkoutFinishView.before.swift`.

## Verification

Local checks run on Windows:

- Design lint: zero errors/warnings after corrections.
- Design checker self-tests: 44/44 passed.
- Contrast: 288 token combinations pass AA, including the added recap surfaces/text/action/role pairs. This is arithmetic validation, not a native rendered visual review.
- Exercise catalog: 873 entries validated; 13 illustrations and 860 existing muscle-map fallbacks. This task does not pretend every exercise has bespoke artwork.
- Anatomy geometry: all 30 authored regions pass coverage/bounds/area/edge validation.
- Copy claims, fixture exercise IDs and App Store metadata checks passed.
- New Swift files parsed with tree-sitter; this is syntax screening, not Swift type checking. The UI test file has a pre-existing parser limitation also present at HEAD.
- `git diff --check` passed.

Added XCTest coverage (execution requires Xcode): consistent 5 exercises / 15 sets / 6,720 lb fixture; conversion and weekly reconciliation; mixed roles; duration branches/pauses; explicit load conventions; unsupported/timed/bodyweight sets; duplicate IDs; missing mappings; calendar boundaries; legacy JSON; save failure/retry/edit identity; temporary on-disk store reopen before and after finish. Production saving/error/alternate/share views produce image attachments. UI coverage traverses completion, edit, exercises, map/list/contributions, weekly, share/cancel, Done, save retry, light mode, long names and accessibility XXXL.

Fixture isolation: DEBUG plus `--completion-fixture` plus screenshot-mode flag are required. The repository opens a separate in-memory container before any user store; the fixture is never written into an account's real workout history. Save failure injection additionally requires `--completion-save-failure`.

## Native reproduction and remaining verification

On a Mac with Xcode:

```sh
xcodegen generate
xcodebuild test -project Peptide.xcodeproj -scheme PeptideTrainingValidation \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -parallel-testing-enabled NO -resultBundlePath TrainingTests.xcresult
xcodebuild test -project Peptide.xcodeproj -scheme PeptideUICapture \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PeptideUITests/ScreenshotTests/test_captureWorkoutCompletion \
  -only-testing:PeptideUITests/ScreenshotTests/test_captureWorkoutCompletionLayouts \
  -only-testing:PeptideUITests/ScreenshotTests/test_captureWorkoutCompletionSaveError \
  -only-testing:PeptideUITests/ScreenshotTests/test_captureWorkoutCompletionEditValidation \
  -parallel-testing-enabled NO -resultBundlePath Screenshots.xcresult
xcrun xcresulttool export attachments --path TrainingTests.xcresult --output-path screenshots/training
xcrun xcresulttool export attachments --path Screenshots.xcresult --output-path screenshots/ui
```

Choose an installed simulator name from `xcrun simctl list devices available`. Repeat the layout pass at 375×812, 393×852, a large phone and the smallest supported phone width. Snapshot attachments are named `completion-01…08`, with extra map/list/contribution/retry/layout captures. These are expected output locations, not a claim that screenshots already exist.

Remaining, ordered by importance:

1. Native compilation, XCTest/UI execution and visual inspection are not yet verified in this Windows environment. GitHub macOS CI has been rejecting jobs before execution due account billing; the current attempt will be recorded below. Do not treat parser/lint checks as an iOS build.
2. Once native execution is available, inspect all eight areas at actual phone scale, footer/scroll behavior, large-text metrics, native share cancellation/Photos denial, VoiceOver reading order and reduced motion. Exercise airplane-mode finish, force termination before/after the durable boundary, and actual CloudKit availability changes on a test device. No sync claim depends on these passing.
3. Existing anatomy is reused and aligned, but includes the project's shorts/shoe details. A replacement matte unclothed mannequin pack would need the same front/back crop and corresponding region masks, or re-authoring all 30 masks. No unlicensed external anatomy was added.
4. The existing catalog has many anatomy fallbacks, not full exercise-pose illustrations. They remain functional and accurately labeled.

Native run result: [37199438351](https://github.com/Wrexist/Atlas/actions/runs/37199438351), commit `dc9927f`, failed before any steps ran. GitHub's annotation: “The job was not started because your account is locked due to a billing issue.” No current native screenshots or test results were produced. Follow-up source compatibility fixes therefore also remain unbuilt until a macOS runner is available.

## Follow-up review, 2026-10-04

- Removed horizontal fixed sizing from metric values in the vertical fallback, so large text can wrap instead of clipping. The horizontal metrics card still uses its ideal width to select the appropriate layout.
- Summary and Weekly progress now refresh their shared store on app resume, calendar-day changes and time-zone changes. The weekly destination observes the store rather than capturing a stale week snapshot. Added tests for crossing Sunday/Monday and Stockholm's 169-hour daylight-saving week.
- Share presentation is driven by an identifiable rendered image instead of a separate boolean/image pair. Privacy choices are captured at the explicit Share tap, before rendering begins.
- Added a shared saved-edit validation boundary. Changing a completed set to timed/distance requires an actual positive measurement. A workout that previously had working sets must retain one. Older manual logs with no structured sets can still have their name/notes corrected.
- Numeric fields retain invalid text and block Save, instead of silently saving the last successfully parsed value. Parsing uses the locale's decimal separator, supports decimal digits and rejects blank/ambiguous input. Unedited canonical loads are not rounded back into storage. Added keyboard Done and an isolated UI test for blank input, correction and persisted reload.
- Kept history's intentional one-time session seed private and applied the same validation to its editor.
- Added history → View summary, with no repeated success haptic/announcement and a refresh of history after recap edits. This makes manual/missing-duration branches accessible through real saved data. Legacy manual workouts continue to count toward weekly workouts while their missing structured set totals remain unavailable.
- Raised recap supporting text from the existing 11-point caption token to the 15-point subheadline token. Metric values now use a native text-style token that respects the view's Dynamic Type environment. Added native snapshot cases at 320, 375, 393 and 430 points, including accessibility XXXL; those snapshots await macOS execution.

Follow-up local checks: design lint has zero errors/warnings; all 288 contrast pairs pass; new/changed production Swift files pass syntax screening. Focused XCTest and UI additions are **not executed** here. A fresh native attempt, [37200711167](https://github.com/Wrexist/Atlas/actions/runs/37200711167) at `a741d2e`, was again rejected with the same billing-lock annotation and no executed steps. No new native screenshots exist from this pass.
