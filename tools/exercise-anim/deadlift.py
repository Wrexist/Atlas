# Conventional barbell deadlift, overhand grip just outside the knees, bar close to the shins.
# blender -b human.blend -P deadlift.py -- [--preview] [--stills] [--anim]
import bpy, math, sys, os
import numpy as np
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_rig as A

GRIP_X = 0.28                  # hands (thumbs included) just clear the legs, lockout to floor
PLATE_R = 0.225
SHOULDER_AHEAD = 0.17         # shoulders this far in front of the bar at the floor (hips high, flat back, shins near
                              # vertical), easing to over the bar at lockout

A.setup()
A.train(primary=['lower_back'], secondary=['glutes', 'hamstrings', 'quads', 'lats', 'middle_back', 'traps', 'forearms', 'calves'])
P, D = A.P, A.D
bar = A.holder("Bar")
A.barbell(bar)
stance = {s: A.rest_head("foot." + s) * 1 for s in ("L", "R")}
for s, sx in (("L", 1), ("R", -1)):
    stance[s].x = sx * 0.14                      # hip-width stance
A.plant_feet(toe_out_deg=8, ankles=stance)
A.ik_arms(bar, {"L": (0.3, 0.8, 0.5), "R": (-0.3, 0.8, 0.5)})

midfoot_y = float(np.mean([(A.rest_head("foot." + s) + A.rest_head("toe3-1." + s)).y / 2 for s in ("L", "R")]))
arm_len = sum(A.arm_lengths("L"))


def pose(drop, back, lean, bar_pos):
    A.set_root(drop, back, lean)
    A.rotate_local("neck01", (1, 0, 0), -0.45 * lean)
    bar.matrix_world = Matrix.Translation(bar_pos)
    A.update()


def bisect(f, lo, hi, n=16):
    """Root of f, positive at lo and negative at hi."""
    for _ in range(n):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if f(mid) > 0 else (lo, mid)
    return (lo + hi) / 2


def reach_slack():
    """Straight-arm length minus shoulder-to-wrist distance (both arms averaged); 0 = arms just straight."""
    d = [(A.hand_targets[s].matrix_world.translation - A.head("upperarm01." + s)).length for s in ("L", "R")]
    return 0.975 * arm_len - sum(d) / 2              # arms just short of locked: a fully straight arm makes the
                                                     # IK elbow direction ill-defined and it twitches


# ---- grip with the bar where straight arms hang at lockout
pose(0, 0, 0, Vector((0, midfoot_y, 0.7)))
for s, sx in (("L", 1), ("R", -1)):
    A.grip_on(s, bar, (sx * GRIP_X, 0, 0), thumbward=(-sx, 0, 0), palm_to_handle=(0, 1, -0.3), square=True)
A.update()
top_z = bisect(lambda z: (pose(0, 0, 0, Vector((0, midfoot_y, z))), -reach_slack())[1], 0.3, 1.2)


def legs_front(z):
    """Front-most leg skin (y) at height z, within the bar's span between the hands."""
    co = A.world_coords(A.body)
    legs = A.body_mask & ~A.hand_mask & (np.abs(co[:, 0]) < GRIP_X - 0.04) & (np.abs(co[:, 2] - z) < A.BAR_R + 0.004)
    return co[legs, 1].min() if legs.any() else 9.0


def solve(pos, ahead):
    """drop/back/lean: straight arms reach the bar, shoulders just ahead of it, legs just behind it."""
    lean = drop = 0.0
    contact = pos.y + A.BAR_R + 0.004

    def legs_gap(back):
        nonlocal lean, drop
        for _ in range(2):
            drop = bisect(lambda d: (pose(d, back, lean, pos), -reach_slack())[1], 0.0, 0.8)
            lean = bisect(lambda l: (pose(drop, back, l, pos), A.head("upperarm01.L").y - (pos.y - ahead))[1], 0.0, 1.5)
        pose(drop, back, lean, pos)
        return contact - legs_front(pos.z)

    back = bisect(legs_gap, -0.1, 0.6, n=12)
    legs_gap(back)
    return drop, back, lean


A.set_root(0.25, 0.15, 0.6)
A.solve_pole_angles({"L": (0.2, 1, 0.2), "R": (-0.2, 1, 0.2)}, {"L": (0.12, -1, 0), "R": (-0.12, -1, 0)})   # knees over the toes

