# Atlas body map (AnatomyV2)

The muscle map, the weekly heat map and every exercise visual draw the same
grey 3D body: `atlas_body_front` / `atlas_body_back` in
`Peptide/Resources/Assets.xcassets/AnatomyV2` (1024 × 1536, transparent
background; `prompts-v2.json` records how the art was made). Each muscle head
is a polygon in `Peptide/Resources/anatomy-regions-v2.json`:

- coordinates are artwork pixels, authored for the figure's right side
  (viewer's left, `x < 509`) and mirrored about the sculpt's midline,
  `TrainingAnatomy.mirrorAxis` (509 — the canvas centre is three pixels off);
- `TrainingAnatomy.path` smooths each polygon with quadratic curves through
  the edge midpoints, so the drawn outline sits slightly inside the vertices;
- the same path clips the tint and answers taps.

## Editing regions

```sh
python3 tools/anatomy/v2_preview.py grid front 270 240 520 520 /tmp/chest.png --regions pecSternal,deltAnterior
python3 tools/anatomy/v2_preview.py regions /tmp/anatomy      # every region, distinct colours
python3 tools/anatomy/v2_preview.py exercises /tmp/anatomy    # reference lifts, light + dark
python3 scripts/anatomy-review.py --check-alpha               # keys, bounds, crossings, inside the body
```

`grid` crops an enlarged, contrast-stretched patch ruled every 25 px with the
named outlines and vertex indices, for placing points on the sculpted
borders. `regions` and `exercises` reproduce the app's renderer (base image,
`colorMultiply` copy clipped by the blurred path); their highlight rules are a
Python twin of `ExerciseAnatomyEngine.highlights(for:)` and
`AnatomicalMuscle.headWeights` — keep them in step.
