# Exercise focus and catalog visual rollout

Implemented on 2026-10-03. The shared presentation now covers all 873 catalog exercises. There are 13 dedicated illustrations; 860 entries use their individual muscle maps. This is not completion of the bespoke 873-poster or live-metrics production work.

## Delivered code

- Active workouts now open a shared focused exercise screen: illustration, exercise navigation, editable pill fields, set progress, inline rest/skip/adjust controls, pause/resume, and actual session metrics.
- Incline Dumbbell Press uses a bundled transparent illustration in the hero and the shared image component (including library/picker thumbnails). Exercise details use the same hero and consistent muscle legend colors.
- Every exercise uses the same offline visual component in the workout, picker, routine rows and detail screen. Pending illustrations use the exercise's actual primary/secondary muscle map; remote photo thumbnails and the mixed-style photo carousel have been removed. Custom exercises retain their own muscle mapping.
- Workout options expose overview, add exercise, finish, and discard. Overview retains workout rename, exercise removal confirmation, rest settings, prior-set fill, and plate calculator. Set-number menus expose warmup/deletion in focus mode.
- Selection uses workout entry IDs so duplicate exercise entries stay independent. Rest context includes source and target set IDs.
- Pause/rest/selection state is persisted through an optional `StoredWorkoutSession.focusData` payload. Older records have nil focus state. Pause freezes active duration and remaining rest; resume reconstructs the deadline. Completion, undo and removal reconcile owned rest state.
- Rest expiration and Skip never log the next set. Completing the final working set does not create an unnecessary rest. Final completion exposes the existing finish flow.
- Live Activities project saved selection, pause, and rest data. History, finish, Home, and widget durations use the same pause-aware calculation.
- The original `RestTimerOverlay` and its separate state were removed. No second countdown owns the same workout.
- Thirteen exact-ID illustrations are bundled: incline dumbbell press, barbell squat, deadlift, flat barbell press, flat dumbbell press, barbell row, cable row, pull-ups, push-ups, dumbbell curl, lateral raise, leg press and plank. There is no name-based pose substitution.
- An exhaustive generated manifest accounts for all 873 entries. The production queue supplies exact movement/equipment/muscle briefs for the remaining 860; SHA-256 checks and unique-ID validation detect missing, changed or misassigned artwork.
- The rest/paused hero is more compact, completion checks use contrasting light glyphs, singular set counts read correctly, and detail metadata wraps into adaptive columns.

## Main files

| File | Role |
|---|---|
| `Peptide/Features/Train/Components/WorkoutFocusView.swift` | Focused layout, exercise strip, rest header and session footer |
| `Peptide/Features/Train/Components/ExerciseHeroView.swift` | Shared poster and anatomy fallback |
| `Peptide/Models/Training/ExerciseVisualAssets.swift` | Stable-ID manifest lookup |
| `scripts/exercise-art-catalog.py` | Registry/queue generation and integrity checks |
| `tools/exercise-art/README.md` | Production workflow and exact outstanding coverage |
| `Peptide/Features/Train/Components/SetEditorRow.swift` | Reused logging controls with focus style and accessibility-size reflow |
| `Peptide/Models/Training/WorkoutFocusState.swift` | Codable selection, pause and rest state; clock arithmetic and selection repair |
| `Peptide/Services/WorkoutSessionService.swift` | Authoritative completion, pause, rest and notification mutations |
| `PeptideTests/WorkoutFocusTests.swift` | Clock, persistence, progression and Live Activity regression tests |

## Checks completed here

- `python -X utf8 scripts/design-lint.py --all`: zero errors, zero warnings. UTF-8 mode is required by the existing script on this Windows machine.
- `git diff --check`: clean.
- Remote Xcode app/UI-test build and the expanded UI capture passed; see the run below. This does not substitute for the still-pending unit/device checks.
- Artwork: 1254 × 1254 RGBA PNG, 1,080,453 bytes, alpha range 0–255; catalog ID and asset-catalog filename verified.

## Required macOS and device validation

