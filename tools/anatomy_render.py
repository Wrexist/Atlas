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
# Output dir: env override (used by the CI workflow) or the default below.
OUTPUT_DIR = os.environ.get("ATLAS_ANATOMY_OUT", "/tmp/atlas_anatomy")
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


def use_camera(name):
    cam = bpy.data.objects.get(name)
    if cam is None:
        raise RuntimeError(f"Camera '{name}' not found — create it first.")
    bpy.context.scene.camera = cam


def setup_render():
    s = bpy.context.scene
    # EEVEE renders the stylised grey figure far faster/cheaper than
    # Cycles on a CI runner. Fall back across engine ids by Blender
    # version, then Cycles as a last resort.
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
        try:
            s.render.engine = eng
            break
        except Exception:
            continue
    if s.render.engine == "CYCLES":
        s.cycles.samples = SAMPLES
    s.render.film_transparent = True            # transparent background
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGBA"
    s.render.resolution_x = RES
    s.render.resolution_y = int(RES * 2.4)      # match our 1 : 2.4 figure ratio
    s.render.resolution_percentage = 100


def dump_scene_info():
    """Reconnaissance: write every collection + mesh-object name to the
    output dir so the GROUPS mapping can be built from the real model
    without opening Blender locally. Always runs first."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    cols = sorted(c.name for c in bpy.data.collections)
    with open(os.path.join(OUTPUT_DIR, "collections.txt"), "w") as f:
        f.write("\n".join(cols))

    meshes = sorted(o.name for o in bpy.data.objects if o.type == "MESH")
    with open(os.path.join(OUTPUT_DIR, "object_names.txt"), "w") as f:
        f.write("\n".join(meshes))

    cams = [o.name for o in bpy.data.objects if o.type == "CAMERA"]
    print(f"[recon] collections: {len(cols)}  mesh objects: {len(meshes)}  cameras: {cams}")
    print("[recon] first 40 mesh names:")
    for n in meshes[:40]:
        print("   ", n)


def scene_bounds():
    import mathutils
    mins = [1e9] * 3
    maxs = [-1e9] * 3
    for o in all_meshes():
        if o.hide_render:
            continue
        for corner in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(corner)
            for i in range(3):
                mins[i] = min(mins[i], w[i])
                maxs[i] = max(maxs[i], w[i])
    return mins, maxs


def ensure_cameras():
    """Use the scene's CAM_FRONT/CAM_BACK if present; otherwise build
    orthographic front/back cameras framing the model."""
    if bpy.data.objects.get(CAM_FRONT) and bpy.data.objects.get(CAM_BACK):
        return
    import math
    mins, maxs = scene_bounds()
    center = [(mins[i] + maxs[i]) / 2 for i in range(3)]
    height = max(0.1, maxs[2] - mins[2])
    dist = height * 3 + 1

    def make_cam(name, y, flip):
        cam_data = bpy.data.cameras.new(name)
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = height * 1.15
        cam = bpy.data.objects.new(name, cam_data)
        bpy.context.scene.collection.objects.link(cam)
        cam.location = (center[0], y, center[2])
        cam.rotation_euler = (math.radians(90), 0, math.radians(180) if flip else 0)

    make_cam(CAM_FRONT, mins[1] - dist, flip=False)
    make_cam(CAM_BACK, maxs[1] + dist, flip=True)


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("  wrote", path)


# ------------------------------------------------------------------ main
def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Always dump the model's structure first — this is the recon output
    # that lets the GROUPS mapping be built from the real Z-Anatomy names.
    dump_scene_info()

    # First runs are recon-only (just the name dump) so a fragile camera
    # or a heavy render can't lose the reconnaissance. Once GROUPS +
    # cameras are configured, set ATLAS_ANATOMY_RECON=0 to render.
    if os.environ.get("ATLAS_ANATOMY_RECON", "1") == "1":
        print("[recon] dump complete; skipping render "
              "(set ATLAS_ANATOMY_RECON=0 to render).")
        return

    try:
        setup_render()
        ensure_cameras()

        print("Base renders…")
        show_all()
        use_camera(CAM_FRONT)
        render_to(os.path.join(OUTPUT_DIR, "anatomy_body_front.png"))
        use_camera(CAM_BACK)
        render_to(os.path.join(OUTPUT_DIR, "anatomy_body_back.png"))

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
            for o in objs:
                for i, s in enumerate(o.material_slots):
                    if i < len(saved[o.name]):
                        s.material = saved[o.name][i]

        show_all()
        print("\nDone. Rendered to", OUTPUT_DIR)
        if missing:
            print("MISSING (fix GROUPS for these):", ", ".join(missing))
    except Exception as exc:  # recon dump already written — don't lose it
        print("::warning:: render step failed (recon dump preserved):", exc)


if __name__ == "__main__":
    main()

