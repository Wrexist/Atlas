# Spec-driven exercise builder on top of atlas_rig: a posture (standing, seated, incline, lying), an implement, and
# arm key poses given as segment directions in the torso's frame. One spec per exercise in specs/<slug>.json.
# blender -b human.blend -P kit.py -- <slug> [--preview] [--stills] [--anim]
import bpy, json, math, sys, os
import numpy as np
from mathutils import Vector, Matrix, Quaternion
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_rig as A

HERE = os.path.dirname(os.path.abspath(__file__))
SIDES = (("L", 1), ("R", -1))
BENCH_TOP = 0.45


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


def bench(seat_y0, seat_y1, back_deg=None, back_len=0.85, top=BENCH_TOP):
    """Flat pad from y0 to y1 (y1 > y0 is behind the figure) + optional backrest hinged at y1, `back_deg` from the
    floor. Returns the props."""
    props = [box("BenchSeat", (0.30, seat_y1 - seat_y0, 0.07), (0, (seat_y0 + seat_y1) / 2, top - 0.035))]
    if back_deg is not None:
        a = math.radians(back_deg)
        d = Vector((0, math.cos(a), math.sin(a)))
        c = Vector((0, seat_y1, top)) + d * (back_len / 2) + Vector((0, -math.sin(a), math.cos(a))) * -0.035
        props.append(box("BenchBack", (0.30, back_len, 0.07), c, rot_x=a))
        foot = Vector((0, seat_y1, top)) + d * back_len * 0.8
        props.append(box("BenchStrut", (0.06, 0.06, foot.z), (0, foot.y, foot.z / 2)))
    for y in (seat_y0 + 0.08, seat_y1 - 0.04):
        props.append(box("BenchLeg", (0.06, 0.06, top - 0.07), (0, y, (top - 0.07) / 2)))
        props.append(box("BenchFoot", (0.40, 0.07, 0.04), (0, y, 0.02)))
    return props


# ---------------------------------------------------------------- postures
def torso_frame():
    """(lateral toward the figure's left, forward out of the chest, up the spine) in world space."""
    up = (A.head("spine01") - A.head("spine05")).normalized()
    lat = A.head("upperarm01.L") - A.head("upperarm01.R")
    lat = (lat - lat.dot(up) * up).normalized()
    fwd = lat.cross(up)
    return lat, fwd, up


def stand(p):
    A.plant_feet(toe_out_deg=p.get("toe_out", 8))
    A.set_root(0, 0, math.radians(p.get("lean", 0)))
    return []


def seat(p):
    """Sitting on a flat bench (or the seat of an incline bench), thighs level, feet under the knees."""
    hip = A.rest_head("upperleg01.L")
    thigh = (A.rest_head("lowerleg01.L") - hip).length
    drop = hip.z - (BENCH_TOP + 0.105)
    lean = math.radians(p.get("lean", 0))
    back_deg = p.get("back_deg")
    if back_deg is not None:                           # lying back against the pad
        lean = -math.radians(90 - back_deg)
    width = p.get("knees_apart", 0.2)
    ankles = {s: (sx * width, hip.y - thigh * 0.98, A.rest_head("foot.L").z) for s, sx in SIDES}
    A.plant_feet(toe_out_deg=12, ankles=ankles)
    for s, sx in SIDES:
        bpy.data.objects["KneePole." + s].location = (sx * width * 1.3, hip.y - thigh, 1.2)
    A.set_root(drop, 0, lean)
    hip_y = A.head("upperleg01.L").y
    seat_back = hip_y + 0.16
    return bench(hip_y - 0.22 if back_deg is None else hip_y - 0.30, seat_back,
                 back_deg=back_deg if back_deg is not None else p.get("backrest"))


POSTURES = {"stand": stand, "seat": seat}


# ---------------------------------------------------------------- arm key poses
def tdir(v, sx):
    """Torso-frame direction (out, forward, up) -> world, mirrored for the right side."""
    lat, fwd, up = torso_frame()
    return (lat * (v[0] * sx) + fwd * v[1] + up * v[2]).normalized()


def slerp_dir(a, b, t):
    a, b = Vector(a).normalized(), Vector(b).normalized()
    ang = a.angle(b) if a.dot(b) < 0.99999 else 0.0
    if ang < 1e-5:
        return a.lerp(b, t).normalized()
    return ((math.sin((1 - t) * ang) * a + math.sin(t * ang) * b) / math.sin(ang)).normalized()


