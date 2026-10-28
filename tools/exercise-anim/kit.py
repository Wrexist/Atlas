# Spec-driven exercise builder on top of atlas_rig, so 873 clips don't each need a hand-written script.
# A spec (specs/<slug>.json) gives a posture, optional whole-body key poses, an implement, and arm key poses as
# segment directions; everything is interpolated over one rep and keyed.
# blender -b human.blend -P kit.py -- <slug> [--preview] [--stills] [--anim]
import bpy, json, math, sys, os
import numpy as np
from mathutils import Vector, Matrix, Quaternion
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_rig as A

HERE = os.path.dirname(os.path.abspath(__file__))
SIDES = (("L", 1), ("R", -1))
BENCH_TOP = 0.45
PLATE_R = 0.225                 # barbell plate radius (atlas_rig.barbell)
HAND_TO_HANDLE = 0.085          # wrist joint to the handle axis along the fingers (closed grip)


# ---------------------------------------------------------------- props
def box(name, size, loc, rot_x=0.0, mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=(rot_x, 0, 0))
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    b = o.modifiers.new("bevel", 'BEVEL')
    b.width, b.segments = 0.012, 3
    o.data.materials.append(mat or A.BLACK)
    return o


def rod(name, a, b, radius, mat=None):
    """Cylinder from world point a to b."""
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius, depth=(b - a).length, location=(a + b) / 2)
    o = bpy.context.object
    o.name = name
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = (b - a).to_track_quat('Z', 'Y')
    o.data.materials.append(mat or A.STEEL)
    bpy.ops.object.shade_smooth()
    return o


def bench(seat_y0, seat_y1, back_deg=None, back_len=0.85, top=BENCH_TOP):
    """Pad from y0 to y1 (y1 behind the figure) + optional backrest hinged at y1, `back_deg` above level."""
    props = [box("BenchSeat", (0.30, seat_y1 - seat_y0, 0.07), (0, (seat_y0 + seat_y1) / 2, top - 0.035))]
    if back_deg is not None:
        a = math.radians(back_deg)
        d = Vector((0, math.cos(a), math.sin(a)))
        n = Vector((0, -math.sin(a), math.cos(a)))
        c = Vector((0, seat_y1, top)) + d * (back_len / 2) - n * 0.035
        props.append(box("BenchBack", (0.30, back_len, 0.07), c, rot_x=a))
        foot = Vector((0, seat_y1, top)) + d * back_len * 0.8
        if foot.z > 0.1:
            props.append(box("BenchStrut", (0.06, 0.06, foot.z), (0, foot.y, foot.z / 2)))
    for y in (seat_y0 + 0.08, seat_y1 - 0.04):
        props.append(box("BenchLeg", (0.06, 0.06, top - 0.07), (0, y, (top - 0.07) / 2)))
        props.append(box("BenchFoot", (0.40, 0.07, 0.04), (0, y, 0.02)))
    return props


def pullup_bar(z, half=0.7):
    props = [rod("PullBar", (-half, 0, z), (half, 0, z), A.BAR_R)]
    for sx in (1, -1):
        props.append(box("Upright", (0.06, 0.06, z + 0.1), (sx * (half + 0.03), 0, (z + 0.1) / 2)))
    return props


# ---------------------------------------------------------------- frames + poses
def torso_frame():
    """(lateral toward the figure's left, forward out of the chest, up the spine) in world space."""
    up = (A.head("spine01") - A.head("spine05")).normalized()
    lat = A.head("upperarm01.L") - A.head("upperarm01.R")
    lat = (lat - lat.dot(up) * up).normalized()
    return lat, lat.cross(up), up


WORLD_FRAME = (Vector((1, 0, 0)), Vector((0, -1, 0)), Vector((0, 0, 1)))


def tdir(v, sx, frame="torso"):
    """Direction (out, forward, up) in the torso (or world) frame -> world, mirrored for the right side."""
    lat, fwd, up = torso_frame() if frame == "torso" else WORLD_FRAME
    return (lat * (v[0] * sx) + fwd * v[1] + up * v[2]).normalized()


def slerp_dir(a, b, t):
    a, b = Vector(a).normalized(), Vector(b).normalized()
    ang = a.angle(b) if a.dot(b) < 0.99999 else 0.0
    if ang < 1e-5:
        return a.lerp(b, t).normalized()
    return ((math.sin((1 - t) * ang) * a + math.sin(t * ang) * b) / math.sin(ang)).normalized()


LINEAR = False                  # set for cycling specs (circles): constant speed through the keys


def interp(keys, t, fn):
    """Eased (or, for cycles, linear) piecewise interpolation of key poses at phase t in [0, 1]."""
    if len(keys) == 1:
        return keys[0]
    n = len(keys) - 1
    x = min(max(t, 0.0) * n, n - 1e-9)
    i = int(x)
    return fn(keys[i], keys[i + 1], (x - i) if LINEAR else A.ease(x - i))


def arm_pose(keys, t):
    return interp(keys, t, lambda a, b, u: dict({k: slerp_dir(a[k], b[k], u) for k in ("upper", "fore", "thumb")},
                                                 flex=a.get("flex", 0) + (b.get("flex", 0) - a.get("flex", 0)) * u))


def body_pose(keys, t):
    return interp(keys, t, lambda a, b, u: {k: a.get(k, 0) + (b.get(k, 0) - a.get(k, 0)) * u
                                            for k in set(a) | set(b)})


class Arms:
    """Arm key poses -> world elbow/wrist positions (exact segment lengths, so always reachable)."""

    def __init__(self, spec, ph):
        a = spec.get("arm", {})
        self.keys = a.get("keys", [{"upper": (0.08, 0, -1), "fore": (0.05, 0.1, -1), "thumb": (0, 1, 0)}])
        self.rest = a.get("rest", self.keys[0])
        self.frame = a.get("frame", "torso")
        self.elbow_out = a.get("elbow_out", (1, 0, 0))
        self.active = {s for s, _ in SIDES if a.get("sides", "both") in ("both", s)}
        self.offset_r = a.get("offset_R", 0)
        self.ph = ph

    def pose(self, fr, s):
        if s not in self.active:
            return self.rest
        t = self.ph(fr, s)
        if s == "R" and self.offset_r:          # cycles: right arm half a stride behind (running arm swing)
            t = (t + self.offset_r) % 1.0
        return arm_pose(self.keys, t)

    def target(self, fr, s, sx):
        pose = self.pose(fr, s)
        upper, fore = A.arm_lengths(s)
        shoulder = A.head("upperarm01." + s)
        U, F = tdir(pose["upper"], sx, self.frame), tdir(pose["fore"], sx, self.frame)
        elbow = shoulder + U * upper * 0.995
        wrist = elbow + F * fore * 0.995
        return elbow, wrist, F, tdir(pose["thumb"], sx, self.frame)

    def pole_dir(self, sx):
        return tdir(self.elbow_out, sx, self.frame)

    def set_poles(self, fr):
        for s, sx in SIDES:
            elbow = self.target(fr, s, sx)[0]
            bpy.data.objects["ElbowPole." + s].location = elbow + self.pole_dir(sx) * 0.5

    def key_poles(self, fr):
        for s, _ in SIDES:
            bpy.data.objects["ElbowPole." + s].keyframe_insert("location", frame=fr)


