# Standing dumbbell lateral raise to shoulder height, slight elbow bend, neutral-to-pronated grip.
# blender -b human.blend -P lateral_raise.py -- [--preview] [--stills] [--anim]
import bpy, math, sys, os
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_rig as A

ABD_BOTTOM, ABD_TOP = 12, 86               # arm abduction (deg)
SCAPULAR = 20                              # raise in the scapular plane, a little in front of the body
ELBOW_BEND = 22

A.setup()
A.train(primary=['side_delts'], secondary=[])
A.plant_feet(toe_out_deg=8)
bells = {s: A.holder("Dumbbell." + s) for s in ("L", "R")}
for h in bells.values():
    A.dumbbell(h)
A.ik_arms(bells, {"L": (0.9, 0.7, 1.3), "R": (-0.9, 0.7, 1.3)}, poles_in_world=True)       # elbows back/out
for s in ("L", "R"):
    A.grip_on(s, bells[s], (0, 0, 0), thumbward=(1, 0, 0), palm_to_handle=(0, 0, 1), radius=A.DB_R)
A.update()

upper, fore = A.arm_lengths("L")
SHOULDER = {s: A.head("upperarm01." + s) for s in ("L", "R")}     # fixed: no shrug


def place(abd_deg):
    for s, sx in (("L", 1), ("R", -1)):
        plane = Matrix.Rotation(math.radians(-sx * SCAPULAR), 3, 'Z')
        u = plane @ Matrix.Rotation(math.radians(-sx * abd_deg), 3, 'Y') @ Vector((0, 0, -1))
        fwd = plane @ Vector((0, -1, 0))
        fwd = (fwd - fwd.dot(u) * u).normalized()
        b = math.radians(ELBOW_BEND)
        f = (u * math.cos(b) + fwd * math.sin(b)).normalized()
        e = SHOULDER[s] + u * upper
        bells[s].matrix_world = A.holder_for_hand(s, e + f * fore, f, fwd)          # thumb leads forward
    A.update()
    for s in ("L", "R"):
        A.straighten_wrist(s, bells[s])


place(50)
A.solve_pole_angles({"L": (0.2, 1, 0.4), "R": (-0.2, 1, 0.4)})
place(ABD_BOTTOM)
for s in ("L", "R"):
    A.seat_palm(s)
for s in ("L", "R"):
    A.wrap_hand(s)

for fr in range(1, A.LOOP + 2):
    A.scene.frame_set(fr)
    place(ABD_BOTTOM + (ABD_TOP - ABD_BOTTOM) * A.rep_phase(fr, bottom=40, hold=6))
    for h in bells.values():
        A.key_holder(h, fr)
A.report([1, 25, 44, 70])
meshes = [o for h in bells.values() for o in h.children if o.type == 'MESH']
for fr in (1, 44):
    print(f"CHECK f{fr}: body inside dumbbells {A.body_vs_equipment(fr, meshes):.1f} mm")

A.setup_render()
cam = A.main_camera(meshes)
hands = A.closeup_camera("L", 44, offset=(0.2, -0.35, 0.3), lens=70)
A.finish("lateral_raise", cam, hands, mid_frame=44)
