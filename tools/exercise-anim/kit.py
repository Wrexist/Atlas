# Spec-driven exercise builder on top of atlas_rig, so 873 clips don't each need a hand-written script.
# A spec (specs/<slug>.json) gives a posture, optional whole-body key poses, an implement, and arm key poses as
# segment directions; everything is interpolated over one rep and keyed.
# blender -b human.blend -P kit.py -- <slug> [--preview] [--stills] [--anim]
import bpy, json, math, sys, os
import numpy as np
from mathutils import Vector, Matrix, Quaternion
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_rig as A
import equip as E

HERE = os.path.dirname(os.path.abspath(__file__))
SIDES = (("L", 1), ("R", -1))
BENCH_TOP = 0.45
PLATE_R = 0.225                 # barbell plate radius (atlas_rig.barbell)
HAND_TO_HANDLE = 0.085          # wrist joint to the handle axis along the fingers (closed grip)


# ---------------------------------------------------------------- props
PADDED = ("Pad", "Bench", "Seat")                        # upholstered: soft rounded foam
SOFT_BOX = ("Box", "Step", "Platform", "Block")         # plyo boxes, blocks, platforms: firm foam, rounded edges
STEELWORK = ("Post", "Strut", "Foot", "Leg", "Beam", "Rail", "Base", "Upright", "Skid")