The remote macOS build and `ScreenshotTests/test_captureExerciseRollout` passed on iPhone 16 Pro Max in [run 37144600196](https://github.com/Wrexist/Atlas/actions/runs/37144600196), at app commit `a04f8e2`. Fourteen real captures are saved under `artifacts/exercise-rollout/` and were visually inspected. The run checked exact decimal weights and reps, set completion, rest/skip, pause/discard, adding several different exercises, correct selected artwork, and the muscle-map fallback in both appearances. Numeric selection no longer opens a competing row context menu. Four-set rest content still requires a small scroll to move the footer fully above the home indicator; logging and paused captures show the footer without that adjustment.

The workstation has no local Xcode/iOS SDK. The 16 new unit tests, hardware notification/Live Activity checks, and CloudKit migration have not yet been executed. The catalog validation and asset hash checks pass locally and the prior manifest check also passed on the macOS runner.

1. Generate the project with `xcodegen generate` and build the app plus widget and Watch targets.
2. Run `WorkoutFocusStateTests`, `WorkoutFocusServiceTests`, and existing workout/session/migration/activity/history tests. Run SwiftLint and existing PR checks.
3. Start a workout; add **Incline Dumbbell Press**; add four sets. Edit weight and reps, complete two sets, confirm inline rest and both completion markers.
4. Pause during rest; background/minimize, then resume. Confirm elapsed time and rest remain frozen while paused and agree with Live Activity state.
5. Relaunch during rest and while paused; confirm restoration. Undo the source set, delete the rest target, skip rest, and finish the final set. Confirm no extra set or stale rest alert.
6. Finish while paused and compare active duration in history, finish, Home and widgets. Repeat with an old stored workout to validate optional-field migration on a real store, including CloudKit.
7. Review small/large phones, dark mode, keyboard entry, VoiceOver, Reduce Motion and accessibility XXXL. Layout uses a scrollable panel and shrinks the hero at accessibility sizes. Default-size light/dark captures were inspected; small-phone and accessibility XXXL captures remain outstanding.

## Scope still outstanding

- Exercise-specific art for the remaining 860 catalog entries, specialist movement review, the shared rig/equipment production pipeline, and any animation. The 13 generated stills establish a visual benchmark; they are not a reusable 3D source scene or a reviewed full-library art pack.
- Duration/distance/assistance tracking modes and superset round progression remain separate phases. Existing weight/reps semantics are preserved in this slice.
- Live HR and session energy require the planned Watch/HealthKit capture work. The footer currently shows real set count, logged volume and active duration; it does not invent sensor readings.
- Versioned hosted media, catalog-wide prefetch/cache management and production artwork review remain later work.

## Artwork provenance and prompt

Built-in `image_gen` was used (no API/CLI fallback). The original output was copied into the repository without image post-processing. A static visual inspection found one complete figure, bench and two dumbbells in the requested composition; movement/anatomy review and on-device light/dark review remain part of release validation.

Saved asset: `Peptide/Resources/Assets.xcassets/ExerciseArt/atlas_incline_dumbbell_press.imageset/incline-dumbbell-press.png`.

Exact generation prompt, with `transparent_background: true`:

> Create one isolated transparent PNG illustration for the Atlas iOS exercise app, no UI, no text. Premium soft studio 3D anatomical fitness illustration. A neutral faceless gray muscular adult male mannequin wearing modest black athletic shorts and white trainers, reclined securely on a black adjustable workout bench at 30 degrees incline. Entire bench, feet, body, hands and two dumbbells visible with generous clear margins. Three-quarter front view, feet toward lower left, head toward upper right. Both feet planted on floor, shoulder blades and head supported, holding two equal dark adjustable dumbbells above upper chest at the top of an incline dumbbell press, forearms approximately vertical, wrists neutral, arms nearly extended but not hyperextended. Highlight pectoralis major in warm orange, anterior deltoids and triceps blue, rest of body gray. Anatomically plausible, two arms two hands, proper grips, clean symmetric dumbbells. Soft realistic matte materials and dimensional anatomy, delicate contact shadow, light studio illumination. Transparent background including all corners; no baked rectangular background, no gradients outside subject, no watermark. Compose a single subject, portrait-ish square canvas. This is a static exercise illustration, not a medical diagram.
