# Shared rig, grip, look and render code for the Atlas exercise loops.
# Every exercise script: `import atlas_rig as A; A.setup(); ...build equipment + keys...; A.finish(name)`.
import bpy, bmesh, math, sys, os, subprocess, time
import numpy as np
from mathutils import Vector, Matrix, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
os.makedirs(OUT, exist_ok=True)

PYTHON = os.environ.get("ATLAS_PYTHON", "python")     # system Python with numpy, scipy, Pillow (for composite.py)
FPS = 30
LOOP = 90                       # frames 1..90 rendered, frame 91 == frame 1
SKIN_GAP = 0.0008

scene = rig = body = shoes = P = D = None
body_mask = hand_mask = None
masks = []
holders = []                    # empties carrying equipment + hand targets, keyed in world space
hand_targets = {}
look_target = None


# ---------------------------------------------------------------- basics
def update():
    bpy.context.view_layer.update()


def world_coords(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    co = co.reshape(-1, 3)
    mw = np.array(obj.matrix_world)
    return co @ mw[:3, :3].T + mw[:3, 3]


def group_weights(obj, names):
    idx = {obj.vertex_groups[n].index for n in names if n in obj.vertex_groups}
    w = np.zeros(len(obj.data.vertices))
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group in idx:
                w[v.index] += g.weight
    return w


def head(name):
    return rig.matrix_world @ P[name].head


def tail(name):
    return rig.matrix_world @ P[name].tail


def rest_head(name):
    return Vector(D[name].head_local)


def empty(name, parent=None, size=0.05):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    scene.collection.objects.link(e)
    e.parent = parent
    return e


def holder(name):
    h = empty(name, size=0.2)
    h.rotation_mode = 'QUATERNION'
    holders.append(h)
    return h


# ---------------------------------------------------------------- materials
def material(name, color, rough=0.6, metal=0.0, sss=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if sss:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = (0.6, 0.6, 0.6)
        b.inputs["Subsurface Scale"].default_value = 0.01
    return m


def clay():
    m = material("AtlasClay", (0.36, 0.36, 0.36), rough=0.6, sss=0.1)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Specular IOR Level"].default_value = 0.35
    tex = nt.nodes.new("ShaderNodeTexNoise")          # fine grain, like the sculpt's fabric/skin texture
    tex.inputs["Scale"].default_value = 900
    tex.inputs["Detail"].default_value = 4
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.06
    bump.inputs["Distance"].default_value = 0.0005
    nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    # very faint grazing-angle lift: softens the darkest roll-off without hazing the body (glow stays behind it)
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    rim = nt.nodes.new("ShaderNodeMath")
    rim.operation, rim.inputs[1].default_value = 'MULTIPLY', 0.12
    nt.links.new(bump.outputs["Normal"], lw.inputs["Normal"])
    nt.links.new(lw.outputs["Facing"], rim.inputs[0])
    b.inputs["Emission Color"].default_value = (0.6, 0.6, 0.6, 1)
    nt.links.new(rim.outputs[0], b.inputs["Emission Strength"])
    muscle_tint(nt, b, rim)
    solid_aov(m)
    return m


def srgb_to_linear(rgb):
    return tuple(((c / 255 + 0.055) / 1.055) ** 2.4 if c / 255 > 0.04045 else c / 255 / 12.92 for c in rgb)


def solid_aov(m):
    """AOV 'solid' = 1 on figure + equipment; the shadow-catcher floor writes nothing (0)."""
    nt = m.node_tree
    v = nt.nodes.new("ShaderNodeValue")
    v.outputs[0].default_value = 1.0
    out = nt.nodes.new("ShaderNodeOutputAOV")
    out.aov_name = "solid"
    nt.links.new(v.outputs[0], out.inputs["Value"])


def muscle_tint(nt, bsdf, rim):
    """Write the trained-muscle fields (atlas_primary / atlas_secondary attributes, sharpened to a ~1.5 cm edge) to
    the tier_p / tier_s AOVs. The tint itself is applied after the view transform in composite.py, multiplying the
    shaded grey by the exact app colour like the app's muscle map, so AgX can't shift the hue."""
    for attr, aov in (("atlas_primary", "tier_p"), ("atlas_secondary", "tier_s")):
        at = nt.nodes.new("ShaderNodeAttribute")
        at.attribute_name = attr
        edge = nt.nodes.new("ShaderNodeMapRange")
        edge.interpolation_type = 'SMOOTHSTEP'
        edge.inputs["From Min"].default_value, edge.inputs["From Max"].default_value = 0.25, 0.75
        nt.links.new(at.outputs["Fac"], edge.inputs["Value"])
        out = nt.nodes.new("ShaderNodeOutputAOV")
        out.aov_name = aov
        nt.links.new(edge.outputs["Result"], out.inputs["Value"])


STEEL = PLATE = BLACK = None


def equipment_materials():
    global STEEL, PLATE, BLACK
    STEEL = material("Steel", (0.10, 0.10, 0.105), rough=0.3, metal=0.9)
    PLATE = material("Plate", (0.012, 0.012, 0.013), rough=0.55)
    BLACK = material("BenchBlack", (0.015, 0.015, 0.016), rough=0.7)
    for m in (STEEL, PLATE, BLACK):
        solid_aov(m)


# ---------------------------------------------------------------- body prep
def make_faceless():
    """Close the eye sockets and mouth and soften the features into a mannequin face like the anatomy sculpt."""
    co = np.array([v.co for v in body.data.vertices])
    hc = np.array(D["head"].head_local)
    body_w = group_weights(body, ["body"])
    face = (body_w > 0) & (co[:, 2] > hc[2] - 0.07) & (co[:, 1] < hc[1] + 0.01) & (np.abs(co[:, 0]) < 0.08)
    # cavity verts (eye sockets, mouth) are mostly enclosed: most rays off their normal hit the head again
    from mathutils.bvhtree import BVHTree
    # body skin only: MPFB keeps helper shells (hair, tights, eyeballs) in the same mesh
    bvh = BVHTree.FromPolygons([v.co for v in body.data.vertices],
                               [p.vertices for p in body.data.polygons if all(body_w[i] > 0 for i in p.vertices)])
    rng = np.random.default_rng(1)
    dirs = rng.normal(size=(48, 3))
    dirs /= np.linalg.norm(dirs, axis=1)[:, None]
    cavity = []
    for i in np.nonzero(face)[0]:
        n = body.data.vertices[i].normal
        o = Vector(co[i]) + n * 0.0005
        hits = total = 0
        for d in dirs:
            d = Vector(d)
            if d.dot(n) <= 0.05:
                continue
            total += 1
            if bvh.ray_cast(o, d, 0.12)[0] is not None:
                hits += 1
        if total and hits / total > 0.7:
            cavity.append(int(i))
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in cavity], context='VERTS')
    edges = [e for e in bm.edges if e.is_boundary and all(v.co.z > hc[2] - 0.07 and v.co.y < hc[1] for v in e.verts)]
    filled = bmesh.ops.holes_fill(bm, edges=edges, sides=0)["faces"]
    bmesh.ops.triangulate(bm, faces=filled)
    bm.to_mesh(body.data)
    bm.free()

    co = np.array([v.co for v in body.data.vertices])
    vg = body.vertex_groups.new(name="faceless")
    eyes_z = hc[2] + 0.06
    for i in range(len(co)):
        if co[i, 2] > hc[2] - 0.08 and co[i, 1] < hc[1] + 0.01:
            w = np.clip((hc[1] + 0.01 - co[i, 1]) / 0.04, 0, 1) * np.clip(1.25 - abs(co[i, 2] - eyes_z) / 0.12, 0, 1)                 * np.clip(1.4 - abs(co[i, 0]) / 0.06, 0, 1)
            if w > 0:
                vg.add([i], float(min(1.0, w)), 'REPLACE')
    sm = body.modifiers.new("Faceless", 'SMOOTH')
    sm.vertex_group = "faceless"
    sm.factor = 0.9
    sm.iterations = 45
    body.modifiers.move(len(body.modifiers) - 1, 0)
    bpy.ops.object.modifier_apply(modifier=sm.name)      # bake it: rest-shape only, keeps solves fast
    print(f"FACELESS removed {len(cavity)} cavity verts, filled {len(filled)} faces")
    return cavity