# ---- lockout: tall, bar resting against the thighs on straight arms; this fixes the vertical bar path
pose(0, 0, 0, Vector((0, midfoot_y, top_z)))
BAR_Y = midfoot_y
for _ in range(3):
    BAR_Y = legs_front(top_z) - A.BAR_R - 0.004
    top_z = bisect(lambda z: (pose(0, 0, 0, Vector((0, BAR_Y, z))), -reach_slack())[1], 0.3, 1.2)
pose(0, 0, 0, Vector((0, BAR_Y, top_z)))
for s, sx in (("L", 1), ("R", -1)):
    A.grip_neutral(s, bar, (sx * GRIP_X, 0, 0), thumbward=(-sx, 0, 0), palm_guess=(0, 1, -0.3), square=True)
for s in ("L", "R"):
    A.seat_palm(s)
for s in ("L", "R"):
    A.wrap_hand(s)

samples = [(0.0, top_z, BAR_Y, 0.0, 0.0, 0.0)]
for t in np.linspace(0.1, 1, 10):
    z = top_z + (PLATE_R - top_z) * t
    drop, back, lean = solve(Vector((0, BAR_Y, z)), SHOULDER_AHEAD * t)
    samples.append((t, z, BAR_Y, drop, back, lean))
pose(*samples[-1][3:6], Vector((0, BAR_Y, PLATE_R)))
hip, knee = A.head("upperleg01.L"), A.head("lowerleg01.L")
print(f"FLOOR hip {hip.z:.3f} knee {knee.z:.3f} (+{(hip.z - knee.z) * 100:.0f} cm), thigh "
      f"{math.degrees(math.atan2(hip.z - knee.z, (hip - knee).xy.length)):.0f} deg below horizontal, knee y {knee.y:.3f} vs bar {BAR_Y:.3f}")
for row in samples:
    print("SAMPLE t={:.3f} bar z {:.3f} y {:.3f}  drop {:.3f} back {:.3f} lean {:.0f}".format(*row[:5], math.degrees(row[5])))
S = np.array(samples)


def phase(fr, top=4, bottom=42, hold=4):
    """Lockout -> floor -> lockout: 0 held at lockout for `top` frames either side of the loop point (~0.3 s in all),
    eased down to the floor (1) by `bottom`, a short pause, eased back up."""
    f = fr - 1
    if f <= top:
        return 0.0
    if f <= bottom:
        return A.ease((f - top) / (bottom - top))
    if f <= bottom + hold:
        return 1.0
    return A.ease(1 - (f - bottom - hold) / (A.LOOP - top - bottom - hold))


def at(t):
    """Pose along the path, monotone-cubic through the samples (linear interpolation kinks at every sample, which
    shows as a jolt in the torso)."""
    return [A.pchip(S[:, 0], S[:, k], t) for k in range(1, 6)]


# bar roll per frame keeps the wrists straight; picked frame by frame it jumps in whole degrees and the arms
# twitch with it, so solve it first and smooth it round the loop before keying
# pose per frame, lightly smoothed in time round the loop (the lean rises steeply just off lockout)
path = np.array([at(phase(fr)) for fr in range(1, A.LOOP + 1)])
path = np.stack([A.smooth(path[:, k], 2.5, loop=True) for k in range(path.shape[1])], 1)
rolls = []
for fr in range(1, A.LOOP + 1):
    z, y, drop, back, lean = path[fr - 1]
    pose(drop, back, lean, Vector((0, y, z)))
    rolls.append(A.roll_neutral(bar))
rolls = A.smooth(np.array(rolls, float), 3.0, loop=True)
for fr in range(1, A.LOOP + 2):
    A.scene.frame_set(fr)
    z, y, drop, back, lean = path[(fr - 1) % A.LOOP]
    pose(drop, back, lean, Vector((0, y, z)))
    A.roll_holder(bar, rolls[(fr - 1) % A.LOOP])
    A.key_bones(["root", "neck01"], fr)
    A.key_hip(fr)
    A.key_holder(bar, fr)
A.report([1, 25, 45, 70])

A.setup_render()
cam = A.main_camera([o for o in bar.children if o.type == 'MESH'], az_deg=125, el_deg=12)   # rear-side 3/4: erectors, glutes, hamstrings
hands = A.closeup_camera("L", 45, offset=(0.05, -0.5, 0.18), lens=70)
under = A.closeup_camera("L", 1, offset=(0.06, -0.22, -0.3), lens=70)        # from below the bar
A.finish("deadlift", cam, hands, mid_frame=45, extra_cams=[("under", under)])
