# Gym equipment drawn to commercial standard: powder-coated steel frames, upholstered pads, rubber grips and
# plate-loaded lever arms that turn on a real axle. Shared by kit.py (benches, machines).
import math
import bpy
from mathutils import Vector, Matrix, Quaternion
import atlas_rig as A

_MATS = {}


def _mat(name, color, rough, metal=0.0, coat=0.0):
    if name not in _MATS:
        m = A.material(name, color, rough=rough, metal=metal)
        b = m.node_tree.nodes["Principled BSDF"]
        if coat:
            b.inputs["Coat Weight"].default_value = coat
            b.inputs["Coat Roughness"].default_value = 0.25
        A.solid_aov(m)
        _MATS[name] = m
    return _MATS[name]


def frame_mat():
    """Satin graphite powder coat: dark, with a soft highlight that follows the tube edges."""
    return _mat("EqFrame", (0.028, 0.03, 0.033), 0.38, metal=0.55, coat=0.35)


def pad_mat():
    """Upholstery vinyl: near-black, a broad soft sheen."""
    return _mat("EqPad", (0.016, 0.016, 0.018), 0.48, coat=0.2)


def grip_mat():
    return _mat("EqGrip", (0.02, 0.02, 0.021), 0.85)


def metal_mat():
    """Brushed steel for axles, plate horns and end caps: the only bright accent."""
    return _mat("EqMetal", (0.42, 0.43, 0.45), 0.24, metal=1.0)


def plate_mat():
    return _mat("EqPlate", (0.014, 0.014, 0.015), 0.6)


def _finish(o, mat, bevel, segments=4):
    o.data.materials.append(mat)
    if bevel:
        b = o.modifiers.new("bevel", 'BEVEL')
        b.width, b.segments, b.limit_method = bevel, segments, 'ANGLE'
        b.harden_normals = True
    bpy.ops.object.shade_smooth()
    return o


def _orient(a, b):
    """Rotation taking local Z onto a->b (local Y kept as level as it can be)."""
    return (Vector(b) - Vector(a)).to_track_quat('Z', 'Y')


def tube(name, a, b, w=0.075, h=0.075, mat=None, roll=0.0):
    """Rectangular steel tube from a to b, w x h cross-section, edges rounded like formed tubing."""
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(a + b) / 2)
    o = bpy.context.object
    o.name = name
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = _orient(a, b) @ Quaternion((0, 0, 1), roll)
    o.scale = (w, h, (b - a).length)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(o, mat or frame_mat(), min(w, h) * 0.28)


def round_tube(name, a, b, r=0.03, mat=None):
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=r, depth=(b - a).length, location=(a + b) / 2)
    o = bpy.context.object
    o.name = name
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = _orient(a, b)
    return _finish(o, mat or frame_mat(), r * 0.25, 3)


def joint(name, at, r, mat=None):
    """A rounded knuckle where two tubes meet, so bends read as formed steel, not crossed sticks."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=32, ring_count=16, location=at)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat or frame_mat())
    bpy.ops.object.shade_smooth()
    return o


def cushion(name, size, at, rot_x=0.0, rot_z=0.0):
    """Upholstered pad: thick foam with a soft rounded edge on a thin backing board."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=at, rotation=(rot_x, 0, rot_z))
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(o, pad_mat(), min(size) * 0.42, 6)


def foot(name, at, length=0.62, axis='x'):
    """Floor foot: wide rectangular tube with rubber end caps."""
    at = Vector(at)
    d = Vector((length / 2, 0, 0)) if axis == 'x' else Vector((0, length / 2, 0))
    base = Vector((0, 0, 0.035))
    parts = [tube(name, at - d + base, at + d + base, 0.08, 0.07)]
    for s in (1, -1):
        e = at + d * s + base
        parts.append(tube(name + "Cap", e, e + d.normalized() * 0.03 * s, 0.085, 0.075, mat=grip_mat()))
    return parts


def hub(name, at, axis, r=0.065, depth=0.09):
    """Axle housing with a brushed steel cap facing out along `axis`."""
    at, axis = Vector(at), Vector(axis).normalized()
    parts = [round_tube(name, at - axis * depth / 2, at + axis * depth / 2, r)]
    parts.append(round_tube(name + "Cap", at + axis * depth / 2, at + axis * (depth / 2 + 0.012), r * 0.62,
                            mat=metal_mat()))
    return parts


def plates(name, at, axis, n=2, r=0.225):
    """Bumper-style plates on a horn: rubber disc with a steel hub ring."""
    at, axis = Vector(at), Vector(axis).normalized()
    out = []
    for i in range(n):
        c = at + axis * (0.03 + i * 0.045)
        out.append(round_tube(name, c - axis * 0.02, c + axis * 0.02, r, mat=plate_mat()))
        out.append(round_tube(name + "Hub", c - axis * 0.022, c + axis * 0.022, 0.06, mat=metal_mat()))
    return out


def grip(h, length=0.13):
    """Handle on a holder's X axis: knurled-look rubber sleeve between steel collars."""
    A.cylinder(h, A.DB_R, length, mat=grip_mat(), verts=48)
    for sx in (1, -1):
        A.cylinder(h, A.DB_R + 0.006, 0.012, x=sx * (length / 2 + 0.006), mat=metal_mat(), verts=48)


def parent_keep(objs, holder):
    """Parent objects built in world space to `holder`, keeping where they are."""
    bpy.context.view_layer.update()                     # a fresh object's matrix_world is stale until then
    inv = holder.matrix_world.inverted()
    for o in objs:
        o.parent = holder
        o.matrix_parent_inverse = inv
