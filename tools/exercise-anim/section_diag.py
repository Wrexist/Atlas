# Thin cross-sections of one hand round its handle (2 mm slabs at each finger), to check the wrap really hugs.
# blender -b <exercise>.blend -P section_diag.py -- <frame> <side> <out.png>
import bpy, sys
import numpy as np
from mathutils import Vector, Matrix
frame, side, out = sys.argv[sys.argv.index("--") + 1:][:3]
sc = bpy.context.scene
sc.frame_set(int(frame))
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.film_transparent = False
sc.render.resolution_x = sc.render.resolution_y = 400
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'SINGLE'
sc.display.shading.single_color = (0.8, 0.8, 0.8)
sc.display.shading.show_backface_culling = False
tgt = bpy.data.objects["HandIK." + side]
m = tgt.parent.matrix_world
o = m @ Vector(tgt["handle_centre"])
a = (m.to_3x3() @ Vector(tgt["handle_axis"])).normalized()
p = (m.to_3x3() @ Vector(tgt["palm_n"])).normalized()
f = a.cross(p) if side == "L" else p.cross(a)
rig = bpy.data.objects["Human.rig"]
for k in (2, 3, 4, 5):
    mid = rig.matrix_world @ rig.pose.bones[f"finger{k}-2.{side}"].head
    off = (mid - o).dot(a)
    cd = bpy.data.cameras.new("sec"); cd.type = 'ORTHO'; cd.ortho_scale = 0.09
    cd.clip_start, cd.clip_end = 1.0 - 0.003, 1.0 + 0.003
    cam = bpy.data.objects.new("sec", cd); sc.collection.objects.link(cam)
    cam.location = o + a * (off + 1.0)
    cam.rotation_euler = Matrix((f, -p, a)).transposed().to_euler()     # fingers right, palm at the bottom
    sc.camera = cam
    sc.render.filepath = out.replace(".png", f"_f{k}.png")
    bpy.ops.render.render(write_still=True)
