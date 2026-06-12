# Anatomy asset pack generator

Generates the 3D-rendered muscle-map images bundled in
`Peptide/Resources/Assets.xcassets/Anatomy` — the pack that switches
`MuscleMapView` from vector drawing to image rendering (see
`AnatomyAssets.swift`).

Every muscle belly is built as an inflated 3D mesh from the *same*
normalized geometry as `BodyAnatomy.swift` (`geometry.py` is its Python
twin), rendered with Cycles under studio lighting in neutral gray so the
app can tint training intensity over it with `colorMultiply`. Masks are
rasterized from the same polygons at the same orthographic mapping, so
they are pixel-aligned with the body renders by construction — and
tap-to-identify keeps using the vector paths, which match for the same
reason.

## Regenerating

Requires Python 3.11 with `bpy` (Blender 5.x as a module) and Pillow:

```sh
pip install bpy pillow
python3 blender_build.py            # renders anatomy_body_front/back (~10 min CPU)
python3 make_masks.py ../../Peptide/Resources/Assets.xcassets
```

Intermediate output lands in `/tmp/anatomy/assets` (override with
`ANATOMY_OUT`).

## Keeping geometry in sync

If muscle shapes change in `BodyAnatomy.swift`, mirror the same point
edits in `geometry.py` (coordinates are identical, normalized
`[0…1] × [0…2.4]`), then regenerate. `AnatomyAssets.auditCoverage()`
asserts at launch in DEBUG if any mask is missing, and
`AnatomyDebugView` overlays each mask for alignment QA.