HIP_EASE_TARGETS = ("buttocks-volume-incr", "l-upperleg-muscle-incr", "r-upperleg-muscle-incr",
                    "measure-thigh-circ-incr")
HIP_EASE = (30.0, 65.0, 0.5)    # hip flexion (deg) where the glute/upper-thigh volume starts easing, where it is
                                # fully eased, and how much of it goes: real glutes flatten as they stretch


def hip_ease_delta():
    """Summed (weighted) offsets of the glute and upper-thigh targets, behind/above the thigh only, or None."""
    keys = body.data.shape_keys
    if not keys:
        return None
    basis = np.array([v.co for v in keys.reference_key.data])
    delta = np.zeros_like(basis)
    for kb in keys.key_blocks[1:]:
        if kb.name in HIP_EASE_TARGETS:
            delta += (np.array([v.co for v in kb.data]) - basis) * kb.value
    hip = (rest_head("upperleg01.L") + rest_head("upperleg01.R")) / 2
    knee_z = rest_head("lowerleg01.L").z
    # the back of the hip and upper thigh only: the quads (front) keep their size through the squat
    behind = np.clip((basis[:, 1] - (hip.y - 0.03)) / 0.04, 0, 1)
    upper = np.clip((basis[:, 2] - knee_z) / (hip.z - knee_z) * 1.5 - 0.3, 0, 1)
    return delta * (behind * upper)[:, None]


def add_hip_ease_keys(delta):
    """Shape keys hip_ease.L / .R that take HIP_EASE[2] of the glute/upper-thigh volume away (keyed by key_hip)."""
    body.shape_key_add(name="Basis", from_mix=False)
    co = np.array([v.co for v in body.data.vertices])
    for side, sx in (("L", 1), ("R", -1)):
        kb = body.shape_key_add(name=f"hip_ease.{side}", from_mix=False)
        w = np.clip(0.5 + sx * co[:, 0] / 0.01, 0, 1)[:, None]          # soft split at the midline
        kb.data.foreach_set("co", (co - HIP_EASE[2] * delta * w).ravel())
        kb.value = 0.0


def hip_flexion(side):
    """Degrees the thigh is flexed forward of the torso line (0 standing)."""
    thigh = head("lowerleg01." + side) - head("upperleg01." + side)
    torso = head("neck01") - head("spine05")
    return math.degrees(math.pi - thigh.angle(torso))


def key_hip(frame):
    """Key the hip-ease shape keys for the current pose."""
    keys = body.data.shape_keys
    if not keys:
        return
    lo, hi, _ = HIP_EASE
    for side in ("L", "R"):
        kb = keys.key_blocks.get("hip_ease." + side)
        if kb:
            kb.value = float(np.clip((hip_flexion(side) - lo) / (hi - lo), 0, 1))
            kb.keyframe_insert("value", frame=frame)


def hip_corrective():
    """Corrective smooth over the hips/glutes, after the armature: keeps the glutes from ballooning when the hips
    hinge deep (deadlift, squat) while leaving the rest pose untouched."""
    w = group_weights(body, ["pelvis.L", "pelvis.R", "upperleg01.L", "upperleg01.R", "spine05", "root"])
    co = np.array([v.co for v in body.data.vertices])
    hip_z = (rest_head("upperleg01.L").z + rest_head("upperleg01.R").z) / 2
    w *= np.clip(1.4 - np.abs(co[:, 2] - hip_z) / 0.2, 0, 1)
    vg = body.vertex_groups.new(name="hip_corrective")
    for i in np.nonzero(w > 0.02)[0]:
        vg.add([int(i)], float(min(1.0, w[i])), 'REPLACE')
    cs = body.modifiers.new("HipCorrective", 'CORRECTIVE_SMOOTH')
    cs.vertex_group = vg.name
    cs.factor, cs.iterations, cs.smooth_type = 1.0, 40, 'LENGTH_WEIGHTED'
    cs.rest_source = 'ORCO'
    arm = [i for i, m in enumerate(body.modifiers) if m.type == 'ARMATURE'][0]
    body.modifiers.move(len(body.modifiers) - 1, arm + 1)


def setup():
    global scene, rig, body, shoes, P, D, body_mask, hand_mask, masks, look_target
    scene = bpy.context.scene
    rig = bpy.data.objects["Human.rig"]
    body = bpy.data.objects["Human"]
    shoes = bpy.data.objects["Shoes"]
    P, D = rig.pose.bones, rig.data.bones

    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    ease = hip_ease_delta()
    if body.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    cavity = make_faceless()
    if ease is not None:
        add_hip_ease_keys(np.delete(ease, cavity, axis=0))
    hip_corrective()
    masks = [m for m in body.modifiers if m.type == 'MASK']
    for m in masks:
        m.show_viewport = False                          # stable vertex indices while measuring
    body_mask = group_weights(body, ["body"]) > 0
    hand_mask = group_weights(body, [g.name for g in body.vertex_groups
                                     if g.name.startswith(("finger", "metacarpal", "wrist"))]) > 0.2
    skin = clay()
    for o in (body, shoes):
        o.data.materials.clear()
        o.data.materials.append(skin)
        for poly in o.data.polygons:
            poly.material_index = 0
            poly.use_smooth = True
    for pb in P:
        pb.rotation_mode = 'QUATERNION'
    equipment_materials()
    look_target = empty("LookTarget")
    scene.frame_start, scene.frame_end = 1, LOOP
    scene.render.fps = FPS


# ---------------------------------------------------------------- trained-muscle highlight
# Same tiers + colours as the app's muscle map (dark mode): AppColor.trainingPrimaryMuscle / trainingSecondaryMuscle.
PRIMARY_RGB = (0xFF, 0xAC, 0x73)
SECONDARY_RGB = (0x80, 0xAD, 0xFF)
MUSCLE_EDGE = 0.03              # signed-margin metres mapped onto 0..1 around the 0.5 outline (shader sharpens it)
SEGMENTS = {"thigh": ("upperleg01", "lowerleg01"), "shin": ("lowerleg01", "foot"),
            "upperarm": ("upperarm01", "lowerarm01"), "forearm": ("lowerarm01", "wrist")}
TRUNK = ["spine05", "spine04", "spine03", "spine02", "spine01", "root", "pelvis", "clavicle", "breast", "shoulder01",
         "neck01", "neck02"]


def _bump(t, centre, width):
    return np.exp(-((t - centre) / width) ** 2)


