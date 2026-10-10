# Easier portion entry and meal corrections

Scan review now offers **Enter exact grams** on included foods. The sheet holds a local draft, previews the same calorie/macro calculations as the review, and only changes the item on Apply. Cancel discards typing. The input accepts decimal points or commas without grouping separators and validates the established 5–2,000 g range. Invalid/partial values cannot be applied. Gram controls preserve fractional amounts after Apply, and preset highlights only match the actual selected amount.

Saved meal editing now includes Meal name. It trims surrounding whitespace, rejects an empty name, and updates the existing entry rather than replacing its identity, date, source or category. Cancel continues to discard the editor's local draft. Keyboard dismissal follows the existing editing flow.

## Files

- FoodPortionEditor.swift: exact entry, validation and preview.
- MealScanFlow.swift: integrated portion sheet and fractional display/steppers.
- MealEntryEditorSheet.swift: editable name and empty-name validation.
- FoodPortionInputTests.swift: decimal formats, boundaries, partial/invalid inputs.

## Verification

Passed locally: design lint (zero errors/warnings), token contrast (288 pairs), copy claims, syntax parsing of four Swift files, and git whitespace checks. Added XCTest coverage is not executed. Parsing does not validate SwiftUI types or native layout.

Native build/tests/screenshots remain unavailable locally on Windows. The last GitHub macOS attempt was blocked by an account billing lock before any steps: https://github.com/Wrexist/Atlas/actions/runs/37213083112.

Remaining device checks:
1. Scan a meal, select Enter exact grams, enter 125,5 and Apply. Confirm 125.5 g in an English locale (125,5 g in Swedish), matching preview kcal, and +10 g produces 135.5 g.
2. Enter an invalid amount; confirm Apply is disabled and no fake zero total appears. Cancel a valid draft and confirm the original portion remains.
3. Edit nutrition, then change exact grams; confirm corrected values scale. Reset estimate and verify the amount stays selected.
4. Open a saved meal, correct its name, Save, and verify ID/date/totals are unchanged. Confirm Cancel and empty-name validation.
5. Inspect small-phone and large-text layouts, VoiceOver labels, keyboard Done, and both sheets' dismissal. Run FoodPortionInputTests and existing food/meal suites before release.
