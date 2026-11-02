# Recipe images

Photos for the bundled recipe library (`Peptide/Resources/recipe-library.json`).

- `prompts.json` maps each recipe id to a photo prompt. Every prompt uses the
  same style: an overhead 90° shot of the dish on a matte charcoal ceramic
  plate, dark slate background, soft diffused daylight from the upper left,
  minimal props, no text, no hands, square 1:1.
- Each recipe has two image sets in `Peptide/Resources/Assets.xcassets/Recipes/`:
  `recipe-<id>` (768 px JPEG photo) and `recipe-<id>-cutout` (384 px transparent
  PNG of just the plate). `RecipeImage` / `RecipeCutout` load them by name and
  fall back to a drawn plate when one is missing.

## Photos — `generate.py`

Drives a local ComfyUI (http://127.0.0.1:8188) with FLUX.1-schnell
(`flux1-schnell-fp8.safetensors`, euler / simple, 4 steps, CFG 1, 1024 px).

```
python tools/recipe-images/generate.py generate          # every id without a PNG in raw/
python tools/recipe-images/generate.py generate <id>...  # specific ids
python tools/recipe-images/generate.py export            # JPEG image sets + contact-sheet.jpg
```

Seeds are fixed per id. FLUX ignores negative prompts at CFG 1, so a photo with
cutlery, napkins, stray props or a light shaft is re-rolled: bump the id in
`rerolls.json`, delete `raw/recipe-<id>.png` and run `generate` again. Full-size
PNGs in `raw/` are not committed.

## Cutouts — `cutout.py`

Needs `rembg` (BiRefNet `birefnet-general`), scikit-image and `pngquant` on PATH.

```
python tools/recipe-images/cutout.py [ids...]   # image sets + cutout-sheet.jpg
```

BiRefNet keeps the food but drops the dark plate, so the plate is found with a
Hough circle on edges and merged with the food mask; food lying further than 6 %
outside the rim (props, cutlery) is cut away. Each cutout is cropped square to the
plate with 2 % padding, scaled to 384 px and compressed with pngquant.