def _muscle_rules():
    """Muscle -> (bone groups, limb segment or None, margin(g)): the signed distance (m, > 0 inside) of each vertex
    from the muscle's outline, for the left side. g holds per-vertex rest data: co, t (0 at the segment's start
    joint, 1 at its end), th (degrees round the limb: 0 front, 90 lateral, +-180 back, -90 medial), rad (m from the
    limb axis), L (segment length). Outlines follow the app's muscle map regions."""
    hip = np.array((rest_head("upperleg01.L") + rest_head("upperleg01.R")) / 2)
    nip, clav = rest_head("breast.L").z, rest_head("clavicle.L").z
    sp3, sp1, neck = rest_head("spine03").z, rest_head("spine01").z, rest_head("neck02").z
    shoulder_z = rest_head("upperarm01.L").z - 0.02
    thigh, shin = ["upperleg01", "upperleg02"], ["lowerleg01", "lowerleg02"]
    arm, fore = ["upperarm01", "upperarm02", "shoulder01"], ["lowerarm01", "lowerarm02"]

    def ang(g, lo, hi):                       # inside lo < th < hi (degrees, may be arrays)
        return np.minimum(g["th"] - lo, hi - g["th"]) * g["rad"] * np.pi / 180

    def back(g, half):                        # within `half` degrees of straight back
        return (half - (180 - np.abs(g["th"]))) * g["rad"] * np.pi / 180

    def along(g, lo, hi):
        return np.minimum(g["t"] - lo, hi - g["t"]) * g["L"]

    def box(g, axis, lo, hi):
        return np.minimum(g["co"][:, axis] - lo, hi - g["co"][:, axis])

    def ellipse(g, cx, cz, rx, rz):           # in the x/z (frontal) plane, metres from the rim (approx.)
        d = np.sqrt(((g["co"][:, 0] - cx) / rx) ** 2 + ((g["co"][:, 2] - cz) / rz) ** 2)
        return (1 - d) * min(rx, rz)

    def taper(t, t0, t1, fade=0.18):           # 0 at the ends of [t0, t1], 1 inside after `fade`
        return np.clip(np.minimum((t - t0) / fade, (t1 - t) / fade), 0, 1)

    def quads(g):
        tp = taper(g["t"], 0.04, 0.97)
        lo = -(50 + 55 * _bump(g["t"], 0.82, 0.09)) * tp            # vastus medialis teardrop above the knee
        return np.minimum(ang(g, lo, 105 * tp), along(g, 0.06, 0.96))

    def adductors(g):
        tp = taper(g["t"], -0.02, 0.62, 0.25)
        lo_q = -(50 + 55 * _bump(g["t"], 0.82, 0.09)) * taper(g["t"], 0.04, 0.97)
        return np.minimum(ang(g, -150 * tp, lo_q), along(g, 0.0, 0.62))

    def hamstrings(g):
        return np.minimum(back(g, 62 * np.sqrt(taper(g["t"], 0.16, 0.92, 0.3))), along(g, 0.16, 0.92))

    def calves(g):                             # gastrocnemius heads + soleus, back of the lower leg only
        w = 60 * np.sqrt(taper(g["t"], 0.04, 0.62, 0.22)) + 28 * _bump(g["t"], 0.66, 0.08)
        # the medial head stays behind the tibia line, so no blue reads on the shin from the front
        behind_tibia = np.where(g["th"] < 0, (np.abs(g["th"]) - 115) * g["rad"] * np.pi / 180, 1.0)
        return np.minimum.reduce([back(g, w), along(g, 0.04, 0.76), behind_tibia])

    def glutes(g):
        behind = g["co"][:, 1] - (hip[1] - 0.03)
        return np.minimum(ellipse(g, 0.09, hip[2] - 0.02, 0.095, 0.12), behind)

    def behind_spine(g, depth):
        return g["co"][:, 1] - (float(rest_head("spine03").y) + depth)

    def lower_back(g):                         # erector columns either side of the spine
        x = np.abs(g["co"][:, 0])
        return np.minimum.reduce([x - 0.012, 0.085 - x, box(g, 2, hip[2] + 0.08, sp3 + 0.15),
                                  behind_spine(g, 0.0)])

    def middle_back(g):                        # rhomboids, between the shoulder blades
        x, z = np.abs(g["co"][:, 0]), g["co"][:, 2]
        return np.minimum.reduce([0.085 - x, z - (sp3 + 0.1 + 0.5 * x), shoulder_z - z, behind_spine(g, 0.02)])

    def lats(g):                               # V from the armpit down to the lower spine
        x, z = np.abs(g["co"][:, 0]), g["co"][:, 2]
        low = hip[2] + 0.1
        return np.minimum.reduce([x - (0.02 + 0.55 * (z - low)), 0.215 - x, z - low,
                                  (sp3 + 0.13 + 0.5 * (x - 0.06)) - z, behind_spine(g, -0.04)])

    def traps(g):                              # diamond: narrow at mid-back, widest at the shoulders, up the neck
        x, z = np.abs(g["co"][:, 0]), g["co"][:, 2]
        width = np.minimum(0.02 + 0.75 * (z - sp3), np.maximum(0.045, 0.2 - 1.6 * (z - shoulder_z)))
        return np.minimum.reduce([width - x, box(g, 2, sp3, neck), behind_spine(g, 0.0)])

    def chest(g):
        x, z = np.abs(g["co"][:, 0]), g["co"][:, 2]
        bottom = nip - 0.045 + 0.6 * np.clip(x - 0.12, 0, None)
        return np.minimum.reduce([x - 0.012, 0.19 - x, z - bottom, clav - 0.012 - z,
                                  -(g["co"][:, 1] - float(rest_head("spine03").y)) - 0.02])

    def abs_(g):
        x = np.abs(g["co"][:, 0])
        return np.minimum.reduce([0.085 - x, box(g, 2, hip[2] + 0.03, nip - 0.08),
                                  -(g["co"][:, 1] - float(rest_head("spine03").y)) - 0.03])

    def delt(lo, hi):
        def m(g):
            tp = taper(g["t"], -0.3, 0.55, 0.15)
            mid, half = (lo + hi) / 2, (hi - lo) / 2
            th = (g["th"] - mid + 180) % 360 - 180
            return np.minimum((half * tp - np.abs(th)) * g["rad"] * np.pi / 180, along(g, -0.3, 0.55))
        return m

    def biceps(g):                             # both heads, front of the upper arm, narrowing to the tendon
        tp = np.sqrt(taper(g["t"], 0.24, 0.97, 0.2))           # starts below the front delt
        return np.minimum(ang(g, -75 * tp, 65 * tp), along(g, 0.24, 0.97))

    def triceps(g):
        return np.minimum(back(g, 70 * taper(g["t"], 0.2, 0.93, 0.25)), along(g, 0.2, 0.93))

    def forearms(g):
        return along(g, 0.0, 0.86)

    return {"quads": (thigh, "thigh", quads), "adductors": (thigh, "thigh", adductors),
            "hamstrings": (thigh, "thigh", hamstrings), "calves": (shin, "shin", calves),
            "glutes": (thigh + ["pelvis", "root", "spine05"], None, glutes),
            "lower_back": (TRUNK, None, lower_back), "middle_back": (TRUNK, None, middle_back),
            "lats": (TRUNK + ["upperarm01"], None, lats), "traps": (TRUNK, None, traps),
            "chest": (TRUNK, None, chest), "abs": (TRUNK, None, abs_),
            "front_delts": (arm, "upperarm", delt(-60, 30)), "side_delts": (arm, "upperarm", delt(25, 140)),
            "rear_delts": (arm, "upperarm", delt(125, 215)),
            "biceps": (arm, "upperarm", biceps), "triceps": (arm, "upperarm", triceps),
            "forearms": (fore, "forearm", forearms)}


def _limb_frame(co, seg):
    """Per-vertex (t, theta, radius, length) round the left limb segment `seg`."""
    a, b = (np.array(rest_head(f"{j}.L")) for j in SEGMENTS[seg])
    L = float(np.linalg.norm(b - a))
    ax = (b - a) / L
    front = np.array((0.0, -1.0, 0.0))
    front = front - front.dot(ax) * ax
    front /= np.linalg.norm(front)
    lat = np.cross(ax, front)
    lat = lat if lat[0] > 0 else -lat
    rel = co - a
    radial = rel - np.outer(rel @ ax, ax)
    th = np.degrees(np.arctan2(radial @ lat, radial @ front))
    return rel @ ax / L, th, np.linalg.norm(radial, axis=1), L


def _mirror_index(co):
    """For each vertex, the index of its mirror image across x = 0 (MPFB meshes are symmetric)."""
    from mathutils.kdtree import KDTree
    kd = KDTree(len(co))
    for i, c in enumerate(co):
        kd.insert(c, i)
    kd.balance()
    return np.array([kd.find((-c[0], c[1], c[2]))[1] for c in co])


_mirror = None


def muscle_mask(name):
    """0..1 per-vertex field of one muscle region on the rest mesh, 0.5 on its outline; left side solved, right
    side mirrored from it so both match exactly."""
    global _mirror
    bones, seg, margin = _muscle_rules()[name]
    co = np.array([v.co for v in body.data.vertices])
    if _mirror is None:
        _mirror = _mirror_index(co)
    names = [b if b in ("root", "neck01", "neck02") or b.startswith("spine") else f"{b}.L" for b in bones]
    member = (group_weights(body, names) > 0.15) & body_mask & ~hand_mask & (co[:, 0] > -0.003)
    g = {"co": co}
    if seg:
        g["t"], g["th"], g["rad"], g["L"] = _limb_frame(co, seg)
    field = np.where(member, np.clip(0.5 + margin(g) / MUSCLE_EDGE, 0, 1), 0.0)
    left = co[:, 0] >= 0
    return np.where(left, field, field[_mirror])