# ---------------------------------------------------------------- postures
# Each sets the feet/legs and the base root offset (drop, back, lean in rad) and returns its props.
def stand(p):
    A.plant_feet(toe_out_deg=p.get("toe_out", 8), ankles=stance(p.get("width")))
    free = p.get("free_leg")
    if free:                                    # that leg is posed by hip/knee keys instead (quad stretch, leg swings)
        A.P["lowerleg02." + free].constraints["IK"].mute = True
        for c in A.P["foot." + free].constraints:
            c.mute = True
    lean0 = math.radians(p.get("lean", 0))
    if p.get("feet_move"):
        p["_move"] = feet_mover(lean0)
    return (0, 0, lean0), []


def feet_mover(lean0):
    """Body keys that also move the feet: `air` lifts the whole body and both feet (jumps), `fx_`/`fy_`/`fz_<side>`
    offset one foot (strides, tucks, star jumps); the foot targets are keyed every frame."""
    feet = {s: bpy.data.objects["FootIK." + s] for s, _ in SIDES}
    start = {s: o.location.copy() for s, o in feet.items()}

    def move(k):
        lean = lean0 + math.radians(k.get("lean", 0))
        A.set_root(k.get("drop", 0) - k.get("air", 0), k.get("back", 0), lean)
        for s, o in feet.items():
            o.location = start[s] + Vector((k.get("fx_" + s, 0), k.get("fy_" + s, 0),
                                            k.get("air", 0) + k.get("fz_" + s, 0)))
            o.keyframe_insert("location", frame=A.scene.frame_current)
        return lean
    return move


def stance(width):
    if width is None:
        return None
    z = A.rest_head("foot.L").z
    return {s: (sx * width, A.rest_head("foot.L").y, z) for s, sx in SIDES}


def seat(p):
    """Sitting on a bench, feet under the knees; `back_deg` lies back on a backrest at that angle (0 = flat bench)."""
    hip = A.rest_head("upperleg01.L")
    thigh = (A.rest_head("lowerleg01.L") - hip).length
    drop = hip.z - (BENCH_TOP + 0.105)
    back_deg = p.get("back_deg")
    lean = -math.radians(90 - back_deg) if back_deg is not None else math.radians(p.get("lean", 0))
    width = p.get("knees_apart", 0.2)
    reach = p.get("feet_fwd", 0.98)
    if not p.get("feet_free"):
        A.plant_feet(toe_out_deg=12, ankles={s: (sx * width, hip.y - thigh * reach, A.rest_head("foot.L").z)
                                             for s, sx in SIDES})
        for s, sx in SIDES:
            bpy.data.objects["KneePole." + s].location = (sx * width * 1.3, hip.y - thigh, 1.2)
    A.set_root(drop, 0, lean)
    hip_y = A.head("upperleg01.L").y
    props = [] if p.get("no_bench") else bench(hip_y - (0.22 if back_deg is None else 0.30), hip_y + 0.16,
                                               back_deg=back_deg if back_deg is not None else p.get("backrest"))
    return (drop, 0, lean), props


def floor_supine(p):
    """Lying on the floor face up, knees bent (`knees` deg) with feet flat, or legs straight (knees 0)."""
    rest_hip = A.rest_head("upperleg01.L")
    drop = rest_hip.z - 0.11                            # spine joints ~11 cm above the floor
    A.set_root(drop, 0, -math.pi / 2)
    hip = A.head("upperleg01.L")
    knees = p.get("knees", 90)
    thigh = (A.rest_head("lowerleg01.L") - rest_hip).length
    shin = (A.rest_head("foot.L") - A.rest_head("lowerleg01.L")).length
    interior = math.radians(180 - knees)
    run = math.sqrt(thigh ** 2 + shin ** 2 - 2 * thigh * shin * math.cos(interior))
    ankle_z = A.rest_head("foot.L").z
    run = math.sqrt(max(run ** 2 - (hip.z - ankle_z) ** 2, 0.0))
    if p.get("feet_free"):
        return (drop, 0, -math.pi / 2), []
    apart, reach = p.get("feet_apart", 0.15), p.get("feet_reach", 0.99)
    A.plant_feet(toe_out_deg=6, ankles={s: (sx * apart, hip.y - run * reach, ankle_z) for s, sx in SIDES},
                 knee_up=1.0)
    out = p.get("knees_out", 0.2)
    for s, sx in SIDES:
        bpy.data.objects["KneePole." + s].location = (sx * (0.25 + out), hip.y - run / 2, 1.2)
    p["knees_point"] = {s: (sx * out, 0, 1) for s, sx in SIDES}
    if knees < 30:
        pitch_feet(-80)                         # straight legs: toes up
    return (drop, 0, -math.pi / 2), []


def pitch_feet(deg):
    """Tip both foot targets about their ankles (positive = toes down)."""
    for s, _ in SIDES:
        t = bpy.data.objects["FootIK." + s]
        t.matrix_world = Matrix.Translation(t.matrix_world.translation) @ \
            Matrix.Rotation(math.radians(deg), 4, 'X') @ t.matrix_world.to_3x3().to_4x4()


def kneel(p):
    """Kneeling upright: thighs vertical, shins and the tops of the feet on the floor."""
    hip = A.rest_head("upperleg01.L")
    thigh = (A.rest_head("lowerleg01.L") - hip).length
    shin = (A.rest_head("foot.L") - A.rest_head("lowerleg01.L")).length
    drop = hip.z - (0.075 + thigh)
    lean = math.radians(p.get("lean", 0))
    A.set_root(drop, 0, lean)
    hip = A.head("upperleg01.L")
    A.plant_feet(toe_out_deg=0, ankles={s: (sx * 0.13, hip.y + shin * 0.97, 0.09) for s, sx in SIDES})
    pitch_feet(165)
    for s, sx in SIDES:
        bpy.data.objects["KneePole." + s].location = (sx * 0.15, hip.y - 1.0, 0.0)
    p["knees_point"] = {s: (0, -1, -1) for s, _ in SIDES}
    return (drop, 0, lean), []