def box(name, size, loc, rot_x=0.0, mat=None):
    """A prop block, finished by role: pads upholstered, plyo boxes in firm foam, everything else formed steel."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=(rot_x, 0, 0))
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if mat is not None:
        return E._finish(o, mat, 0.012, 3)
    if any(name.endswith(w) for w in STEELWORK):
        return E._finish(o, E.frame_mat(), min(size) * 0.28, 4)
    if any(w in name for w in PADDED):
        return E._finish(o, E.pad_mat(), min(size) * 0.42, 6)
    if any(w in name for w in SOFT_BOX):
        return E._finish(o, E.pad_mat(), min(0.03, min(size) * 0.3), 5)
    return E._finish(o, E.frame_mat(), min(size) * 0.28, 4)


def rod(name, a, b, radius, mat=None):
    """Cylinder from world point a to b."""
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius, depth=(b - a).length, location=(a + b) / 2)
    o = bpy.context.object
    o.name = name
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = (b - a).to_track_quat('Z', 'Y')
    o.data.materials.append(mat or (E.metal_mat() if radius < 0.03 else E.frame_mat()))
    bpy.ops.object.shade_smooth()
    return o


def bench(seat_y0, seat_y1, back_deg=None, back_len=0.85, top=BENCH_TOP, legs=True):
    """Upholstered pad from y0 to y1 (y1 behind the figure) + optional backrest hinged at y1, `back_deg` above level,
    on a commercial bench frame: a spine tube under the pad, two uprights and floor feet. `legs` False leaves
    only the pads (a machine's own frame carries them)."""
    T = 0.075
    seat = E.cushion("BenchSeat", (0.30, seat_y1 - seat_y0, T), (0, (seat_y0 + seat_y1) / 2, top - T / 2))
    props = [seat]
    back = None
    if back_deg is not None:
        a = math.radians(back_deg)
        d = Vector((0, math.cos(a), math.sin(a)))
        n = Vector((0, -math.sin(a), math.cos(a)))
        c = Vector((0, seat_y1, top)) + d * (back_len / 2) - n * (T / 2)
        back = E.cushion("BenchBack", (0.30, back_len, T), c, rot_x=a)
        props.append(back)
    if not legs:
        return props
    z = top - T - 0.03
    props.append(E.tube("BenchSpine", (0, seat_y0 + min(0.18, (seat_y1 - seat_y0) * 0.3), z), (0, seat_y1 - 0.02, z),
                        0.09, 0.05))
    front_leg = seat_y0 + min(0.22, (seat_y1 - seat_y0) * 0.4)    # set back under the pad, clear of the shins
    for y in (front_leg, seat_y1 - 0.06):
        props.append(E.tube("BenchLeg", (0, y, 0.07), (0, y, z), 0.07, 0.07))
        props += E.foot("BenchFoot", (0, y, 0), 0.46)
    if back is not None:
        a = math.radians(back_deg)
        d = Vector((0, math.cos(a), math.sin(a)))
        n = Vector((0, -math.sin(a), math.cos(a)))
        under = Vector((0, seat_y1, top)) + d * back_len * 0.55 - n * (T + 0.03)
        if under.z > z + 0.1:
            props.append(E.tube("BenchStrut", (0, seat_y1 - 0.06, z), under, 0.06, 0.05))
            props.append(E.tube("BenchRail", Vector((0, seat_y1, top - T - 0.03)) + d * 0.05, under, 0.07, 0.04))
    return props


def pullup_bar(z, half=0.7):
    props = [rod("PullBar", (-half, 0, z), (half, 0, z), A.BAR_R)]
    for sx in (1, -1):
        props.append(box("Upright", (0.06, 0.06, z + 0.1), (sx * (half + 0.03), 0, (z + 0.1) / 2)))
    return props


def rubber():
    m = bpy.data.materials.get("BandRubber")         # "Rubber" is the shoe soles' material in human.blend
    if m is None:
        m = A.material("BandRubber", (0.03, 0.03, 0.033), rough=0.85)
        A.solid_aov(m)                              # equipment, not body: the composite keeps it dark
    return m


# ---------------------------------------------------------------- frames + poses
def torso_frame():
    """(lateral toward the figure's left, forward out of the chest, up the spine) in world space."""
    up = (A.head("spine01") - A.head("spine05")).normalized()
    lat = A.head("clavicle.L") - A.head("clavicle.R")     # clavicle roots ride the chest, not the moving arms
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
    """Standing; `floor_z` stands on a platform that high (deficit lifts)."""
    h = p.get("floor_z", 0.0)
    ankles = stance(p.get("width", 0.1 if h else None))
    if h:
        ankles = {s: (x, y, z + h) for s, (x, y, z) in ankles.items()}
    A.plant_feet(toe_out_deg=p.get("toe_out", 8), ankles=ankles)
    free = p.get("free_leg")
    if free:                                    # that leg is posed by hip/knee keys instead (quad stretch, leg swings)
        A.P["lowerleg02." + free].constraints["IK"].mute = True
        for c in A.P["foot." + free].constraints:
            c.mute = True
    lean0 = math.radians(p.get("lean", 0))
    # knees track the toes; without this the leg IK kept its default pole angle and squats caved the knees sideways
    p.setdefault("knees_point", {s: (sx * 0.3, -1, 0) for s, sx in SIDES})
    p["_crouch_for_poles"] = True
    if p.get("feet_move"):
        p["_move"] = feet_mover(lean0, -h)
    props = [box("Platform", (0.9, 0.6, h), (0, -0.09, h / 2))] if h else []
    return (-h, 0, lean0), props


def feet_mover(lean0, drop0=0.0):
    """Body keys that also move the feet: `air` lifts the whole body and both feet (jumps), `fx_`/`fy_`/`fz_<side>`
    offset one foot (strides, tucks, star jumps); the foot targets are keyed every frame."""
    feet = {s: bpy.data.objects["FootIK." + s] for s, _ in SIDES}
    start = {s: o.location.copy() for s, o in feet.items()}

    def move(k):
        lean = lean0 + math.radians(k.get("lean", 0))
        A.set_root(drop0 + k.get("drop", 0) - k.get("air", 0), k.get("back", 0), lean)
        if k.get("side"):                       # sideways travel (lateral jumps): toward the figure's left
            A.P["root"].matrix = Matrix.Translation((k["side"], 0, 0)) @ A.P["root"].matrix
            A.update()
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
    drop = hip.z - (BENCH_TOP + 0.12)                   # hip joint over the cushion: seat flesh rests on it, not in it
    back_deg = p.get("back_deg")
    lean = -math.radians(90 - back_deg) if back_deg is not None else math.radians(p.get("lean", 0))
    width = p.get("knees_apart", 0.15)                 # feet about hip width, as people sit on a machine seat
    reach = p.get("feet_fwd", 0.98)
    if not p.get("feet_free"):
        A.plant_feet(toe_out_deg=8, ankles={s: (sx * width, hip.y - thigh * reach, A.rest_head("foot.L").z)
                                            for s, sx in SIDES})
        for s, sx in SIDES:
            bpy.data.objects["KneePole." + s].location = (sx * width * 1.05, hip.y - thigh, 1.2)
        p.setdefault("knees_point", {s: (sx * (0.15 + width), -1, 0.2) for s, sx in SIDES})   # knees over the toes
    A.set_root(drop, 0, lean)
    if not p.get("no_bench") and not p.get("feet_free"):   # glutes rest on the cushion, compressing it ~1 cm
        # (free legs still hang straight here, so there is nothing to measure the glutes by: keep the fixed drop)
        A.update()
        hip_now = A.head("upperleg01.L")
        pts = A.world_coords(A.body)[A.body_mask]
        seat_pts = pts[(np.abs(pts[:, 1] - hip_now.y) < 0.09) & (np.abs(pts[:, 0]) < 0.2) & (pts[:, 2] < hip_now.z) &
                       (pts[:, 2] > hip_now.z - 0.17)]       # the glutes, not legs hanging below
        if len(seat_pts):
            drop += float(seat_pts[:, 2].min()) - (BENCH_TOP - 0.012)
            A.set_root(drop, 0, lean)
    hip_y = A.head("upperleg01.L").y
    props = [] if p.get("no_bench") else bench(hip_y - p.get("seat_front", 0.2 if back_deg is None else 0.30), hip_y + 0.16,
                                               back_deg=back_deg if back_deg is not None else p.get("backrest"),
                                               legs=not p.get("machine"))
    return (drop, 0, lean), props


def floor_supine(p):
    """Lying on the floor face up, knees bent (`knees` deg) with feet flat, or legs straight (knees 0)."""
    rest_hip = A.rest_head("upperleg01.L")
    on = p.get("bench_z", 0.0)                          # lying on a flat bench instead of the floor
    drop = rest_hip.z - 0.11 - on                       # spine joints ~11 cm above the floor (or pad)
    A.set_root(drop, 0, -math.pi / 2)
    hip = A.head("upperleg01.L")
    if on:
        head_y = A.head("head").y
        p["_bench"] = bench(hip.y - p.get("bench_past_hip", 0.22), head_y + 0.2, top=on)
    knees = p.get("knees", 90)
    thigh = (A.rest_head("lowerleg01.L") - rest_hip).length
    shin = (A.rest_head("foot.L") - A.rest_head("lowerleg01.L")).length
    interior = math.radians(180 - knees)
    run = math.sqrt(thigh ** 2 + shin ** 2 - 2 * thigh * shin * math.cos(interior))
    ankle_z = A.rest_head("foot.L").z
    run = math.sqrt(max(run ** 2 - (hip.z - ankle_z) ** 2, 0.0))
    if p.get("feet_free"):
        return (drop, 0, -math.pi / 2), p.get("_bench", [])
    apart, reach = p.get("feet_apart", 0.26 if on else 0.15), p.get("feet_reach", 0.99)
    A.plant_feet(toe_out_deg=6, ankles={s: (sx * apart, hip.y - run * reach, ankle_z) for s, sx in SIDES},
                 knee_up=1.0)
    out = p.get("knees_out", 0.2)
    for s, sx in SIDES:
        bpy.data.objects["KneePole." + s].location = (sx * (0.25 + out), hip.y - run / 2, 1.2)
    p["knees_point"] = {s: (sx * out, 0, 1) for s, sx in SIDES}
    if knees < 30:
        pitch_feet(-80)                         # straight legs: toes up
    return (drop, 0, -math.pi / 2), p.get("_bench", [])


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
    up = p.get("front_z", 0.0)                          # lead foot on a step (deficit / elevated lunges)
    for s, sx in SIDES:
        ankles[s] = (sx * 0.12, hip.y - p.get("front", 0.45), z + up) if s == lead else \
            (sx * 0.12, hip.y + p.get("back", 0.5), z + 0.06)
    A.plant_feet(toe_out_deg=4, ankles=ankles)
    rear = "R" if lead == "L" else "L"
    t = bpy.data.objects["FootIK." + rear]
    t.matrix_world = Matrix.Translation(t.matrix_world.translation) @ Matrix.Rotation(math.radians(40), 4, 'X') @ \
        t.matrix_world.to_3x3().to_4x4()
    p["knees_point"] = {lead: (0, -1, 0), rear: (0, -0.3, -1)}
    lean = math.radians(p.get("lean", 0))
    A.set_root(0, 0, lean)
    props = []
    if up:
        x, y, _ = ankles[lead]
        props.append(box("Step", (0.4, 0.45, up), (x, y - 0.08, up / 2)))
    return (0, 0, lean), props


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
    if not p.get("no_bench"):                           # lie on the pad, compressing it ~1 cm, not sunk into it
        y0, y1 = (hip_y + 0.16, hip_y + 0.74) if p.get("pad_under") == "thighs" else \
            (hip_y - 0.62, hip_y + p.get("pad_past_hip", 0.3))
        A.update()
        pts = A.world_coords(A.body)[A.body_mask]
        on = pts[(pts[:, 1] > y0) & (pts[:, 1] < y1) & (np.abs(pts[:, 0]) < 0.15)]
        if len(on):
            drop += float(on[:, 2].min()) - (top - 0.012)
            A.set_root(drop, 0, lean)
            hip_y = A.head("upperleg01.L").y
    if p.get("no_bench"):
        props = []
    elif p.get("pad_under") == "thighs":                # hyperextension: hips over the pad's front edge
        props = bench(hip_y + 0.16, hip_y + 0.74, top=top)
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
    if p.get("feet_ball"):                              # shins on an exercise ball
        r = p["feet_ball"]
        props.append(solid_prop("Ball", (0, ankle_y - 0.1, r), r))
    elif ankle_z > 0.2:
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
            elif impl == "band_handle":                # the band's end wrapped in the fist
                A.cylinder(h, 0.013, 0.1, mat=rubber(), verts=32)
            elif impl in ("cable", "cable_handle", "handle"):
                cable_handle(h)
            elif impl == "lever":
                E.grip(h)
            elif impl == "cable_rope":
                A.cylinder(h, 0.017, 0.11, mat=A.BLACK, verts=32)
            else:
                A.dumbbell(h)
        self.radius = A.DB_R
        A.ik_arms(self.h, {s: (sx * 0.4, 0.6, 0.9) for s, sx in SIDES}, poles_in_world=True)
        for s, _ in SIDES:
            A.grip_on(s, self.h[s], (0, 0, 0), thumbward=(1, 0, 0), palm_to_handle=(0, 0, 1), radius=self.radius,
                      slide=spec.get("arm", {}).get("slide", 0.012))
        self.cables = Cables(spec, {s: self.h[s] for s in self.hands}) if impl.startswith("cable") else None
        self.on_head = spec.get("arm", {}).get("on_head", False)

    HEAD_R = 0.095              # back of the skull, approximated as a sphere round the head bone's middle

    def place_on_head(self, fr):
        """Hands behind the head (sit-ups, crunches): palms flat on the back of the skull, fingers pointing in to
        meet behind it, thumbs down the neck; tracks the head every frame so the hands stay in contact."""
        A.update()
        _, fwd, _ = torso_frame()
        up = (A.tail("head") - A.head("head")).normalized()
        fwd = (fwd - fwd.dot(up) * up).normalized()
        lat = up.cross(fwd)                     # toward the figure's left, as in torso_frame
        centre = A.head("head").lerp(A.tail("head"), 0.45)
        for s, sx in SIDES:
            x = 0.05
            palm = centre + lat * (sx * x) - fwd * (math.sqrt(self.HEAD_R ** 2 - x ** 2) + 0.012)
            fingers = (-lat * sx - fwd * 0.35).normalized()
            wrist = palm - fingers * 0.05 - fwd * 0.012
            self.h[s].matrix_world = A.holder_for_hand(s, wrist, fingers, -up)
        self.arms.set_poles(fr)
        A.update()

    def place(self, fr):
        if self.on_head:
            self.place_on_head(fr)
            return
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


class LeverArms(PerHand):
    """Plate-loaded lever machine (Hammer Strength style): each handle sits on a rigid arm turning about a fixed
    axle. spec "lever": {"pivot": [out, fwd, up] from the shoulder in the torso frame}. The arm keys only pick
    where the arc starts and which way it runs; the handle stays on the arc and the hand turns with the arm."""

    def __init__(self, spec, arms, impl):
        super().__init__(spec, arms, "lever")
        A.update()
        lat, fwd, up = torso_frame()
        p = spec["lever"]["pivot"]
        self.axle, self.arm = {}, {}
        for s, sx in SIDES:
            if s not in self.hands:
                continue
            P = A.head("upperarm01." + s) + lat * (p[0] * sx) + fwd * p[1] + up * p[2]
            m1 = self.raw(1, s, sx)
            far = max((self.raw(fr, s, sx) for fr in range(1, A.LOOP + 1, 4)),
                      key=lambda m: (m.translation - m1.translation).length)
            d = far.translation - m1.translation
            if d.length > 1e-3:                         # slide the axle so both arc ends sit at one radius
                P = P + d.normalized() * ((far.translation.length_squared - m1.translation.length_squared) / 2
                                          - P.dot(d)) / d.length
            a, b = m1.translation - P, far.translation - P
            n = a.cross(b)
            n = n.normalized() if n.length > 1e-6 else lat * sx
            if n.dot(lat * sx) < 0:
                n = -n                                  # axle points out of the machine on each side
            self.axle[s] = (P, n, a.normalized(), m1)
            self.arm[s] = A.holder("LeverArm." + s)
            self.arm[s].location = P
            A.update()
            E.parent_keep(lever_arm(P, n, m1, lat * sx, horn=not spec["lever"].get("stack")), self.arm[s])

    def raw(self, fr, s, sx):
        _, wrist, F, thumb = self.arms.target(fr, s, sx)
        return A.holder_for_hand(s, wrist, F, thumb)

    def turn(self, fr, s, sx):
        P, n, d1, m1 = self.axle[s]
        v = self.raw(fr, s, sx).translation - P
        v = (v - n * v.dot(n)).normalized()
        return math.atan2(n.dot(d1.cross(v)), d1.dot(v))

    def place(self, fr):
        for s, sx in SIDES:
            if s not in self.hands:
                continue
            P, n, _, m1 = self.axle[s]
            rot = Matrix.Rotation(self.turn(fr, s, sx), 4, n)
            self.h[s].matrix_world = Matrix.Translation(P) @ rot @ Matrix.Translation(-P) @ m1
            self.arm[s].rotation_quaternion = rot.to_quaternion()
        self.arms.set_poles(fr)
        A.update()

    def key(self, fr):
        super().key(fr)
        for o in self.arm.values():
            A.key_holder(o, fr)

    def meshes(self):
        return super().meshes() + [c for o in self.arm.values() for c in o.children]


def machine_frame(spec, gear, props):
    """Static frame of a lever machine: hubs carried on a top beam from a central column standing beyond the
    axles (behind the backrest for presses, in front for rows), a floor rail with feet, a seat post and a
    backrest bracket."""
    hubs = list(gear.axle.values())
    if not hubs:
        return []
    if spec["lever"].get("base") == "ground":
        return ground_base(hubs)
    py = sum(P.y for P, *_ in hubs) / len(hubs)
    pz = sum(P.z for P, *_ in hubs) / len(hubs)
    named = {o.name.split(".")[0]: o for o in props}
    seat, back = named.get("BenchSeat"), named.get("BenchBack")
    hip_y = A.head("upperleg01.L").y
    behind = spec["lever"].get("column", "back" if back is not None else "front") == "back"
    if back is not None and behind:
        back_rear = max((back.matrix_world @ Vector(c)).y for c in back.bound_box)
        ys = max(py, back_rear) + 0.14
    else:
        ys = py + (0.14 if behind else -0.14)
    if not behind:                                      # stand clear in front of the lifter and any chest pad
        pts = A.world_coords(A.body)
        torso = pts[(pts[:, 2] > 0.25) & (np.abs(pts[:, 0]) < 0.3)]     # chest, thighs and knees
        front = torso[:, 1].min() if len(torso) else ys
        for o in props:
            if o.name.startswith("ChestPad"):
                front = min(front, min((o.matrix_world @ Vector(c)).y for c in o.bound_box))
        ys = min(ys, front - 0.15)
    top = Vector((0, ys, pz + 0.08))
    parts = [E.tube("Column", (0, ys, 0.07), top, 0.1, 0.1), E.joint("ColumnTop", top, 0.065)]
    reach = Vector((0, py, pz + 0.08))                  # the beam runs over to sit between the two hubs
    if (reach - top).length > 0.05:
        parts += [E.tube("Boom", top, reach, 0.1, 0.08), E.joint("BoomEnd", reach, 0.055)]
    for P, n, *_ in hubs:
        parts.append(E.tube("Beam", P - n * 0.045, reach, 0.08, 0.08))
    if seat is not None:
        sc = seat.matrix_world.translation
        front = sc.y - (0.3 if behind else -0.3)
        parts.append(E.tube("Rail", (0, ys, 0.07), (0, front, 0.07), 0.1, 0.06))
        parts += E.foot("Foot", (0, ys, 0), 0.7, 'x' if behind else 'y') + E.foot("Foot", (0, front, 0), 0.6)
        low = min((seat.matrix_world @ Vector(c)).z for c in seat.bound_box)
        parts.append(E.tube("SeatPost", (0, sc.y, 0.1), (0, sc.y, low), 0.08, 0.08))
        parts.append(E.tube("SeatArm", (0, sc.y, low - 0.04), (0, ys, low - 0.04), 0.07, 0.05))
    if spec["lever"].get("stack"):
        at = Vector((0, ys + (0.2 if behind else -0.22), 0))     # in line with the column, on the far side
        parts += weight_stack(at, pz + 0.08)
        if not behind:
            parts.append(E.tube("StackArm", (0, ys, pz - 0.2), (0, at.y, pz - 0.2), 0.07, 0.07))
    if back is not None:
        bc = back.matrix_world.translation
        n = back.matrix_world.to_3x3().col[2].normalized()
        if n.y < 0:
            n = -n
        rear = bc + n * 0.06
        parts.append(E.tube("BackBracket", rear, (0, ys, rear.z), 0.07, 0.05))
    return parts


def ground_base(hubs):
    """Ground-based lever machine (shrug, deadlift): a rubber-topped deck under the feet, the axles on short
    towers off its rear edge, tied by a crossbeam."""
    feet = (A.head("foot.L") + A.head("foot.R")) / 2
    parts = [E.tube("Deck", (0, feet.y - 0.45, 0.005), (0, feet.y + 0.45, 0.005), 1.1, 0.01)]   # flush deck plate
    for P, n, *_ in hubs:
        base = Vector((P.x, P.y, 0.01))
        if P.z > 0.12:
            parts.append(E.tube("Tower", base, P - Vector((0, 0, 0.06)), 0.09, 0.09))
    if len(hubs) == 2:
        (a, na, *_), (b, nb, *_) = hubs
        parts.append(E.tube("Cross", a - na * 0.045, b - nb * 0.045, 0.08, 0.08))
    return parts


def weight_stack(at, top_z, side=None):
    """Selectorized stack: guide rods, a column of plates with a steel top plate, and a cap beam; plates run
    along `side` (world x by default)."""
    side = (side or Vector((1, 0, 0))).normalized()
    up = Vector((0, 0, 1))
    parts = []
    for d in (-0.12, 0.12):
        parts.append(E.round_tube("GuideRod", at + side * d + up * 0.06, at + side * d + up * top_z, 0.012,
                                  mat=E.metal_mat()))
    z = 0.1
    for i in range(14):
        parts.append(E.tube("StackPlate", at - side * 0.17 + up * z, at + side * 0.17 + up * z, 0.15, 0.022,
                            mat=E.plate_mat()))
        z += 0.026
    parts.append(E.tube("TopPlate", at - side * 0.17 + up * (z + 0.02), at + side * 0.17 + up * (z + 0.02), 0.15,
                        0.04, mat=E.metal_mat()))
    parts.append(E.tube("StackCap", at - side * 0.22 + up * top_z, at + side * 0.22 + up * top_z, 0.1, 0.08))
    parts.append(E.tube("StackBase", at - side * 0.22 + up * 0.04, at + side * 0.22 + up * 0.04, 0.2, 0.08))
    return parts


def lever_arm(P, n, m1, out, horn=True):
    """Arm from the axle at P to the handle on holder matrix m1: formed rectangular tube bowing out round the
    shoulder, a steel plate horn with two plates, and the axle hub."""
    h = m1.translation
    x = m1.to_3x3().col[0].normalized()                 # handle axis
    end = h + x * (0.085 if x.dot(P - h) > 0 else -0.085)   # the arm meets the handle at the end nearer the axle
    end = end + out * 0.07                              # the arm takes the handle on its outer side
    knee = end + (P - end) * 0.4 + out * 0.1
    parts = [E.tube("Arm", end, knee, 0.055, 0.085), E.joint("ArmKnee", knee, 0.045),
             E.tube("Arm", knee, P, 0.055, 0.085), E.joint("ArmEnd", end, 0.034)]
    if horn:
        horn_at = P + (knee - P) * 0.22                 # horn sticks out sideways near the axle, plates clear of the lifter
        parts.append(E.round_tube("HornSleeve", horn_at, horn_at + out * 0.2, 0.034))
        parts.append(E.round_tube("Horn", horn_at + out * 0.2, horn_at + out * 0.42, 0.025, mat=E.metal_mat()))
        parts += E.plates("Plate", horn_at + out * 0.24, out, n=2, r=0.2)
    parts += E.hub("Hub", P, n)
    return parts


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


class HeldPlate(Ball):
    """A weight plate held in both hands at its rim (plate raises, twists, weighted crunches): centred between the
    palms, its face toward the chest."""
    R = 0.2

    def __init__(self, spec, arms, impl):
        PerHand.__init__(self, spec, arms, "none")
        self.ball = A.holder("plate")
        A.cylinder(self.ball, self.R, 0.035, mat=A.PLATE, verts=96, bevel=0.006)
        A.cylinder(self.ball, 0.03, 0.04, mat=A.STEEL)

    def place(self, fr):
        super().place(fr)
        lat, fwd, up = torso_frame()
        ends = [self.arms.target(fr, s, sx) for s, sx in SIDES]
        across = (ends[0][1] - ends[1][1]).normalized()         # wrist to wrist: the plate's x axis
        z = fwd - fwd.dot(across) * across
        self.ball.rotation_quaternion = Matrix((across, z.cross(across).normalized(),
                                                z.normalized())).transposed().to_quaternion()
        self.ball.rotation_quaternion = self.ball.rotation_quaternion @ Quaternion((0, 1, 0), math.pi / 2)


class HeldFrame(Ball):
    """A frame held by neutral handles at the sides (trap bar, rickshaw, car-deadlift frame). The handles are per
    hand; the frame follows the hands' midpoint, its x axis wrist to wrist, its z axis up."""

    def __init__(self, spec, arms, impl):
        PerHand.__init__(self, spec, arms, "handle")
        self.ball = A.holder("frame")
        self.kind = spec.get("frame", "hex")
        self.pivot = Vector(spec.get("pivot", (0, 0.9, 0.04)))      # tbar: floor pivot behind the lifter
        self.built = False

    def build(self, d):
        """Frame geometry in the holder's space, handles at x = +-d along y (+y is behind the lifter)."""
        parts = []
        if self.kind == "hex":
            hexa = [(0.42, 0.18), (0.22, 0.45), (-0.22, 0.45), (-0.42, 0.18),
                    (-0.42, -0.18), (-0.22, -0.45), (0.22, -0.45), (0.42, -0.18)]
            for a, b in zip(hexa, hexa[1:] + hexa[:1]):
                parts.append(rod("Hex", (*a, 0), (*b, 0), 0.016))
            for sx in (1, -1):
                for sy in (1, -1):
                    parts.append(rod("HexArm", (sx * d, sy * 0.06, 0), (sx * 0.42, sy * 0.14, 0), 0.014))
                parts.append(rod("Sleeve", (sx * 0.42, 0, 0), (sx * 0.85, 0, 0), 0.025))
            plate_x = 0.62
        elif self.kind == "tbar":                   # landmine bar: x runs from the floor pivot through the hands
            parts.append(rod("TBar", (-self.reach, 0, 0), (0.32, 0, 0), 0.025))
            parts.append(rod("VHandle", (0.0, d, 0), (0.0, -d, 0), 0.016))
            plate_x = 0.2
        else:                                       # rickshaw / car frame: long side rails run on ahead
            for sx in (1, -1):
                parts.append(rod("Rail", (sx * d, 0.25, 0), (sx * d, -1.1, 0), 0.02))
                parts.append(rod("Leg", (sx * d, -1.1, 0), (sx * d, -1.1, -0.35), 0.025))
                parts.append(rod("Sleeve", (sx * d, -1.0, -0.2), (sx * (d + 0.3), -1.0, -0.2), 0.025))
            parts.append(rod("Cross", (d, -1.1, 0), (-d, -1.1, 0), 0.02))
            parts.append(rod("Cross", (d, 0.25, 0), (-d, 0.25, 0), 0.02))
            plate_x = None
        for o in parts:
            o.parent = self.ball
            o.matrix_parent_inverse = Matrix.Identity(4)
        if self.kind == "tbar":
            for x in (plate_x, plate_x + 0.06):
                A.cylinder(self.ball, 0.225, 0.05, x=x, mat=A.PLATE, verts=96, bevel=0.006)
        elif plate_x:
            for sx in (1, -1):
                A.cylinder(self.ball, 0.225, 0.05, x=sx * plate_x, mat=A.PLATE, verts=96, bevel=0.006)
                A.cylinder(self.ball, 0.225, 0.05, x=sx * (plate_x + 0.06), mat=A.PLATE, verts=96, bevel=0.006)
        else:
            for sx in (1, -1):
                o = A.cylinder(self.ball, 0.225, 0.05, mat=A.PLATE, verts=96, bevel=0.006)
                o.location = (sx * (d + 0.2), -1.0, -0.2)
        self.built = True

    def place(self, fr):
        PerHand.place(self, fr)
        ends = [self.arms.target(fr, s, sx) for s, sx in SIDES]
        palms = [w + F * 0.05 for _, w, F, _ in ends]
        across = palms[0] - palms[1]
        mid = (palms[0] + palms[1]) / 2
        if self.kind == "tbar":
            if not self.built:
                self.reach = (mid - self.pivot).length
                self.build(across.length / 2)
            x = (mid - self.pivot).normalized()
            z = Vector((0, 0, 1))
            z = (z - z.dot(x) * x).normalized()
            self.ball.location = mid
            self.ball.rotation_quaternion = Matrix((x, z.cross(x), z)).transposed().to_quaternion()
            return
        if not self.built:
            self.build(across.length / 2)
        x = across.normalized()
        z = Vector((0, 0, 1))
        z = (z - z.dot(x) * x).normalized()
        self.ball.location = (palms[0] + palms[1]) / 2
        self.ball.rotation_quaternion = Matrix((x, z.cross(x), z)).transposed().to_quaternion()


def solid_prop(kind, at, r):
    """A static ball (exercise ball, medicine ball) at world point `at`."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=64, ring_count=32, location=at)
    o = bpy.context.object
    o.name = kind
    o.data.materials.append(A.BLACK)
    bpy.ops.object.shade_smooth()
    return o


def pulley(name, at, axis):
    """Swivel pulley: steel wheel between two side plates, the cable leaving its rim."""
    axis = axis.normalized()
    parts = [E.round_tube(name + "Wheel", at - axis * 0.016, at + axis * 0.016, 0.055, mat=E.metal_mat())]
    for s in (1, -1):
        c = at + axis * 0.03 * s
        parts.append(E.round_tube(name + "Cheek", c - axis * 0.006, c + axis * 0.006, 0.07))
    return parts


def _near_body(col, top):
    """Horizontal distance from a vertical column at `col` (up to `top`) to the nearest body point."""
    pts = A.world_coords(A.body)
    pts = pts[pts[:, 2] < top]
    d = np.hypot(pts[:, 0] - col.x, pts[:, 1] - col.y)
    return float(d.min()) if len(d) else 9.0


def cable_tower(anchors, body_c, fwd):
    """Commercial cable station round its pulleys: an upright column just beyond each pulley with the pulley on
    a short bracket, a weight stack behind it, floor feet, and a top beam when two towers face each other. A
    pulley high over the lifter (pulldowns) hangs from a boom off a column standing past the knees."""
    parts, cols = [], []
    for a in anchors:
        h = Vector((a.x - body_c.x, a.y - body_c.y, 0))
        overhead = h.length < 0.35 and a.z > 1.5
        if h.length < 0.25:
            h = Vector((fwd.x, fwd.y, 0))
        h.normalize()
        side = Vector((-h.y, h.x, 0))
        top = max(2.2, a.z + 0.25)
        if overhead:
            col = Vector((a.x, a.y, 0)) + h * 1.05
            boom_z = a.z + 0.3
            parts += [E.tube("Boom", (col.x, col.y, boom_z), Vector((a.x, a.y, boom_z)) - h * 0.06, 0.09, 0.09),
                      E.round_tube("PulleyStem", a + Vector((0, 0, 0.07)), (a.x, a.y, boom_z - 0.045), 0.018,
                                   mat=E.metal_mat())]
            top = max(top, boom_z + 0.05)
        else:
            col = Vector((a.x, a.y, 0)) + h * 0.2
            while _near_body(col, top) < 0.16:         # never stand the tower in or against the lifter
                col += h * 0.05
            parts.append(E.tube("Bracket", a + h * 0.07, (col.x, col.y, a.z), 0.06, 0.06))
        parts += [E.tube("Column", col + Vector((0, 0, 0.07)), col + Vector((0, 0, top)), 0.11, 0.11),
                  E.joint("ColumnCap", col + Vector((0, 0, top)), 0.07)]
        parts += E.foot("Foot", col + h * 0.12, 0.75, 'x' if abs(side.x) > abs(side.y) else 'y')
        parts += weight_stack(col + h * 0.24, top - 0.1, side)
        axis = side if abs(h.z) < 0.5 else Vector((1, 0, 0))
        parts += pulley("Pulley", a, axis)
        cols.append((col, top))
    if len(cols) == 2 and (cols[0][0] - cols[1][0]).length > 0.8:
        (c0, t0), (c1, t1) = cols
        z = min(t0, t1)
        parts.append(E.tube("TopBeam", (c0.x, c0.y, z), (c1.x, c1.y, z), 0.1, 0.1))
    return parts


class Cables:
    """A cable from a pulley (`cable.anchor`, torso-frame offset from the shoulders at frame 1) to each handle,
    the pulleys mounted on a cable tower with its weight stack."""

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
            m = sx if c.get("mirror", True) else 1          # one pulley off to one side for both hands
            a = mid + lat * off[0] * m + fwd * off[1] + up * off[2]
            a.z = max(a.z, 0.12)
            self.anchor[s] = a
            self.lines[s] = rod("Cable." + s, a - Vector((0, 0, 0.5)), a + Vector((0, 0, 0.5)), 0.003)
        pulleys = []
        for a in self.anchor.values():
            if all((a - p).length > 0.1 for p in pulleys):
                pulleys.append(a)
        hips = (A.head("upperleg01.L") + A.head("upperleg01.R")) / 2
        world_fwd = fwd if abs(fwd.z) < 0.9 else up
        self.props = cable_tower(pulleys, hips, world_fwd)

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
    """A cambered curl bar: straight where the hands grip (|x| >= 0.12), with the W-bend in the middle."""
    for sx in (1, -1):
        A.cylinder(h, A.BAR_R, 0.36, x=sx * 0.295, mat=A.STEEL, verts=48)
        pts = [Vector((sx * 0.115, 0, 0)), Vector((sx * 0.075, 0, 0.035)), Vector((0, 0, 0))]
        for a, b in zip(pts, pts[1:]):
            seg = A.cylinder(h, A.BAR_R, (b - a).length + 0.012, mat=A.STEEL, verts=48)
            seg.matrix_basis = Matrix.Translation((a + b) / 2) @ (b - a).to_track_quat('Z', 'Y').to_matrix().to_4x4()
    for sx in (1, -1):
        A.cylinder(h, 0.03, 0.03, x=sx * 0.49, mat=A.STEEL)
        A.cylinder(h, 0.025, 0.13, x=sx * 0.56, mat=A.STEEL)
        A.cylinder(h, 0.17, 0.035, x=sx * 0.53, mat=A.PLATE, verts=96, bevel=0.006)


def short_bar(h, length=0.55):
    A.cylinder(h, A.BAR_R, length, mat=A.STEEL, verts=48)


class Bar:
    """Both hands on one bar: centred between the hands' key-pose positions, grip width fixed, rolled with the
    forearms and then frame by frame (smoothed) to keep the wrists straight."""

    def __init__(self, spec, arms, impl):
        self.arms = arms
        self.bar = A.holder("Bar")
        a = spec.get("arm", {})
        if impl == "cable_bar":                 # a lat bar when the grip is wide: both hands always on the bar
            short_bar(self.bar, max(0.55, 2 * a.get("grip", 0.22) + 0.3))
        else:
            {"barbell": A.barbell, "ezbar": ezbar}[impl](self.bar)
        self.gx = a.get("grip", 0.22)
        self.slide = a.get("slide", 0.012)
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
            A.grip_on(s, self.bar, (sx * self.gx, 0, 0), thumbward=(sx * self.tsign, 0, 0), palm_to_handle=self.palm,
                      slide=self.slide)
        A.update()

    def finish_grip(self):
        for s, sx in SIDES:
            A.grip_neutral(s, self.bar, (sx * self.gx, 0, 0), thumbward=(sx * self.tsign, 0, 0),
                           palm_guess=self.palm, slide=self.slide)
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


RACK_SLIDE = 0.04      # bar this far from the knuckles toward the wrist: across the heel of the palm, over the forearm


class BackBar:
    """Barbell resting on the upper back (back squat, good morning, lunge): rides with the torso, hands hold it."""

    def __init__(self, spec, arms, impl):
        self.arms = arms
        a = spec.get("arm", {})
        self.spec_arm = a
        self.gx = a.get("grip", 0.42)
        self.at = a.get("bar_at", "back")
        default = (0, 0.17, -0.02) if self.at == "hips" else (0, -0.085, 0.035)
        self.palm = a.get("palm", (0, 1, 0) if self.at == "hips" else (0, -1, 0.3))
        self.on = a.get("bar_on", default)                  # bar centre from mid-shoulders/hips: (_, forward, up)
        self.bar = A.holder("Bar")
        A.barbell(self.bar)
        self.cables = None
        self.pole = {}
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
                pole = tdir(self.pole[s], sx) if s in self.pole else self.arms.pole_dir(sx)
                bpy.data.objects["ElbowPole." + s].location = (shoulder + hand) / 2 + pole * 0.6
        A.update()

    def grip(self):
        if self.at == "hips" or "bar_on" in self.spec_arm:          # hip thrust, front rack: keep the rolled grip
            for s, sx in SIDES:
                A.grip_neutral(s, self.bar, (sx * self.gx, 0, 0), thumbward=(-sx, 0, 0), palm_guess=self.palm)
        else:
            self.rack_grip()
            return
        for s, _ in SIDES:
            A.seat_palm(s)
        for s, _ in SIDES:
            A.wrap_hand(s)

    def rack_grip(self):
        """Bar on the back: elbows down and back under the bar, forearms pointing at it, bar across the heel of the
        palm with the hand on the forearm's line (wrist straight), as in a real back-squat grip.

        Each elbow is the point upper-arm length from the shoulder and forearm-plus-hand length from its handle,
        on the side the spec's `elbow_out` asks for; the fingers then continue the forearm."""
        A.update()
        m = self.bar.matrix_world
        inv = m.to_3x3().inverted()
        lat, fwd, up = torso_frame()
        palms = {}
        for s, sx in SIDES:
            handle = m @ Vector((sx * self.gx, 0, 0))
            a = (m.to_3x3() @ Vector((-sx, 0, 0))).normalized()
            upper, fore = A.arm_lengths(s)
            rest = A.handle_in_hand(s, RACK_SLIDE, A.BAR_R, square=1)
            reach_ = fore + (rest.translation - A.D["wrist." + s].matrix_local.translation).length * 0.9
            shoulder = A.head("upperarm01." + s)
            want = self.arms.pole_dir(sx)
            axis = handle - shoulder
            dist = axis.length
            axis.normalize()
            along = (dist ** 2 + upper ** 2 - reach_ ** 2) / (2 * dist)
            out = (want - want.dot(axis) * axis).normalized()
            elbow = shoulder + axis * along + out * math.sqrt(max(upper ** 2 - along ** 2, 0.0))
            f = handle - elbow
            f = (f - f.dot(a) * a).normalized()
            palms[s] = inv @ (f.cross(a) if s == "L" else a.cross(f))
            d = (elbow - (shoulder + handle) / 2).normalized()
            self.pole[s] = (d.dot(lat) * sx, d.dot(fwd), d.dot(up))
            A.grip_on(s, self.bar, (sx * self.gx, 0, 0), (-sx, 0, 0), palms[s], slide=RACK_SLIDE, square=1)
        for _ in range(2):
            self.place(1)
            A.solve_pole_angles({s: tdir(self.pole[s], sx) for s, sx in SIDES})
            for s, sx in SIDES:
                A.regrip(s, self.bar, (sx * self.gx, 0, 0), (-sx, 0, 0), palms[s], slide=RACK_SLIDE, span=30,
                         squares=(0.0, 1.0))

    def key(self, fr):
        A.key_holder(self.bar, fr)

    def meshes(self):
        return [o for o in self.bar.children if o.type == 'MESH']


def suspension_ring(h, r=0.09):
    """A gymnastic ring gripped at its lower arc (the holder's origin, x along the grip) on a strap to the ceiling."""
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.016, major_segments=64, minor_segments=16,
                                     location=(0, 0, r), rotation=(math.pi / 2, 0, 0))
    ring = bpy.context.object
    ring.data.materials.append(A.BLACK)
    bpy.ops.object.shade_smooth()
    ring.parent = h
    ring.matrix_parent_inverse = Matrix.Identity(4)
    top = Vector(h.location) + Vector((0, 0, 2 * r))
    return [ring, rod("Strap", top, (top.x, top.y, 2.8), 0.012, mat=A.BLACK)]


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
            hang = a.get("hang", False)                 # hands under the handle (rows) instead of on top
            for s, sx in SIDES:
                w = pts[s][1]
                h = A.holder("Dip." + s)
                h.location = (w.x + sx * 0.02, w.y, w.z + (0.03 if hang else -0.03))
                h.rotation_quaternion = Vector((0, 1, 0)).to_track_quat('X', 'Z')
                if a.get("rings"):
                    self.props += suspension_ring(h)
                else:
                    A.cylinder(h, 0.02, 1.0, mat=A.STEEL, verts=48)
                    self.props.append(box("DipPost", (0.05, 0.05, h.location.z), (h.location.x, w.y + 0.4,
                                                                                    h.location.z / 2)))
                self.h[s] = h
            A.ik_arms(self.h, {s: (sx * 0.5, 0, 1) for s, sx in SIDES}, poles_in_world=True)
            for s, sx in SIDES:
                A.grip_on(s, self.h[s], (0, 0, 0), thumbward=(-1, 0, 0), palm_to_handle=(0, 0, 1 if hang else -1),
                          radius=0.02)
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
            if a.get("on_dumbbell"):                    # hands on a dumbbell lying on the floor
                db = A.holder("FloorDB")
                db.location = (0, sum(h.location.y for h in self.h.values()) / 2, 0.06)
                A.dumbbell(db, handle=0.135, head_r=0.06, head_w=0.07)
                self.props += [o for o in db.children if o.type == 'MESH']
            if a.get("hand_box"):
                z, y = a["hand_z"], sum(h.location.y for h in self.h.values()) / 2
                self.props.append(box("HandBox", (0.75, 0.35, z), (0, y, z / 2)))
            if a.get("prowler"):                            # hands on the two uprights, sled runs on ahead
                y = sum(h.location.y for h in self.h.values()) / 2 - 0.035
                for h in self.h.values():
                    self.props.append(box("Upright", (0.045, 0.045, 1.3), (h.location.x, y, 0.65)))
                self.props.append(box("Sled", (0.7, 0.9, 0.06), (0, y - 0.42, 0.06)))
                self.props.append(box("Skid", (0.06, 1.0, 0.03), (0.32, y - 0.42, 0.015)))
                self.props.append(box("Skid", (0.06, 1.0, 0.03), (-0.32, y - 0.42, 0.015)))
                self.props.append(box("PlatePost", (0.06, 0.06, 0.4), (0, y - 0.55, 0.29)))
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
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.05, depth=0.36, location=c, rotation=(0, math.pi / 2, 0))
    pad = bpy.context.object
    pad.name = "LegPad"
    pad.data.materials.append(E.pad_mat())
    bpy.ops.object.shade_smooth()
    A.update()
    attach(pad, "lowerleg01.L")
    return pad


