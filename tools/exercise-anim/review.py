# Review stills of a saved exercise .blend: main 3/4 front camera, the same camera swung round behind the figure,
# and swung round to a pure side view (main camera sits 35 degrees off the front).
# blender -b <exercise>.blend -P review.py -- <out_prefix> <frame> [frame ...]   (raw RGBA PNGs + tiers/, composite after)
import bpy, sys, os
from mathutils import Matrix
args = sys.argv[sys.argv.index("--") + 1:]
out, frames = os.path.abspath(args[0]), [int(f) for f in args[1:]]
sc = bpy.context.scene
cam = bpy.data.objects["Cam"]
look = bpy.data.objects["LookTarget"].location
back = cam.copy()
back.data = cam.data.copy()
sc.collection.objects.link(back)
back.matrix_world = Matrix.Translation(look) @ Matrix.Rotation(3.14159, 4, 'Z') @ Matrix.Translation(-look) @ cam.matrix_world
back.data.shift_x = cam.data.shift_x
side = cam.copy()
side.data = cam.data.copy()
sc.collection.objects.link(side)
side.matrix_world = Matrix.Translation(look) @ Matrix.Rotation(0.96, 4, 'Z') @ Matrix.Translation(-look) @ cam.matrix_world
sc.cycles.samples = 64
sc.render.resolution_percentage = 50
for fr in frames:
    for tag, c in (("front", cam), ("back", back), ("side", side)):
        sc.camera = c
        sc.frame_set(fr)
        path = f"{out}_{tag}_{fr}.png"
        sc.render.filepath = path
        tiers = os.path.join(os.path.dirname(path), "tiers")
        os.makedirs(tiers, exist_ok=True)
        fo = next(n for n in sc.compositing_node_group.nodes if n.bl_idname == "CompositorNodeOutputFile")
        prefix = os.path.splitext(os.path.basename(path))[0] + "_tiers_"
        fo.directory, fo.file_name = tiers, prefix
        bpy.ops.render.render(write_still=True)
        for f in os.listdir(tiers):              # File Output appends the frame number
            if f.startswith(prefix):
                os.replace(os.path.join(tiers, f), os.path.join(tiers, os.path.basename(path)))
