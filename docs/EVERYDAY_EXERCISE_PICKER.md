# Everyday exercise picking

The existing shared Add exercise sheet now keeps an ordered selection tray above its Add button. Search and muscle/equipment filters do not clear selections. Each selected exercise can be removed directly, and Clear removes all picks. Clearing search/filters preserves picks. The footer uses the existing safe-area inset so it reserves space in the list.

The same behavior serves active workouts and routine building. Cancel retains its existing behavior: uncommitted exercise selections are discarded. Custom exercise creation retains its existing save behavior and appends the new exercise after existing picks.

Loading and failure are now distinct from no results. A failed library load offers Retry and preserves selection. Empty search offers Clear search and filters as well as custom exercise creation. Scrolling dismisses the keyboard interactively. Selection icons occupy their own column instead of overlaying long exercise labels.

ExercisePickerSelection owns stable-ID ordering and a one-time commit guard. Repeated Add/custom completion callbacks cannot re-submit the selection within the same presentation. This does not change the parent's persistence behavior or intentionally repeated exercises already present in a workout.

## Files

- Peptide/Features/Train/ExercisePickerSheet.swift
- Peptide/Features/Train/ExercisePickerSelection.swift
- PeptideTests/ExercisePickerSelectionTests.swift

## Checks

Passed locally: design lint (zero errors/warnings), contrast tokens (288 pairs), copy claims, Swift syntax parsing for all three files, and git diff whitespace checks. Parsing is not compilation.

Added XCTest coverage for stable-ID removal, ordering, clear/reselect, empty commit, duplicate custom exercise handling, and repeated commit protection. XCTest and native visual verification have not run in this Windows workspace. No Xcode is available; the latest macOS Actions attempt was blocked before running by the GitHub account's billing lock: https://github.com/Wrexist/Atlas/actions/runs/37213083112.

## Native reproduction / remaining verification

1. Start an isolated workout and open Add exercise. Pick two exercises, search for a third, and select it. Confirm the tray keeps the original order.
2. Apply a muscle/equipment filter that hides those exercises. Remove the middle pick from the tray. Clear search/filters; the two remaining rows should still be selected.
3. Tap Add repeatedly. Confirm only two entries are added, in tray order. Repeat in the routine builder.
4. Select exercises then Cancel; confirm the parent has no additions. Reopen, select exercises, create a custom exercise, and confirm it follows the selected exercises.
5. Test 375-point width, accessibility text, long names, VoiceOver removal labels, and keyboard visibility. Verify the footer and last row remain reachable, then capture native screenshots.
6. In an isolated test build, inject library load failure and verify Retry does not clear the selection or suggest the catalog is empty.
