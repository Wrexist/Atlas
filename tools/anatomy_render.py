#!/usr/bin/env python3
"""
Render the photoreal anatomy assets for Atlas's muscle map.

WHAT THIS DOES
  Renders, from a single locked camera per facing:
    * anatomy_body_front.png / anatomy_body_back.png  — the shaded base
    * anatomy_<muscle>.png                            — one white mask per
                                                        muscle, perfectly
                                                        aligned to the base
  Output names match `AnatomyAssets` so the PNGs drop straight into
  Assets.xcassets/Anatomy/<name>.imageset/.

WHY IT ALIGNS PERFECTLY
  Every mask is the *same camera render* with only one muscle group
  visible, painted flat white. Same camera + same canvas = pixel-perfect
  registration, no hand-tracing.

HOW TO RUN
  1. Open a muscle-separated model in Blender. Recommended: Z-Anatomy
     (open-source, CC-BY-SA) — File > Open the .blend, isolate the
     "Muscular system" collection.
  2. Pose neutrally (A/T-stance), facing -Y.
  3. Add two orthographic cameras:
       "Cam_Front"  looking at the body from the front (-Y)
       "Cam_Back"   looking from behind (+Y)
     Frame the whole body identically in both. DON'T move them after.
  4. Set OUTPUT_DIR below.
  5. Run headless:
       blender your_model.blend --background --python tools/anatomy_render.py
     …or paste into Blender's Scripting tab and Run.

VERIFY THE MAPPING
  GROUPS matches our 24 muscle regions to Z-Anatomy object names by
  case-insensitive substring. Z-Anatomy's left/right meshes usually end
  in ".l"/".r" or "(left)"/"(right)"; the SIDE filter below splits those
  for our left/right regions. If your model names differ, adjust GROUPS /
  SIDE only — nothing else.
"""

import bpy
import os

# ---------------------------------------------------------------- config
OUTPUT_DIR = "/tmp/atlas_anatomy"     # <- set me
RES = 1200                             # px on the short (width) axis; height scales
SAMPLES = 256                          # Cycles samples for the base render
CAM_FRONT = "Cam_Front"
CAM_BACK = "Cam_Back"

# raw AnatomicalMuscle value -> substrings that identify its meshes
GROUPS = {
    # ---- front ----
    "chest":          ["pectoralis major"],
    "abdominals":     ["rectus abdominis"],
    "obliques":       ["external oblique", "obliquus externus"],
    "shouldersFront": ["deltoid"],
    "neckFront":      ["sternocleidomastoid"],
    "bicepsLeft":     ["biceps brachii"],
    "bicepsRight":    ["biceps brachii"],
    "forearmsFront":  ["brachioradialis", "flexor carpi", "pronator teres"],
    "quadricepsLeft":  ["rectus femoris", "vastus lateralis", "vastus medialis"],
    "quadricepsRight": ["rectus femoris", "vastus lateralis", "vastus medialis"],
    "adductors":      ["adductor longus", "adductor magnus", "gracilis"],
    "calvesFront":    ["gastrocnemius", "soleus", "tibialis anterior"],
    # ---- back ----
    "traps":          ["trapezius"],
    "lats":           ["latissimus dorsi", "teres major"],
    "lowerBack":      ["erector spinae", "thoracolumbar"],
    "shouldersBack":  ["deltoid"],
    "tricepsLeft":    ["triceps brachii"],
    "tricepsRight":   ["triceps brachii"],
    "forearmsBack":   ["extensor carpi", "extensor digitorum", "anconeus"],
    "glutesLeft":     ["gluteus maximus", "gluteus medius"],
    "glutesRight":    ["gluteus maximus", "gluteus medius"],
    "hamstringsLeft":  ["biceps femoris", "semitendinosus", "semimembranosus"],
    "hamstringsRight": ["biceps femoris", "semitendinosus", "semimembranosus"],
    "calvesBack":     ["gastrocnemius", "soleus"],
}