def train(primary=(), secondary=()):
    """Tint the muscles this exercise trains, app-style: `primary` orange, `secondary` blue (vertex attributes read
    by the clay shader; primary is drawn over secondary)."""
    n = len(body.data.vertices)
    for attr, names in (("atlas_primary", primary), ("atlas_secondary", secondary)):
        w = np.zeros(n)
        for m in names:
            w = np.maximum(w, muscle_mask(m))
        a = body.data.attributes.get(attr) or body.data.attributes.new(attr, 'FLOAT', 'POINT')
        a.data.foreach_set("value", w.astype(np.float32))
        print(f"TRAIN {attr[6:]} {list(names)}: {(w > 0.5).sum()} verts")


# ---------------------------------------------------------------- equipment meshes
def cylinder(parent, radius, depth, x=0.0, mat=None, verts=64, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=(x, 0, 0),
                                        rotation=(0, math.pi / 2, 0))
    o = bpy.context.object
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    if bevel:
        b = o.modifiers.new("bevel", 'BEVEL')
        b.width, b.segments = bevel, 3
        o.data.polygons.foreach_set("use_smooth", [True] * len(o.data.polygons))
        o.data.update()
        o.modifiers.new("wn", 'WEIGHTED_NORMAL')
    o.parent = parent
    o.matrix_parent_inverse = Matrix.Identity(4)
    return o


BAR_R = 0.0145


def barbell(h, length=2.2):
    """Olympic bar along the holder's X axis, centred on it: 28-29 mm shaft, 1.31 m between the inner collars,
    2x20 kg + 1x10 kg per side (plate radius 0.225)."""
    cylinder(h, BAR_R, 1.31, mat=STEEL, verts=48)
    for sx in (1, -1):
        cylinder(h, 0.035, 0.03, x=sx * 0.67, mat=STEEL)
        cylinder(h, 0.025, length / 2 - 0.685, x=sx * (0.685 + length / 2) / 2, mat=STEEL)
        x = 0.69
        for rad, w in ((0.225, 0.055), (0.225, 0.055), (0.17, 0.035)):
            cylinder(h, rad, w, x=sx * (x + w / 2), mat=PLATE, verts=96, bevel=0.006)
            cylinder(h, 0.03, w + 0.004, x=sx * (x + w / 2), mat=STEEL)
            x += w + 0.002


DB_R = 0.015                    # ~30 mm dumbbell handle


def dumbbell(h, handle=0.135, head_r=0.06, head_w=0.07):
    cylinder(h, DB_R, handle + 0.02, mat=STEEL, verts=48)
    for sx in (1, -1):
        cylinder(h, head_r, head_w, x=sx * (handle / 2 + head_w / 2), mat=PLATE, verts=6, bevel=0.008)


# ---------------------------------------------------------------- IK
def add_ik(bone, target, pole, chain=4):
    """IK over a 4-bone MPFB limb (01/02 halves of each segment). The 02 halves may only twist, so the limb bends
    at the anatomical joints (hip/knee, shoulder/elbow) and the segments stay straight like bones."""
    c = P[bone].constraints.new('IK')
    c.target, c.pole_target, c.chain_count, c.iterations = target, pole, chain, 500
    b = P[bone]
    for _ in range(chain):
        if b.name.split(".")[0].endswith("02"):
            b.lock_ik_x = b.lock_ik_z = True
        b = b.parent
    return c


def copy_rot(bone, target):
    c = P[bone].constraints.new('COPY_ROTATION')
    c.target = target
    return c


def plant_feet(toe_out_deg=10, ankles=None, knee_up=0.45):
    """Ankle IK + feet flat on the floor (rest stance unless world `ankles` given), knees following the toes."""
    for s, sx in (("L", 1), ("R", -1)):
        foot_rest = D["foot." + s].matrix_local.copy()
        ankle = Vector(ankles[s]) if ankles else foot_rest.translation
        rot = Matrix.Rotation(math.radians(sx * toe_out_deg), 3, 'Z')
        tgt = empty("FootIK." + s)
        tgt.matrix_world = Matrix.Translation(ankle) @ (rot @ foot_rest.to_3x3()).to_4x4()
        pole = empty("KneePole." + s)
        pole.location = ankle + rot @ Vector((sx * 0.35, -1, 0)).normalized() + Vector((0, 0, knee_up))
        add_ik("lowerleg02." + s, tgt, pole)
        copy_rot("foot." + s, tgt)


def ik_arms(h, poles, poles_in_world=False):
    """Wrist IK + hand orientation from targets parented to the holder `h` (or per-side holders).

    Elbow poles ride with the holder unless `poles_in_world`."""
    for s in ("L", "R"):
        hs = h[s] if isinstance(h, dict) else h
        tgt = empty("HandIK." + s, parent=hs)
        pole = empty("ElbowPole." + s, parent=None if poles_in_world else hs)
        pole.location = poles[s]
        add_ik("lowerarm02." + s, tgt, pole)
        copy_rot("wrist." + s, tgt)
        hand_targets[s] = tgt


def solve_pole_angles(arm_want, leg_want=None):
    """Pick IK pole angles so elbows/knees point where the exercise needs them."""
    pairs = [("lowerarm02.L", arm_want["L"]), ("lowerarm02.R", arm_want["R"])]
    if leg_want:
        pairs += [("lowerleg02.L", leg_want["L"]), ("lowerleg02.R", leg_want["R"])]
    for bone, want in pairs:
        c = P[bone].constraints["IK"]
        joint = bone.replace("02", "01")
        best = None
        for deg in range(-180, 180, 5):
            c.pole_angle = math.radians(deg)
            update()
            mid = (head(D[joint].parent.parent.name) + tail(bone)) / 2
            score = (head(joint) - mid).normalized().dot(Vector(want).normalized())
            if best is None or score > best[0]:
                best = (score, deg)
        c.pole_angle = math.radians(best[1])
        print(f"POLE {bone}: {best[1]} deg (alignment {best[0]:.2f})")
    update()


# ---------------------------------------------------------------- grip
def hand_frame_rest(s, square=False):
    """Rest hand frame (fingers, knuckle line toward the thumb side, palm normal) + palm half-thickness.

    `square` (0..1) turns the handle from along the slanted knuckle line toward square to the hand's long axis
    (wrist -> middle knuckle); at 1 a neutral wrist and a vertical forearm put it diagonally across the palm, as in a
    real hanging grip."""
    wrist = rest_head("wrist." + s)
    knuck_line = (rest_head("finger2-1." + s) - rest_head("finger5-1." + s)).normalized()
    f = rest_head("finger3-1." + s) - wrist
    f_knuck = (f - f.dot(knuck_line) * knuck_line).normalized()
    f = f_knuck.lerp(f.normalized(), float(square)).normalized()
    knuck_line = (knuck_line - knuck_line.dot(f) * f).normalized()
    # (fingers, thumb side, palm) is right-handed for a left hand, left-handed for a right hand
    p = f.cross(knuck_line) if s == "L" else -f.cross(knuck_line)
    co = np.array([v.co for v in body.data.vertices])
    mc = group_weights(body, ["metacarpal2." + s, "metacarpal3." + s, "metacarpal4." + s]) > 0.5
    knuck = (rest_head("finger2-1." + s) + rest_head("finger5-1." + s)) / 2
    t_palm = float(((co[mc] - np.array(knuck)) @ np.array(p)).max())
    return Matrix((f, knuck_line, p)).transposed(), knuck, t_palm


def frame_from(s, thumbward, palm_to_handle):
    a = Vector(thumbward).normalized()
    p = Vector(palm_to_handle)
    p = (p - p.dot(a) * a).normalized()
    f = a.cross(p) if s == "L" else p.cross(a)
    return Matrix((f, a, p)).transposed()


def handle_in_hand(s, slide, radius, square=False):
    """Matrix of the handle (X = handle axis toward the thumb side) in rest armature space."""
    F, knuck, t = hand_frame_rest(s, square)
    f, a, p = F.col[0], F.col[1], F.col[2]
    centre = knuck - f * slide + p * (t + radius)
    # handle frame: x = knuckle line (thumb side), y = finger dir, z = palm normal
    m = Matrix((a, f, p)).transposed().to_4x4()
    m.translation = centre
    return m


