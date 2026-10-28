# Recipe images

Photos for the bundled recipe library (`Peptide/Resources/recipe-library.json`).

- `prompts.json` maps each recipe id to a photo prompt. Every prompt uses the
  same style: an overhead 90° shot of the dish on a matte charcoal ceramic
  plate, dark slate background, soft diffused daylight from the upper left,
  minimal props, no text, no hands, square 1:1.
- The images are generated locally in ComfyUI. Save each one as
  `recipe-<id>.png` at 1024 × 1024 px.
- Add each image to `Peptide/Resources/Assets.xcassets/Recipes/` as an image
  set named `recipe-<id>`. `RecipeImage` loads it by that name and falls back
  to a drawn plate until it exists, so photos can be added a few at a time.