def leg_lever(pad, props):
    """Leg extension / leg curl machine round the shin pad: a lever arm from a hub on the knee axis down to the
    roller, riding with the shin, the hub on a column beside the knee, and a weight stack tower beside the seat
    joined to it by a floor rail."""
    knee = (A.head("lowerleg01.L") + A.head("lowerleg01.R")) / 2
    c = pad.matrix_world.translation
    sx = -1
    hub_at = Vector((sx * 0.29, knee.y, knee.z))
    end = Vector((sx * 0.29, c.y, c.z))
    arm = [E.tube("LegArm", hub_at, end, 0.05, 0.075), E.joint("LegArmEnd", end, 0.04),
           E.round_tube("PadAxle", end, Vector((0, c.y, c.z)), 0.016, mat=E.metal_mat())]
    for o in arm:
        attach(o, "lowerleg01.L")
    col = Vector((sx * 0.45, knee.y, 0))
    named = {o.name.split(".")[0]: o for o in props}
    seat = named.get("BenchSeat")
    rear_y = seat.matrix_world.translation.y + 0.35 if seat is not None else knee.y + 0.6
    stack_at = Vector((sx * 0.62, rear_y, 0))
    parts = arm + [E.tube("Column", col + Vector((0, 0, 0.07)), (col.x, col.y, hub_at.z), 0.09, 0.09),
                   E.tube("HubArm", (col.x, col.y, hub_at.z), hub_at, 0.08, 0.08)]
    parts += E.hub("Hub", hub_at, Vector((sx, 0, 0)), r=0.07, depth=0.1)
    parts += E.foot("Foot", col, 0.6, 'y')
    parts.append(E.tube("Rail", col + Vector((0, 0, 0.05)), stack_at + Vector((0, 0, 0.05)), 0.09, 0.06))
    parts += weight_stack(stack_at, 1.55, Vector((0, 1, 0)))
    parts += [E.tube("StackPost", stack_at + Vector((0, -0.28, 0.07)), stack_at + Vector((0, -0.28, 1.6)), 0.08,
                     0.08),
              E.tube("StackPost", stack_at + Vector((0, 0.28, 0.07)), stack_at + Vector((0, 0.28, 1.6)), 0.08, 0.08)]
    return parts