def grip_on(s, h, centre, thumbward, palm_to_handle, slide=0.012, radius=BAR_R, square=False):
    """Place hand target `s` (child of holder h) so the handle at `centre` sits in the palm.

    All vectors are in the holder's local space."""
    F_rest, _, _ = hand_frame_rest(s, square)
    F_des = frame_from(s, thumbward, palm_to_handle)
    R = F_des @ F_rest.transposed()
    wrist_rest = D["wrist." + s].matrix_local
    handle = handle_in_hand(s, slide, radius, square)
    wrist_pos = Vector(centre) - R @ (handle.translation - wrist_rest.translation)
    tgt = hand_targets[s]
    tgt.matrix_parent_inverse = Matrix.Identity(4)
    tgt.matrix_basis = Matrix.Translation(wrist_pos) @ (R @ wrist_rest.to_3x3()).to_4x4()
    tgt["palm_n"] = list(F_des.col[2])
    tgt["handle_axis"] = list(Vector(thumbward).normalized())
    tgt["handle_centre"] = list(centre)
    tgt["radius"] = radius
    tgt["slide"] = slide


def hand_line(s, rest=False):
    """Wrist-to-middle-knuckle direction in the forearm's frame (rest or posed) + that frame in world space."""
    if rest:
        fore = D["lowerarm02." + s].matrix_local.to_3x3()
        line = rest_head("finger3-1." + s) - rest_head("wrist." + s)
    else:
        fore = (rig.matrix_world @ P["lowerarm02." + s].matrix).to_3x3().normalized()
        line = head("finger3-1." + s) - head("wrist." + s)
    return fore.inverted() @ line.normalized(), fore


def wrist_bend(s):
    """Degrees the hand is bent (flexion/extension + deviation) away from its rest line with the forearm."""
    return math.degrees(hand_line(s, rest=True)[0].angle(hand_line(s)[0]))


def roll_neutral(h, span=40):
    """Roll a barbell holder about its own axis (invisible on a round bar) to keep both wrists straightest."""
    base = h.matrix_world.copy()

    def bend(deg):
        h.matrix_world = base @ Matrix.Rotation(math.radians(deg), 4, 'X')
        update()
        return wrist_bend("L") + wrist_bend("R")

    best = min(range(-span, span + 1, 5), key=bend)
    best = min((best + k for k in (-2, -1, 0, 1, 2)), key=bend)
    bend(best)
    return best


def roll_holder(h, deg):
    """Roll a barbell holder about its own axis by `deg` from its current pose."""
    h.matrix_world = h.matrix_world @ Matrix.Rotation(math.radians(deg), 4, 'X')
    update()


def pchip(x, y, t):
    """Monotone cubic (Fritsch-Carlson) interpolation of samples (x, y) at t: smooth, no overshoot."""
    x, y = np.asarray(x, float), np.asarray(y, float)
    h, delta = np.diff(x), np.diff(y) / np.diff(x)
    m = np.zeros_like(y)
    m[1:-1] = np.where(delta[:-1] * delta[1:] > 0,
                       (3 * (h[:-1] + h[1:])) / ((2 * h[1:] + h[:-1]) / np.where(delta[:-1] == 0, 1, delta[:-1])
                                                 + (h[1:] + 2 * h[:-1]) / np.where(delta[1:] == 0, 1, delta[1:])), 0)
    m[0], m[-1] = delta[0], delta[-1]
    i = int(np.clip(np.searchsorted(x, t) - 1, 0, len(h) - 1))
    s = (t - x[i]) / h[i]
    return float((2 * s ** 3 - 3 * s ** 2 + 1) * y[i] + (s ** 3 - 2 * s ** 2 + s) * h[i] * m[i]
                 + (-2 * s ** 3 + 3 * s ** 2) * y[i + 1] + (s ** 3 - s ** 2) * h[i] * m[i + 1])


def smooth(values, sigma, loop=False):
    """Gaussian smoothing of a 1-D series (sigma in samples); `loop` wraps it round, else the ends are held."""
    r = int(3 * sigma) + 1
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    padded = np.concatenate([values[-r:], values, values[:r]]) if loop else np.pad(values, r, mode='edge')
    return np.convolve(padded, k, mode='valid')


def straighten_wrist(s, h):
    """Swing a dumbbell holder about the wrist so the hand sits on the forearm's line (wrist neutral)."""
    want = hand_line(s, rest=True)[0]
    for _ in range(3):
        cur, fore = hand_line(s)
        q = fore @ cur.rotation_difference(want).to_matrix() @ fore.inverted()
        w = head("wrist." + s)
        h.matrix_world = Matrix.Translation(w) @ q.to_4x4() @ Matrix.Translation(-w) @ h.matrix_world
        update()


def grip_neutral(s, h, centre, thumbward, palm_guess, slide=0.012, radius=BAR_R, span=70, square=False):
    """grip_on, with the hand rolled round the bar (within `span` deg of `palm_guess`) to keep the wrist straight."""
    axis = Vector(thumbward).normalized()

    def bend(deg):
        grip_on(s, h, centre, thumbward, Quaternion(axis, math.radians(deg)) @ Vector(palm_guess), slide, radius, square)
        update()
        return wrist_bend(s)

    best = min(range(-span, span + 1, 5), key=bend)
    best = min((best + k for k in (-4, -2, 0, 2, 4)), key=bend)
    print(f"GRIP {s}: rolled {best} deg, wrist bend {bend(best):.1f} deg")


def handle_axis_world(s):
    tgt = hand_targets[s]
    m = tgt.parent.matrix_world
    return m @ Vector(tgt["handle_centre"]), (m.to_3x3() @ Vector(tgt["handle_axis"])).normalized()


def dist_to_axis(pts, o, d):
    rel = pts - np.array(o)
    along = rel @ np.array(d)
    return np.linalg.norm(rel - np.outer(along, np.array(d)), axis=1), along


def seat_palm(s):
    """Slide the hand along its palm normal until the palm skin just meets the handle."""
    tgt = hand_targets[s]
    palm = group_weights(body, [f"metacarpal{k}.{s}" for k in range(1, 5)] + ["wrist." + s]) > 0.5
    n = Vector(tgt["palm_n"])
    r = tgt["radius"]
    for _ in range(5):
        o, d = handle_axis_world(s)
        dist, along = dist_to_axis(world_coords(body)[palm], o, d)
        gap = dist[np.abs(along) < 0.07].min() - r - SKIN_GAP
        tgt.location += n * gap
        update()
    print(f"PALM {s}: residual gap {gap * 1000:.1f} mm")


def curl(bone, angle, axis_world):
    pb = P[bone]
    m = (rig.matrix_world @ pb.matrix).to_3x3().normalized()
    ax = (m.inverted() @ axis_world).normalized()
    pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion(ax, angle)
    update()


def hand_dirs_world(s):
    """(fingers, thumb side, palm-to-handle) directions of hand `s`, in world space."""
    tgt = hand_targets[s]
    m = tgt.parent.matrix_world.to_3x3()
    p = (m @ Vector(tgt["palm_n"])).normalized()
    a = (m @ Vector(tgt["handle_axis"])).normalized()
    f = a.cross(p) if s == "L" else p.cross(a)
    return f, a, p


def handle_clearance(s, verts):
    o, d = handle_axis_world(s)
    dist, along = dist_to_axis(world_coords(body)[verts], o, d)
    near = np.abs(along) < 0.12
    return dist[near].min() - hand_targets[s]["radius"] if near.any() else 1.0


def straighten_in_plane(s, chain):
    """Lay the finger across the handle and straighten it, so curling about the handle axis wraps it round
    the bar instead of fanning it along it. A slight lean toward the middle finger closes the gaps."""
    o, d = handle_axis_world(s)
    first = tail(chain[0]) - head(chain[0])
    direction = (first - first.dot(d) * d).normalized()
    toward_middle = (head(f"finger3-1.{s}") - head(chain[0])).dot(d)
    direction = (direction + d * toward_middle / 0.15).normalized()
    for bone in chain:
        aim(bone, head(bone) + direction)


JOINT_LIMITS = (95, 110, 90)    # MCP, PIP, DIP flexion limits (deg)


