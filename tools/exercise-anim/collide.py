# Body-vs-equipment interpenetration check: for sampled frames, body and shoe vertices that sit inside an
# equipment mesh deeper than a tolerance are reported per object. Run kit.py with ATLAS_COLLIDE=1.
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import atlas_rig as A

SOFT = ("Pad", "Bench", "Seat", "Back", "Cushion")      # upholstery the body presses into a little


def _bvh(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    mw = obj.matrix_world
    verts = [mw @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    ev.to_mesh_clear()
    if not polys:
        return None, None
    v = np.array(verts)
    return BVHTree.FromPolygons(verts, polys), (v.min(0), v.max(0))


def _verts(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    out = [obj.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return out


def _body_bvh(objs, part_all):
    """The deformed body (and shoes) as one BVH, normals outward."""
    dg = bpy.context.evaluated_depsgraph_get()
    verts, polys, face_part = [], [], []
    for obj in objs:
        ev = obj.evaluated_get(dg)
        me = ev.to_mesh()
        base = len(verts)
        keep = _mask(obj)
        verts += [obj.matrix_world @ v.co for v in me.vertices]
        for p in me.polygons:
            if all(keep[i] for i in p.vertices):
                polys.append(tuple(base + i for i in p.vertices))
                face_part.append(part_all[base + p.vertices[0]])
        ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys), face_part


def _mask(obj):
    """Rendered vertices: the body's helper geometry (proxy cubes, clothing helpers) is masked out at render."""
    if obj.name == "Human" and A.body_mask is not None:
        return A.body_mask
    return np.ones(len(obj.data.vertices), dtype=bool)


def _parts(objs):
    """Body part (dominant vertex group, side-free) per stacked vertex of `objs`."""
    out = []
    for obj in objs:
        bones = A.rig.data.bones
        names = {g.index: g.name for g in obj.vertex_groups if g.name in bones}
        for v in obj.data.vertices:
            best = max((g for g in v.groups if g.group in names), key=lambda g: g.weight, default=None)
            out.append(names.get(best.group, obj.name) if best else obj.name)
    return out


def check(objs, frames, tol=0.012):
    body = [o for o in (bpy.data.objects.get("Human"), bpy.data.objects.get("Shoes")) if o]
    keep = np.concatenate([_mask(o) for o in body])
    part_all = np.array(_parts(body))
    part = part_all[keep]
    hits = {}
    A.scene.frame_set(frames[0])
    print("JOINTS", {b: tuple(round(v, 2) for v in A.head(b)) for b in ("upperleg01.L", "lowerleg01.L", "foot.L")})
    body_trees, body_face_part = {}, {}
    for fr in frames:
        A.scene.frame_set(fr)
        pts = np.vstack([A.world_coords(o) for o in body])[keep]
        for o in objs:
            if o.type != 'MESH' or o.name.startswith("Cable."):
                continue
            tree, box = _bvh(o)
            if tree is None:
                continue
            lo, hi = box
            inside = np.all((pts > lo) & (pts < hi), axis=1)
            sel, sel_part = pts[inside], part[inside]
            where = {}
            limit = 0.042 if any(w in o.name for w in SOFT) else tol     # cushions compress
            worst, n = 0.0, 0
            for p, bp in zip(sel, sel_part):
                loc, nrm, _, d = tree.find_nearest(Vector(p))
                if loc is None:
                    continue
                if (Vector(p) - loc).dot(nrm) < 0 and limit < d < 0.15:
                    n += 1
                    worst = max(worst, d)
                    where[bp] = where.get(bp, 0) + 1
            if len(sel):                                # and the other way: equipment corners inside the body
                body_tree = body_trees.get(fr)
                if body_tree is None:
                    body_tree, body_face_part[fr] = _body_bvh(body, part_all)
                    body_trees[fr] = body_tree
                for p in _verts(o):
                    loc, nrm, fi, d = body_tree.find_nearest(p)
                    if loc is not None and (p - loc).dot(nrm) < 0 and limit < d < 0.15:
                        n += 1
                        worst = max(worst, d)
                        bp = "in:" + body_face_part[fr][fi]
                        where[bp] = where.get(bp, 0) + 1
            if n > 3:
                h = hits.setdefault(o.name, [0.0, 0, [], {}])
                h[0] = max(h[0], worst)
                h[1] = max(h[1], n)
                h[2].append(fr)
                for k, c in where.items():
                    h[3][k] = h[3].get(k, 0) + c
    for name, (worst, n, frs, where) in sorted(hits.items(), key=lambda kv: -kv[1][0]):
        top = ",".join(k for k, _ in sorted(where.items(), key=lambda kv: -kv[1])[:3])
        print("COLLIDE %-22s depth %3.0f mm  verts %4d  frames %d/%d  body %s" % (name, worst * 1000, n, len(frs),
                                                                                len(frames), top))
    print("COLLIDE_DONE %d objects" % len(hits))
    return hits