def hack_frame(pad, length, fwd):
    """Hack squat frame: two steel guide rails behind the back pad along the sled's actual travel (the pad's
    path over the loop) on rail beams, a rear tower holding their top, and floor rails out to the feet."""
    path = []
    for fr in range(1, A.LOOP + 1, 3):
        A.scene.frame_set(fr)
        corners = [pad.matrix_world @ Vector(v) for v in pad.bound_box]
        path.append(sum(corners, Vector()) / 8)
    A.scene.frame_set(1)
    top_p = max(path, key=lambda p: p.z)
    low_p = min(path, key=lambda p: p.z)
    up = (top_p - low_p).normalized() if (top_p - low_p).length > 0.05 else Vector((0, 0, 1))
    back = -(fwd - fwd.dot(up) * up).normalized()
    mid = (top_p + low_p) / 2 + back * 0.17
    length = max(length, (top_p - low_p).length + 0.9)
    lo, hi = mid - up * length / 2, mid + up * length / 2
    if lo.z < 0.15:
        lo = lo + up * ((0.15 - lo.z) / up.z)
    feet = (A.head("foot.L") + A.head("foot.R")) / 2
    parts = []
    for x in (-0.14, 0.14):
        dx = Vector((x, 0, 0))
        parts.append(E.round_tube("HackRail", lo + dx, hi + dx, 0.022, mat=E.metal_mat()))
        parts.append(E.tube("HackBeam", lo + dx + back * 0.06, hi + dx + back * 0.06, 0.07, 0.07))
        top = lo + (hi - lo) * 0.55 + dx + back * 0.06   # tower meets the beam mid-rail, below the hands
        post_x = x * 4.0                            # outside the elbows
        parts.append(E.tube("HackPost", (post_x, top.y, 0.07), (post_x, top.y, top.z), 0.09, 0.09))
        parts.append(E.tube("HackArm", (post_x, top.y, top.z), top, 0.07, 0.07))
        low = lo + dx + back * 0.06
        parts.append(E.tube("HackLeg", (x, low.y, 0.07), low, 0.08, 0.08))
        parts.append(E.tube("HackBase", (post_x, feet.y - 0.35, 0.05), (post_x, top.y + 0.1, 0.05), 0.09, 0.07))
    for y in (feet.y - 0.3, top.y):
        parts.append(E.tube("HackCross", (-0.6, y, 0.05), (0.6, y, 0.05), 0.08, 0.07))
    return parts


