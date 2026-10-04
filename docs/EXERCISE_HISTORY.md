# Exercise history

Exercise details now include a read-only **Your history** card before muscle anatomy and instructions. Open Train → Exercises → an exercise to review it. The same detail screen is available from workout instructions.

- Last 90 rolling days, selected by workout start time, consistent with existing history dates. Completed sessions only; completed non-warm-up sets only.
- Latest three workouts initially, with Show all for the complete window. A chart shows working-set counts for the latest eight visits, oldest to newest. Dates and actual set values are accessible in the list.
- Workout links open the existing saved-workout detail/editor. DataStore revisions and foregrounding refresh history. Canonical units remain unchanged; presentation uses the current profile preference.
- Uses WorkoutRecapEngine for set inclusion and deduplication. Repeated entries for the same exercise are combined per visit; session IDs are deduplicated. Existing timed, distance, bodyweight and load-convention formatting is reused without inferred multipliers.
- No strength claims, new personal-record calculation, or comparison of incompatible load conventions. Chart counts are logged activity, not estimated activation.
- Uses an existing throwing, date-bounded repository read so a read failure produces Retry rather than a false empty history. No persistence changes or dependencies.
- Exercise-library failure now exits the loading state with Retry.

## Files

ExerciseDetailView.swift, Components/ExerciseHistorySection.swift, Services/ExerciseHistoryEngine.swift, PeptideTests/ExerciseHistoryTests.swift.

## Verification

Local checks passed: design lint (0 errors/warnings), token contrast (288 pairs), copy claims, git diff whitespace, and tree-sitter syntax parsing of all four Swift files. Syntax parsing does not compile Swift or validate SwiftUI types.

Added XCTest cases for active/warm-up/incomplete exclusions, unrelated exercises, duplicated sessions/entries/sets, chronological ordering, preserved paired/timed measurements, and edited-session identity. These tests have not run: this Windows workspace has no Xcode. The latest native Actions attempt in this branch was rejected before any steps because the GitHub account is locked by a billing issue: https://github.com/Wrexist/Atlas/actions/runs/37213083112. No new native screenshots are claimed.

## Remaining native checks

1. Run ExerciseHistoryTests and the app build on a Mac after runner access is restored.
2. Open a previously logged exercise; confirm latest three workouts and Show all, then open one, edit reps, return, and verify the updated row. Change display units and repeat.
3. Check an unlogged exercise, a timed/bodyweight exercise, multiple visits on one day, large text, VoiceOver, and 375-point width. Confirm all destinations work from both the library and the active-workout instructions sheet.
4. Inject a repository read failure and library load failure in an isolated test build; verify Retry without changing stored workouts. Capture actual device screenshots of loaded, empty and error states.
