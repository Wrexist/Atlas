# Atlas interaction polish — 2026-10-04

## Implemented

- Shared glass and primary actions use the existing ScalePressStyle: restrained
  160 ms response, no scaling or animation under Reduce Motion. CTA text wraps
  rather than shrinking at accessibility sizes. No extra automatic haptics.
- Workout art no longer shrinks when rest starts. Status content fades separately
  from set rows, with a reserved standard-size header and natural accessibility
  reflow. Completing/unchecking a set clears keyboard focus. Rest has Skip,
  Adjust, and explicit Undo; elapsed rest gives foreground selection feedback
  and a VoiceOver announcement. Rest still uses persisted deadlines.
- Undo resolves the current rest's source by stable entry/set IDs, preserves
  edited reps/load, uses the established update/persist path and returns focus
  to that exercise. Repeated Undo cannot undo another record. Paused workouts
  reject it. Existing repairFocus already cancels invalid rest and notifications.
- Train foregrounds Start/Resume and the latest workout, with View all opening
  history. Detailed trends and the calendar are expandable. Expansion and map
  period use scene storage; overview scroll position is owned by Train.
- Exercise browsing state is owned by Train: search, filters and scroll identity
  survive section switches. Changed filters clear stale scroll targets. Native
  iOS 18 zoom links list rows to details; Reduce Motion uses standard navigation.
  Active-workout instructions use an item-backed sheet with a stable exercise.
- Library loading is distinct from unavailable/empty/results. Failed loading
  exits the spinner and exposes Retry. Existing catalog caching is retained.
- Muscle highlights use a brief tint transition; selection has tactile feedback,
  a named row and the existing aligned outline/list route. Role copy consistently
  says Supporting across these edited training surfaces.
- Artwork retains aspect ratio and a shared neutral thumbnail surface. Missing
  bundled images now fall back to the exercise's mapped anatomy. Unillustrated
  thumbnails include an equipment glyph; labels reflow on narrow/large-type rows.
- Achievement confetti doesn't replace an active habit/level-up burst. Home
  defers mounting its achievement toast while the celebration queue is occupied,
  retaining its existing achievement queue and dismiss/acknowledgement behavior.

No storage migration, new dependency, new physiological interpretation, or
exercise substitution was introduced. The existing workout saved check remains.

## Files

DesignSystem: `Animations/StaggerHelper.swift`, `Components/GlassButton.swift`,
`Components/PrimaryCTAButton.swift`.

Train: `TrainContainerView.swift`, `TrainOverviewView.swift`,
`ExerciseBrowsingState.swift`, `ExerciseLibraryView.swift`, `ExerciseDetailView.swift`,
`ActiveWorkoutView.swift`; components `WorkoutFocusView`, `SetEditorRow`,
`ExerciseHeroView`, `ExerciseImageView`, `ExerciseRow`, `TrainingBodyExplorer`,
`MuscleMapView`.

Other: `Services/WorkoutSessionService.swift`, `Home/HomeView.swift`,
`Home/Components/CelebrationHostView.swift`.

Tests: `WorkoutFocusTests.swift`, `ExerciseBrowsingStateTests.swift`,
`PeptideUITests/ScreenshotTests.swift`.

Pre-existing milestone/pulse work was preserved. This document describes this
interaction pass, not every uncommitted animation change in the workspace.

## Verification

- `python -X utf8 scripts/design-lint.py --all`: 0 errors, 0 warnings.
- `python -X utf8 scripts/contrast-check.py`: 288 token pairs, none below AA.
- `python -X utf8 scripts/check-copy-claims.py`: passed.
- `python -X utf8 scripts/exercise-art-catalog.py --check`: passed; 873 entries,
  13 dedicated illustrations, 860 mapped fallbacks.
- Swift tree-sitter source checks: changed app/unit-test sources parse. The UI
  screenshot file has the same parser limitation at HEAD; this is not a Swift
  compiler or XCTest result.
- Added XCTest coverage for durable Undo, preserving edited measurements,
  repeated Undo, pause protection, and browsing-state reset behavior.
- Added UI coverage/capture routes for rest Undo and re-completion, returning from
  details, switching sections with an active search, and expanded training trends.

## Remaining verification and assets

1. Native compilation, XCTest, visual screenshots and frame pacing are not
   verified on this Windows host. Xcode/Simulator are absent. The last macOS
   Actions attempt was refused by GitHub's account billing lock before any steps.
   No new native screenshot is represented as captured here.
2. Run `xcodegen generate`, then the Peptide test scheme for
   WorkoutFocusServiceTests and ExerciseBrowsingStateTests. Run PeptideUICapture
   with ScreenshotTests/test_captureWorkoutFocus and
   ScreenshotTests/test_capturePremiumTrainingContinuity. Captures use isolated
   ScreenshotMode fixtures, never the user's live workouts.
3. Inspect at 375×812, 393×852, the smallest supported width and larger phones;
   repeat with accessibility XXXL and Reduce Motion. Check set-row positions
   around rest, header wrapping, keyboard dismissal, zoom cancellation, restored
   scroll, VoiceOver announcements and rapid Undo/re-completion. Test background
   rest expiry and simultaneous achievement/level-up notifications.
4. Dedicated artwork is still incomplete: 860 exercises use accurate mapped
   fallbacks. Existing per-exercise production briefs and registry are in
   `tools/exercise-art/pending.jsonl` and `catalog.csv`. Each new pose needs
   movement/equipment/highlight review before registration. This pass does not
   claim that 860 new exercise illustrations were produced.

Screenshot names prepared by UI tests: `premium-01-library`,
`premium-02-exercise-detail`, `premium-03-restored-search`, `premium-04-overview`,
`premium-05-training-trends`, plus existing `incline-light/dark-*` captures.
