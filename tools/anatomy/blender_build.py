#!/usr/bin/env python3
"""Build the Atlas anatomy asset pack with Blender (bpy).

Constructs an inflated 3D mesh for every muscle head from the exact 2D
geometry validated in geometry.py, renders a studio-lit neutral-gray
body (front + back) with Cycles, and writes per-muscle alpha masks
rasterized from the same polygons — pixel-aligned with the orthographic
render by construction.

Output (in /tmp/anatomy/assets):
  anatomy_body_front.png, anatomy_body_back.png
  anatomy_<muscleRawValue>_front_mask.png intermediates merged into
  anatomy_<muscleRawValue>.png  (one alpha mask per muscle)
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spline import catmull_closed, mirror_pts, rounded_rect_poly  # noqa: E402
import geometry as G  # noqa: E402

import bpy  # noqa: E402


OUT = os.environ.get("ANATOMY_OUT", "/tmp/anatomy/assets")
RES_X, RES_Y = 2400, 5760          # 1 : 2.4
GRID = 0.0028                      # heightfield step in normalized units
SAMPLES = int(__import__("os").environ.get("SAMPLES", 64))

os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------- geometry

def polygons_for(name):
    """Sampled polygons for a muscle (lobes + mirrors + rects)."""
    spec = G.MUSCLES[name]
    polys = []
    for lobe in spec["lobes"]:
        poly = catmull_closed(lobe, samples_per_seg=12)
        polys.append(poly)
        if spec.get("mirror"):
            polys.append(mirror_pts(poly))
    for rect in spec.get("rects", []):
        polys.append(rounded_rect_poly(*rect))
    return polys


def silhouette():
    pts = list(G.SILHOUETTE_RIGHT)
    pts += [(1 - x, y) for (x, y) in reversed(G.SILHOUETTE_RIGHT[1:-1])]
    return catmull_closed(pts, samples_per_seg=12)


def rasterize(poly, x0, y0, nx, ny, step):
    """Boolean inside-mask of a polygon on a grid (even-odd rule)."""
    xs = x0 + (np.arange(nx) + 0.5) * step
    ys = y0 + (np.arange(ny) + 0.5) * step
    inside = np.zeros((ny, nx), dtype=bool)
    px = np.array([p[0] for p in poly])
    py = np.array([p[1] for p in poly])
    n = len(poly)
    for row, y in enumerate(ys):
        cond = (py > y) != (np.roll(py, -1) > y)
        if not cond.any():
            continue
        i = np.where(cond)[0]
        xi = px[i] + (y - py[i]) / (np.roll(py, -1)[i] - py[i]) * (np.roll(px, -1)[i] - px[i])
        xi.sort()
        for k in range(0, len(xi) - 1, 2):
            inside[row] |= (xs >= xi[k]) & (xs <= xi[k + 1])
    return inside


def chamfer_dt(mask):
    """Two-pass chamfer distance transform (in grid cells)."""
    big = 1e6
    d = np.where(mask, big, 0.0)
    ny, nx = d.shape
    for y in range(ny):
        for x in range(nx):
            if d[y, x] == 0:
                continue
            best = d[y, x]
            if x > 0:
                best = min(best, d[y, x - 1] + 1)
            if y > 0:
                best = min(best, d[y - 1, x] + 1, d[y - 1, x - 1] + 1.414 if x > 0 else big)
                if x + 1 < nx:
                    best = min(best, d[y - 1, x + 1] + 1.414)
            d[y, x] = best
    for y in range(ny - 1, -1, -1):
        for x in range(nx - 1, -1, -1):
            if d[y, x] == 0:
                continue
            best = d[y, x]
            if x + 1 < nx:
                best = min(best, d[y, x + 1] + 1)
            if y + 1 < ny:
                best = min(best, d[y + 1, x] + 1, d[y + 1, x + 1] + 1.414 if x + 1 < nx else big)
                if x > 0:
                    best = min(best, d[y + 1, x - 1] + 1.414)
            d[y, x] = best
    return d


def build_heightfield(poly, depth, z_base, name, material, erode=False, features=None):
    """Inflated pillow mesh over a polygon footprint."""
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    x0, x1 = min(xs) - GRID, max(xs) + GRID
    y0, y1 = min(ys) - GRID, max(ys) + GRID
    nx = max(int((x1 - x0) / GRID), 4)
    ny = max(int((y1 - y0) / GRID), 4)
    mask = rasterize(poly, x0, y0, nx, ny, GRID)
    if erode:
        m = mask
        er = m.copy()
        er[1:, :] &= m[:-1, :]; er[:-1, :] &= m[1:, :]
        er[:, 1:] &= m[:, :-1]; er[:, :-1] &= m[:, 1:]
        if er.sum() > 16:
            mask = er
    if not mask.any():
        return None
    dt = chamfer_dt(mask)
    dmax = dt.max()
    if dmax <= 0:
        return None
    h = np.sqrt(np.clip(dt / dmax, 0, 1))  # rounded profile
    # soften the medial-axis ridge so the belly reads as one smooth dome
    for _ in range(6):
        acc = h.copy()
        acc[1:, :] += h[:-1, :]; acc[:-1, :] += h[1:, :]
        acc[:, 1:] += h[:, :-1]; acc[:, :-1] += h[:, 1:]
        h = np.where(mask, acc / 5.0, 0.0)
    peak = h.max()
    if peak > 0:
        h = h / peak
    if features is not None:
        gx = x0 + (np.arange(nx) + 0.5) * GRID
        gy = y0 + (np.arange(ny) + 0.5) * GRID
        WX, WY = np.meshgrid(gx, gy)
        h = np.where(mask, np.clip(h + features(WX, WY), 0.04, 1.3), 0.0)

    verts, faces = [], []
    vid = -np.ones((ny + 1, nx + 1), dtype=int)

    def corner_h(cy, cx):
        acc, cnt = 0.0, 0
        for oy in (cy - 1, cy):
            for ox in (cx - 1, cx):
                if 0 <= oy < ny and 0 <= ox < nx and mask[oy, ox]:
                    acc += h[oy, ox]
                    cnt += 1
        return acc / cnt if cnt else 0.0

    for cy in range(ny):
        for cx in range(nx):
            if not mask[cy, cx]:
                continue
            ids = []
            for (gy, gx) in ((cy, cx), (cy, cx + 1), (cy + 1, cx + 1), (cy + 1, cx)):
                if vid[gy, gx] < 0:
                    wx = x0 + gx * GRID
                    wy = y0 + gy * GRID
                    hz = corner_h(gy, gx)
                    # normalized space -> Blender: X right, Y up, Z out
                    verts.append((wx, 2.4 - wy, z_base + depth * hz))
                    vid[gy, gx] = len(verts) - 1
                ids.append(vid[gy, gx])
            faces.append(tuple(ids))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for poly_ in mesh.polygons:
        poly_.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(material)
    bpy.context.scene.collection.objects.link(obj)
    smooth = obj.modifiers.new("relax", "SMOOTH")
    smooth.factor = 1.0
    smooth.iterations = 10
    return obj




def gaussian(WX, WY, cx, cy, sx, sy, amp):
    return amp * np.exp(-(((WX - cx) / sx) ** 2 + ((WY - cy) / sy) ** 2) / 2)


def build_head(front):
    """Smooth head dome; the front view gets sculpted mannequin
    features — brow, eye sockets, nose, lips, cheeks, chin."""
    poly = [(0.5 + 0.078 * math.cos(2 * math.pi * i / 48),
             0.172 + 0.125 * math.sin(2 * math.pi * i / 48)) for i in range(48)]

    def face(WX, WY):
        dh = np.zeros_like(WX)
        dh += gaussian(WX, WY, 0.500, 0.142, 0.052, 0.014, 0.22)   # brow ridge
        dh += gaussian(WX, WY, 0.471, 0.165, 0.015, 0.011, -0.26)  # eye L
        dh += gaussian(WX, WY, 0.529, 0.165, 0.015, 0.011, -0.26)  # eye R
        dh += gaussian(WX, WY, 0.500, 0.190, 0.010, 0.030, 0.30)   # nose bridge
        dh += gaussian(WX, WY, 0.500, 0.213, 0.014, 0.011, 0.28)   # nose tip
        dh += gaussian(WX, WY, 0.460, 0.205, 0.020, 0.022, 0.12)   # cheek L
        dh += gaussian(WX, WY, 0.540, 0.205, 0.020, 0.022, 0.12)   # cheek R
        dh += gaussian(WX, WY, 0.500, 0.247, 0.020, 0.0075, 0.14)  # lips
        dh += gaussian(WX, WY, 0.500, 0.262, 0.024, 0.006, -0.10)  # lip shadow
        dh += gaussian(WX, WY, 0.500, 0.282, 0.018, 0.012, 0.12)   # chin
        return dh

    skin = bpy.data.materials.new("skin")
    skin.use_nodes = True
    _flesh_skin(skin.node_tree.nodes["Principled BSDF"], base=(0.585, 0.50, 0.455))
    build_heightfield(poly, depth=0.075, z_base=-0.012, name="head",
                      material=skin, features=face if front else None)

# ---------------------------------------------------------------- scene

def _set_input(node, name, value):
    """Set a shader-node input by name only if that socket exists.

    Principled BSDF socket names drift across Blender versions
    (`Subsurface` → `Subsurface Weight`, `Specular` → `Specular IOR
    Level`); setting both spellings and skipping the absent one keeps the
    build working on 4.x and 5.x alike.
    """
    if name in node.inputs:
        node.inputs[name].default_value = value


def _flesh_skin(bsdf, base):
    """Apply the shared smooth-flesh look to a Principled BSDF: warm
    desaturated base, soft roughness, and subsurface scattering for the
    waxy light falloff of real muscle. No bump, no bands — volume and
    seams come from the geometry and the lighting, not a texture."""
    _set_input(bsdf, "Base Color", (*base, 1.0))
    _set_input(bsdf, "Roughness", 0.52)
    _set_input(bsdf, "Specular IOR Level", 0.35)
    _set_input(bsdf, "Specular", 0.35)
    # Subsurface radius is in geometry units (body height == 2.4), so a few
    # centimetres of soft red-weighted bleed through each belly.
    _set_input(bsdf, "Subsurface Weight", 0.32)
    _set_input(bsdf, "Subsurface", 0.32)
    _set_input(bsdf, "Subsurface Radius", (0.055, 0.030, 0.022))
    _set_input(bsdf, "Subsurface Scale", 0.08)


def make_material(name, gray, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (gray, gray, gray, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return m


_muscle_mat = None


def muscle_material():
    """Smooth subsurface flesh material shared by every muscle belly.

    The old pack tinted a wave-banded bump texture, which read as diagonal
    hatching once the app composited it — the "striped cutout" look. This
    drops the texture entirely: muscles are rounded forms catching one
    soft key light, with subsurface scattering doing the soft falloff and
    Cycles' contact shadows carving the seams. The app still tints
    training intensity over the neutral render with `colorMultiply`."""
    global _muscle_mat
    if _muscle_mat is not None:
        return _muscle_mat
    m = bpy.data.materials.new("muscle")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    # Deliberate desaturated warm tone, lifted clear of muddy mid-gray and
    # of the near-black backing so untrained muscle reads as a calm base.
    _flesh_skin(bsdf, base=(0.585, 0.50, 0.455))
    _muscle_mat = m
    return m


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.device = "CPU"
    scene.render.resolution_x = RES_X
    scene.render.resolution_y = RES_Y
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"

    # Dim, slightly cool ambient so deep muscle seams read as soft contact
    # shadow rather than crushing to pure black. The transparent film keeps
    # the PNG background clear; the world only fills the lighting.
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.045, 0.05, 0.06, 1.0)
    bg.inputs["Strength"].default_value = 0.06
    scene.world = world

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.4  # covers vertical extent on portrait sensor
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (0.5, 1.2, 4.0)
    scene.collection.objects.link(cam)
    scene.camera = cam

    def light(name, kind, loc, energy, size=1.0, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = color
        if kind == "AREA":
            ld.size = size
        lo = bpy.data.objects.new(name, ld)
        lo.location = loc
        # aim at body center
        direction = np.array([0.5, 1.2, 0.0]) - np.array(loc)
        rot = direction_to_rotation(direction)
        lo.rotation_euler = rot
        scene.collection.objects.link(lo)

    # One studio rig, identical for front and back so the two renders feel
    # like one object: a large soft warm key upper-left, a cooler fill
    # opposite at lower intensity, and a rim from behind to lift the body
    # off the black. Big area sources keep shadows soft and premium.
    light("key", "AREA", (-1.1, 2.8, 2.8), 90, size=3.0, color=(1.0, 0.97, 0.93))
    light("fill", "AREA", (2.0, 1.0, 2.4), 22, size=3.2, color=(0.90, 0.95, 1.0))
    light("rim", "AREA", (0.5, -0.9, 1.8), 30, size=3.5)
    return scene


def direction_to_rotation(direction):
    """Euler rotation that points a light's -Z axis along `direction`."""
    d = direction / np.linalg.norm(direction)
    rot_x = math.acos(-d[2])
    rot_z = math.atan2(-d[0], d[1])
    return (rot_x, 0.0, rot_z)


def build_view(front):
    scene = reset_scene()
    backing_mat = make_material("backing", 0.045, 0.7)

    build_heightfield(silhouette(), depth=0.045, z_base=-0.05,
                      name="backing", material=backing_mat)

    build_head(front)

    for name, spec in G.MUSCLES.items():
        if spec["back"] != (not front):
            continue
        for i, poly in enumerate(polygons_for(name)):
            xs = [p[0] for p in poly]
            ys = [p[1] for p in poly]
            extent = min(max(xs) - min(xs), max(ys) - min(ys))
            depth = max(0.025, min(0.085, extent * 0.42))
            build_heightfield(poly, depth=depth, z_base=0.0,
                              name=f"{name}_{i}",
                              material=muscle_material(), erode=True)

    out = f"{OUT}/anatomy_body_{'front' if front else 'back'}.png"
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("rendered", out)


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "both"
    if which in ("front", "both"):
        build_view(front=True)
    if which in ("back", "both"):
        build_view(front=False)
