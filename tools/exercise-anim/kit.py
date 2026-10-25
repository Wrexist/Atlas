# Spec-driven exercise builder on top of atlas_rig, so 873 clips don't each need a hand-written script.
# A spec (specs/<slug>.json) gives a posture, optional whole-body key poses, an implement, and arm key poses as
# segment directions; everything is interpolated over one rep and keyed.
# blender -b human.blend -P kit.py -- <slug> [--preview] [--stills] [--anim]
import bpy, json, math, sys, os
import numpy as np
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_rig as A

HERE = os.path.dirname(os.path.abspath(__file__))
SIDES = (("L", 1), ("R", -1))
BENCH_TOP = 0.45
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


def interp(keys, t, fn):
    """Eased piecewise interpolation of key poses at phase t in [0, 1]."""
    if len(keys) == 1:
        return keys[0]
    n = len(keys) - 1
    x = min(max(t, 0.0) * n, n - 1e-9)
    i = int(x)
    return fn(keys[i], keys[i + 1], A.ease(x - i))


def arm_pose(keys, t):
    return interp(keys, t, lambda a, b, u: {k: slerp_dir(a[k], b[k], u) for k in ("upper", "fore", "thumb")})


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
        self.ph = ph

    def pose(self, fr, s):
        return arm_pose(self.keys, self.ph(fr, s)) if s in self.active else self.rest

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
    return (0, 0, math.radians(p.get("lean", 0))), []


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
    A.plant_feet(toe_out_deg=6, ankles={s: (sx * 0.15, hip.y - run * 0.99, ankle_z) for s, sx in SIDES},
                 knee_up=1.0)
    for s, sx in SIDES:
        bpy.data.objects["KneePole." + s].location = (sx * 0.25, hip.y - run / 2, 1.2)
    p["knees_point"] = {s: (sx * 0.2, 0, 1) for s, sx in SIDES}
    return (drop, 0, -math.pi / 2), []


POSTURES = {"stand": stand, "seat": seat, "floor_supine": floor_supine}


# ---------------------------------------------------------------- implements
class PerHand:
    """One object per hand (dumbbell, kettlebell, cable handle): placed at the hand's key-pose wrist, wrist kept
    neutral."""

    def __init__(self, spec, arms, impl):
        self.arms, self.impl = arms, impl
        self.h = {s: A.holder(f"{impl}.{s}") for s, _ in SIDES}
        for s, h in self.h.items():
            if impl == "kettlebell":
                kettlebell(h, s)
            elif impl in ("cable", "cable_handle"):
                cable_handle(h)
            else:
                A.dumbbell(h)
        self.radius = A.DB_R
        A.ik_arms(self.h, {s: (sx * 0.4, 0.6, 0.9) for s, sx in SIDES}, poles_in_world=True)
        for s, _ in SIDES:
            A.grip_on(s, self.h[s], (0, 0, 0), thumbward=(1, 0, 0), palm_to_handle=(0, 0, 1), radius=self.radius)
        self.cables = Cables(spec, {s: self.h[s] for s, _ in SIDES}) if impl.startswith("cable") else None

    def place(self, fr):
        for s, sx in SIDES:
            _, wrist, F, thumb = self.arms.target(fr, s, sx)
            self.h[s].matrix_world = A.holder_for_hand(s, wrist, F, thumb)
        self.arms.set_poles(fr)
        A.update()
        for s, _ in SIDES:
            A.straighten_wrist(s, self.h[s])

    def grip(self):
        for s, _ in SIDES:
            A.seat_palm(s)
        for s, _ in SIDES:
            A.wrap_hand(s)

    def key(self, fr):
        for h in self.h.values():
            A.key_holder(h, fr)
        if self.cables:
            self.cables.key(fr)

    def meshes(self):
        return [o for h in self.h.values() for o in h.children if o.type == 'MESH'] + \
               (self.cables.meshes() if self.cables else [])


def kettlebell(h, s):
    """Handle along the holder's X axis, bell hanging beyond the fingers."""
    A.cylinder(h, A.DB_R, 0.13, mat=A.STEEL, verts=48)
    f = A.frame_from(s, (1, 0, 0), (0, 0, 1)).col[0]
    for sx in (1, -1):
        post = A.cylinder(h, 0.016, 0.07, mat=A.PLATE, verts=32)
        post.matrix_parent_inverse = Matrix.Identity(4)
        post.matrix_basis = Matrix.Translation(Vector((sx * 0.065, 0, 0)) + f * 0.035) @ \
            f.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.1, segments=48, ring_count=24, location=(0, 0, 0))
    bell = bpy.context.object
    bell.data.materials.append(A.PLATE)
    bpy.ops.object.shade_smooth()
    bell.parent = h
    bell.matrix_parent_inverse = Matrix.Identity(4)
    bell.location = f * 0.15


def cable_handle(h):
    A.cylinder(h, A.DB_R, 0.12, mat=A.PLATE, verts=48)


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


# ---------------------------------------------------------------- build
def load(slug):
    with open(os.path.join(HERE, "specs", slug + ".json")) as f:
        spec = json.load(f)
    spec.setdefault("slug", slug)
    return spec


def phases(spec):
    """Per-frame phase per side: one rep (0 -> 1 -> 0), or one rep per arm in turn when `alternate`."""
    bottom, hold = spec.get("bottom", 40), spec.get("hold", 4)
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

    def body(fr):
        if not body_keys:
            return
        k = body_pose(body_keys, ph(fr, "L"))
        lean = l0 + math.radians(k.get("lean", 0))
        A.set_root(d0 + k.get("drop", 0), b0 + k.get("back", 0), lean)
        A.rotate_local("neck01", (1, 0, 0), -head_level * (lean - l0))
        A.update()

    body(1)
    A.update()
    impl = spec.get("implement", "dumbbell")
    arms = Arms(spec, ph)
    gear = Bar(spec, arms, impl) if impl in ("barbell", "ezbar", "cable_bar") else PerHand(spec, arms, impl)
    props += gear.cables.props if gear.cables else []

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
            A.key_bones(["root", "neck01"], fr)

    A.report([1, 23, 45, 68])
    A.setup_render()
    cam_spec = spec.get("camera", {})
    cam = A.main_camera(gear.meshes() + props, az_deg=cam_spec.get("az", 35), el_deg=cam_spec.get("el", 6))
    hands = A.closeup_camera("L", 1, offset=(0.14, -0.45, 0.12), lens=70)
    A.finish(spec["slug"], cam, hands, mid_frame=spec.get("bottom", 40) + 2)


if __name__ == "__main__":
    build(load(A.ARGS[0]))
