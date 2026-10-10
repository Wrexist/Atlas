# Exercise artwork

The visual system covers all 873 bundled exercises. `illustrations.json` records
the 13 movement-specific PNGs currently integrated; the other 860 deliberately
render their own muscle maps. A map is not a movement illustration or animation.

`catalog.csv` is the readable inventory of every exercise, its visual status,
muscles, equipment, asset, instruction count and next production action. Queue
entries without source instructions are marked `needsMovementReference`.

`pending.jsonl` is the complete production queue, one exact brief per outstanding
exercise, including equipment, muscles, original instructions and source paths.
Do not assign one pose to several variations just because their names resemble
each other. Custom exercises use their user-entered muscle data.

## Add an illustration

1. Read the exact queue entry and source movement. Resolve missing/ambiguous
   instructions before producing art.
2. Generate one transparent PNG using the built-in image generator. Match the
   gray mannequin, graphite equipment, black shorts, white trainers, orange
   primary and blue secondary muscles. The style prompt is in
   `scripts/exercise-art-catalog.py`; individual pose prompts are in the index.
3. Inspect the pose, number of limbs, grips, equipment contact, framing, muscle
   coloring and true alpha. Review against the exact exercise, not its name only.
   Generated anatomical artwork still needs specialist movement review before
   it can serve as authoritative form instruction. Keep rejected variants out.
4. Copy the PNG into its own `ExerciseArt/atlas_<id>.imageset`, add Contents.json,
   then record its exact ID, asset name, SHA-256 and review notes in the index.
5. Run `python -X utf8 scripts/exercise-art-catalog.py --sync`, then `--check`.
   The generated app manifest and pending queue must be committed together.
6. Run the asset unit tests and inspect real simulator captures in light/dark,
   compact thumbnails and large text. `test_captureExerciseRollout` exercises
   new art and the map fallback through the actual workout flow.

This starter pack is bundled for offline use. Expanding all 873 full-resolution
posters inside the binary is not the delivery architecture: a versioned media
host, optimized exports, bounded downloads and offline caching remain necessary
before publishing the complete poster collection. Do not point the app at local
generator output paths or mark queue entries complete before files exist.

## Start and finish photos

Until an exercise has its own 3D poster, it shows its start and finish photos
(alternating, with the muscle map inset) instead of the muscle map alone. The
1,746 photos come from [free-exercise-db](https://github.com/yuhonas/free-exercise-db)
(Unlicense, public domain), pinned to one commit, capped at 600 px and bundled
in `Peptide/Resources/ExercisePhotos/` (about 46 MB) so they work offline.

- `python3 scripts/exercise-photos.py` downloads and resizes any missing pair.
- `python3 scripts/exercise-photos.py --check` verifies every catalog exercise
  has both photos; `ExercisePhotosTests` asserts the same inside the app.
- A 3D poster always wins over the photos. Share cards never show the photos:
  a stock photo is not the user's own workout.
