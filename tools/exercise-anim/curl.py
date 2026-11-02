# Standing dumbbell biceps curl, both arms, elbows pinned at the sides, supinated grip.
# blender -b human.blend -P curl.py -- [--preview] [--stills] [--anim]
import bpy, math, sys, os
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_rig as A

FLEX_BOTTOM, FLEX_TOP = 12, 132            # elbow flexion (deg)

A.setup()
A.train(primary=['biceps'], secondary=['forearms'])
A.plant_feet(toe_out_deg=8)
bells = {s: A.holder("Dumbbell." + s) for s in ("L", "R")}
for h in bells.values():
    A.dumbbell(h)
A.ik_arms(bells, {"L": (0.35, 0.6, 0.95), "R": (-0.35, 0.6, 0.95)}, poles_in_world=True)   # elbows back
for s in ("L", "R"):
    A.grip_on(s, bells[s], (0, 0, 0), thumbward=(1, 0, 0), palm_to_handle=(0, 0, 1), radius=A.DB_R)
A.update()

upper, fore = A.arm_lengths("L")


def elbow(s, sx):
    shoulder = A.head("upperarm01." + s)
    return shoulder + Vector((sx * 0.035, 0.02, -1)).normalized() * upper     # upper arm hanging, just off the lats


def place(flex_deg):
    th = math.radians(flex_deg)
    for s, sx in (("L", 1), ("R", -1)):
        e = elbow(s, sx)
        bpy.data.objects["ElbowPole." + s].location = e + Vector((sx * 0.1, 0.6, 0))   # elbow pinned behind, at the side
        f = Vector((sx * 0.2, -math.sin(th), -math.cos(th))).normalized()    # forearm, hands slightly out
        bells[s].matrix_world = A.holder_for_hand(s, e + f * fore, f, Vector((sx, 0, 0)))
    A.update()
    for s in ("L", "R"):
        A.straighten_wrist(s, bells[s])


place(60)
A.solve_pole_angles({"L": (0.1, 1, -0.2), "R": (-0.1, 1, -0.2)})
place(FLEX_BOTTOM)
for s in ("L", "R"):
    A.seat_palm(s)
for s in ("L", "R"):
    A.wrap_hand(s)

for fr in range(1, A.LOOP + 2):
    A.scene.frame_set(fr)
    place(FLEX_BOTTOM + (FLEX_TOP - FLEX_BOTTOM) * A.rep_phase(fr, bottom=40, hold=6))
    for h in bells.values():
        A.key_holder(h, fr)
    for s in ("L", "R"):
        bpy.data.objects["ElbowPole." + s].keyframe_insert("location", frame=fr)
A.report([1, 25, 44, 70])
meshes = [o for h in bells.values() for o in h.children if o.type == 'MESH']
for fr in (1, 44):
    print(f"CHECK f{fr}: body inside dumbbells {A.body_vs_equipment(fr, meshes):.1f} mm")

A.setup_render()
cam = A.main_camera(meshes)
hands = A.closeup_camera("L", 1, offset=(0.14, -0.45, 0.12), lens=70)       # from the front: palm + wrap visible
A.finish("curl", cam, hands, mid_frame=44)
