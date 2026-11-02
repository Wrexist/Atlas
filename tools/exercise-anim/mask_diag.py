# Rest-pose front/back renders of the muscle masks: every region alternately primary (orange) / secondary (blue).
# blender -b human.blend -P mask_diag.py -- <out_prefix>
import bpy, sys, os, math
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_rig as A
out = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
A.setup()
names = list(A._muscle_rules())
# neighbours get different tiers so every outline is visible
A.train(primary=["quads", "hamstrings", "glutes", "lower_back", "lats", "chest", "side_delts", "biceps", "triceps"],
        secondary=["adductors", "calves", "abs", "middle_back", "traps", "front_delts", "rear_delts", "forearms"])
A.setup_render()
A.scene.cycles.samples = 24
A.scene.render.resolution_percentage = 50
cd = bpy.data.cameras.new("C"); cd.type = 'ORTHO'; cd.ortho_scale = 2.0
cam = bpy.data.objects.new("C", cd); A.scene.collection.objects.link(cam); A.scene.camera = cam
A.look_target.location = Vector((0, 0, 1.0))
for tag, d in (("front", Vector((0.25, -1, 0.1))), ("back", Vector((-0.25, 1, 0.1)))):
    d.normalize()
    cam.location = Vector((0, 0, 1.0)) + d * 6
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    A.render_still(f"{out}_{tag}.png", 1, cam, 50)