def sweep(f, max_deg):
    """Largest angle in [0, max_deg] reached by stepping closed from 0 while clearance f(angle) stays > SKIN_GAP."""
    lo, step = 0.0, math.radians(5)
    while lo + step <= math.radians(max_deg):
        if f(lo + step) <= SKIN_GAP:
            hi = lo + step
            for _ in range(7):
                mid = (lo + hi) / 2
                lo, hi = (mid, hi) if f(mid) > SKIN_GAP else (lo, mid)
            return lo
        lo += step
    return lo


def wrap_chain(s, chain):
    """Wrap one finger round the handle like a real grip: close the MCP until the proximal phalanx touches, then
    the PIP until the middle phalanx touches, then the DIP until the tip touches, so every segment hugs the bar.

    Each sweep starts open and steps closed, checking the joint's segment and everything beyond it, so no
    segment can start or pass inside the bar."""
    straighten_in_plane(s, chain)
    o, d = handle_axis_world(s)
    to_axis = o - head(chain[0])
    to_axis -= to_axis.dot(d) * d
    sign = 1 if d.cross(tail(chain[0]) - head(chain[0])).dot(to_axis) > 0 else -1     # every joint flexes the same way
    segs = [group_weights(body, [b]) > 0.5 for b in chain]

    def seg_clear():
        o, d = handle_axis_world(s)
        dist, along = dist_to_axis(world_coords(body), o, d)
        r = hand_targets[s]["radius"]
        near = np.abs(along) < 0.12
        return [float((dist[sg & near] - r).min()) if (sg & near).any() else 1.0 for sg in segs]

    angles = []
    for j, (bone, limit) in enumerate(zip(chain, JOINT_LIMITS)):
        q0 = P[bone].rotation_quaternion.copy()

        def bend(ang):
            P[bone].rotation_quaternion = q0
            update()
            curl(bone, sign * ang, handle_axis_world(s)[1])
            return min(seg_clear()[j:])
        ang = sweep(bend, limit)
        bend(ang)
        angles.append(math.degrees(ang))
    c = seg_clear()
    print(f"WRAP {chain[0][:-2]} {s}: MCP {angles[0]:.0f} PIP {angles[1]:.0f} DIP {angles[2]:.0f} deg, "
          f"segment clearance {' / '.join(f'{x * 1000:.1f}' for x in c)} mm")


def wrap_hand(s):
    """Fingers curled round the handle, thumb wrapped over them on the far side."""
    for k in (2, 3, 4, 5):
        wrap_chain(s, [f"finger{k}-1.{s}", f"finger{k}-2.{s}", f"finger{k}-3.{s}"])
    wrap_thumb(s)


# thumb joint waypoints around the handle, in mm of (fingers, thumb side, palm-to-handle) from the handle axis:
# MCP below the handle on the wrist side, IP round the far side; sets which way the thumb winds before closing
THUMB_PATH = ((-36, 20, -14), (-30, 25, 14), (-12, 17, 35))


def aim(bone, target):
    cur = (tail(bone) - head(bone)).normalized()
    want = (target - head(bone)).normalized()
    ang = cur.angle(want)
    if ang > 1e-4:
        curl(bone, ang, cur.cross(want).normalized())


def reach(bones, target, iters=12):
    """CCD: rotate each joint, tip first, so the chain's tip moves onto `target`."""
    for _ in range(iters):
        for b in reversed(bones):
            h = head(b)
            cur, want = (tail(bones[-1]) - h).normalized(), (target - h).normalized()
            ang = cur.angle(want)
            if ang > 1e-4:
                curl(b, ang, cur.cross(want).normalized())


def wrap_thumb(s):
    """Full grip: wind the thumb loosely round the far side of the handle (THUMB_PATH, opened out), then close the
    MCP and IP joints in turn until the thumb touches the bar or the fingers wrapped under it."""
    from mathutils.kdtree import KDTree
    f, a, p = hand_dirs_world(s)
    o, _ = handle_axis_world(s)
    r = hand_targets[s]["radius"]
    bones = [f"finger1-{k}.{s}" for k in (1, 2, 3)]
    segs = [group_weights(body, [b]) > 0.4 for b in bones[1:]]
    fingers = group_weights(body, [f"finger{k}-{j}.{s}" for k in (2, 3, 4, 5) for j in (1, 2, 3)]) > 0.4

    def clearance(seg_from):
        co = world_coords(body)
        kd = KDTree(int(fingers.sum()))
        for i, c in enumerate(co[fingers]):
            kd.insert(c, i)
        kd.balance()
        pts = co[segs[seg_from] | segs[-1]]
        dist, _ = dist_to_axis(pts, o, a)
        return min(dist.min() - r, min(kd.find(c)[2] for c in pts))

    shift = (hand_targets[s]["slide"] - 0.012) * 1000          # path is set for slide 0.012: keep it fixed to the hand
    for open_scale in (1.4, 1.6, 1.8, 2.0):
        for b, (wf, wa, wp) in zip(bones, THUMB_PATH):
            k = 1 if b == bones[0] else open_scale
            aim(b, o + (f * (wf * k - shift) + p * wp * k + a * wa) / 1000)
        if clearance(0) > SKIN_GAP:
            break
    open_pose = {b: P[b].rotation_quaternion.copy() for b in bones}

    def close(order):
        """Close the thumb joints in `order` (indices into bones[1:]) until contact; -> wrap angle, labels."""
        for b in bones:
            P[b].rotation_quaternion = open_pose[b]
        update()
        angles = {}
        for j in order:
            b = bones[1 + j]
            q0 = P[b].rotation_quaternion.copy()

            def bend(ang):
                P[b].rotation_quaternion = q0
                update()
                curl(b, sign * ang, a)
                return clearance(j)

            def tip_to_axis(sg):
                P[b].rotation_quaternion = q0
                update()
                curl(b, sg * math.radians(10), a)
                return dist_to_axis(np.array([tail(bones[2])]), o, a)[0][0]
            sign = min((1, -1), key=tip_to_axis)          # close toward the bar
            ang = sweep(bend, 100)
            bend(ang)
            angles[j] = f"{math.degrees(ang):.0f} deg"
        tip = tail(bones[2]) - o
        # how far round the bar the tip got: 0 on the wrist side, 90 over the far side, 180 on the finger side
        return math.degrees(math.atan2(tip.dot(p), -tip.dot(f))), [angles[0], angles[1]]

    # MCP first lays the thumb along the bar; IP first hooks it so it wraps further: keep whichever goes further round
    results = [(close(order), order) for order in ((0, 1), (1, 0))]
    (wrap, angles), order = max(results, key=lambda r: r[0][0])
    close(order)
    tip = tail(bones[2]) - o
    print(f"THUMB {s}: closed MCP {angles[0]} IP {angles[1]} ({'IP' if order[0] else 'MCP'} first, wrap {wrap:.0f} deg, "
          f"opened {open_scale:.1f}x), clearance "
          f"{clearance(0) * 1000:.1f} mm, tip (f {tip.dot(f) * 1000:.0f}, a {tip.dot(a) * 1000:.0f}, "
          f"p {tip.dot(p) * 1000:.0f}) mm, {(tip - tip.dot(a) * a).length * 1000:.0f} mm from the bar axis")


FINGER_BONES = [f"finger{k}-{j}" for k in range(1, 6) for j in (1, 2, 3)]


def regrip(s, h, centre, thumbward, palm_guess, slide=0.012, radius=BAR_R, span=70):
    """Per-frame grip: pick the hand's roll round the bar and its angle across the palm (`square`) that keep the
    wrist straightest for the current arm pose, seat the palm, and wrap the fingers and thumb afresh.

    Call after the frame's body + equipment pose is set; then key_hand(s, frame)."""
    axis = Vector(thumbward).normalized()
    hand_targets[s].rotation_mode = 'QUATERNION'
    for b in FINGER_BONES:
        P[f"{b}.{s}"].rotation_quaternion = Quaternion()

    def bend(sq, deg):
        grip_on(s, h, centre, thumbward, Quaternion(axis, math.radians(deg)) @ Vector(palm_guess), slide, radius, sq)
        update()
        return wrist_bend(s)

    best = min(((sq, deg) for sq in np.arange(-1.0, 2.01, 0.25) for deg in range(-span, span + 1, 5)),
               key=lambda c: bend(*c))
    best = min(((min(2.0, max(-1.0, best[0] + dq)), best[1] + dd) for dq in (-0.1, 0, 0.1) for dd in (-2, 0, 2)),
               key=lambda c: bend(*c))
    wb = bend(*best)
    seat_palm(s)
    wrap_hand(s)
    print(f"REGRIP {s}: square {best[0]:.2f}, roll {best[1]} deg, wrist bend {wb:.1f} deg")
    return wb


