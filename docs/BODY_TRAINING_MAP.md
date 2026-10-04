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

### Body usability refinement (2026-10-04)

- `TrainingBodyExplorer` now supplies Both / Front / Back controls across the active/saved session card, recent training map and long-term training history. A single side can grow to 340 points wide; large accessibility text defaults to Front.
- Front/back captions make orientation explicit. A full-width, minimum-44-point muscle menu provides an alternative to small anatomical tap targets, including in the long-term history card.
- Session legends adapt to narrow widths; primary and secondary legend symbols differ as well as their colors. VoiceOver uses readable muscle names in stable order and identifies intensity values as relative training scores.
- Asset highlights have lightly feathered edges and a less opaque primary tint to preserve more of the gray body's shading. The source illustrations and region coordinates remain unchanged; this is not an anatomical-accuracy upgrade.
- Design lint passes with zero errors and warnings. Native verification of revision `98940d9` was attempted in [run 37187550704](https://github.com/Wrexist/Atlas/actions/runs/37187550704), but GitHub refused to start the job: **“The job was not started because your account is locked due to a billing issue.”** No new native build, UI pass or screenshot is claimed for this refinement. The successful run documented above verifies the previous revision only.
- Once Actions is available, rerun `test_captureMuscleTraining`: it now also selects Front and Back, checks selection state and captures each side in both appearances.

### Outline refinement (2026-10-04)

All 30 control polygons were revised against the unchanged source artwork. The chest regions now follow a broader fan; shoulder, arm and thigh regions taper along the illustrated limbs; the medial upper-back and lat regions have clearer separation. The calf projection stops above the long Achilles region. Original PNGs and the runtime curve construction are unchanged, so the rendered region and tap path still share one geometry source.

Reference checks used OpenStax's [pectoral girdle and upper limb chapter](https://openstax.org/books/anatomy-and-physiology-2e/pages/11-5-muscles-of-the-pectoral-girdle-and-upper-limbs) and [pelvic girdle and lower limb chapter](https://openstax.org/books/anatomy-and-physiology/pages/11-6-appendicular-muscles-of-the-pelvic-girdle-and-lower-limbs). These are original illustrative projections over clothing, not copied textbook contours or medically validated segmentations. Deep muscles such as the rhomboids and soleus are represented by simplified location regions rather than a literal superficial dissection. Independent anatomical review remains outstanding.

Added `scripts/anatomy-review.py`:

- Validates all catalog keys, nondegenerate control polygons, canvas bounds, duplicate vertices and crossing edges. This standard-library check is included in the screenshot workflow.
- Optional `--check-alpha` (Pillow required) samples the exact quadratic paths on a three-pixel grid on both sides of the body. The revised regions had **zero sampled points outside the opaque body**; this is a sampling check, not a proof for every pixel.
- `--output artifacts/anatomy-refinement/index.html` creates an interactive browser review page using the unmodified production images and the same quadratic geometry. Regions can be isolated and the background toggled. It was visually inspected in light and dark backgrounds, including upper and lower body. This preview does not emulate SwiftUI color compositing, sizing or interactions and is not a native screenshot.

Native verification was retried on October 4 (attempt 2 of run `37187550704`). GitHub again rejected the job before any steps started because the account is locked due to a billing issue. This retry used the earlier usability revision, not the new outlines. Native verification of the new geometry remains pending; local checks cannot replace it.

### Remaining release checks

1. Check small-screen and largest Dynamic Type layouts, VoiceOver and real-device performance. Review region outlines with a qualified anatomy/movement reviewer.
2. Add duration/distance/assistance logging with backward-compatible persistence and category-specific validation. Retain the shared visual system.
3. Complete focused superset transitions and timer handling.
4. Expand dedicated exercise artwork in reviewed batches. Resolve five missing source instruction records. Add versioned media delivery and offline caching before full-catalog production.
5. Verify real-device notification, Live Activity, termination/restoration, CloudKit migration, Watch and widget behavior before release.

No merge or production release is part of this update.