def calf_machine(pad, bone):
    """Seated calf machine: the thigh pad sits on a lever that rides with the thighs, pivots on a hub low behind
    the heels and carries a plate horn out front."""
    A.update()
    corners = [pad.matrix_world @ Vector(v) for v in pad.bound_box]
    lo = np.min(np.array(corners), axis=0)
    hi = np.max(np.array(corners), axis=0)
    pts = A.world_coords(A.body)[A.body_mask]
    under = pts[(pts[:, 0] > lo[0]) & (pts[:, 0] < hi[0]) & (pts[:, 1] > lo[1]) & (pts[:, 1] < hi[1]) &
                (pts[:, 2] > lo[2] - 0.25) & (pts[:, 2] < hi[2] + 0.06)]    # the thighs, not the hands above
    if len(under):                                      # rest the pad on top of the thighs, not in them
        lift = float(under[:, 2].max()) + 0.006 - lo[2]
        if lift > 0:
            pad.matrix_world = Matrix.Translation((0, 0, lift)) @ pad.matrix_world
            A.update()
    corners = [pad.matrix_world @ Vector(v) for v in pad.bound_box]
    c = sum(corners, Vector()) / 8
    sx = -1                                         # far side: the camera sees the calves
    knee = A.head("lowerleg01.L")
    ankle = A.head("foot.L")
    pivot = Vector((sx * 0.52, ankle.y + 0.18, 0.2))
    top = Vector((sx * 0.52, c.y, c.z))
    front = top + Vector((0, -0.38, -0.05))
    arm = [E.tube("CalfArm", pivot, top, 0.06, 0.08), E.joint("CalfKnee", top, 0.045),
           E.tube("CalfArm", top, front, 0.06, 0.08), E.joint("CalfEnd", front, 0.04),
           E.tube("CalfBar", Vector((sx * 0.22, c.y, c.z + 0.03)), top + Vector((0, 0, 0.03)), 0.05, 0.05),
           E.round_tube("Horn", front, front + Vector((sx * 0.3, 0, 0)), 0.025, mat=E.metal_mat())]
    arm += E.plates("Plate", front + Vector((sx * 0.08, 0, 0)), Vector((sx, 0, 0)), n=2, r=0.2)
    for o in arm:
        attach(o, bone)
    parts = arm + E.hub("Hub", pivot, Vector((sx, 0, 0)))
    parts.append(E.tube("CalfTower", (sx * 0.6, pivot.y, 0.07), pivot + Vector((sx * 0.08, 0, 0)), 0.08, 0.08))
    parts += E.foot("CalfFoot", (sx * 0.6, pivot.y, 0), 0.7, 'y')
    parts.append(E.tube("CalfBase", (sx * 0.6, pivot.y, 0.05), (-sx * 0.3, pivot.y, 0.05), 0.08, 0.06))
    return parts


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
    centre = elbow - along * 0.12 - normal * 0.11
    tilt = math.atan2(along.z, -along.y)                # pad's long axis from level toward the figure's front
    pad = box("PreacherPad", (0.55, 0.34, 0.07), centre, rot_x=-tilt)
    foot = centre + along * 0.15 - normal * 0.05       # under the pad's front edge, clear of the chest
    knee_y = sum(A.head("lowerleg01." + s).y for s, _ in SIDES) / 2
    base = Vector((0, min(knee_y - 0.24, foot.y), 0))            # the stand rises in front of the shins
    bend = Vector((0, base.y, foot.z - 0.06))
    parts = [pad, E.tube("PreacherPost", base + Vector((0, 0, 0.07)), bend, 0.08, 0.08), E.joint("PreacherBend", bend, 0.05),
             E.tube("PreacherArm", bend, foot, 0.07, 0.07)]
    return parts + E.foot("PreacherFoot", base + Vector((0, 0.12, 0)), 0.5, 'y')     # between the feet


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
    low = plate_c + under - d * 0.15
    high = plate_c + under + d * (travel + 0.3)
    props = [plate] + sled(plate, plate_c, d, under) + bench(hip_y - 0.30, hip_y + 0.16, back_deg=back_deg, legs=False)
    for x in (-0.24, 0.24):
        props.append(E.round_tube("SledRail", low + Vector((x, 0, 0)), high + Vector((x, 0, 0)), 0.022,
                                  mat=E.metal_mat()))
        props.append(E.tube("RailBeam", low + Vector((x, 0, -0.06)), high + Vector((x, 0, -0.06)), 0.06, 0.09))
        props.append(E.tube("RailLeg", (x, high.y, 0.07), high + Vector((x, 0, -0.1)), 0.08, 0.08))
        props.append(E.tube("RailLeg", (x, low.y, 0.07), low + Vector((x, 0, -0.1)), 0.08, 0.08))
        props.append(E.tube("BaseRail", (x, high.y - 0.1, 0.05), (x, hip_y + 0.45, 0.05), 0.09, 0.07))
    for y in (high.y - 0.05, hip_y + 0.4):
        props.append(E.tube("BaseCross", (-0.3, y, 0.05), (0.3, y, 0.05), 0.08, 0.07))
    seat_low = BENCH_TOP - 0.11
    props.append(E.tube("SeatPost", (0, hip_y - 0.1, 0.08), (0, hip_y - 0.1, seat_low), 0.1, 0.1))
    props.append(E.tube("SeatPost", (0, hip_y + 0.3, 0.08), (0, hip_y + 0.3, seat_low + 0.15), 0.08, 0.08))
    return (drop, 0, lean), props


