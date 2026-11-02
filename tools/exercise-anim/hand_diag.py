# Workbench close-ups of one hand round its handle from 4 sides (back, palm/underside, both ends of the handle).
# blender -b <exercise>.blend -P hand_diag.py -- <frame> <side> <out_prefix>
import bpy, sys, os
from mathutils import Vector, Matrix
frame, side, out = sys.argv[sys.argv.index("--") + 1:][:3]
out = os.path.abspath(out)
sc = bpy.context.scene
sc.frame_set(int(frame))
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.film_transparent = False
sc.render.resolution_x = sc.render.resolution_y = 600
sc.render.resolution_percentage = 100
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True
tgt = bpy.data.objects["HandIK." + side]
m = tgt.parent.matrix_world
o = m @ Vector(tgt["handle_centre"])
a = (m.to_3x3() @ Vector(tgt["handle_axis"])).normalized()
p = (m.to_3x3() @ Vector(tgt["palm_n"])).normalized()
f = a.cross(p) if side == "L" else p.cross(a)
views = {"back": -p + 0.25 * f, "under": p + 0.25 * f, "thumbend": a + 0.12 * f, "pinkyend": -a + 0.12 * f}
for name, d in views.items():
    d = d.normalized()
    cd = bpy.data.cameras.new(name); cd.type = 'ORTHO'; cd.ortho_scale = 0.17
    half = 0.05 if name in ("thumbend", "pinkyend") else 0.09
    cd.clip_start, cd.clip_end = 1.0 - half, 1.0 + half
    cam = bpy.data.objects.new(name, cd); sc.collection.objects.link(cam)
    cam.location = o + d * 1.0
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    if name in ("thumbend", "pinkyend"):            # palm at the bottom, fingers to the right
        x = f if name == "thumbend" else -f
        x = (x - x.dot(d) * d).normalized()
        cam.rotation_euler = Matrix((x, d.cross(x), d)).transposed().to_euler()
    sc.camera = cam
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