def key_hand(s, frame):
    tgt = hand_targets[s]
    tgt.keyframe_insert("location", frame=frame)
    tgt.keyframe_insert("rotation_quaternion", frame=frame)
    key_bones([f"{b}.{s}" for b in FINGER_BONES], frame)


def hand_clipping():
    """Max penetration (mm) of any hand vertex into its handle, both hands."""
    co = world_coords(body)
    worst = -1.0
    for s in ("L", "R"):
        o, d = handle_axis_world(s)
        dist, along = dist_to_axis(co[hand_mask & body_mask], o, d)
        near = np.abs(along) < 0.12
        if near.any():
            worst = max(worst, float((hand_targets[s]["radius"] - dist[near]).max()))
    return worst * 1000


def arm_lengths(s):
    upper = (rest_head("lowerarm01." + s) - rest_head("upperarm01." + s)).length
    fore = (rest_head("wrist." + s) - rest_head("lowerarm01." + s)).length
    return upper, fore


def holder_for_hand(s, wrist_pos, f, a):
    """World matrix for a dumbbell holder so hand `s` has fingers `f`, thumb side `a`, wrist at `wrist_pos`.

    Assumes grip_on(s, h, (0,0,0), thumbward=(1,0,0), palm_to_handle=(0,0,1))."""
    f = Vector(f).normalized()
    a = Vector(a)
    a = (a - a.dot(f) * f).normalized()
    p = f.cross(a) if s == "L" else a.cross(f)
    world = Matrix((f, a, p)).transposed()
    local = frame_from(s, (1, 0, 0), (0, 0, 1))
    q = world @ local.transposed()
    tgt_local = hand_targets[s].matrix_basis.translation
    m = q.to_4x4()
    m.translation = Vector(wrist_pos) - q @ tgt_local
    return m


# ---------------------------------------------------------------- body pose helpers
def set_root(drop=0.0, back=0.0, lean=0.0, base=None):
    """Move/pitch the whole upper body about the hips (lean > 0 tips the chest forward)."""
    rest = D["root"].matrix_local.copy()
    pivot = rest.translation.copy()
    m = Matrix.Translation(pivot + Vector((0, back, -drop))) @ Matrix.Rotation(lean, 4, 'X') @ \
        Matrix.Translation(-pivot) @ rest
    P["root"].matrix = m
    update()


def rotate_local(bone, axis_world, angle):
    """Set a bone's pose rotation to `angle` about a world axis (given in rest orientation)."""
    ax = (D[bone].matrix_local.to_3x3().inverted() @ Vector(axis_world)).normalized()
    P[bone].rotation_quaternion = Quaternion(ax, angle)


def key_bones(names, frame):
    for n in names:
        P[n].keyframe_insert("location", frame=frame)
        P[n].keyframe_insert("rotation_quaternion", frame=frame)


def key_holder(h, frame):
    h.keyframe_insert("location", frame=frame)
    h.keyframe_insert("rotation_quaternion", frame=frame)


def ease(t):
    return 0.5 - 0.5 * math.cos(math.pi * min(max(t, 0.0), 1.0))


def rep_phase(frame, bottom=44, hold=4):
    """0 -> 1 -> 0 over the loop with eased ends and a short pause at the far end."""
    f = frame - 1
    if f <= bottom:
        return ease(f / bottom)
    if f <= bottom + hold:
        return 1.0
    return ease(1 - (f - bottom - hold) / (LOOP - bottom - hold))


# ---------------------------------------------------------------- checks
def body_vs_equipment(frame, objs):
    """Penetration (mm) of body vertices (hands excluded) into equipment, via a BVH of the equipment."""
    from mathutils.bvhtree import BVHTree
    scene.frame_set(frame)
    update()
    dg = bpy.context.evaluated_depsgraph_get()
    co = world_coords(body)[body_mask & ~hand_mask]
    worst = 0.0
    for o in objs:
        ev = o.evaluated_get(dg)
        bvh = BVHTree.FromObject(ev, dg)
        inv = o.matrix_world.inverted()
        for p in co[::3]:
            loc = inv @ Vector(p)
            hit = bvh.find_nearest(loc, 0.03)
            if hit[0] is not None:
                n = hit[1]
                if (loc - hit[0]).dot(n) < 0:
                    worst = max(worst, (loc - hit[0]).length)
    return worst * 1000


def report(frames):
    for fr in frames:
        scene.frame_set(fr)
        update()
        errs = [(tail("lowerarm02." + s) - hand_targets[s].matrix_world.translation).length * 1000 for s in ("L", "R")]
        print(f"CHECK f{fr}: hand-in-handle {hand_clipping():.1f} mm (neg = clear), "
              f"wrist IK error {errs[0]:.1f}/{errs[1]:.1f} mm, wrist bend {wrist_bend('L'):.0f}/{wrist_bend('R'):.0f} deg")


