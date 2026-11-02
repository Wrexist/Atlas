# Quick front/side/top-of-hand diagnostic renders of a saved exercise .blend (Workbench).
import bpy, sys, math
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
frame, out = int(args[0]), args[1]
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.film_transparent = False
sc.render.resolution_percentage = 40
sc.display.shading.light = 'STUDIO'
sc.display.shading.show_cavity = True
sc.frame_set(frame)
tgt = bpy.data.objects["LookTarget"].location
views = {"front": Vector((0, -1, 0.05)), "side": Vector((1, 0, 0.05)), "back": Vector((0.2, 1, 0.6))}
extra = args[2:] if len(args) > 2 else views.keys()
rig = bpy.data.objects["Human.rig"]
close = {"face": (rig.matrix_world @ rig.pose.bones["head"].head + Vector((0, 0, 0.08)), Vector((0.3, -1, 0.1)), 0.35),
         "handL": (bpy.data.objects["HandIK.L"].matrix_world.translation, Vector((0.5, -1, 0.6)), 0.3),
         "handLb": (bpy.data.objects["HandIK.L"].matrix_world.translation, Vector((0.3, 1, 0.5)), 0.3),
         "handLs": (bpy.data.objects["HandIK.L"].matrix_world.translation, Vector((1, 0, 0.2)), 0.3),
         "groin": (rig.matrix_world @ rig.pose.bones["root"].head + Vector((0, 0, -0.08)), Vector((0.2, -1, 0.1)), 0.4),
         "handLm": (bpy.data.objects["HandIK.L"].matrix_world.translation, Vector((-1, -0.3, 0.1)), 0.25)}
for name in extra:
    if name in close:
        tgt, d, scale = close[name]
        d = d.normalized()
    else:
        d, scale = views[name].normalized(), 2.6
    cd = bpy.data.cameras.new(name); cd.type = 'ORTHO'; cd.ortho_scale = scale
    if name in close:
        cd.clip_start = 5.8          # slice away everything between the camera and the hand
    cam = bpy.data.objects.new(name, cd); sc.collection.objects.link(cam)
    cam.location = tgt + d * 6
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