def support(p):
    """Held up on straight arms between dip bars at `bar_z`, knees bent so the feet clear the floor."""
    reach = sum(A.arm_lengths("L")) + 0.03
    drop = A.rest_head("upperarm01.L").z - (p.get("bar_z", 1.25) + reach * 0.97)
    knees = math.radians(p.get("knees", 75))

    def move(k):
        lean = math.radians(p.get("lean", 0) + k.get("lean", 0))
        A.set_root(drop + k.get("drop", 0), k.get("back", 0), lean)
        for s, _ in SIDES:
            A.rotate_local("lowerleg01." + s, (1, 0, 0), knees)
        return lean

    move({})
    p["_move"] = move
    return (drop, 0, math.radians(p.get("lean", 0))), []


def split(p):
    """Lunge stance: lead foot `front` m ahead, rear foot `back` m behind on its toes."""
    hip = A.rest_head("upperleg01.L")
    z = A.rest_head("foot.L").z
    lead = p.get("lead", "L")
    ankles = {}
    for s, sx in SIDES:
        ankles[s] = (sx * 0.12, hip.y - p.get("front", 0.45), z) if s == lead else \
            (sx * 0.12, hip.y + p.get("back", 0.5), z + 0.06)
    A.plant_feet(toe_out_deg=4, ankles=ankles)
    rear = "R" if lead == "L" else "L"
    t = bpy.data.objects["FootIK." + rear]
    t.matrix_world = Matrix.Translation(t.matrix_world.translation) @ Matrix.Rotation(math.radians(40), 4, 'X') @ \
        t.matrix_world.to_3x3().to_4x4()
    p["knees_point"] = {lead: (0, -1, 0), rear: (0, -0.3, -1)}
    lean = math.radians(p.get("lean", 0))
    A.set_root(0, 0, lean)
    return (0, 0, lean), []


def bridge(p):
    """Glute bridge / hip thrust: shoulders on the floor (or on a bench at `shoulders_z`), feet planted; body key
    `lift` raises the hips about the shoulders (1 = body level on a bench, 25 deg on the floor)."""
    pivot = A.D["root"].matrix_local.translation
    v = (A.rest_head("upperarm01.L") + A.rest_head("upperarm01.R")) / 2 - pivot
    v.x = 0
    sz = p.get("shoulders_z", 0.0) + 0.12
    torso = v.length
    base = math.degrees(math.asin(min((sz - 0.2) / torso, 0.95))) if sz > 0.3 else 0.0
    shoulders = Vector((0, pivot.y + torso, sz))

    def pose(beta):
        lean = math.radians(-90 + base - beta)
        root = shoulders - Matrix.Rotation(lean, 3, 'X') @ v
        return lean, root

    def move(k):
        lean, root = pose(k.get("lift", 0) * (base or 25))
        A.set_root(pivot.z - root.z, root.y - pivot.y, lean)
        return lean

    _, top = pose(p.get("top", base or 25))
    move({})
    hip_off = A.rest_head("upperleg01.L") - pivot
    ank_z = A.rest_head("foot.L").z
    A.plant_feet(toe_out_deg=6, ankles={s: (sx * 0.15, top.y + hip_off.y - p.get("feet_fwd", 0.45), ank_z)
                                        for s, sx in SIDES}, knee_up=1.0)
    for s, sx in SIDES:
        bpy.data.objects["KneePole." + s].location = (sx * 0.25, top.y - 0.3, 1.4)
    p["knees_point"] = {s: (sx * 0.15, 0, 1) for s, sx in SIDES}
    p["_move"] = move
    props = []
    if p.get("shoulders_z"):
        top_z = p["shoulders_z"]
        props.append(box("ThrustBench", (1.1, 0.36, top_z), (0, shoulders.y + 0.1, top_z / 2)))
    return (0, 0, math.radians(-90 + base)), props


def prone(p):
    """Lying face down on a pad at `top` (leg curl, chest-supported row); legs free past the knees."""
    hip = A.rest_head("upperleg01.L")
    top = p.get("top", 0.62)
    drop = hip.z - (top + 0.12)
    lean = math.radians(90 - p.get("incline", 0))
    A.set_root(drop, 0, lean)
    hip_y = A.head("upperleg01.L").y
    if p.get("no_bench"):
        props = []
    elif p.get("pad_under") == "thighs":                # hyperextension: hips over the pad's front edge
        props = bench(hip_y + 0.04, hip_y + 0.62, top=top)
    else:
        props = bench(hip_y - 0.62, hip_y + p.get("pad_past_hip", 0.3), top=top)
    return (drop, 0, lean), props


def plank(p):
    """Straight body from the toes, face down, `alpha` deg above level; body key `alpha` pivots it about the toes."""
    pivot = A.D["root"].matrix_local.translation
    length = pivot.z - A.rest_head("foot.L").z
    ankle_z = p.get("feet_z", 0.13)                     # raised on a box for decline push-ups
    lean0 = math.radians(90 - p.get("alpha", 20))
    ankle_y = pivot.y + length * math.sin(lean0)

    def move(k):
        lean = math.radians(90 - p.get("alpha", 20) - k.get("alpha", 0))
        hip = Vector((0, ankle_y - length * math.sin(lean), ankle_z + length * math.cos(lean)))
        A.set_root(pivot.z - hip.z + k.get("drop", 0), hip.y - pivot.y, lean)
        return lean

    move({})
    A.plant_feet(toe_out_deg=0, ankles={s: (sx * 0.11, ankle_y, ankle_z) for s, sx in SIDES})
    pitch_feet(p.get("toe_pitch", 62))
    p["knees_point"] = {s: (0, -math.cos(lean0), -math.sin(lean0)) for s, _ in SIDES}
    p["_move"] = move
    if p.get("feet_move"):                              # mountain climbers: knees driven toward the chest
        feet = {s: bpy.data.objects["FootIK." + s] for s, _ in SIDES}
        start = {s: o.location.copy() for s, o in feet.items()}

        def move_feet(k):
            for s, o in feet.items():
                o.location = start[s] + Vector((0, k.get("fy_" + s, 0), k.get("fz_" + s, 0)))
                o.keyframe_insert("location", frame=A.scene.frame_current)
            return move(k)
        p["_move"] = move_feet
    props = []
    if ankle_z > 0.2:
        props.append(box("FeetBox", (0.5, 0.4, ankle_z - 0.08), (0, ankle_y + 0.05, (ankle_z - 0.08) / 2)))
    return (0, 0, lean0), props


