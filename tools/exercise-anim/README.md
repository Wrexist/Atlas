# Exercise animations

Blender scripts that render the looping exercise clips used in the app. Each clip is a grey clay figure on black,
with the muscles the exercise trains tinted in the app's colours (primary `#FFAC73`, secondary `#80ADFF`).

## Requirements

- **Blender 5.2.1 LTS.** The scripts use the 5.x compositor API (`scene.compositing_node_group`,
  File Output `file_output_items`). They won't run on 4.x.
- **MPFB 2.0.18**, the MakeHuman add-on, installed as a Blender extension from extensions.blender.org
  (`bl_ext.blender_org.mpfb`). It is only needed to rebuild `human.blend` with `gen_human.py`. The exercise scripts
  load the saved `human.blend` and don't import MPFB.
- **System Python 3** with `numpy`, `scipy` and `Pillow`, plus **ffmpeg** on `PATH`. `composite.py` uses them to
  add the glow, the muscle tint and the mp4 encode. Set `ATLAS_PYTHON` if the interpreter isn't called `python`.

## Files

| File | What it does |
|---|---|
| `gen_human.py` | Builds `human.blend`: the MPFB muscular male, the default rig with finger bones, and the running shoes |
| `human.blend` | The generated body + rig (committed so rendering doesn't need MPFB) |
| `atlas_rig.py` | Shared code: grips and finger wrap, per-frame re-grip, IK, muscle masks, look, camera, render |
| `squat.py`, `deadlift.py`, `bench.py`, `curl.py`, `lateral_raise.py` | One exercise each: pose solve, keys, cameras |
| `composite.py` | Post step: muscle tint, rim glow, floor shadow, mp4 encode |
| `render_all.sh` | Renders stills + loop for one or more exercises |
| `edge_check.py`, `flicker_score.py`, `jitter_diag.py`, `review.py`, `hand_diag.py`, `section_diag.py`, `mask_diag.py`, `diag_views.py`, `montage.py` | Review and QA tools (edge stability, temporal flicker, pose pops, front/back/side stills, hand close-ups) |
| `dl/shoes02/clothes/punkduck_running_shoes_01/` | The shoe asset `gen_human.py` attaches |

## Render one exercise headless

```sh
# optional: rebuild the body (needs MPFB 2.0.18)
blender -b -P gen_human.py

# solve + render stills and the 90-frame loop; writes out/<exercise>.mp4 and out/<exercise>_*.png
blender -b human.blend -P squat.py -- --stills --anim

# or several at once (set BLENDER to the binary path)
BLENDER=/path/to/blender sh render_all.sh squat curl
```

Flags after `--`: `--preview` (32 samples, 50 % size, 3 stills), `--stills` (top, mid and hand close-ups), and
`--anim` (frames to `out/frames_<exercise>/`, then encoded to mp4). With no flags the script only solves the pose and
saves `<exercise>.blend`.

## Render settings

- Cycles, 1080×1350, 30 fps, 90-frame loop (frame 91 = frame 1). Output is RGBA 16-bit PNG with a transparent film.
  The black background and the glow are added in `composite.py`.
- 256 samples, adaptive threshold 0.004 (min 96), fixed seed (`use_animated_seed` off), filter 1.5 px, max bounces 6.
- **GPU assumptions.** Device, OptiX backend and OptiX denoiser (albedo + normal, prefilter Accurate) are used when an
  NVIDIA OptiX device is present. Without one (e.g. CI runners) `atlas_rig.setup_render` falls back to CPU with the
  OpenImageDenoise denoiser.
- AgX view, look "Medium High Contrast", exposure −0.55. Four area lights move with the framing target.
- AOVs `tier_p` / `tier_s` (muscle masks) and `solid` (figure vs. floor) are written to `tiers/` next to every
  render. `composite.py` needs them for the tint and the shadow.
- The shadow-catcher floor is 2.2 m, camera rays only. Every floor pixel is path-traced, so it roughly doubles render
  time compared with no floor.

Timing on an RTX 3060 (OptiX): about 5 s per frame without the floor and about 11–12 s per frame with it. The pose
solve takes ~1 min on top, or ~15–20 min for bench, whose hands are re-solved every 10 frames.

## Credits

- Running shoes ("RunningShoes", `punkduck_running_shoes_01`) by **punkduck**, licensed **CC-BY 3.0**, from the
  MakeHuman community "shoes02" asset pack.
- Body and rig generated with MPFB (MakeHuman), whose assets are CC0.