def sled(plate, c, d, under):
    """The leg press carriage under the footplate: side runners on the rails and a plate horn each side with
    two plates, all riding with the plate."""
    parts = []
    for sx in (1, -1):
        r = c + under + Vector((sx * 0.24, 0, 0))
        parts.append(E.tube("SledRunner", r - d * 0.22, r + d * 0.45, 0.07, 0.07))
        horn = r + d * 0.4                              # high on the carriage, the plates clear of the feet
        parts.append(E.round_tube("HornSleeve", horn, horn + Vector((sx * 0.14, 0, 0)), 0.034))
        parts.append(E.round_tube("Horn", horn + Vector((sx * 0.14, 0, 0)), horn + Vector((sx * 0.36, 0, 0)), 0.025,
                                  mat=E.metal_mat()))
        parts += E.plates("Plate", horn + Vector((sx * 0.15, 0, 0)), Vector((sx, 0, 0)), n=3, r=0.2)
    E.parent_keep(parts, plate)
    return parts


POSTURES["leg_press"] = leg_press


def prone_incline(p):
    """Chest down on an incline bench `incline` deg above level (chest-supported rows, spider curls, prone raises):
    hips at the pad's low end `hip_z` m up, legs reaching back to the balls of the feet on the floor."""
    a = math.radians(p.get("incline", 35))
    hip = A.rest_head("upperleg01.L")
    hz = p.get("hip_z", 0.86)
    lean = math.pi / 2 - a
    drop = hip.z - hz
    A.set_root(drop, 0, lean)
    leg = (A.rest_head("lowerleg01.L") - hip).length + (A.rest_head("foot.L") - A.rest_head("lowerleg01.L")).length
    hip_w = A.head("upperleg01.L")
    ankle_z = A.rest_head("foot.L").z + 0.05
    run = math.sqrt(max((leg * 0.96) ** 2 - (hip_w.z - ankle_z) ** 2, 0.01))
    A.plant_feet(toe_out_deg=4, ankles={s: (sx * 0.14, hip_w.y + run, ankle_z) for s, sx in SIDES})
    pitch_feet(50)                                      # up on the balls of the feet
    p["knees_point"] = {s: (0, -0.3, -1) for s, _ in SIDES}
    A.update()
    _, fwd, up = torso_frame()
    shoulders = (A.head("upperarm01.L") + A.head("upperarm01.R")) / 2
    mid = (hip_w + shoulders) / 2
    spine = (shoulders - hip_w).normalized()
    length = (shoulders - hip_w).length + p.get("pad_past", -0.02)
    centre = mid + fwd * 0.155 + spine * (p.get("pad_past", -0.02) / 2)
    tilt = math.atan2(spine.z, -spine.y)
    pad = box("InclinePad", (0.32, length, 0.07), centre, rot_x=-tilt)
    low = centre - spine * (length / 2) + fwd * 0.04
    high = centre + spine * (length * 0.3) + fwd * 0.04
    props = [pad, box("PadPost", (0.07, 0.07, low.z), (0, low.y, low.z / 2)),
             box("PadStrut", (0.06, 0.06, high.z), (0, high.y, high.z / 2)),
             box("PadFoot", (0.42, 0.07, 0.04), (0, low.y, 0.02)), box("PadFoot", (0.42, 0.07, 0.04), (0, high.y, 0.02))]
    return (drop, 0, lean), props