def hang(p):
    """Hanging free (feet off the floor, legs straight); the hands hold an overhead bar at `bar_z`."""
    reach = sum(A.arm_lengths("L")) + HAND_TO_HANDLE
    drop = A.rest_head("upperarm01.L").z - (p.get("bar_z", 2.35) - reach * 0.97)
    knees = math.radians(p.get("knees", 0))

    def move(k):
        A.set_root(drop + k.get("drop", 0), k.get("back", 0), math.radians(p.get("lean", 0) + k.get("lean", 0)))
        for s, _ in SIDES:
            A.rotate_local("lowerleg01." + s, (1, 0, 0), knees)
        return math.radians(p.get("lean", 0) + k.get("lean", 0))

    move({})
    p["_move"] = move
    return (drop, 0, math.radians(p.get("lean", 0))), []


POSTURES = {"stand": stand, "seat": seat, "floor_supine": floor_supine, "plank": plank, "hang": hang, "kneel": kneel,
            "support": support, "split": split, "bridge": bridge,
            "prone": prone}


# ---------------------------------------------------------------- implements
class PerHand:
    """One object per hand (dumbbell, kettlebell, cable handle): placed at the hand's key-pose wrist, wrist kept
    neutral."""

    def __init__(self, spec, arms, impl):
        self.arms, self.impl = arms, impl
        self.h = {s: A.holder(f"{impl}.{s}") for s, _ in SIDES}
        self.hands = [s for s, _ in SIDES if s in spec.get("hands", "LR")] if impl != "none" else []
        for s, h in self.h.items():
            if s not in self.hands:
                continue
            if impl == "kettlebell":
                kettlebell(h, s, rack=spec.get("kb") == "rack")
            elif impl in ("cable", "cable_handle", "handle"):
                cable_handle(h)
            elif impl == "cable_rope":
                A.cylinder(h, 0.017, 0.11, mat=A.BLACK, verts=32)
            else:
                A.dumbbell(h)
        self.radius = A.DB_R
        A.ik_arms(self.h, {s: (sx * 0.4, 0.6, 0.9) for s, sx in SIDES}, poles_in_world=True)
        for s, _ in SIDES:
            A.grip_on(s, self.h[s], (0, 0, 0), thumbward=(1, 0, 0), palm_to_handle=(0, 0, 1), radius=self.radius)
        self.cables = Cables(spec, {s: self.h[s] for s in self.hands}) if impl.startswith("cable") else None

    def place(self, fr):
        for s, sx in SIDES:
            _, wrist, F, thumb = self.arms.target(fr, s, sx)
            self.h[s].matrix_world = A.holder_for_hand(s, wrist, F, thumb)
        self.arms.set_poles(fr)
        A.update()
        for s, sx in SIDES:
            A.straighten_wrist(s, self.h[s])
            flex = self.arms.pose(fr, s).get("flex", 0)
            if flex:                                    # wrist curls: bend the hand about the thumb axis
                _, _, F, thumb = self.arms.target(fr, s, sx)
                axis = (thumb - thumb.dot(F) * F).normalized()
                w = A.head("wrist." + s)
                self.h[s].matrix_world = Matrix.Translation(w) @ Matrix.Rotation(math.radians(flex * sx), 4, axis) @ \
                    Matrix.Translation(-w) @ self.h[s].matrix_world
        A.update()

    def grip(self):
        for s in self.hands:
            A.seat_palm(s)
        for s in self.hands:
            A.wrap_hand(s)

    def key(self, fr):
        for h in self.h.values():
            A.key_holder(h, fr)
        if self.cables:
            self.cables.key(fr)

    def meshes(self):
        return [o for h in self.h.values() for o in h.children if o.type == 'MESH'] + \
               (self.cables.meshes() if self.cables else [])


def kettlebell(h, s, rack=False):
    """Handle along the holder's X axis; the bell hangs beyond the fingers, or (`rack`) rests on the back of the
    wrist as in a press or front rack."""
    A.cylinder(h, A.DB_R, 0.13, mat=A.STEEL, verts=48)
    F = A.frame_from(s, (1, 0, 0), (0, 0, 1))
    f, p = F.col[0], F.col[2]
    d = (-p * 0.8 - f * 0.6).normalized() if rack else f
    reach = 0.15 if rack else 0.16
    for sx in (1, -1):
        a, b = Vector((sx * 0.065, 0, 0)), d * (reach - 0.06) + Vector((sx * 0.045, 0, 0))
        post = A.cylinder(h, 0.015, (b - a).length, mat=A.PLATE, verts=32)
        post.matrix_basis = Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat('Z', 'Y').to_matrix().to_4x4()
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.1, segments=48, ring_count=24, location=(0, 0, 0))
    bell = bpy.context.object
    bell.data.materials.append(A.PLATE)
    bpy.ops.object.shade_smooth()
    bell.parent = h
    bell.matrix_parent_inverse = Matrix.Identity(4)
    bell.location = d * reach


def cable_handle(h):
    A.cylinder(h, A.DB_R, 0.12, mat=A.PLATE, verts=48)


class Ball(PerHand):
    """A medicine ball held between both palms: the hands follow their key poses and the ball sits between them."""
    R = 0.12

    def __init__(self, spec, arms, impl):
        super().__init__(spec, arms, "none")
        self.ball = A.holder("ball")
        bpy.ops.mesh.primitive_uv_sphere_add(radius=self.R, segments=48, ring_count=24, location=(0, 0, 0))
        o = bpy.context.object
        o.data.materials.append(A.PLATE)
        bpy.ops.object.shade_smooth()
        o.parent = self.ball
        o.matrix_parent_inverse = Matrix.Identity(4)

    def place(self, fr):
        super().place(fr)
        ends = [self.arms.target(fr, s, sx) for s, sx in SIDES]          # (elbow, wrist, forearm dir, thumb)
        palms = [w + F * 0.05 for _, w, F, _ in ends]
        self.ball.location = (palms[0] + palms[1]) / 2

    def key(self, fr):
        super().key(fr)
        A.key_holder(self.ball, fr)

    def meshes(self):
        return super().meshes() + list(self.ball.children)