# ---------------------------------------------------------------- look + render
def setup_render():
    for m in masks:
        m.show_viewport = True
    for o in (body, shoes):
        sub = o.modifiers.new("Subdiv", 'SUBSURF')
        sub.levels, sub.render_levels = 0, 1
    world = bpy.data.worlds.new("Black")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world
    r = scene.render
    r.film_transparent = True                        # black + glow composited in post (composite.py)
    r.resolution_x, r.resolution_y = map(int, os.environ.get("ATLAS_RES", "1080x1350").split("x"))
    r.image_settings.file_format = 'PNG'
    r.image_settings.color_mode = 'RGBA'
    r.image_settings.color_depth = '16'
    tier_output()
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = -0.55
    r.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for dev in prefs.devices:
        dev.use = dev.type == 'OPTIX'
    optix = any(dev.type == 'OPTIX' for dev in prefs.devices)        # no NVIDIA GPU (e.g. CI): CPU + OIDN
    scene.cycles.device = 'GPU' if optix else 'CPU'
    # edge stability: enough samples that silhouette pixels converge, a fixed seed (same noise pattern every frame),
    # and the OptiX denoiser guided by albedo + normal so it keeps the outline instead of smearing it per frame
    c = scene.cycles
    c.samples = int(os.environ.get("ATLAS_SAMPLES", 256))          # CPU runners render with fewer samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = float(os.environ.get("ATLAS_ADAPTIVE", 0.004))
    c.adaptive_min_samples = min(96, c.samples // 2)
    c.seed = 0
    c.use_animated_seed = False
    c.use_denoising = True
    c.denoiser = 'OPTIX' if optix else 'OPENIMAGEDENOISE'
    c.denoising_input_passes = 'RGB_ALBEDO_NORMAL'
    c.denoising_prefilter = 'ACCURATE'
    c.max_bounces = 6
    r.filter_size = 1.5

    def area(name, loc, power, size, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, 'AREA')
        ld.energy, ld.size, ld.color = power, size, color
        lo = bpy.data.objects.new(name, ld)
        scene.collection.objects.link(lo)
        lo.location = Vector(loc) + look_target.location
        aim = lo.constraints.new('TRACK_TO')
        aim.target = look_target
    # light rig moves with the look target so every exercise gets the same lighting
    shadow_floor()
    area("Key", (2.2, -2.6, 2.2), 190, 2.4)
    area("Fill", (-2.8, -1.8, 0.4), 40, 3.0, (0.95, 0.97, 1.0))
    area("Rim", (-0.8, 3.0, 1.9), 300, 1.6)
    area("RimR", (1.9, 2.4, 0.3), 120, 1.2)


TIERS = None                    # compositor File Output node writing the muscle tier map


def tier_output():
    """Compositor: image straight through; tier_p (R) / tier_s (G) AOVs saved raw (no view transform)."""
    global TIERS
    vl = scene.view_layers[0]
    for name in ("tier_p", "tier_s", "solid"):
        a = vl.aovs.add()
        a.name, a.type = name, 'VALUE'
    ng = bpy.data.node_groups.new("AtlasComp", "CompositorNodeTree")
    scene.compositing_node_group = ng
    ng.interface.new_socket("Image", in_out='OUTPUT', socket_type='NodeSocketColor')
    rl, out = ng.nodes.new("CompositorNodeRLayers"), ng.nodes.new("NodeGroupOutput")
    ng.links.new(rl.outputs["Image"], out.inputs[0])
    comb = ng.nodes.new("CompositorNodeCombineColor")
    ng.links.new(rl.outputs["tier_p"], comb.inputs["Red"])
    ng.links.new(rl.outputs["tier_s"], comb.inputs["Green"])
    ng.links.new(rl.outputs["solid"], comb.inputs["Blue"])
    TIERS = ng.nodes.new("CompositorNodeOutputFile")
    TIERS.save_as_render = False
    TIERS.format.media_type = 'IMAGE'
    TIERS.format.file_format, TIERS.format.color_mode, TIERS.format.color_depth = 'PNG', 'RGB', '16'
    TIERS.file_output_items.new('RGBA', "tiers")
    ng.links.new(comb.outputs[0], TIERS.inputs[0])


def tier_path(raw):
    """Where composite.py looks for the tier map of a raw render: <dir>/tiers/<name>."""
    return os.path.join(os.path.dirname(raw), "tiers", os.path.basename(raw))


def collect_tiers(directory, prefix, target):
    """Rename the File Output node's <prefix><frame>.png in `directory` to `target`."""
    for f in os.listdir(directory):
        if f.startswith(prefix) and f.endswith(".png"):
            os.replace(os.path.join(directory, f), target)
            return


def shadow_floor():
    """Invisible floor that only catches shadows: grounds the feet, bench and plates (composite.py darkens the glow
    with it)."""
    bpy.ops.mesh.primitive_plane_add(size=2.2, location=(0, 0, 0))                # just round the feet: every floor pixel is path-traced
    floor = bpy.context.object
    floor.name = "ShadowFloor"
    floor.is_shadow_catcher = True
    # camera rays only: a full-frame floor that also feeds bounces made every frame 6x slower
    floor.visible_diffuse = floor.visible_glossy = floor.visible_transmission = floor.visible_volume_scatter = False
    floor.data.materials.append(material("Floor", (0.5, 0.5, 0.5)))


def frame_points(objs, frames):
    pts = []
    for fr in frames:
        scene.frame_set(fr)
        update()
        for o in objs:
            pts.append(world_coords(o))
    return np.vstack(pts)


def main_camera(equipment, fill=0.80, az_deg=35, el_deg=6, lens=65):
    """3/4 front camera, auto-framed so the figure + equipment fills `fill` of the frame height."""
    cd = bpy.data.cameras.new("Cam")
    cd.sensor_fit = 'VERTICAL'
    cd.sensor_height = 36
    cd.lens = lens
    cam = bpy.data.objects.new("Cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    pts = frame_points([body, shoes] + list(equipment), range(1, LOOP + 1, 9))
    lo3, hi3 = pts.min(0), pts.max(0)
    look_target.location = Vector(((lo3[0] + hi3[0]) / 2, (lo3[1] + hi3[1]) / 2, (lo3[2] + hi3[2]) / 2))
    az, el = math.radians(az_deg), math.radians(el_deg)
    direction = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    tanv = math.tan(math.atan(18 / lens))
    aspect = scene.render.resolution_x / scene.render.resolution_y

    def extents(dist):
        cam.location = look_target.location + direction * dist
        cam.rotation_euler = (-direction).to_track_quat('-Z', 'Y').to_euler()
        update()
        m = np.array(cam.matrix_world.inverted())
        c = pts @ m[:3, :3].T + m[:3, 3]
        ys = c[:, 1] / -c[:, 2] / tanv
        xs = c[:, 0] / -c[:, 2] / (tanv * aspect)
        return ys.min(), ys.max(), xs.min(), xs.max()

    lo, hi = 1.5, 20.0
    for _ in range(40):
        dist = (lo + hi) / 2
        y0, y1, x0, x1 = extents(dist)
        lo, hi = (dist, hi) if (y1 - y0) / 2 > fill or (x1 - x0) / 2 > 0.96 else (lo, dist)
    y0, y1, x0, x1 = extents(hi)
    # shift is a fraction of the larger (vertical) sensor dimension
    cd.shift_y = (y0 + y1) / 2 / 2
    cd.shift_x = (x0 + x1) / 2 / 2 * aspect
    print(f"CAMERA dist {hi:.2f} m, fills {(y1 - y0) / 2 * 100:.0f}% height, {(x1 - x0) / 2 * 100:.0f}% width")
    return cam


def closeup_camera(s, frame, offset, lens=85, look_offset=(0, 0, 0)):
    """Close-up of hand `s`; `offset` is camera position relative to the hand, in world space."""
    cd = bpy.data.cameras.new("HandsCam")
    cd.lens = lens
    cd.sensor_fit = 'VERTICAL'
    cam = bpy.data.objects.new("HandsCam", cd)
    scene.collection.objects.link(cam)
    scene.frame_set(frame)
    update()
    o, _ = handle_axis_world(s)
    tgt = empty("HandsLook")
    tgt.location = o + Vector(look_offset)
    cam.location = o + Vector(offset)
    cam.rotation_euler = (tgt.location - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam["frame"] = frame
    return cam


def render_still(path, frame, cam, pct=100):
    scene.camera = cam
    scene.frame_set(frame)
    scene.render.resolution_percentage = pct
    scene.render.filepath = path
    tiers = os.path.dirname(tier_path(path))
    os.makedirs(tiers, exist_ok=True)
    prefix = os.path.splitext(os.path.basename(path))[0] + "_tiers_"
    TIERS.directory, TIERS.file_name = tiers, prefix
    t = time.time()
    bpy.ops.render.render(write_still=True)
    collect_tiers(tiers, prefix, tier_path(path))
    print(f"RENDERED {os.path.basename(path)} in {time.time() - t:.1f} s")


def composite_still(src, dst):
    subprocess.run([PYTHON, "-P", os.path.join(HERE, "composite.py"), "still", src, dst], check=True)


def finish(name, cam, hands_cam, mid_frame, extra_cams=()):
    """Handle --preview / --stills / --anim for an exercise; `extra_cams` are (tag, camera) close-ups for --stills."""
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, f"{name}.blend"))
    if "--preview" in ARGS:
        scene.cycles.samples = 32
        for tag, fr, c in (("top", 1, cam), ("mid", mid_frame, cam), ("hands", hands_cam["frame"], hands_cam)):
            raw = os.path.join(OUT, f"raw_preview_{name}_{tag}.png")
            render_still(raw, fr, c, 50)
            composite_still(raw, os.path.join(OUT, f"preview_{name}_{tag}.png"))
    if "--stills" in ARGS:
        shots = [("top", 1, cam), ("mid", mid_frame, cam), ("hands", hands_cam["frame"], hands_cam)]
        for tag, fr, c in shots + [(tag, c["frame"], c) for tag, c in extra_cams]:
            raw = os.path.join(OUT, f"raw_{name}_{tag}.png")
            render_still(raw, fr, c)
            composite_still(raw, os.path.join(OUT, f"{name}_{tag}.png"))
    if "--anim" in ARGS:
        scene.camera = cam
        scene.render.resolution_percentage = 100
        scene.frame_end = int(os.environ.get("ATLAS_FRAMES", LOOP))   # benchmark: render only the first N frames
        frames = os.path.join(OUT, "frames_" + name)
        os.makedirs(frames, exist_ok=True)
        for f in os.listdir(frames):
            if f.endswith(".png"):
                os.remove(os.path.join(frames, f))
        scene.render.filepath = os.path.join(frames, "")
        TIERS.directory, TIERS.file_name = os.path.join(frames, "tiers"), ""
        t = time.time()
        bpy.ops.render.render(animation=True)
        print(f"RENDERED animation {name} ({LOOP} frames) in {time.time() - t:.0f} s")
        mp4 = os.path.join(OUT, f"{name}.mp4")
        subprocess.run([PYTHON, "-P", os.path.join(HERE, "composite.py"), "video", frames, mp4, str(FPS)], check=True)
        print(f"VIDEO {mp4} {os.path.getsize(mp4) / 1e6:.1f} MB")
