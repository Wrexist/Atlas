#!/usr/bin/env python3
"""Generate per-muscle alpha masks and Xcode imagesets for the anatomy pack.

Masks are rasterized from the same polygons the Blender renders are
built from, at the same orthographic mapping, so they are pixel-aligned
with `anatomy_body_front/back` by construction. Run after
blender_build.py; pass the path to Assets.xcassets to also write the
imageset folders the app loads.

Usage:
    python3 make_masks.py [path/to/Assets.xcassets]
"""
import json
import os
import shutil
import sys

from PIL import Image, ImageDraw

import geometry as G
from spline import catmull_closed, mirror_pts, rounded_rect_poly

OUT = os.environ.get("ANATOMY_OUT", "/tmp/anatomy/assets")
SS = 4              # supersampling factor for clean mask edges
W, H = 1200, 2880   # must match blender_build.py's final output size


def polygons_for(name):
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


def write_masks():
    for name in G.MUSCLES:
        big = Image.new("L", (W * SS, H * SS), 0)
        d = ImageDraw.Draw(big)
        for poly in polygons_for(name):
            d.polygon([(x * W * SS, y / 2.4 * H * SS) for (x, y) in poly], fill=255)
        alpha = big.resize((W, H), Image.LANCZOS)
        mask = Image.new("RGBA", (W, H), (255, 255, 255, 0))
        mask.putalpha(alpha)
        mask.save(f"{OUT}/anatomy_{name}.png")
    print("masks written:", len(G.MUSCLES))


def write_imagesets(catalog):
    anatomy_dir = os.path.join(catalog, "Anatomy")
    os.makedirs(anatomy_dir, exist_ok=True)
    with open(os.path.join(anatomy_dir, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

    names = ["anatomy_body_front", "anatomy_body_back"] + [
        f"anatomy_{n}" for n in G.MUSCLES
    ]
    for name in names:
        src = f"{OUT}/{name}.png"
        if not os.path.exists(src):
            raise SystemExit(f"missing {src} — run blender_build.py first")
        iset = os.path.join(anatomy_dir, f"{name}.imageset")
        os.makedirs(iset, exist_ok=True)
        shutil.copy(src, os.path.join(iset, f"{name}.png"))
        with open(os.path.join(iset, "Contents.json"), "w") as f:
            json.dump({
                "images": [{"filename": f"{name}.png", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }, f, indent=2)
    print("imagesets written:", len(names))


if __name__ == "__main__":
    write_masks()
    if len(sys.argv) > 1:
        write_imagesets(sys.argv[1])