class Cables:
    """A cable from a pulley (`cable.anchor`, torso-frame offset from the shoulders at frame 1) to each handle."""

    def __init__(self, spec, ends):
        c = spec.get("cable", {})
        self.ends = ends
        self.lines = {}
        lat, fwd, up = torso_frame()
        mid = (A.head("upperarm01.L") + A.head("upperarm01.R")) / 2
        self.anchor = {}
        for s, sx in SIDES:
            if s not in ends:
                continue
            off = c.get("anchor", (0, 1.2, -1.2))
            a = mid + lat * off[0] * sx + fwd * off[1] + up * off[2]
            a.z = max(a.z, 0.12)
            self.anchor[s] = a
            box("Pulley." + s, (0.09, 0.09, 0.09), a)
            self.lines[s] = rod("Cable." + s, a - Vector((0, 0, 0.5)), a + Vector((0, 0, 0.5)), 0.003)
        self.props = [bpy.data.objects["Pulley." + s] for s in self.anchor]

    def key(self, fr):
        for s, line in self.lines.items():
            b = self.ends[s].matrix_world.translation
            a = self.anchor[s]
            line.location = (a + b) / 2
            line.rotation_quaternion = (b - a).to_track_quat('Z', 'Y')
            line.scale = (1, 1, (b - a).length)
            line.keyframe_insert("location", frame=fr)
            line.keyframe_insert("rotation_quaternion", frame=fr)
            line.keyframe_insert("scale", frame=fr)

    def meshes(self):
        return list(self.lines.values()) + self.props


def ezbar(h):
    A.cylinder(h, A.BAR_R, 0.95, mat=A.STEEL, verts=48)
    for sx in (1, -1):
        A.cylinder(h, 0.03, 0.03, x=sx * 0.49, mat=A.STEEL)
        A.cylinder(h, 0.025, 0.13, x=sx * 0.56, mat=A.STEEL)
        A.cylinder(h, 0.17, 0.035, x=sx * 0.53, mat=A.PLATE, verts=96, bevel=0.006)


def short_bar(h):
    A.cylinder(h, A.BAR_R, 0.55, mat=A.STEEL, verts=48)


class Bar:
    """Both hands on one bar: centred between the hands' key-pose positions, grip width fixed, rolled with the
    forearms and then frame by frame (smoothed) to keep the wrists straight."""

    def __init__(self, spec, arms, impl):
        self.arms = arms
        self.bar = A.holder("Bar")
        {"barbell": A.barbell, "ezbar": ezbar, "cable_bar": short_bar}[impl](self.bar)
        a = spec.get("arm", {})
        self.gx = a.get("grip", 0.22)
        self.palm = a.get("palm", (0, -1, 0))
        self.tsign = 1 if arms.keys[0]["thumb"][0] > 0 else -1     # thumbs out (underhand) or in (overhand)
        A.ik_arms(self.bar, {s: (sx * 0.4, 0.6, 0.9) for s, sx in SIDES}, poles_in_world=True)
        self.f1 = None
        self.rolls = None
        self.cables = Cables(spec, {"L": self.bar}) if impl == "cable_bar" else None

    def fore_dir(self, fr):
        return sum((self.arms.target(fr, s, sx)[2] for s, sx in SIDES), Vector()).normalized()

    def place(self, fr):
        lat = torso_frame()[0]
        if self.f1 is None:
            self.f1 = self.fore_dir(1)
        a, b = self.f1 - self.f1.dot(lat) * lat, self.fore_dir(fr)
        b = b - b.dot(lat) * lat
        ang = a.angle(b) if a.length > 1e-6 and b.length > 1e-6 else 0.0
        if a.cross(b).dot(lat) < 0:
            ang = -ang
        lat, fwd, up = torso_frame()
        m = (Matrix((lat, -fwd, up)).transposed() @ Matrix.Rotation(ang, 3, 'X')).to_4x4()
        pts = [self.arms.target(fr, s, sx) for s, sx in SIDES]
        m.translation = sum((w + F * HAND_TO_HANDLE for _, w, F, _ in pts), Vector()) / 2
        self.bar.matrix_world = m
        self.arms.set_poles(fr)
        A.update()
        if self.rolls is not None:
            A.roll_holder(self.bar, self.rolls[(fr - 1) % A.LOOP])

    def grip(self):
        for s, sx in SIDES:
            A.grip_on(s, self.bar, (sx * self.gx, 0, 0), thumbward=(sx * self.tsign, 0, 0), palm_to_handle=self.palm)
        A.update()

    def finish_grip(self):
        for s, sx in SIDES:
            A.grip_neutral(s, self.bar, (sx * self.gx, 0, 0), thumbward=(sx * self.tsign, 0, 0),
                           palm_guess=self.palm)
        for s, _ in SIDES:
            A.seat_palm(s)
        for s, _ in SIDES:
            A.wrap_hand(s)

    def solve_rolls(self, body):
        rolls = []
        for fr in range(1, A.LOOP + 1):
            A.scene.frame_set(fr)
            body(fr)
            self.place(fr)
            rolls.append(A.roll_neutral(self.bar, span=25))
        self.rolls = A.smooth(np.array(rolls, float), 3.0, loop=True)

    def key(self, fr):
        A.key_holder(self.bar, fr)
        if self.cables:
            self.cables.key(fr)

    def meshes(self):
        return [o for o in self.bar.children if o.type == 'MESH'] + (self.cables.meshes() if self.cables else [])


class BackBar:
    """Barbell resting on the upper back (back squat, good morning, lunge): rides with the torso, hands hold it."""

    def __init__(self, spec, arms, impl):
        self.arms = arms
        a = spec.get("arm", {})
        self.gx = a.get("grip", 0.42)
        self.at = a.get("bar_at", "back")
        default = (0, 0.17, -0.02) if self.at == "hips" else (0, -0.085, 0.035)
        self.palm = a.get("palm", (0, 1, 0) if self.at == "hips" else (0, -1, 0.3))
        self.on = a.get("bar_on", default)                  # bar centre from mid-shoulders/hips: (_, forward, up)
        self.bar = A.holder("Bar")
        A.barbell(self.bar)
        self.cables = None
        self.place(1)
        A.ik_arms(self.bar, {s: (sx * 0.4, 0.6, 0.9) for s, sx in SIDES}, poles_in_world=True)
        for s, sx in SIDES:
            A.grip_on(s, self.bar, (sx * self.gx, 0, 0), thumbward=(-sx, 0, 0), palm_to_handle=self.palm)

    def place(self, fr):
        lat, fwd, up = torso_frame()
        m = Matrix((lat, -fwd, up)).transposed().to_4x4()
        joint = "upperleg01" if self.at == "hips" else "upperarm01"
        mid = (A.head(joint + ".L") + A.head(joint + ".R")) / 2
        m.translation = mid + fwd * self.on[1] + up * self.on[2]
        self.bar.matrix_world = m
        if "ElbowPole.L" in bpy.data.objects:
            for s, sx in SIDES:
                hand = A.hand_targets[s].matrix_world.translation
                shoulder = A.head("upperarm01." + s)
                bpy.data.objects["ElbowPole." + s].location = (shoulder + hand) / 2 + self.arms.pole_dir(sx) * 0.6
        A.update()

    def grip(self):
        for s, sx in SIDES:
            A.grip_neutral(s, self.bar, (sx * self.gx, 0, 0), thumbward=(-sx, 0, 0), palm_guess=self.palm)
        for s, _ in SIDES:
            A.seat_palm(s)
        for s, _ in SIDES:
            A.wrap_hand(s)

    def key(self, fr):
        A.key_holder(self.bar, fr)

    def meshes(self):
        return [o for o in self.bar.children if o.type == 'MESH']


