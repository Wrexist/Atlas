# Food scan and calorie review

Photo meal scan review now supports editing calories, protein, carbs and fat per included food through the existing nutrition editor. Values describe the current portion and are converted back to its per-100 g basis; later portion changes scale the correction. Reset estimate restores the original nutrition while keeping the chosen portion. Correcting nutrition invalidates the saved-to-library indicator so the revised food can be saved again. Renaming a food alone does not recalculate nutrition.

The meal total, final Log button, individual entries and combined meal use the same corrected item values. Calories remain independently editable rather than being replaced by a macro-derived estimate. The shared barcode/photo editor rejects negative, missing, noninteger and greater-than-100,000 inputs, with inline validation text.

Review now exposes the actual log date/time and permits correction. Existing photo-date and selected-day defaults remain; the button no longer incorrectly says Today. Camera captures reset stale photo timestamps. Repeated Log taps are guarded within the presentation. Existing DataStore save semantics are unchanged; no new durable-save guarantee is claimed.

Cancelled photo loads/analysis no longer show failure or apply stale results after cancellation. Camera-denied/restricted Use Library actions now open the library. Portion steppers have minimum hit areas; serving controls and presets use the existing gram-mode 5–2,000 g bounds consistently. No additional scan/upload or dependency was introduced.

## Files and checks

Changed MealScanFlow.swift, EditNutritionSheet.swift and EditableFoodItemTests.swift. Added tests for correction scaling, reset preserving portion, saved-library invalidation, and invalid corrections. Tests are authored but not executed.

Local design lint passed with zero errors/warnings; contrast checked 288 token pairs; copy claims and git whitespace checks passed. All three Swift files passed syntax parsing, which is not a Swift compile.

## Remaining native verification

This Windows environment lacks Xcode. The latest GitHub macOS attempt was blocked before execution by an account billing lock (https://github.com/Wrexist/Atlas/actions/runs/37213083112). No new native screenshots or live scanner results are claimed.

On an isolated device/test account:
1. Scan a meal, edit a food's kcal/macros, halve its portion and check the totals; reset and confirm the portion stays unchanged.
2. Exclude an item, log separately and as one meal in separate runs; compare displayed versus diary totals.
3. Pick an older photo, change its logging day, and confirm the diary date. Retake with the camera and verify the timestamp defaults correctly.
4. Cancel during image loading and analysis; verify no error or stale review appears. Test denied camera → Use Library.
5. Test negative/empty/oversized nutrition input, Cancel in the editor, repeated Log taps, VoiceOver, large text and small-phone layout. Run EditableFoodItemTests and existing meal scanner/logging regression suites.

Model recognition accuracy and daily calorie-target formulas were not changed by this review improvement.
