#!/usr/bin/env python3
"""Render Atlas's muscle-map pack from the Z-Anatomy model.

SOURCE / LICENCE
  Geometry: Z-Anatomy (https://www.z-anatomy.com), CC BY-SA 4.0. The
  rendered images are a derivative work and inherit CC BY-SA 4.0 — keep
  the credit in Profile › About (see `AnatomyAssets.attribution`).

WHAT IT PRODUCES (into $ATLAS_ANATOMY_OUT, default /tmp/atlas_pack)
  anatomy_body_front.png / anatomy_body_back.png          — colour body
  anatomy_body_front_gray.png / anatomy_body_back_gray.png — grey tint src
  anatomy_<AnatomicalMuscle rawValue>.png                  — one alpha mask
                                                            per muscle head
  The body is the full muscular-system écorché. The eye sockets are filled
  with Z-Anatomy's eyeball meshes so the face reads as a medical model, not
  a hollow-socketed "monster". Every image shares one locked orthographic
  camera per facing, so masks are pixel-aligned to the bodies.

HOW TO RUN (headless, Blender-as-a-module)
  pip install bpy pillow
  # Z-Anatomy "Models of human anatomy" → Z-Anatomy.zip → Startup.blend
  ZANATOMY_BLEND=/path/Startup.blend python3 tools/render_zanatomy.py
  python3 tools/install_anatomy_pack.py   # copies the PNGs into the catalog

NOTES THAT MATTER (learned the hard way)
  * Cycles on CPU — EEVEE needs a GPU/EGL context CI runners lack.
  * Render in the model's own scene; a fresh scene drops the rig and the
    deformable muscles collapse.
  * Include only the "Muscular system" collection in the view layer —
    evaluating all ~4500 objects OOMs.
  * Merge every belly into ONE decimated mesh; Cycles' geometry export
    OOMs on 500+ separate high-poly objects.
"""
import bpy, os, math, mathutils

BLEND = os.environ.get("ZANATOMY_BLEND", "/tmp/zanatomy/Z-Anatomy/Startup.blend")
OUT = os.environ.get("ATLAS_ANATOMY_OUT", "/tmp/atlas_pack")
RES_X, RES_Y = 1200, 2880          # 1 : 2.4, matches BodyAnatomy.aspect
os.makedirs(OUT, exist_ok=True)

# Non-muscle structures to drop from the bellies / masks.
SKIP = ["fascia", "bursa", "septum", "membrane", "retinaculum", "sheath",
        "aponeurosis", "raphe", "tendon", "ligament"]
MASK_SKIP = SKIP + ["nerve", "artery", "vein", "node",
                    "capitis", "cervicis", "colli", "trochanteric"]

# AnatomicalMuscle rawValue -> (Z-Anatomy name substrings, facing)
GROUPS = {
    "pecClavicular": (["clavicular head of pectoralis major"], "front"),
    "pecSternal": (["sternocostal head of pectoralis major",
                    "sternal head of pectoralis major"], "front"),
    "deltAnterior": (["clavicular part of deltoid"], "front"),
    "deltLateralFront": (["acromial part of deltoid"], "front"),
    "biceps": (["biceps brachii", "brachialis"], "front"),
    "forearmFront": (["flexor carpi", "flexor digitorum superficialis",
                      "palmaris longus", "pronator teres", "brachioradialis"], "front"),
    "abdominals": (["rectus abdominis"], "front"),
    "obliques": (["external abdominal oblique"], "front"),
    "quadRectus": (["rectus femoris"], "front"),
    "quadLateralis": (["vastus lateralis"], "front"),
    "quadMedialis": (["vastus medialis", "vastus intermedius"], "front"),
    "adductors": (["adductor longus", "adductor magnus", "adductor brevis",
                   "gracilis", "pectineus"], "front"),
    "tibialis": (["tibialis anterior"], "front"),
    "neck": (["sternocleidomastoid"], "front"),
    "trapsUpper": (["descending part of trapezius"], "back"),
    "trapsLower": (["ascending part of trapezius", "transverse part of trapezius"], "back"),
    "rhomboids": (["rhomboid"], "back"),
    "deltPosterior": (["spinal part of deltoid"], "back"),
    "deltLateralBack": (["acromial part of deltoid"], "back"),
    "tricepsLong": (["long head of triceps brachii"], "back"),
    "tricepsLateral": (["lateral head of triceps brachii",
                        "medial head of triceps brachii"], "back"),
    "lats": (["latissimus dorsi"], "back"),
    "lowerBack": (["iliocostalis", "longissimus", "spinalis"], "back"),
    "forearmBack": (["extensor carpi", "extensor digitorum",
                     "extensor digiti minimi", "anconeus", "supinator"], "back"),
    "glutes": (["gluteus maximus"], "back"),
    "gluteMedius": (["gluteus medius"], "back"),
    "hamstringLateral": (["biceps femoris"], "back"),
    "hamstringMedial": (["semitendinosus", "semimembranosus"], "back"),
    "gastrocnemius": (["gastrocnemius"], "back"),
    "soleus": (["soleus"], "back"),
}