class Anchored:
    """Hands fixed in the world (floor, pull-up bar): set from the arm key pose at frame 1, then the body moves and
    the arms follow by IK."""

    def __init__(self, spec, arms, impl):
        self.arms, self.impl = arms, impl
        a = spec.get("arm", {})
        pts = {s: arms.target(1, s, sx) for s, sx in SIDES}
        self.cables = None
        self.props = []
        if impl == "dip_bars":
            self.h = {}
            for s, sx in SIDES:
                w = pts[s][1]
                h = A.holder("Dip." + s)
                h.location = (w.x + sx * 0.02, w.y, w.z - 0.03)
                h.rotation_quaternion = Vector((0, 1, 0)).to_track_quat('X', 'Z')
                A.cylinder(h, 0.02, 1.0, mat=A.STEEL, verts=48)
                self.props.append(box("DipPost", (0.05, 0.05, h.location.z), (h.location.x, w.y + 0.4,
                                                                                h.location.z / 2)))
                self.h[s] = h
            A.ik_arms(self.h, {s: (sx * 0.5, 0, 1) for s, sx in SIDES}, poles_in_world=True)
            for s, sx in SIDES:
                A.grip_on(s, self.h[s], (0, 0, 0), thumbward=(-1, 0, 0), palm_to_handle=(0, 0, -1), radius=0.02)
        elif impl == "floor":
            self.h = {}
            for s, sx in SIDES:
                w = pts[s][1]
                h = A.holder("Hand." + s)
                h.location = (w.x, w.y - 0.05, a.get("hand_z", 0.0))
                self.h[s] = h
            A.ik_arms(self.h, {s: (sx * 0.5, 0, 1) for s, sx in SIDES}, poles_in_world=True)
            for s, sx in SIDES:
                A.grip_on(s, self.h[s], (0, 0, 0), thumbward=(-sx, 0, 0), palm_to_handle=(0, 0, -1), slide=0.0,
                          radius=0.0)
            if a.get("hand_box"):
                z, y = a["hand_z"], sum(h.location.y for h in self.h.values()) / 2
                self.props.append(box("HandBox", (0.75, 0.35, z), (0, y, z / 2)))
        else:
            bar = A.holder("Bar")
            centre = sum((w + F * HAND_TO_HANDLE for _, w, F, _ in pts.values()), Vector()) / 2
            bar.location = centre
            A.cylinder(bar, A.BAR_R, 1.44, mat=A.STEEL, verts=48)
            for sx in (1, -1):                              # bar runs into the posts, which stop just above it
                self.props.append(box("Upright", (0.07, 0.07, centre.z + 0.05),
                                      (sx * 0.69, centre.y, (centre.z + 0.05) / 2)))
            self.h = {s: bar for s, _ in SIDES}
            A.ik_arms(bar, {s: (sx * 0.5, 0, 1) for s, sx in SIDES}, poles_in_world=True)
            self.gx = a.get("grip", 0.3)
            self.tsign = 1 if arms.keys[0]["thumb"][0] > 0 else -1
            self.palm = a.get("palm", (0, -1, 0))
            for s, sx in SIDES:
                A.grip_on(s, bar, (sx * self.gx, 0, 0), thumbward=(sx * self.tsign, 0, 0), palm_to_handle=self.palm)

    def place(self, fr):
        for s, sx in SIDES:
            shoulder = A.head("upperarm01." + s)
            hand = A.hand_targets[s].matrix_world.translation
            bpy.data.objects["ElbowPole." + s].location = (shoulder + hand) / 2 + self.arms.pole_dir(sx) * 0.6
        A.update()

    def grip(self):
        if self.impl == "floor":
            return
        if self.impl == "dip_bars":
            for s, _ in SIDES:
                A.seat_palm(s)
                A.wrap_hand(s)
            return
        for s, sx in SIDES:
            A.grip_neutral(s, self.h[s], (sx * self.gx, 0, 0), thumbward=(sx * self.tsign, 0, 0),
                           palm_guess=self.palm)
        for s, _ in SIDES:
            A.seat_palm(s)
        for s, _ in SIDES:
            A.wrap_hand(s)

    def key(self, fr):
        pass

    def meshes(self):
        return [o for h in set(self.h.values()) for o in h.children if o.type == 'MESH'] + self.props


def posed_dir(bone, rest_dir):
    """World direction that `rest_dir` (world, in the rest pose) points along after bone `bone` is posed."""
    m = A.rig.matrix_world.to_3x3() @ A.P[bone].matrix.to_3x3() @ A.D[bone].matrix_local.to_3x3().inverted()
    return (m @ Vector(rest_dir)).normalized()


def attach(obj, bone):
    """Parent `obj` to `bone`, keeping its current world placement."""
    pb = A.P[bone]
    m = A.rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0))
    world = obj.matrix_world.copy()
    obj.parent, obj.parent_type, obj.parent_bone = A.rig, 'BONE', bone
    obj.matrix_parent_inverse = m.inverted()
    obj.matrix_basis = world


def leg_pad(side_of_shin):
    """Roller pad across both shins just above the ankles, in front (leg extension) or behind (leg curl); it
    rides with the left shin, so only for symmetric leg moves."""
    mid = (A.head("foot.L") + A.head("foot.R")) / 2
    along = posed_dir("lowerleg01.L", (0, 0, 1))
    front = posed_dir("lowerleg01.L", (0, -1, 0)) * (1 if side_of_shin == "front" else -1)
    c = mid + along * 0.07 + front * 0.085
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.05, depth=0.42, location=c, rotation=(0, math.pi / 2, 0))
    pad = bpy.context.object
    pad.name = "LegPad"
    pad.data.materials.append(A.BLACK)
    bpy.ops.object.shade_smooth()
    A.update()
    attach(pad, "lowerleg01.L")
    return pad


