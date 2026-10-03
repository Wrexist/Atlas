# Body training map

## Implemented

- A versioned front/back gray fitness mannequin rendered from unchanged image-generation outputs. It wears fitted full-coverage training clothing. Two 1024 x 1536 images live in `Assets.xcassets/AnatomyV2`.
- Thirty muscle-region paths in `Resources/anatomy-regions-v2.json`. Every region is bilateral. `TrainingAnatomy.path` supplies both the tint clip and the tap target, so the two cannot drift independently.
- Shared `SessionMuscleCard` in active workout overview, completion and saved workout details. Only exercises with at least one completed non-warmup set contribute. Undoing the last completed working set removes the exercise's highlights.
- Today / 7 days / 30 days selection on the Train map. Detail sheets use the same period. The training-history card uses all history or the matching twelve-calendar-week boundary.
- Muscle detail sheets show actual completed set counts and contributing saved workout links. An accessible menu also opens muscle details without requiring precise diagram taps.
- The history card is named Training history rather than Muscle gains. Weighted visualization scores are labeled separately from actual sets. These estimates do not measure activation, growth or recovery.
- Existing catalog posters remain unchanged: 13 dedicated poses, 860 muscle-map fallbacks. All fallbacks now share the new body renderer.
- The finish confirmation sheet is owned by the stable workout navigation container. Finishing switches the content to the summary and closes only that sheet; the summary remains until Done. The UI capture exposed the previous conditional-presenter/double-dismiss bug.
- Today milestone prompts only present while Today is selected, including a second check after their deferred delay. Hidden Today content can no longer interrupt a workout summary on Train.

## Artwork provenance and maintenance

Generated using the built-in image generation tool. Exact prompts are in `tools/anatomy/prompts-v2.json`. The initial unclothed concept was rejected; the selected production images show a fully clothed mannequin. Source PNG alpha is preserved; apparent background color in RGB channels is transparent in the actual alpha channel.

Muscle locations are illustrative, manually authored overlays, not anatomical segmentation inferred from scans. They need specialist review before making stronger anatomical claims. Do not independently resize/crop the art or reuse old `BodyAnatomy` masks with these images. Update source art and region geometry together. The original asset pack remains a fallback if the new pack is incomplete.

## Verification

- Local design lint, catalog validation and diff checks pass.
- Dedicated `PeptideTrainingValidation` scheme runs the muscle heatmap, gains aggregation, workout focus and artwork tests without compiling the unrelated legacy test backlog.
- `test_captureMuscleTraining` exercises period controls, logs a working set, opens the active map and muscle sheet, finishes a workout, and captures the result in light and dark appearance.
- Native app build, all **50 training tests**, and the complete UI capture test passed on app revision `fe82665` in [run 37159818927](https://github.com/Wrexist/Atlas/actions/runs/37159818927).
- The iPhone 16 Pro Max simulator exported **12 real app screenshots**, six each in light and dark appearance. Captures cover Today, 30 days, the active session map, muscle details, workout completion and return to training history. Representative empty, active, detail, completed and aggregate screens were visually inspected; the completion summary remains presented until Done in both appearances.
- Local captures are in `artifacts/body-training-final/` with descriptive `body-light-*` and `body-dark-*` names. The workflow's `app-screenshots` artifact also contains the exported originals and manifest.
- Capture automation hides the demo reminder, uses explicit sheet action identifiers and scrolls the finish form to its confirmation action. Simulator validation does not replace the device and accessibility checks below.

## Remaining roadmap

1. Check small-screen and largest Dynamic Type layouts, VoiceOver and real-device performance. Review region outlines with a qualified anatomy/movement reviewer.
2. Add duration/distance/assistance logging with backward-compatible persistence and category-specific validation. Retain the shared visual system.
3. Complete focused superset transitions and timer handling.
4. Expand dedicated exercise artwork in reviewed batches. Resolve five missing source instruction records. Add versioned media delivery and offline caching before full-catalog production.
5. Verify real-device notification, Live Activity, termination/restoration, CloudKit migration, Watch and widget behavior before release.

No merge or production release is part of this update.
