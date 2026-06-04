# Photoreal Anatomy Map — Production Plan

Goal: replace the vector muscle map with a **photoreal, grayscale muscular
body** (front + back) where each muscle is tinted by how hard it was
trained — matching the reference render — while staying crisp, performant,
and license-clean.

The app code is already prepared for this. This doc is the plan to produce
and drop in the art.

---

## 0. Where we are today

- `MuscleMapView` renders a detailed **vector** figure (skeleton + sculpted
  muscles + grooves) as the always-available fallback.
- `AnatomyAssets` defines the asset contract. The moment the named images
  ship in the catalog, `AnatomyAssets.isAvailable` flips to `true` and
  `MuscleMapView` renders the **asset** path automatically — zero call-site
  changes.
- The asset renderer now tints a **copy of the shaded base** clipped to
  each muscle's mask (`colorMultiply` + `.mask`), so a tinted muscle keeps
  its photoreal shadows instead of turning into a flat blob.

So the only remaining work is: **produce the art**, **map it to the 24
muscle regions**, **drop it in the catalog**, and **QA**.

---

## 1. Acceptance criteria ("beautiful and perfect")

- [ ] Front and back grayscale bodies, studio-lit, athletic proportions,
      photoreal muscle definition (like the reference).
- [ ] All **24** `AnatomicalMuscle` regions individually tintable and
      **pixel-aligned** to the base (no halo, no gap, no overlap bleed).
- [ ] Tint preserves the underlying shading and ramps smoothly with
      training intensity (cool wash → saturated hot).
- [ ] Crisp on every device: provide @2x and @3x (or one ≥3x master).
- [ ] Looks right in dark mode (the app is dark-first); a light variant is
      optional.
- [ ] Smooth cross-fade when intensities change (already wired via
      `.animation(value: highlights)`).
- [ ] Total added asset weight budget: **≤ ~6–8 MB** in the app (compress
      aggressively; see §6).
- [ ] No copyrighted/3rd-party art shipped without a distribution license
      (see §7).

---

## 2. Asset specification (the contract)

Drop these into `Assets.xcassets` (one `.imageset` per name). Names come
from `AnatomyAssets`:

| Asset | Purpose |
|---|---|
| `anatomy_body_front` | Grayscale shaded front body (the base) |
| `anatomy_body_back`  | Grayscale shaded back body (the base) |
| `anatomy_<muscle>`   | One alpha/white silhouette per muscle, **same canvas + camera** as the base |

`<muscle>` is the `AnatomicalMuscle` raw value. All 24:

```
Front: chest, abdominals, obliques, shouldersFront, neckFront,
       bicepsLeft, bicepsRight, forearmsFront,
       quadricepsLeft, quadricepsRight, adductors, calvesFront
Back:  traps, lats, lowerBack, shouldersBack,
       tricepsLeft, tricepsRight, forearmsBack,
       glutesLeft, glutesRight, hamstringsLeft, hamstringsRight, calvesBack
```

Rules that make alignment "perfect":
- **Identical canvas** for the base and every mask of the same facing
  (e.g. 1200×2880 px front; 1200×2880 px back). Same camera, same crop.
- Masks are **white shape on transparent** (or white-on-black, alpha
  trimmed). The base supplies shading; masks only define *where*.
- Transparent background on the base too (so it floats on the app's dark
  surface). Trim to a consistent bounding box.
- Front/back bodies should share a vertical scale so the two halves match
  when shown side by side.
- Export @2x and @3x, or a single 3x master (`Single Scale`) and let iOS
  downscale.

---

## 3. Sourcing the art — options & recommendation

| Option | Quality | Alignment | Cost | License risk | Verdict |
|---|---|---|---|---|---|
| **A. 3D model → rendered base + masks** | High, photoreal | **Perfect** (same camera) | Low (time) | Low (use open model) | **Recommended** |
| B. Commission a 3D/medical illustrator | High | High (spec it) | $$ ($300–$1500) | Low (work-for-hire) | Good if no in-house Blender |
| C. License a muscle-map UI kit | Medium–High | Depends on kit | $ ($20–$200) | Medium (read EULA) | Fast, less control |
| D. AI image generation | Stylish base, **bad masks** | Poor | $ | Murky | Base only, not masks |

**Recommended: Option A** — render from a muscle-separated 3D anatomy model.
It's the only route that guarantees pixel-perfect masks (each mask is the
same render with one muscle group isolated), gives full control over light
and style, and can be license-clean.