def arm_pad(arms):
    """Preacher pad under both upper arms at their frame-1 key pose."""
    pts = [arms.target(1, s, sx) for s, sx in SIDES]
    shoulders = [A.head("upperarm01." + s) for s, _ in SIDES]
    elbow = (pts[0][0] + pts[1][0]) / 2
    shoulder = (shoulders[0] + shoulders[1]) / 2
    along = (elbow - shoulder)
    along.x = 0
    along.normalize()
    normal = Vector((0, along.z, -along.y))             # perpendicular in the sagittal plane, pointing back/up
    if normal.z < 0:
        normal = -normal
    centre = elbow - along * 0.12 - normal * 0.075
    tilt = math.atan2(along.z, -along.y)                # pad's long axis from level toward the figure's front
    pad = box("PreacherPad", (0.55, 0.34, 0.07), centre, rot_x=-tilt)
    foot = centre - normal * 0.05
    post = box("PreacherPost", (0.07, 0.07, foot.z), (0, foot.y, foot.z / 2))
    base = box("PreacherBase", (0.45, 0.08, 0.04), (0, foot.y, 0.02))
    return [pad, post, base]


def bench_dip(p):
    """Hands on a bench behind the hips, legs straight out in front, heels on the floor."""
    hip = A.rest_head("upperleg01.L")
    top = p.get("bench_top", 0.45)
    drop = hip.z - p.get("hip_z", 0.55)
    A.set_root(drop, p.get("back", 0.0), math.radians(p.get("lean", 5)))
    hip = A.head("upperleg01.L")
    leg = A.rest_head("upperleg01.L").z - A.rest_head("foot.L").z
    run = math.sqrt(max((leg * 0.97) ** 2 - (hip.z - 0.09) ** 2, 0.01))
    A.plant_feet(toe_out_deg=6, ankles={s: (sx * 0.13, hip.y - run, 0.09) for s, sx in SIDES})
    pitch_feet(-35)
    p["knees_point"] = {s: (0, 0, 1) for s, _ in SIDES}
    return (drop, p.get("back", 0.0), math.radians(p.get("lean", 5))), [
        box("DipBench", (0.9, 0.36, top), (0, hip.y + 0.32, top / 2))]


POSTURES["bench_dip"] = bench_dip


def leg_press(p):
    """Reclined in a leg press, feet on a sled plate `sled_deg` above level; body key `press` (0..1) pushes the
    feet and plate `travel` m up the sled (knees `bottom` m from full reach at 0)."""
    hip = A.rest_head("upperleg01.L")
    drop = hip.z - (BENCH_TOP + 0.105)
    back_deg = p.get("back_deg", 40)
    lean = -math.radians(90 - back_deg)
    A.set_root(drop, 0, lean)
    hip = A.head("upperleg01.L")
    leg = (A.rest_head("lowerleg01.L") - A.rest_head("upperleg01.L")).length + \
        (A.rest_head("foot.L") - A.rest_head("lowerleg01.L")).length
    a = math.radians(p.get("sled_deg", 40))
    d = Vector((0, -math.cos(a), math.sin(a)))
    travel = p.get("travel", 0.32)
    reach = leg * 0.97 - travel
    width = p.get("width", 0.15)
    base = {s: Vector((sx * width, hip.y, hip.z)) + d * reach for s, sx in SIDES}
    A.plant_feet(toe_out_deg=10, ankles={s: tuple(v) for s, v in base.items()}, knee_up=1.0)
    pitch_feet(p.get("foot_pitch", -130))
    for s, sx in SIDES:
        bpy.data.objects["KneePole." + s].location = (sx * 0.35, hip.y - 0.3, hip.z + 1.2)
    p["knees_point"] = {s: (sx * 0.2, 0, 1) for s, sx in SIDES}
    plate_c = (base["L"] + base["R"]) / 2 + d * 0.11
    plate = box("SledPlate", (0.62, 0.48, 0.04), plate_c, rot_x=math.pi / 2 - a)
    targets = [bpy.data.objects["FootIK." + s] for s, _ in SIDES] + [plate]
    starts = [o.location.copy() for o in targets]

    def move(k):
        for o, v in zip(targets, starts):
            o.location = v + d * travel * k.get("press", 0)
            o.keyframe_insert("location", frame=A.scene.frame_current)
        return lean

    p["_move"] = move
    hip_y = A.head("upperleg01.L").y
    under = Vector((0, -math.sin(a), -math.cos(a))) * 0.07     # rails just behind the plate
    rails = [rod("SledRail", plate_c + under + Vector((x, 0, 0)) - d * 0.15,
                 plate_c + under + Vector((x, 0, 0)) + d * (travel + 0.25), 0.02) for x in (-0.2, 0.2)]
    low = plate_c + under - d * 0.15
    post = box("SledPost", (0.5, 0.08, low.z), (0, low.y, low.z / 2))
    props = [plate, post] + rails + bench(hip_y - 0.30, hip_y + 0.16, back_deg=back_deg)
    return (drop, 0, lean), props


POSTURES["leg_press"] = leg_press


SPINE = ["spine04", "spine03", "spine02", "spine01"]


def spine_bend(bone, curl_deg, twist_deg, side_deg=0.0):
    """Flex (forward), twist (toward the figure's left) and side-bend (toward the figure's left) one spine bone, deg."""
    rest = A.D[bone].matrix_local.to_3x3().inverted()
    q = Quaternion((rest @ Vector((1, 0, 0))).normalized(), math.radians(curl_deg)) @ \
        Quaternion((rest @ Vector((0, 0, 1))).normalized(), math.radians(twist_deg)) @ \
        Quaternion((rest @ Vector((0, 1, 0))).normalized(), math.radians(-side_deg))
    A.P[bone].rotation_quaternion = q


class Heels:
    """Raise the heels (deg, positive = up) about the balls of the feet, moving the foot IK targets."""

    def __init__(self):
        self.base, self.ball = {}, {}
        for s, _ in SIDES:
            t = bpy.data.objects["FootIK." + s]
            self.base[s] = t.matrix_world.copy()
            local = A.D["foot." + s].matrix_local.inverted() @ A.rest_head("toe1-1." + s)
            self.ball[s] = t.matrix_world @ local

    def set(self, deg):
        for s, _ in SIDES:
            b = self.ball[s]
            bpy.data.objects["FootIK." + s].matrix_world = Matrix.Translation(b) @ \
                Matrix.Rotation(math.radians(deg), 4, 'X') @ Matrix.Translation(-b) @ self.base[s]

    def key(self, fr):
        for s, _ in SIDES:
            t = bpy.data.objects["FootIK." + s]
            t.keyframe_insert("location", frame=fr)
            t.keyframe_insert("rotation_quaternion" if t.rotation_mode == 'QUATERNION' else "rotation_euler", frame=fr)