def log(*a):
    print(*a, flush=True)


def isolate_muscular(vl):
    """Exclude every collection from the view layer, then re-include only
    the Muscular system branch (evaluating ~4500 objects OOMs)."""
    parent = {}

    def index(lc):
        for ch in lc.children:
            parent[ch] = lc
            index(ch)
    index(vl.layer_collection)

    def set_excl(lc, val):
        for ch in lc.children:
            ch.exclude = val
            set_excl(ch, val)
    set_excl(vl.layer_collection, True)

    def include(lc):
        lc.exclude = False
        for ch in lc.children:
            include(ch)
    for lc in list(parent):
        if lc.collection and lc.collection.name == "Muscular system":
            cur = lc
            while cur is not None:
                cur.exclude = False
                cur = parent.get(cur)
            include(lc)


def bbox(objs):
    mn, mx = [1e9] * 3, [-1e9] * 3
    for o in objs:
        for v in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(v)
            for i in range(3):
                mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
    return mn, mx


def setin(bsdf, name, value):
    if name in bsdf.inputs:
        bsdf.inputs[name].default_value = value


def material(name, base, subsurface):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    setin(b, "Base Color", (*base, 1.0))
    setin(b, "Roughness", 0.6)
    setin(b, "Subsurface Weight", subsurface)
    setin(b, "Subsurface", subsurface)
    if subsurface:
        setin(b, "Subsurface Radius", (0.04, 0.02, 0.014))
        setin(b, "Subsurface Scale", 0.03)
    return m


def mask_material():
    m = bpy.data.materials.new("mask")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    setin(b, "Base Color", (1, 1, 1, 1))
    setin(b, "Emission Color", (1, 1, 1, 1))
    setin(b, "Emission Strength", 1.0)
    return m