Best base model: **Z-Anatomy** (open-source Blender anatomy atlas,
muscle meshes individually named; CC-BY-SA — attribution + share-alike;
fine for app images with an acknowledgements credit). Alternatives:
BodyParts3D (CC-BY-SA), or a purchased TurboSquid/CGTrader écorché model
with an editorial/app license.

---

## 4. Production pipeline (Option A, Blender)

One-time setup, then fully scriptable so re-renders are a button press.

1. **Scene setup**
   - Import the écorché (muscle) model; pose in a neutral A/T-stance
     matching the reference proportions.
   - Lock an **orthographic camera** for FRONT; duplicate + rotate 180° for
     BACK. Never move it again (alignment depends on this).
   - Studio 3-point light, soft. Neutral gray muscle material for the base
     render (matte, slight subsurface for realism).

2. **Base renders**
   - Render `anatomy_body_front.png` and `anatomy_body_back.png` at ≥3x
     target resolution, transparent background (Film → Transparent).

3. **Per-muscle mask pass (scripted)**
   - For each of the 24 regions: hide all meshes, show only that muscle's
     mesh group, assign a pure-white emission/holdout material, render the
     **same camera** → white silhouette on transparent. Save as
     `anatomy_<muscle>.png`.
   - This is the alignment guarantee: every mask is the identical camera
     render with one group visible.

   Blender Python skeleton (`tools/anatomy_render.py`):
   ```python
   import bpy

   # AnatomicalMuscle rawValue  ->  list of Z-Anatomy object names
   GROUPS = {
       "chest": ["Pectoralis_major.L", "Pectoralis_major.R"],
       "abdominals": ["Rectus_abdominis.L", "Rectus_abdominis.R"],
       "shouldersFront": ["Deltoid.L", "Deltoid.R"],
       "bicepsLeft": ["Biceps_brachii.L"],
       "bicepsRight": ["Biceps_brachii.R"],
       "lats": ["Latissimus_dorsi.L", "Latissimus_dorsi.R"],
       "quadricepsLeft": ["Vastus_lateralis.L", "Rectus_femoris.L",
                           "Vastus_medialis.L"],
       # … fill in all 24 regions …
   }

   def render(path):
       bpy.context.scene.render.filepath = path
       bpy.ops.render.render(write_still=True)

   def show_only(names):
       for obj in bpy.data.objects:
           if obj.type == 'MESH':
               obj.hide_render = obj.name not in names

   # 1) base passes (all muscle meshes visible, gray material)
   show_only([o.name for o in bpy.data.objects if o.type == 'MESH'])
   # set camera FRONT, render "…/anatomy_body_front.png", then BACK …

   # 2) mask passes (white material), one per region, per facing
   for raw, names in GROUPS.items():
       show_only(names)            # only this muscle
       # set white holdout material on `names`
       render(f"…/anatomy_{raw}.png")  # front camera
       # (repeat with back camera for back-side muscles)
   ```