# ---------------------------------------------------------------- build
def load(slug):
    path = os.path.join(HERE, "specs", slug + ".json")
    if not os.path.exists(path):
        path = os.path.join(HERE, "specs", "gen", slug + ".json")
    with open(path) as f:
        spec = json.load(f)
    spec.setdefault("slug", slug)
    return spec


def phases(spec):
    """Per-frame phase per side: one rep (0 -> 1 -> 0), or one rep per arm in turn when `alternate`."""
    bottom, hold = spec.get("bottom", 40), spec.get("hold", 4)
    if spec.get("cycle"):                       # keys run once round per loop (first key repeated last)
        global LINEAR
        LINEAR = True
        return lambda fr, s: ((fr - 1) % A.LOOP) / A.LOOP
    if spec.get("alternate"):
        half = A.LOOP // 2

        def ph(fr, s):
            local = (fr - 1) % A.LOOP
            if (local < half) != (s == "L"):
                return 0.0
            return A.rep_phase(1 + int((local % half) * A.LOOP / half), bottom=bottom, hold=hold)
        return ph
    return lambda fr, s: A.rep_phase(fr, bottom=bottom, hold=hold)


def build(spec):
    A.setup()
    A.train(primary=spec["primary"], secondary=spec.get("secondary", []))
    (d0, b0, l0), props = POSTURES[spec["posture"]["type"]](spec["posture"])
    ph = phases(spec)
    body_keys = spec.get("body", {}).get("keys")
    head_level = spec.get("body", {}).get("head_level", 0.6)

    move = spec["posture"].get("_move")
    keyed = ["root", "neck01"]
    if body_keys:
        names = set().union(*body_keys)
        if names & {"curl", "twist", "side"}:
            keyed += SPINE
        if "shrug" in names:
            keyed += ["clavicle.L", "clavicle.R"]
        if any(n.startswith(("hip", "knee")) for n in names):
            keyed += [f"{b}.{s}" for b in ("upperleg01", "lowerleg01") for s, _ in SIDES]
    heel = Heels() if body_keys and any("heel" in k for k in body_keys) else None

    def body(fr):
        if not body_keys:
            return
        k = body_pose(body_keys, ph(fr, "L"))
        if move:
            lean = move(k)
        else:
            lean = l0 + math.radians(k.get("lean", 0))
            A.set_root(d0 + k.get("drop", 0), b0 + k.get("back", 0), lean)
        nod = -head_level * (lean - l0) - math.radians(k.get("curl", 0)) * 0.3 + math.radians(k.get("nod", 0))
        if "tilt" in k or "turn" in k:
            spine_bend("neck01", math.degrees(nod), k.get("turn", 0), k.get("tilt", 0))
        else:
            A.rotate_local("neck01", (1, 0, 0), nod)
        if {"curl", "twist", "side"} & set(k):
            for b in SPINE:
                spine_bend(b, k.get("curl", 0) / len(SPINE), k.get("twist", 0) / len(SPINE),
                           k.get("side", 0) / len(SPINE))
        for s, _ in SIDES:
            if f"hip_{s}" in k or "hip" in k:
                A.rotate_local("upperleg01." + s, (1, 0, 0), -math.radians(k.get(f"hip_{s}", k.get("hip", 0))))
            if f"knee_{s}" in k or "knee" in k:
                A.rotate_local("lowerleg01." + s, (1, 0, 0), math.radians(k.get(f"knee_{s}", k.get("knee", 0))))
        if "shrug" in k:
            for s, sx in SIDES:
                A.rotate_local("clavicle." + s, (0, 1, 0), -sx * math.radians(k["shrug"]))
        if heel:
            heel.set(k.get("heel", 0))
        A.update()

    def key_body(fr):
        A.key_bones(keyed, fr)
        if heel:
            heel.key(fr)

    body(1)
    A.update()
    if spec.get("pad"):
        props.append(leg_pad(spec["pad"]))
    for b in spec.get("boxes", []):
        props.append(box("Box", b["size"], b["at"], rot_x=math.radians(b.get("rot_x", 0))))
    impl = spec.get("implement", "dumbbell")
    arms = Arms(spec, ph)
    if impl == "barbell_back":
        gear = BackBar(spec, arms, impl)
    elif impl in ("floor", "pullup_bar", "dip_bars"):
        gear = Anchored(spec, arms, impl)
        props += gear.props
    elif impl in ("barbell", "ezbar", "cable_bar"):
        gear = Bar(spec, arms, impl)
    elif impl == "ball":
        gear = Ball(spec, arms, impl)
    else:
        gear = PerHand(spec, arms, impl)
    props += gear.cables.props if gear.cables else []
    if spec.get("arm", {}).get("pad"):
        props += arm_pad(arms)

    gear.place(1)
    if spec.get("bar_floor") and body_keys:          # first key starts with the plates on the floor
        body_keys[0]["drop"] = body_keys[0].get("drop", 0) + gear.bar.matrix_world.translation.z - PLATE_R
        body(1)
        gear.place(1)
    gear.grip() if isinstance(gear, Bar) else None
    A.solve_pole_angles({s: arms.pole_dir(sx) for s, sx in SIDES}, spec["posture"].get("knees_point"))
    gear.place(1)
    if isinstance(gear, Bar):
        gear.finish_grip()
        gear.solve_rolls(body)
    else:
        gear.grip()
    for fr in range(1, A.LOOP + 2):
        A.scene.frame_set(fr)
        body(fr)
        gear.place(fr)
        gear.key(fr)
        arms.key_poles(fr)
        if body_keys:
            key_body(fr)

    A.report([1, 23, 45, 68])
    A.setup_render()
    cam_spec = spec.get("camera", {})
    cam = A.main_camera(gear.meshes() + props, az_deg=cam_spec.get("az", 35), el_deg=cam_spec.get("el", 6))
    hands = A.closeup_camera("L", 1, offset=(0.14, -0.45, 0.12), lens=70)
    A.finish(spec["slug"], cam, hands, mid_frame=spec.get("bottom", 40) + 2)


if __name__ == "__main__":
    build(load(A.ARGS[0]))