# which camera each region is rendered from
FACING = {
    "chest": "front", "abdominals": "front", "obliques": "front",
    "shouldersFront": "front", "neckFront": "front", "bicepsLeft": "front",
    "bicepsRight": "front", "forearmsFront": "front", "quadricepsLeft": "front",
    "quadricepsRight": "front", "adductors": "front", "calvesFront": "front",
    "traps": "back", "lats": "back", "lowerBack": "back", "shouldersBack": "back",
    "tricepsLeft": "back", "tricepsRight": "back", "forearmsBack": "back",
    "glutesLeft": "back", "glutesRight": "back", "hamstringsLeft": "back",
    "hamstringsRight": "back", "calvesBack": "back",
}

# regions that should only take the left- or right-side meshes
SIDE = {
    "bicepsLeft": "l", "bicepsRight": "r",
    "quadricepsLeft": "l", "quadricepsRight": "r",
    "tricepsLeft": "l", "tricepsRight": "r",
    "glutesLeft": "l", "glutesRight": "r",
    "hamstringsLeft": "l", "hamstringsRight": "r",
}


# ------------------------------------------------------------- utilities
def all_meshes():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def side_of(name):
    n = name.lower()
    if n.endswith(".l") or "(left)" in n or " left" in n or n.endswith("_l"):
        return "l"
    if n.endswith(".r") or "(right)" in n or " right" in n or n.endswith("_r"):
        return "r"
    return None


def meshes_for(raw):
    subs = [s.lower() for s in GROUPS[raw]]
    want_side = SIDE.get(raw)
    out = []
    for o in all_meshes():
        n = o.name.lower()
        if any(s in n for s in subs):
            if want_side and side_of(o.name) not in (want_side, None):
                continue
            out.append(o)
    return out


def show_only(objs):
    keep = {o.name for o in objs}
    for o in all_meshes():
        o.hide_render = o.name not in keep


def show_all():
    for o in all_meshes():
        o.hide_render = False


def white_material():
    m = bpy.data.materials.get("ATLAS_MASK_WHITE")
    if m is None:
        m = bpy.data.materials.new("ATLAS_MASK_WHITE")
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (1, 1, 1, 1)
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = (1, 1, 1, 1)
                bsdf.inputs["Emission Strength"].default_value = 1.0
    return m


def setup_render():
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.samples = SAMPLES
    s.render.film_transparent = True            # transparent background
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGBA"
    s.render.resolution_x = RES
    s.render.resolution_y = int(RES * 2.4)      # match our 1 : 2.4 figure ratio
    s.render.resolution_percentage = 100


def use_camera(name):
    cam = bpy.data.objects.get(name)
    if cam is None:
        raise RuntimeError(f"Camera '{name}' not found — create it first.")
    bpy.context.scene.camera = cam


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("  wrote", path)


# ------------------------------------------------------------------ main
def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    setup_render()

    # 1) base renders — every muscle visible, original materials
    print("Base renders…")
    show_all()
    use_camera(CAM_FRONT)
    render_to(os.path.join(OUTPUT_DIR, "anatomy_body_front.png"))
    use_camera(CAM_BACK)
    render_to(os.path.join(OUTPUT_DIR, "anatomy_body_back.png"))

    # 2) mask passes — one muscle, flat white, same camera
    print("Mask renders…")
    white = white_material()
    saved = {o.name: [s.material for s in o.material_slots] for o in all_meshes()}
    missing = []
    for raw in GROUPS:
        objs = meshes_for(raw)
        if not objs:
            missing.append(raw)
            print(f"  !! no meshes matched for '{raw}' — check GROUPS")
            continue
        show_only(objs)
        for o in objs:
            if not o.material_slots:
                o.data.materials.append(white)
            for s in o.material_slots:
                s.material = white
        use_camera(CAM_FRONT if FACING[raw] == "front" else CAM_BACK)
        render_to(os.path.join(OUTPUT_DIR, f"anatomy_{raw}.png"))
        # restore this region's materials before the next pass
        for o in objs:
            for i, s in enumerate(o.material_slots):
                if i < len(saved[o.name]):
                    s.material = saved[o.name][i]

    show_all()
    print("\nDone.")
    print(f"Rendered to {OUTPUT_DIR}")
    if missing:
        print("MISSING (fix GROUPS for these):", ", ".join(missing))
    print("Next: drop each PNG into "
          "Peptide/Resources/Assets.xcassets/Anatomy/<name>.imageset/")


if __name__ == "__main__":
    main()