4. **Post / packaging (scripted)**
   - Trim all images to the shared bounding box; verify identical
     dimensions; (optionally) feather mask edges 1px to avoid aliasing
     halos.
   - Generate `Contents.json` for each `.imageset` (or use Xcode import).
   - `pngquant`/`oxipng` to compress masks (they're 1-bit-ish → tiny).

5. **Mapping table** — the `GROUPS` dict above is the single source of
   truth tying Z-Anatomy meshes → our 24 regions. Keep it in the repo so
   re-renders are reproducible. Left/right/center splits already match our
   taxonomy (`bicepsLeft`, `glutesRight`, `adductors`, …).

---

## 5. Swift integration (already mostly done)

- ✅ `AnatomyAssets` contract + auto-detect.
- ✅ Shading-preserving tint (`colorMultiply` copy of base, masked).
- ✅ Intensity ramp via `tintStrength` (primary/secondary/heatmap).
- ✅ Animated transitions.
- **To add when art lands:**
  - A `#Preview` / debug screen that cycles each of the 24 muscles
    highlighted, to eyeball every mask's alignment (see §6 QA harness).
  - Optional: tune `heatmapHotColor` / `primaryColor` against the real
    grayscale base for best contrast.
  - Optional dark/light base variants if a light theme ships.

No other code changes are required.

---

## 6. QA & validation

- **Alignment harness**: a debug view that overlays each mask outline on
  the base, and a mode that highlights all 24 at low opacity — any halo,
  gap, or misregistration is obvious.
- **Coverage**: assert every `AnatomicalMuscle.allCases` has a non-nil
  `UIImage(named: AnatomyAssets.mask(for:))` at launch in DEBUG; fail
  loudly if one is missing (mirrors the existing peptide-count CI guard
  idea in the audit plan).
- **Intensity sweep**: render the weekly heatmap with synthetic 0→1
  frequencies and confirm the ramp reads (faint → saturated).
- **Device matrix**: small iPhone → iPad, light/dark, Dynamic Type
  (labels around the map), ≥120 Hz scroll for jank.
- **Perf/memory**: images are large; verify decode cost and that the two
  bases aren't both decoded when only one facing is shown. Consider
  `.interpolation(.high)` and downsampled thumbnails for the small
  Today/finish surfaces vs the full exercise-detail view.

---

## 7. Licensing & attribution

- If using **Z-Anatomy / BodyParts3D (CC-BY-SA)**: add a credit in the
  app's acknowledgements/settings, keep the render scripts + mapping in the
  repo (share-alike applies to the derived images). Confirm SA is
  acceptable for the shipped PNGs; if not, use a model with a permissive or
  purchased app license.
- If **commissioning**: get a written work-for-hire / full buyout so the
  app owns the renders.
- **Never** ship the reference JPG or any unlicensed third-party render.

---

## 8. Milestones, effort, decision gates

| Phase | Work | Est. | Gate |
|---|---|---|---|
| **P0 Prototype** | Render 1 base + 3 masks (chest, lats, quads), drop in, see it live | 0.5–1 day | Looks better than vector? proceed |
| **P1 Full render** | Pose, light, render base ×2 + all 24 masks, package | 1–3 days | All masks aligned |
| **P2 Swift polish** | Debug harness, coverage guard, colour tuning | 0.5 day | QA checklist green |
| **P3 Ship** | Compress, size budget, device matrix, attribution | 0.5 day | Under size budget, no missing masks |

Total ≈ **3–5 focused days** (Option A in-house), or ~1 week elapsed if
commissioned (Option B).

Decision needed up front:
1. **Build vs commission** the art (Option A vs B/C).
2. **Source model + license** (Z-Anatomy recommended).
3. **Expand taxonomy?** Optional split (serratus, forearm flexor/extensor,
   calf heads, upper/lower traps). Each new region also needs a row in
   `AnatomicalMuscle.regions(forRawMuscle:)` + a test; skip for v1 unless
   the reference look demands it.

---

## 9. Risks & mitigations

- **Mask misalignment** → all masks rendered from the *same locked camera*;
  alignment harness in §6.
- **Asset bloat** → masks are near-binary (compress to KBs); only the two
  bases are heavy; budget + pngquant.
- **License creep** → pick the model/license at P0, document attribution.
- **Tint looks muddy on dark base** → `colorMultiply` keeps shading; tune
  `tintStrength` + hot colour against the real base in P2.
- **Taxonomy drift** → the `GROUPS` mapping is the single source of truth;
  changing regions means updating it + the Swift enum together.

---

## 10. In-repo prep — DONE ✅

1. ✅ `tools/anatomy_render.py` — full Blender render script with the
   complete 24-region `GROUPS` mapping (substring match), per-region
   `FACING`, and left/right `SIDE` split. Renders base + all masks from a
   locked camera.
2. ✅ DEBUG **alignment harness** `AnatomyDebugView` (cycles all 24
   muscles, intensity slider, lists missing masks) + launch-time
   **coverage assertion** (`AnatomyAssets.auditCoverage()` called in
   `PeptideApp.init()` under `#if DEBUG`).
3. ✅ All 26 `.imageset` folders created under
   `Assets.xcassets/Anatomy/` with `Contents.json` — importing art is now
   drag-and-drop (the imageset names already match `AnatomyAssets`).
4. ⏳ Tune `primaryColor` / `secondaryColor` / `heatmapHotColor` once a
   real base render exists (P2).

### How to produce the art now
1. Decide **build vs commission** (Option A vs B) and **source model**
   (Z-Anatomy recommended).
2. Set `OUTPUT_DIR` in `tools/anatomy_render.py`, open the model in
   Blender, add `Cam_Front` / `Cam_Back`, run the script.
3. Drop each rendered PNG into the matching
   `Assets.xcassets/Anatomy/anatomy_<name>.imageset/` (or set it as the
   3x slot).
4. Run the app in DEBUG → open `AnatomyDebugView` to verify every mask
   aligns; the launch audit will flag any missing one.
5. Tune the tint colours (step 4 above) and ship.

The app flips to the photoreal renderer automatically the moment
`anatomy_body_front` + `anatomy_body_back` are present.