POSTURES["prone_incline"] = prone_incline


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


class Lines:
    """Elastic bands and chains (spec `lines`). Each line joins two ends; an end is `{"obj": "L"|"R"|"bar", "at":
    local offset}` (a hand's implement or the bar), `{"bone": name, "t": 0..1}` (a point along a bone), or
    `{"world": [x, y, z]}`, where x/y may be given relative to another end at frame 1 with `"under": <end>` (that
    end's floor point plus the world offset). Bands stretch straight between their ends; a chain (`"chain": true`,
    `"length"`) hangs from its top end and piles up on the floor in front."""

    BAND_R = 0.012
    LINK = 0.05

    def __init__(self, spec, gear):
        self.gear = gear
        self.items = []
        for i, ln in enumerate(spec.get("lines", [])):
            if ln.get("chain"):
                links = []
                for j in range(int(ln.get("length", 1.3) / self.LINK)):
                    bpy.ops.mesh.primitive_torus_add(major_radius=0.022, minor_radius=0.006, major_segments=16,
                                                     minor_segments=8)
                    o = bpy.context.object
                    o.name = f"Chain{i}"
                    o.rotation_mode = 'QUATERNION'
                    o.data.materials.append(A.STEEL)
                    links.append(o)
                self.items.append((ln, links))
            else:
                n = 1 + len(ln.get("via", []))          # a band bent round `via` points is several straight runs
                steel = ln.get("steel")                 # a rigid handle (V-bar) or steel cable instead of a band
                segs = [rod(f"Band{i}", (0, 0, 0), (0, 0, 1), ln.get("r", 0.014) if steel else self.BAND_R,
                            mat=A.STEEL if steel else rubber()) for _ in range(n)]
                self.items.append((ln, segs))
        self.fixed = {}
        self.posts = []

    def end(self, e, key):
        if "obj" in e:
            o = self.gear.bar if e["obj"] == "bar" else self.gear.h[e["obj"]]
            return o.matrix_world @ Vector(e.get("at", (0, 0, 0)))
        if "bone" in e:
            return A.head(e["bone"]).lerp(A.tail(e["bone"]), e.get("t", 0.5)) + Vector(e.get("off", (0, 0, 0)))
        if key not in self.fixed:                       # world ends are fixed at their frame-1 place
            v = Vector(e["world"])
            if "under" in e:
                ref = self.end(e["under"], key + "u")
                v = ref + v if e.get("rel") else Vector((ref.x + v.x, ref.y + v.y, v.z))
            self.fixed[key] = v
            if e.get("post"):                           # hung from a rack upright beside the anchor
                x = v.x + math.copysign(0.09, v.x) * (-1 if e.get("post") == "in" else 1)
                self.posts.append(box("RackPost", (0.07, 0.07, v.z + 0.05), (x, v.y, (v.z + 0.05) / 2)))
                self.posts.append(box("RackPeg", (abs(x - v.x) + 0.03, 0.03, 0.03), ((x + v.x) / 2, v.y, v.z)))
        return self.fixed[key]

    def key(self, fr):
        for i, (ln, o) in enumerate(self.items):
            if ln.get("chain"):
                self.key_chain(o, self.end(ln["a"], f"{i}a"), fr)
                continue
            pts = [ln["a"]] + ln.get("via", []) + [ln["b"]]
            pts = [self.end(e, f"{i}p{j}") for j, e in enumerate(pts)]
            for seg, a, b in zip(o, pts, pts[1:]):
                seg.location = (a + b) / 2
                seg.rotation_quaternion = (b - a).to_track_quat('Z', 'Y')
                seg.scale = (1, 1, (b - a).length)
                for path in ("location", "rotation_quaternion", "scale"):
                    seg.keyframe_insert(path, frame=fr)

    def key_chain(self, links, top, fr):
        lay = Vector((0, -1, 0))                     # the slack lies on the floor toward the camera side
        for j, o in enumerate(links):
            d = (j + 0.5) * self.LINK
            if d < top.z - 0.01:
                o.location = top - Vector((0, 0, d))
                q = Quaternion((1, 0, 0), math.pi / 2)  # ring plane vertical
            else:
                o.location = Vector((top.x, top.y, 0.008)) + lay * (d - top.z) * 0.55 + \
                    Vector(((j % 4 - 1.5) * 0.012, 0, 0))
                q = Quaternion()
            o.rotation_quaternion = q @ Quaternion((0, 0, 1), math.pi / 2 * (j % 2))
            o.keyframe_insert("location", frame=fr)
            o.keyframe_insert("rotation_quaternion", frame=fr)

    def meshes(self):
        return [m for _, o in self.items for m in o] + self.posts


SMITH_X = 0.6           # rails inside the inner collars (+-0.655), outside any grip


def smith_frame(bar):
    """Smith machine round a keyed bar: two upright rails at the bar's (fixed) depth, a carriage sleeve on each
    rail riding with the bar, a top beam and floor feet. Returns (framing meshes, other meshes)."""
    zs, ys = [], []
    for fr in range(1, A.LOOP + 1):
        A.scene.frame_set(fr)
        t = bar.matrix_world.translation
        zs.append(t.z)
        ys.append(t.y)
    y = sum(ys) / len(ys)
    top = max(2.1, max(zs) + 0.45)
    rails, sleeves = [], []
    for sx in (1, -1):
        x = sx * SMITH_X
        post_x = sx * (SMITH_X + 0.14)
        rails.append(E.round_tube("SmithRail", (x, y, 0.1), (x, y, top - 0.04), 0.02, mat=E.metal_mat()))
        for dy in (-0.16, 0.16):
            rails.append(E.tube("SmithPost", (post_x, y + dy, 0.07), (post_x, y + dy, top + 0.04), 0.08, 0.08))
            rails.append(E.tube("SmithArm", (x, y, top), (post_x, y + dy, top), 0.06, 0.06))
            rails.append(E.tube("SmithArm", (x, y, 0.1), (post_x, y + dy, 0.1), 0.06, 0.06))
        rails += E.foot("SmithFoot", (post_x, y, 0), 1.1, 'y')
        sleeve = E.tube("SmithSleeve", (x, y, -0.09), (x, y, 0.09), 0.065, 0.065)
        hook = E.tube("SmithHook", (x - sx * 0.04, y - 0.045, 0.02), (x - sx * 0.04, y - 0.1, 0.06), 0.025, 0.03)
        E.parent_keep([hook], sleeve)
        for fr, z in enumerate(zs, 1):
            sleeve.location.z = z
            sleeve.keyframe_insert("location", frame=fr)
        sleeve.location.z = zs[0]
        sleeve.keyframe_insert("location", frame=A.LOOP + 1)
        sleeves += [sleeve, hook]
    for dy in (-0.16, 0.16):
        rails.append(E.tube("SmithBeam", (-SMITH_X - 0.14, y + dy, top + 0.04), (SMITH_X + 0.14, y + dy, top + 0.04),
                            0.08, 0.08))
    return sleeves, rails


def bench_uprights(bar):
    """Press bench uprights: two posts outside the grip with J-hooks just under the lockout, set a hand's width
    toward the head so the bar racks behind where it is pressed."""
    top = None
    for fr in range(1, A.LOOP + 1):
        A.scene.frame_set(fr)
        t = bar.matrix_world.translation.copy()
        if top is None or t.z > top.z:
            top = t
    y, z = top.y + 0.1, top.z - A.BAR_R - 0.035
    parts = []
    for sx in (1, -1):
        x = sx * 0.6
        parts.append(E.tube("Upright", (x, y, 0.07), (x, y, z + 0.12), 0.07, 0.07))
        parts.append(E.tube("JHook", (x, y - 0.02, z), (x, y - 0.1, z), 0.05, 0.035))
        parts.append(E.tube("JLip", (x, y - 0.1, z), (x, y - 0.1, z + 0.045), 0.05, 0.02))
        parts += E.foot("UprightFoot", (x, y, 0), 0.55, 'y')
    parts.append(E.tube("UprightCross", (-0.6, y, 0.07), (0.6, y, 0.07), 0.07, 0.05))
    return parts