def main():
    log("opening", BLEND)
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    sc = bpy.context.scene
    isolate_muscular(bpy.context.view_layer)

    musc = bpy.data.collections.get("Muscular system")
    allm = [o for o in musc.all_objects if o.type == "MESH"]
    body = [o for o in allm if not any(k in o.name.lower() for k in SKIP)]
    # Eyeballs live outside the muscular system; link them into the scene so
    # the orbits aren't hollow.
    eyes = [o for o in bpy.data.objects
            if o.type == "MESH" and o.name.lower().startswith("eyeball")]
    for o in eyes:
        try:
            sc.collection.objects.link(o)
        except Exception:
            pass
    log("muscle meshes:", len(allm), "body:", len(body), "eyes:", len(eyes))

    # render settings
    sc.use_nodes = False
    sc.render.use_compositing = False
    sc.render.use_sequencer = False
    sc.render.use_multiview = False
    sc.render.use_persistent_data = False
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_x, sc.render.resolution_y = RES_X, RES_Y

    bmn, bmx = bbox(body)
    center = [(bmn[i] + bmx[i]) / 2 for i in range(3)]
    height = max(0.1, bmx[2] - bmn[2]); dist = height * 3 + 1

    def cam(name, y, flip):
        cd = bpy.data.cameras.new(name); cd.type = "ORTHO"; cd.ortho_scale = height * 1.06
        c = bpy.data.objects.new(name, cd); sc.collection.objects.link(c)
        c.location = (center[0], y, center[2])
        c.rotation_euler = (math.radians(90), 0, math.radians(180) if flip else 0)
        return c
    cams = {"front": cam("CF", bmn[1] - dist, False),
            "back": cam("CB", bmx[1] + dist, True)}

    def sun(name, frm, e, col):
        ld = bpy.data.lights.new(name, "SUN"); ld.energy = e; ld.color = col; ld.angle = 0.2
        lo = bpy.data.objects.new(name, ld); sc.collection.objects.link(lo)
        lo.rotation_euler = (mathutils.Vector(center) - mathutils.Vector(frm)).to_track_quat('-Z', 'Y').to_euler()
    sun("kF", (center[0] - height * 0.7, bmn[1] - dist, center[2] + height * 0.5), 3.0, (1, 0.97, 0.93))
    sun("fF", (center[0] + height * 0.8, bmn[1] - dist, center[2]), 1.7, (0.92, 0.96, 1))
    sun("kB", (center[0] - height * 0.7, bmx[1] + dist, center[2] + height * 0.5), 3.0, (1, 0.97, 0.93))
    sun("fB", (center[0] + height * 0.8, bmx[1] + dist, center[2]), 1.7, (0.92, 0.96, 1))
    world = bpy.data.worlds.new("w"); world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Strength"].default_value = 0.15
    bg.inputs["Color"].default_value = (0.06, 0.065, 0.07, 1)
    sc.world = world

    def render(cam_key, path, transform, samples, denoise):
        sc.view_settings.view_transform = transform
        sc.view_settings.exposure = 0.3 if transform == "AgX" else 0.0
        sc.cycles.samples = samples
        sc.cycles.use_denoising = denoise
        sc.camera = cams[cam_key]
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        log("wrote", os.path.basename(path))

    # ---- beauty bodies: merge the écorché into one decimated mesh; the
    #      eyeballs render as separate objects to fill the orbits ----
    def beauty(muscle_mat, eye_mat, suffix):
        for o in list(bpy.data.objects):
            if o.type not in ("CAMERA", "LIGHT"):
                o.hide_render = True
        verts, faces = [], []
        for o in body:
            me = o.data; mw = o.matrix_world; base = len(verts)
            verts.extend([(mw @ v.co)[:] for v in me.vertices])
            for p in me.polygons:
                faces.append(tuple(base + i for i in p.vertices))
        mm = bpy.data.meshes.new("merged"); mm.from_pydata(verts, [], faces); mm.update()
        for poly in mm.polygons:
            poly.use_smooth = True
        merged = bpy.data.objects.new("merged", mm); sc.collection.objects.link(merged)
        merged.data.materials.append(muscle_mat); merged.hide_render = False
        merged.modifiers.new("d", "DECIMATE").ratio = 0.25
        for o in eyes:
            o.hide_render = False
            o.data.materials.clear(); o.data.materials.append(eye_mat)
        render("front", f"{OUT}/anatomy_body_front{suffix}.png", "AgX", 44, True)
        render("back", f"{OUT}/anatomy_body_back{suffix}.png", "AgX", 44, True)
        bpy.data.objects.remove(merged, do_unlink=True)

    beauty(material("muscle", (0.52, 0.26, 0.23), 0.18),
           material("eye", (0.92, 0.90, 0.86), 0.0), "")
    beauty(material("muscle_gray", (0.62, 0.62, 0.62), 0.0),
           material("eye_gray", (0.85, 0.85, 0.85), 0.0), "_gray")

    # ---- per-muscle masks (rendered from the muscle meshes) ----
    white = mask_material()
    missing = []
    for raw, (subs, facing) in GROUPS.items():
        objs = [o for o in allm
                if any(s in o.name.lower() for s in subs)
                and not any(k in o.name.lower() for k in MASK_SKIP)]
        if not objs:
            missing.append(raw); log("  MISSING", raw); continue
        for o in allm:
            o.hide_render = True
        for o in objs:
            o.hide_render = False
            o.data.materials.clear(); o.data.materials.append(white)
        render(facing, f"{OUT}/anatomy_{raw}.png", "Standard", 8, False)
    log("DONE. missing:", missing)


if __name__ == "__main__":
    main()