def arm_pose(keys, t):
    """Interpolate key poses (each {upper, fore, thumb} torso-frame directions) at phase t in [0, 1]."""
    if len(keys) == 1:
        return keys[0]
    n = len(keys) - 1
    x = min(t * n, n - 1e-9)
    i = int(x)
    u = A.ease(x - i)
    return {k: slerp_dir(keys[i][k], keys[i + 1][k], u) for k in ("upper", "fore", "thumb")}


def wrist_target(s, sx, pose):
    upper, fore = A.arm_lengths(s)
    shoulder = A.head("upperarm01." + s)
    U, F = tdir(pose["upper"], sx), tdir(pose["fore"], sx)
    elbow = shoulder + U * upper * 0.995
    wrist = elbow + F * fore * 0.995
    thumb = tdir(pose["thumb"], sx)
    return elbow, wrist, F, thumb


# ---------------------------------------------------------------- two-hand bar
HAND_TO_HANDLE = 0.085          # wrist joint to the handle axis along the fingers (closed grip)


def ezbar(h):
    """Short curl bar: 1.2 m shaft, a 10 kg plate each side."""
    A.cylinder(h, A.BAR_R, 0.95, mat=A.STEEL, verts=48)
    for sx in (1, -1):
        A.cylinder(h, 0.03, 0.03, x=sx * 0.49, mat=A.STEEL)
        A.cylinder(h, 0.025, 0.13, x=sx * 0.56, mat=A.STEEL)
        A.cylinder(h, 0.17, 0.035, x=sx * 0.53, mat=A.PLATE, verts=96, bevel=0.006)


def bar_frame():
    lat, fwd, up = torso_frame()
    return Matrix((lat, -fwd, up)).transposed()


def build_bar(spec, keys, ph, impl):
    """Both hands on one bar: the bar centre follows the mean of the two hands' key-pose positions, the grip width
    stays fixed, and the bar rolls frame by frame (smoothed) to keep the wrists straight."""
    bar = A.holder("Bar")
    (A.barbell if impl == "barbell" else ezbar)(bar)
    gx = spec["arm"].get("grip", 0.22)
    palm = spec["arm"].get("palm", (0, -1, 0))           # palm-to-bar direction in the bar frame at the first key
    tsign = 1 if keys[0]["thumb"][0] > 0 else -1         # thumbs out (underhand) or in (overhand)
    A.ik_arms(bar, {s: (sx * 0.4, 0.6, 0.9) for s, sx in SIDES}, poles_in_world=True)

    def centre(fr):
        pts = []
        for s, sx in SIDES:
            elbow, wrist, F, _ = wrist_target(s, sx, arm_pose(keys, ph(fr, s)))
            pts.append(wrist + F * HAND_TO_HANDLE)
        return (pts[0] + pts[1]) / 2

    def fore_dir(fr):
        return sum((wrist_target(s, sx, arm_pose(keys, ph(fr, s)))[2] for s, sx in SIDES), Vector()).normalized()

    f1 = fore_dir(1)

    def place(fr):
        """Bar at the hands, rolled with the forearms so the grip turns round the bar as the arms swing."""
        lat = torso_frame()[0]
        a, b = f1 - f1.dot(lat) * lat, fore_dir(fr)
        b = b - b.dot(lat) * lat
        ang = a.angle(b) if a.length > 1e-6 and b.length > 1e-6 else 0.0
        if a.cross(b).dot(lat) < 0:
            ang = -ang
        m = bar_frame() @ Matrix.Rotation(ang, 3, 'X')
        m = m.to_4x4()
        m.translation = centre(fr)
        bar.matrix_world = m
        for s, sx in SIDES:
            elbow, _, _, _ = wrist_target(s, sx, arm_pose(keys, ph(fr, s)))
            bpy.data.objects["ElbowPole." + s].location = elbow + tdir(spec["arm"].get("elbow_out", (1, 0, 0)), sx) * 0.5
        A.update()

    place(1)
    for s, sx in SIDES:
        A.grip_on(s, bar, (sx * gx, 0, 0), thumbward=(sx * tsign, 0, 0), palm_to_handle=palm)
    A.update()
    A.solve_pole_angles({s: tdir(spec["arm"].get("elbow_out", (1, 0, 0)), sx) for s, sx in SIDES})
    for s, sx in SIDES:
        A.grip_neutral(s, bar, (sx * gx, 0, 0), thumbward=(sx * tsign, 0, 0), palm_guess=palm)
    for s, _ in SIDES:
        A.seat_palm(s)
    for s, _ in SIDES:
        A.wrap_hand(s)
    rolls = []
    for fr in range(1, A.LOOP + 1):
        A.scene.frame_set(fr)
        place(fr)
        rolls.append(A.roll_neutral(bar, span=25))
    rolls = A.smooth(np.array(rolls, float), 3.0, loop=True)
    for fr in range(1, A.LOOP + 2):
        A.scene.frame_set(fr)
        place(fr)
        A.roll_holder(bar, rolls[(fr - 1) % A.LOOP])
        A.key_holder(bar, fr)
        for s, _ in SIDES:
            bpy.data.objects["ElbowPole." + s].keyframe_insert("location", frame=fr)
    return [o for o in bar.children if o.type == 'MESH']


