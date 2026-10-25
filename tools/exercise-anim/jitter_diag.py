# Frame-to-frame pose jitter of a saved exercise .blend: per bone, the largest second difference of its world
# rotation (deg) over the loop. Smooth motion has small second differences; pops show up as spikes.
# blender -b <exercise>.blend -P jitter_diag.py
import bpy, math
import numpy as np
sc = bpy.context.scene
rig = bpy.data.objects["Human.rig"]
bones = [b.name for b in rig.pose.bones if b.name.endswith(".L") or b.name.startswith(("spine", "neck", "head", "root"))]
bones = [b for b in bones if not b.startswith(("oris", "levator", "tongue", "special", "orbicularis", "oculi",
                                              "temporalis", "risorius", "eye", "toe", "breast", "jaw"))]
holders = [o for o in bpy.data.objects if o.animation_data and o.type == 'EMPTY']
rots = {b: [] for b in bones + [h.name for h in holders]}
for fr in range(1, 92):
    sc.frame_set(fr)
    for b in bones:
        rots[b].append((rig.matrix_world @ rig.pose.bones[b].matrix).to_quaternion())
    for h in holders:
        rots[h.name].append(h.matrix_world.to_quaternion())
for name, q in rots.items():
    d = [math.degrees(q[i].rotation_difference(q[i + 1]).angle) for i in range(len(q) - 1)]
    d = [min(x, 360 - x) for x in d]                     # q and -q are the same rotation
    dd = np.abs(np.diff(d))
    k = int(dd.argmax())
    if dd.max() > 0.5:
        print(f"JITTER {name:14s} max step {max(d):5.2f} deg, max accel {dd.max():5.2f} deg at f{k + 2}, "
          f"frames with accel > 1 deg: {int((dd > 1).sum())}")
keys = bpy.data.objects["Human"].data.shape_keys
if keys and keys.animation_data:
    for kb in keys.key_blocks[1:]:
        v = []
        for fr in range(1, 92):
            sc.frame_set(fr)
            v.append(kb.value)
        dd = np.abs(np.diff(np.diff(v)))
        print(f"SHAPEKEY {kb.name}: range {min(v):.2f}..{max(v):.2f}, max accel {dd.max():.3f} at f{int(dd.argmax()) + 2}")
