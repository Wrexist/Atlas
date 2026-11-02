# Food images

The pictures `FoodArtwork` shows for foods without a product photo (library,
diary, scanners, recipe placeholders). One per category in `FoodThumbnail.swift`;
`prompts.json` keys are the asset ids (`food-<id>` in `Assets.xcassets/Foods`).

Style: a studio photo of the food alone on light grey, cut out to a transparent
256 px PNG, so it sits on the category's tinted tile the same way product
cut-outs do.

```
python tools/food-images/foodimages.py generate [ids...]   # local ComfyUI, FLUX.1-schnell
python tools/food-images/foodimages.py cutout [ids...]     # image sets + contact-sheet.jpg
```

Rendering reuses `tools/recipe-images/generate.py` (same model and seeds scheme).
Re-roll a bad image by bumping its id in `rerolls.json`, deleting
`raw/food-<id>.png` and running `generate` again.
