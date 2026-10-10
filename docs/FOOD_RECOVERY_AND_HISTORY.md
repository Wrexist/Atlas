# Food recovery and history improvements

Implemented the six requested priorities, beginning with scan-draft recovery. No backend, new login, paid dependency, or storage reset was added.

## 1. Recoverable scan review

The photo scanner stores the review's editable foods, original nutrition estimates, portions, exclusions, replacement-food identity, date/category, meal name, combine choice and a resized JPEG together in an atomic, protected Application Support file. The directory is excluded from backup. Resume reopens the review without another AI request. Discard is explicit. Camera/image analysis in progress is not a recoverable review until results arrive.

Close flushes review edits; background transitions also flush. Interactive swipe dismissal is disabled during review so a failed draft write cannot be silently ignored. A write failure leaves the review open with Retry. A read/decode failure offers retry or explicit discard without silently overwriting the file. Identical snapshots skip redundant writes.

The file is device-local and checked against a hashed iCloud identity token. Existing account-change and data-deletion hooks clear it; an open scanner also checks a generation token before saving. Screenshot mode never reads/writes real drafts.

## 2. Confirmation and Undo

Photo scans now finish with Meal logged, actual kcal/date, Done and Undo meal log. Undo removes the complete scan batch and returns to review. The persisted draft includes the pending entry IDs and undo intent so reopening after interruption can finish the same operation. Repeated retries skip IDs already recorded. Done removes the recovery file; failure to remove it does not mark the saved meal as unsaved.

## 3. Stored portions and ingredients

MealEntry has optional food-component snapshots: stable component identity, food name/source, grams, serving information and per-100 g nutrients. New photo logs, food-library/barcode logs, and fully resolved recipes retain those snapshots. Re-log preserves them with a new meal ID. Legacy JSON decodes with unknown components; existing meals are not backfilled with invented amounts.

The saved-meal editor lists the stored foods and allows exact gram edits, recalculating macros across the components. It explains that this replaces manual macro totals. Portion multipliers also scale stored grams. Direct macro edits retain the recorded food/portion snapshot; fiber/sugar are explicitly described as coming from that snapshot.

## 4. Replace wrongly detected food

Each included scan item has Replace with another food. It searches the existing food service and local custom foods, previews replacement kcal at the current gram amount, and requires Replace food to apply. Search is debounced/cancellable; failures retain access to local foods. Cancel changes nothing. Replacement preserves the scan item's ID, grams and inclusion; it changes the food/nutrition and invalidates the saved-library indicator. Reset estimate restores the original scan nutrition and pre-replacement label.

## 5. Durable photo-save boundary

The new photo completion path builds a candidate profile and asks SwiftData for an explicit durable commit before assigning it to DataStore and announcing success. Fallback/inoperable storage fails honestly. Errors restore the profile row's previous content without rolling back unrelated objects. Retry reuses draft entry IDs. All items in one photo are committed through one profile save.

Health writes start after local success and photo-log/Undo tasks are ordered. Health remains optional; its failures do not invalidate a saved local meal. This is not a new durable Health retry queue, and a process termination before a Health write may still require integration reconciliation. Existing barcode/library save semantics are unchanged.

## 6. Fiber and sugar history

Available source fiber and total-sugar values survive logging and re-logging through the component snapshots. Saved meal details show them. The selected day's food entries have a Fiber & sugar card with explicit partial/unavailable treatment. Missing data is never inferred as zero; known zero stays zero. Photo estimates currently do not supply these nutrients, so their absence remains visible. No micronutrient targets, sodium values, or added-sugar claims are invented.

## Files

- Recovery: Services/MealScanDraftStore.swift, Components/MealScanFlow.swift.
- Saving: App/DataStore.swift, Services/SwiftDataRepository.swift.
- History: Models/MealFoodComponent.swift, MealEntry.swift, ScannedProduct.swift; App/LifestyleDataLogic.swift, RecipeDataLogic.swift.
- UI: ReplaceScannedFoodSheet.swift, MealNutrientDetails.swift, FoodPortionEditor.swift, MealEntryEditorSheet.swift, EditNutritionSheet.swift, HomeMealsSection.swift.
- Tests: MealScanRecoveryTests.swift and ScreenshotTests.test_captureFoodReviewRecovery.

## Verification status

Local design lint passed with zero errors/warnings, token contrast checked 288 pairs, copy claims passed, and git whitespace checks passed. Sixteen changed/new Swift files passed syntax parsing. These are not Swift compilation or native layout verification.

Added focused XCTest coverage for draft round-trip (including corrections/exclusions/date/undo identities), corrupt/read/write errors, persistent save failure/retry/relaunch, duplicate prevention, failed/repeated Undo, legacy JSON, replacement/scaling, re-log snapshots, and partial-versus-zero nutrient values. Tests are authored; execution requires Xcode.

Added a screenshot/UI route using only explicit screenshot-mode fixtures (no upload or real storage). It captures draft recovery, review, exact portions, and logged/Undo, then verifies return to review. Run selector: `ScreenshotTests/test_captureFoodReviewRecovery`.

Native verification was attempted for commit `7232330`: [run 37233282069](https://github.com/Wrexist/Atlas/actions/runs/37233282069), job/check `111527286651`. It failed before any steps with the annotation: “The job was not started because your account is locked due to a billing issue.” No build, XCTest, camera verification, or screenshot capture ran. A subsequent focused fix prevents an old open scanner from closing/deleting another account's draft after an identity switch; that fix also remains native-unverified.

## Remaining verification, highest priority first

1. Build and run MealScanRecoveryTests, existing food/recipe/persistence suites, and the screenshot route on macOS. This Windows environment has no Xcode; the most recent prior native run was blocked by GitHub billing before any steps.
2. On a test device: scan → correct portions/macros/exclusions/date → Close → reopen → Resume; force-quit after review and repeat. Verify no extra scan request/quota consumption on Resume.
3. Inject save failure; Retry twice and verify exactly one batch. Force-quit around saving and Undo; reopen and finish the pending operation. Check daily totals and historical dates. Test account changes and storage-full draft failures.
4. Test food replacement online/offline, cancellation, long names, duplicate search results and saved-food selection. Verify the current grams stay fixed.
5. Verify exact component edits, manual totals and portion multipliers, known/unknown fiber/sugar, recipe snapshots and legacy meals. An existing recipe with deleted/unresolved foods still uses the app's prior partial-macro calculation; this change leaves its ingredient/nutrient snapshot unavailable rather than inventing missing foods.
6. Inspect 375-point and larger phones, accessibility text, VoiceOver, reduced motion, keyboard/sheet behavior, Health write/Undo ordering, and current light mode. No fresh native screenshots are claimed until that run succeeds.
