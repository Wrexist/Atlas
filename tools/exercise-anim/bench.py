# Flat barbell bench press: lying on a black bench, feet flat, bar from lockout to the lower chest.
# blender -b human.blend -P bench.py -- [--preview] [--stills] [--anim]
import bpy, math, sys, os
import numpy as np
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_rig as A

BENCH_TOP = 0.45
REGRIP_EVERY = 10
GRIP_X = 0.41                  # a bit wider than the shoulders: forearms vertical at the bottom
CHEST_Z_REST = 1.30            # lower chest (rest height on the standing figure)

A.setup()
A.train(primary=["chest"], secondary=["front_delts", "triceps"])
P, D = A.P, A.D

# ---- lay the figure supine along +y, head away from the camera side
co = np.array([v.co for v in A.body.data.vertices])
torso = A.body_mask & (np.abs(co[:, 0]) < 0.15) & (co[:, 2] > 0.85) & (co[:, 2] < 1.55)
back_y = co[torso, 1].max()                                   # most-protruding back/glute skin
A.rig.matrix_world = Matrix.Translation((0, -1.0, BENCH_TOP + back_y)) @ Matrix.Rotation(-math.pi / 2, 4, 'X')
A.update()


def box(name, size, loc, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    b = o.modifiers.new("bevel", 'BEVEL')
    b.width, b.segments = 0.012, 3
    o.data.materials.append(mat)
    return o


hip_y = (A.rig.matrix_world @ A.rest_head("upperleg01.L")).y
bench = [box("BenchPad", (0.30, 1.32, 0.07), (0, hip_y + 0.43, BENCH_TOP - 0.035), A.BLACK),        # glutes well on the pad
         box("BenchFrame", (0.08, 1.0, 0.06), (0, hip_y + 0.48, BENCH_TOP - 0.10), A.BLACK)]
for y in (hip_y - 0.12, hip_y + 0.98):
    bench.append(box("BenchLeg", (0.06, 0.06, BENCH_TOP - 0.13), (0, y, (BENCH_TOP - 0.13) / 2), A.BLACK))
    bench.append(box("BenchFoot", (0.42, 0.07, 0.04), (0, y, 0.02), A.BLACK))

# ---- feet planted on the floor in front of the bench, knees bent
ankle_h = A.rest_head("foot.L").z
A.plant_feet(toe_out_deg=8, ankles={"L": (0.17, hip_y - 0.42, ankle_h), "R": (-0.17, hip_y - 0.42, ankle_h)})   # under the knees
for s, sx in (("L", 1), ("R", -1)):
    bpy.data.objects["KneePole." + s].location = (sx * 0.19, hip_y - 0.45, 1.3)   # knees up over the feet, shoulder-width

bar = A.holder("Bar")
A.barbell(bar)
A.ik_arms(bar, {"L": (0.5, -0.45, -0.55), "R": (-0.5, -0.45, -0.55)})     # elbows ~60 deg from the torso
arm_len = sum(A.arm_lengths("L"))


def shoulder():
    return (A.head("upperarm01.L") + A.head("upperarm01.R")) / 2


def place(pos):
    bar.matrix_world = Matrix.Translation(pos)
    A.update()


def bisect(f, lo, hi, n=22):
    for _ in range(n):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if f(mid) > 0 else (lo, mid)
    return (lo + hi) / 2


def reach_slack():
    d = [(A.hand_targets[s].matrix_world.translation - A.head("upperarm01." + s)).length for s in ("L", "R")]
    return 0.99 * arm_len - sum(d) / 2


# head resting on the pad: tip the neck back until the skull touches it
skull = (A.group_weights(A.body, ["head"]) > 0.5) & A.body_mask


def head_gap(angle):
    A.rotate_local("neck01", (1, 0, 0), angle)
    A.update()
    return A.world_coords(A.body)[skull, 2].min() - BENCH_TOP - 0.002


if head_gap(0) > 0.002:
    head_gap(bisect(lambda a: -head_gap(a), -0.6, 0.0, n=14))

# ---- grip at lockout: bar over the shoulders on straight arms
s0 = shoulder()
lock_y = s0.y
place(Vector((0, lock_y, s0.z + 0.6)))
for s, sx in (("L", 1), ("R", -1)):
    A.grip_on(s, bar, (sx * GRIP_X, 0, 0), thumbward=(-sx, 0, 0), palm_to_handle=(0, -0.55, 0.83), slide=0.03)
A.update()
lock_z = bisect(lambda z: (place(Vector((0, lock_y, z))), reach_slack())[1], s0.z + 0.2, s0.z + 1.0)
place(Vector((0, lock_y, lock_z)))
A.solve_pole_angles({"L": (0.8, -1.0, -0.6), "R": (-0.8, -1.0, -0.6)}, {"L": (0.2, -0.3, 1), "R": (-0.2, -0.3, 1)})
for s, sx in (("L", 1), ("R", -1)):
    A.grip_neutral(s, bar, (sx * GRIP_X, 0, 0), thumbward=(-sx, 0, 0), palm_guess=(0, -0.55, 0.83), slide=0.03)
for s in ("L", "R"):
    A.seat_palm(s)
for s in ("L", "R"):
    A.wrap_hand(s)

# ---- touch point on the lower chest
chest_y = (A.rig.matrix_world @ Vector((0, 0, CHEST_Z_REST))).y
c = A.world_coords(A.body)
strip = A.body_mask & (np.abs(c[:, 0]) < 0.06) & (np.abs(c[:, 1] - chest_y) < 0.02)
touch_z = c[strip, 2].max() + A.BAR_R + 0.003
print(f"BENCH lockout z {lock_z:.3f} over shoulders y {lock_y:.3f}; touch z {touch_z:.3f} at y {chest_y:.3f}")

for fr in range(1, A.LOOP + 2):
    A.scene.frame_set(fr)
    t = A.rep_phase(fr, bottom=44, hold=3)
    # slight J-curve: the bar drifts toward the chest late in the descent
    y = lock_y + (chest_y - lock_y) * (t ** 0.8)
    z = lock_z + (touch_z - lock_z) * t
    place(Vector((0, y, z)))
    A.key_holder(bar, fr)
    if (fr - 1) % REGRIP_EVERY == 0:             # hands re-solved on these frames, interpolated between
        for s, sx in (("L", 1), ("R", -1)):
            A.regrip(s, bar, (sx * GRIP_X, 0, 0), thumbward=(-sx, 0, 0), palm_guess=(0, -0.55, 0.83), slide=0.03)
            A.key_hand(s, fr)
A.report([1, 3, 25, 46, 48, 70, 88])
A.scene.frame_set(46)
fore = A.head("wrist.L") - A.head("lowerarm01.L")
print(f"BENCH bottom: forearm tilt {math.degrees(math.atan2(fore.x, fore.z)):.0f} deg out, "
      f"{math.degrees(math.atan2(fore.y, fore.z)):.0f} deg headward")

A.setup_render()
cam = A.main_camera([o for o in bar.children if o.type == 'MESH'] + bench, az_deg=56, el_deg=37)   # side-front, high: chest + bar path clear of the near plate
hands = A.closeup_camera("L", 46, offset=(-0.2, -0.38, 0.3), lens=70)
under = A.closeup_camera("L", 1, offset=(0.2, -0.12, -0.3), lens=70)         # from below the bar
A.finish("bench", cam, hands, mid_frame=46, extra_cams=[("under", under)])