def bar_supports(bar, kind):
    """Blocks under the plates or rack pins under the bar at its lowest point, where the lift starts or touches."""
    low, fr_low = None, 1
    for fr in range(1, A.LOOP + 1):
        A.scene.frame_set(fr)
        t = bar.matrix_world.translation.copy()
        if low is None or t.z < low.z:
            low = t
    props = []
    if kind == "blocks":
        top = low.z - PLATE_R
        for sx in (1, -1):
            props.append(box("Block", (0.3, 0.5, top), (sx * 0.78, low.y, top / 2)))
    elif kind == "straps":                      # bar hung in strap loops from the rack's top beam
        top = 2.2
        for sx in (1, -1):
            props.append(box("RackPost", (0.07, 0.07, top), (sx * 0.62, low.y + 0.1, top / 2)))
            for dx in (-0.025, 0.025):
                props.append(rod("Strap", (sx * 0.55 + dx, low.y, top), (sx * 0.55, low.y, low.z - A.BAR_R - 0.01),
                                 0.012, mat=rubber()))
        props.append(box("RackBeam", (1.38, 0.07, 0.07), (0, low.y + 0.1, top)))
    else:
        top = low.z - A.BAR_R
        for sx in (1, -1):
            props.append(box("RackPost", (0.07, 0.07, max(top + 0.6, 1.9)), (sx * 0.62, low.y + 0.1,
                                                                             max(top + 0.6, 1.9) / 2)))
            props.append(box("RackPin", (0.04, 0.4, 0.04), (sx * 0.62, low.y, top - 0.02)))
    return props


class SmithLock:
    """Keeps a Smith bar on its vertical track: the bar's depth is pinned to frame 1. A bar in the hands just
    moves (the arms follow by IK); a bar on the back moves the body instead, so it stays on the shoulders."""

    def __init__(self, gear):
        self.gear, self.y = gear, None

    def apply(self, fr, body_shift):
        bar = self.gear.bar
        t = bar.matrix_world.translation
        if self.y is None:
            self.y = t.y
        dy = t.y - self.y
        if abs(dy) < 1e-5:
            return
        if isinstance(self.gear, BackBar):
            body_shift(-dy)
            self.gear.place(fr)
        else:
            m = bar.matrix_world.copy()
            m.translation.y = self.y
            bar.matrix_world = m
            A.update()


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
    if spec.get("arm", {}).get("pad"):                  # preacher: knees apart round the pad's stand
        spec["posture"].setdefault("knees_apart", 0.24)
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
        if names & {"shrug", "retract"}:
            keyed += ["clavicle.L", "clavicle.R"]
        if any(n.startswith(("hip", "knee")) for n in names):
            keyed += [f"{b}.{s}" for b in ("upperleg01", "lowerleg01") for s, _ in SIDES]
    heel = Heels() if body_keys and any("heel" in k for k in body_keys) else None

    shift = {"back": 0.0}

    def body(fr):
        if not body_keys:
            return
        k = body_pose(body_keys, ph(fr, "L"))
        if move:
            lean = move(k)
        else:
            lean = l0 + math.radians(k.get("lean", 0))
            A.set_root(d0 + k.get("drop", 0), b0 + k.get("back", 0) + shift["back"], lean)
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
        elif "retract" in k:                    # shoulder blades squeezed back (+) or reached forward (-)
            for s, sx in SIDES:
                A.rotate_local("clavicle." + s, (0, 0, 1), -sx * math.radians(k["retract"]))
        if heel:
            heel.set(k.get("heel", 0))
        A.update()

    def key_body(fr):
        A.key_bones(keyed, fr)
        if heel:
            heel.key(fr)

    body(1)
    A.update()
    for b in spec.get("spheres", []):          # exercise balls: static, placed off a joint at frame 1
        A.update()
        ref = A.head(b["bone"]).lerp(A.tail(b["bone"]), b.get("t", 0.5)) if "bone" in b else Vector((0, 0, 0))
        at = ref + Vector(b.get("off", (0, 0, 0)))
        if b.get("floor"):
            at.z = b["r"]
        if "x" in b:
            at.x = b["x"]
        props.append(solid_prop("Ball", at, b["r"]))
    rail_req = []
    for bp in spec.get("pads", []):             # pads riding on the body (hack-squat back pad, shoulder pads)
        A.update()
        bone = bp["bone"]
        c = A.head(bone).lerp(A.tail(bone), bp.get("t", 0.5))
        lat, fwd, up = torso_frame()
        o = bp.get("off", (0, -0.15, 0))
        c = c + lat * o[0] + fwd * o[1] + up * o[2]
        if bp.get("disc"):                      # a weight plate on the lap / hanging off a belt
            bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=bp["disc"], depth=0.035, location=c,
                                                rotation=(math.pi / 2 if bp.get("face_fwd") else 0, 0, 0))
            pad = bpy.context.object
            pad.data.materials.append(A.PLATE)
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
            follow = pad.constraints.new('COPY_LOCATION')     # follows the bone point, keeps its own tilt (the
            follow.target, follow.subtarget = A.rig, bone       # leg's IK twist would otherwise tip it on edge)
            follow.head_tail, follow.use_offset = bp.get("t", 0.5), True
            pad.location = c - A.head(bone).lerp(A.tail(bone), bp.get("t", 0.5))
            props.append(pad)
            continue
        pad = box("BodyPad", bp.get("size", (0.36, 0.08, 0.6)), c,
                  rot_x=math.atan2(-fwd.z, -fwd.y) if bp.get("tilt", True) else 0.0)
        A.update()
        attach(pad, bone)
        props.append(pad)
        if bp.get("rail"):                      # the sled's rails: fixed, behind the pad, from the floor up
            rail_req.append((pad, bp["rail"], fwd.copy()))
        if bone.startswith("upperleg") and spec["posture"]["type"] == "seat" and spec.get("implement") == "none" \
                and bp.get("size", (0.36,))[0] < 1.0:
            props += calf_machine(pad, bone)
    if spec.get("pad"):
        props.append(leg_pad(spec["pad"]))
        if spec["posture"]["type"] in ("seat", "prone") and not spec.get("pad_post") and \
                spec["posture"].get("pad_under") != "thighs":
            props += leg_lever(props[-1], props)
        if spec.get("pad_post"):                # a fixed hook pad (legs don't move): stand it on a post
            c = props[-1].matrix_world.translation
            props.append(box("PadPost", (0.06, 0.06, c.z), (0, c.y, c.z / 2)))
    for b in spec.get("boxes", []):
        if b.get("pad"):                        # an upholstered chest pad on its own post
            at = Vector(b["at"])
            props.append(E.cushion("ChestPad", b["size"], at, rot_x=math.radians(b.get("rot_x", 0))))
            props.append(E.tube("PadPost", (0, at.y - b["size"][1] / 2 - 0.05, 0.07),
                                (0, at.y - b["size"][1] / 2 - 0.05, at.z), 0.07, 0.07))
        else:
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
    elif impl == "plate":
        gear = HeldPlate(spec, arms, impl)
    elif impl == "frame":
        gear = HeldFrame(spec, arms, impl)
    elif impl == "lever":
        gear = LeverArms(spec, arms, impl)
        props += machine_frame(spec, gear, props)
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
    crouch = spec["posture"].get("_crouch_for_poles") and not spec["posture"].get("free_leg")
    if crouch:
        A.set_root(d0 + 0.25, b0, l0)            # straight legs give the knee no direction to score; bend them
    A.solve_pole_angles({s: arms.pole_dir(sx) for s, sx in SIDES}, spec["posture"].get("knees_point"))
    if crouch:
        A.set_root(d0, b0, l0)
        body(1)
    gear.place(1)
    if isinstance(gear, Bar):
        gear.finish_grip()
        gear.solve_rolls(body)
    else:
        gear.grip()
    lock = SmithLock(gear) if spec.get("smith") else None
    lines = Lines(spec, gear) if spec.get("lines") else None

    def shift_body(dy):
        shift["back"] += dy
        body(fr)

    for fr in range(1, A.LOOP + 2):
        A.scene.frame_set(fr)
        shift["back"] = 0.0
        body(fr)
        gear.place(fr)
        if lock:
            for _ in range(3):
                lock.apply(fr, shift_body)
        gear.key(fr)
        if lines:
            lines.key(fr)
        arms.key_poles(fr)
        if body_keys:
            key_body(fr)

    framed = gear.meshes() + props + (lines.meshes() if lines else [])
    if lock:
        sleeves, rails = smith_frame(gear.bar)
        framed += sleeves
    if spec.get("rests_on"):
        framed += bar_supports(gear.bar, spec["rests_on"])
    elif impl == "barbell" and not lock and spec["posture"]["type"] == "seat" and \
            spec["posture"].get("back_deg") is not None and spec["posture"]["back_deg"] < 60:
        framed += bench_uprights(gear.bar)
    for pad, length, fwd in rail_req:
        framed += hack_frame(pad, length, fwd)
    if os.environ.get("ATLAS_COLLIDE") == "1":
        import collide
        collide.check([o for o in bpy.data.objects if o.type == 'MESH' and o.name not in ("Human", "Shoes")],
                      range(1, A.LOOP + 1, 6))
        return
    A.report([1, 23, 45, 68])
    A.setup_render()
    cam_spec = spec.get("camera", {})
    cam = A.main_camera(framed, az_deg=cam_spec.get("az", 35), el_deg=cam_spec.get("el", 6))
    mid = spec.get("bottom", 40) + 2
    hands = A.closeup_camera("L", 1, offset=(0.14, -0.45, 0.12), lens=70)
    extra = [("handsmid", A.closeup_camera("L", mid, offset=(0.14, -0.45, 0.12), lens=70)),
             ("handsback", A.closeup_camera("L", mid, offset=(0.3, 0.4, 0.15), lens=70))]
    A.finish(spec["slug"], cam, hands, mid_frame=mid, extra_cams=extra)


if __name__ == "__main__":
    build(load(A.ARGS[0]))
