# Product page header + search results art

| File | Size | Use |
|---|---|---|
| `out/header-a.png` | 3840 × 1646 (21:9) | Product page header — "Train. Eat. Recover." |
| `out/header-b.png` | 3840 × 1646 (21:9) | Header A/B variant — lifestyle photo, "Every rep. Every meal." |
| `out/search-a.png` | 3840 × 2560 (3:2) | Search results visual — three phones |
| `out/search-b.png` | 3840 × 2560 (3:2) | Search results A/B variant — lifestyle photo |
| `out/search-*-1920.png` | 1920 × 1280 | Same, at the base size |

Headers keep every element inside x 560–3280, y 170–1480, so device crops
and Apple's overlays only cover background.

## Sources

- **Train screens** are real light-mode simulator captures from the 1.3
  UI-test run (`img/train-*.png`). The automated test typed placeholder
  numbers (22 lb × 108 reps) and left clocks at the run time; `phones.js`
  overlays realistic sets and a 9:41 clock in the same type and colours.
- **Meal review** has no light-mode capture yet, so it is a light recreation
  in the app's own cards, type and colours, using `img/meal-photo.jpg`.
- **Lifestyle photo** (`img/lifestyle.jpg`) is AI-generated locally (SDXL)
  and shows no real person. Swap in a licensed photo with the same framing
  if you prefer.

## Regenerate

```bash
python render.py            # all four (+ 1920 copies of the search art)
python render.py header-a   # one
```

Uses the locally installed Chrome or Edge in headless mode.