# ---------------------------------------------------------------- build
def load(slug):
    with open(os.path.join(HERE, "specs", slug + ".json")) as f:
        spec = json.load(f)
    spec.setdefault("slug", slug)
    return spec


def phases(spec):
    """Per-frame phase: one rep (0 -> 1 -> 0), or two alternating reps (each arm once) when `alternate`."""
    hold = spec.get("hold", 4)
    if spec.get("alternate"):
        half = A.LOOP // 2

        def ph(fr, s):
            local = (fr - 1) % A.LOOP
            mine = local < half if s == "L" else local >= half
            if not mine:
                return 0.0
            f = local % half
            return A.rep_phase(1 + int(f * A.LOOP / half), bottom=spec.get("bottom", 40), hold=hold)
        return ph
    return lambda fr, s: A.rep_phase(fr, bottom=spec.get("bottom", 40), hold=hold)


def build(spec):
    A.setup()
    A.train(primary=spec["primary"], secondary=spec.get("secondary", []))
    props = POSTURES[spec["posture"]["type"]](spec["posture"])
    A.update()
    impl = spec.get("implement", "dumbbell")
    keys = spec["arm"]["keys"]
    sides = [s for s in SIDES if spec["arm"].get("sides", "both") in ("both", s[0])]
    ph = phases(spec)
    equipment = []

    if impl == "dumbbell":
        bells = {s: A.holder("Dumbbell." + s) for s, _ in SIDES}
        for h in bells.values():
            A.dumbbell(h)
        A.ik_arms(bells, {s: (sx * 0.4, 0.6, 0.9) for s, sx in SIDES}, poles_in_world=True)
        for s, _ in SIDES:
            A.grip_on(s, bells[s], (0, 0, 0), thumbward=(1, 0, 0), palm_to_handle=(0, 0, 1), radius=A.DB_R)
        A.update()
        rest = spec["arm"].get("rest", keys[0])

        def place(fr):
            for s, sx in SIDES:
                active = (s, sx) in sides
                pose = arm_pose(keys, ph(fr, s)) if active else rest
                elbow, wrist, F, thumb = wrist_target(s, sx, pose)
                bpy.data.objects["ElbowPole." + s].location = elbow + (elbow - A.head("upperarm01." + s)) * 0.1 \
                    + tdir(spec["arm"].get("elbow_out", (1, 0, 0)), sx) * 0.5
                bells[s].matrix_world = A.holder_for_hand(s, wrist, F, thumb)
            A.update()
            for s, _ in SIDES:
                A.straighten_wrist(s, bells[s])

        place(1)
        A.solve_pole_angles({s: tdir(spec["arm"].get("elbow_out", (1, 0, 0)), sx) for s, sx in SIDES})
        place(1)
        for s, _ in SIDES:
            A.seat_palm(s)
        for s, _ in SIDES:
            A.wrap_hand(s)
        for fr in range(1, A.LOOP + 2):
            A.scene.frame_set(fr)
            place(fr)
            for s, _ in SIDES:
                A.key_holder(bells[s], fr)
                bpy.data.objects["ElbowPole." + s].keyframe_insert("location", frame=fr)
        equipment = [o for h in bells.values() for o in h.children if o.type == 'MESH']
    elif impl in ("barbell", "ezbar"):
        equipment = build_bar(spec, keys, ph, impl)
    else:
        raise SystemExit(f"implement {impl} not supported yet")

    A.report([1, 23, 45, 68])
    A.setup_render()
    cam_spec = spec.get("camera", {})
    cam = A.main_camera(equipment + props, az_deg=cam_spec.get("az", 35), el_deg=cam_spec.get("el", 6))
    hands = A.closeup_camera("L", 1, offset=(0.14, -0.45, 0.12), lens=70)
    A.finish(spec["slug"], cam, hands, mid_frame=spec.get("bottom", 40) + 2)


if __name__ == "__main__":
    build(load(A.ARGS[0]))
