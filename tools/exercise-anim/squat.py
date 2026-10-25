# Barbell back squat (high bar), Atlas clay style.
# blender -b human.blend -P squat.py -- [--preview] [--stills] [--anim]
import bpy, math, sys, os
import numpy as np
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_rig as A

GRIP_X = 0.36                 # hand centre, just outside the deltoids: elbows can point down under the bar
REGRIP_EVERY = 45            # the squat hand barely changes over the rep: re-solve at top, bottom, top
SHIN_DEG = 34                 # shin angle at the bottom (knees track forward over the toes)
LEAN_STAND = math.radians(3)

A.setup()
A.train(primary=["quads"], secondary=["glutes", "hamstrings", "calves", "lower_back"])
P, D = A.P, A.D
bar = A.holder("Bar")
A.barbell(bar)
A.plant_feet(toe_out_deg=12)
A.ik_arms(bar, {"L": (0.55, 0.45, -0.75), "R": (-0.55, 0.45, -0.75)})


def pose(drop, back, lean):
    A.set_root(drop, back, lean)
    A.rotate_local("neck01", (1, 0, 0), -0.95 * lean)     # neutral neck, eyes forward
    A.update()
    bar.matrix_world = A.rig.matrix_world @ P["spine01"].matrix @ SPINE_TO_BAR
    A.update()


def bar_on_traps():
    """Bar centre on the upper traps, just below C7, pushed back until it rests on the skin."""
    co = A.world_coords(A.body)
    co = co[A.body_mask & (np.abs(co[:, 0]) < 0.24)]
    sp = A.rig.matrix_world @ P["spine01"].matrix
    up = (sp.to_3x3() @ Vector((0, 1, 0))).normalized()
    back = Vector((0, 1, 0))
    back = (back - back.dot(up) * up).normalized()
    base = A.head("neck01") - up * 0.055
    rel = co - np.array(base)
    u, b = rel @ np.array(up), rel @ np.array(back)
    best = 0.3
    for k in range(300, -100, -1):
        yb = k * 0.001
        if (np.sqrt((b - yb) ** 2 + u ** 2) < A.BAR_R - 0.004).any():   # ~4 mm of trap compression
            break
        best = yb
    print("BAR on traps at", tuple(round(c, 3) for c in base + back * best))
    return sp.inverted() @ Matrix.Translation(base + back * best)


# ---- standing: bar placement, grip
SPINE_TO_BAR = Matrix.Identity(4)
A.set_root(0, 0, LEAN_STAND)
SPINE_TO_BAR = bar_on_traps()
pose(0, 0, LEAN_STAND)
for s, sx in (("L", 1), ("R", -1)):
    A.grip_on(s, bar, (sx * GRIP_X, 0, 0), thumbward=(-sx, 0, 0), palm_to_handle=(0, -1, 0.3), square=True)
A.update()
A.set_root(0.3, 0.1, 0.3)                      # bend the legs so knee pole angles are well defined
A.solve_pole_angles({"L": (0.4, 0.5, -1), "R": (-0.4, 0.5, -1)},
                    {"L": (0.3, -1, 0), "R": (-0.3, -1, 0)})
pose(0, 0, LEAN_STAND)
for s, sx in (("L", 1), ("R", -1)):
    A.grip_neutral(s, bar, (sx * GRIP_X, 0, 0), thumbward=(-sx, 0, 0), palm_guess=(0, -1, 0.3), square=True)
for s in ("L", "R"):
    A.seat_palm(s)

# ---- bottom: thighs parallel, shins at SHIN_DEG, bar over midfoot
midfoot_y = float(np.mean([(A.head("foot." + s) + A.head("toe3-1." + s)).y / 2 for s in ("L", "R")]))
ankle_y = A.head("foot.L").y
shin_len = (A.head("lowerleg01.L") - A.head("foot.L")).length


def legs(drop, back, lean):
    pose(drop, back, lean)
    return A.head("upperleg01.L").z - A.head("lowerleg01.L").z, ankle_y - A.head("lowerleg01.L").y


def bisect(f, lo, hi, n=20):
    """Root of a function that is positive at lo and negative at hi."""
    for _ in range(n):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if f(mid) > 0 else (lo, mid)
    return (lo + hi) / 2


def depth(back, lean):
    return bisect(lambda d: legs(d, back, lean)[0], 0.2, 0.9)


knee_fwd_want = shin_len * math.sin(math.radians(SHIN_DEG))
back, lean = 0.2, math.radians(30)
for _ in range(4):
    back = bisect(lambda b: legs(depth(b, lean), b, lean)[1] - knee_fwd_want, 0.0, 0.5)
    drop = depth(back, lean)

    def bar_ahead(l):
        pose(drop, back, l)
        return bar.matrix_world.translation.y - midfoot_y
    lean = bisect(bar_ahead, 0.0, 1.2)
drop = depth(back, lean)
dz, kf = legs(drop, back, lean)
print(f"BOTTOM drop {drop:.3f} back {back:.3f} lean {math.degrees(lean):.1f} deg, hip-knee {dz * 1000:.0f} mm, "
      f"knee fwd {kf:.3f} (want {knee_fwd_want:.3f}), bar y {bar.matrix_world.translation.y:.3f} "
      f"vs midfoot {midfoot_y:.3f}")
DROP, BACK, LEAN = drop, back, lean

# ---- fingers (the hand is rigid on the bar for the whole rep)
pose(0, 0, LEAN_STAND)
for s in ("L", "R"):
    A.wrap_hand(s)

# ---- keys
for fr in range(1, A.LOOP + 2):
    A.scene.frame_set(fr)
    t = A.rep_phase(fr)
    pose(DROP * t, BACK * t, LEAN_STAND + (LEAN - LEAN_STAND) * t)
    A.key_bones(["root", "neck01"], fr)
    A.key_hip(fr)
    A.key_holder(bar, fr)
    if (fr - 1) % REGRIP_EVERY == 0:             # hands re-solved on these frames, interpolated between
        for s, sx in (("L", 1), ("R", -1)):
            A.regrip(s, bar, (sx * GRIP_X, 0, 0), thumbward=(-sx, 0, 0), palm_guess=(0, -1, 0.3))
            A.key_hand(s, fr)
A.report([1, 23, 45, 70])

A.setup_render()
plates = [o for o in bar.children if o.type == 'MESH']
cam = A.main_camera(plates)
hands = A.closeup_camera("L", 1, offset=(-0.12, 0.55, 0.32), lens=70)
under = A.closeup_camera("L", 1, offset=(0.44, 0.27, -0.34), lens=70)        # from below the bar, outside the arm
A.finish("squat", cam, hands, mid_frame=45, extra_cams=[("under", under)])
