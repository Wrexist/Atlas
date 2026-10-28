#!/usr/bin/env python3
"""Cut each recipe photo out of its slate background into a transparent plate image.

Run with a Python that has rembg (BiRefNet) installed and pngquant on PATH:

    python tools/recipe-images/cutout.py [ids...]

Reads raw/recipe-<id>.png, writes recipe-<id>-cutout.imageset/ into the asset
catalog and refreshes cutout-sheet.jpg.
"""
import argparse
import io
import json
import shutil
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from rembg import new_session, remove
from skimage.feature import canny
from skimage.transform import hough_circle, hough_circle_peaks

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PROMPTS = HERE / "prompts.json"
ASSETS = REPO / "Peptide/Resources/Assets.xcassets/Recipes"
PNGQUANT = shutil.which("pngquant")


def find_plate(photo):
    """Outer rim of the round plate as (cx, cy, r) in photo pixels, via a Hough transform on edges."""
    scale = photo.width / 512
    gray = np.asarray(photo.convert("L").resize((512, 512)), dtype=float) / 255
    radii = np.arange(130, 256, 2)
    accums, xs, ys, rs = hough_circle_peaks(hough_circle(canny(gray, sigma=2.5), radii), radii, total_num_peaks=6)
    # The plate's inner well also forms a circle; take the widest concentric one that is nearly as strong.
    rim = max(
        (i for i in range(len(rs)) if np.hypot(xs[i] - xs[0], ys[i] - ys[0]) < 20 and accums[i] >= 0.6 * accums[0]),
        key=lambda i: rs[i],
    )
    return xs[rim] * scale, ys[rim] * scale, rs[rim] * scale


def disc(photo, cx, cy, r):
    """Anti-aliased disc alpha in 0...1."""
    yy, xx = np.mgrid[0 : photo.height, 0 : photo.width]
    return np.clip(r - np.hypot(xx + 0.5 - cx, yy + 0.5 - cy), 0, 1)


def food_mask(session, photo, cache):
    if not cache.exists():
        remove(photo, session=session, only_mask=True, post_process_mask=True).save(cache)
    return np.array(Image.open(cache), dtype=float)


def cut(session, photo, cache, size, padding):
    cx, cy, r = find_plate(photo)
    food = food_mask(session, photo, cache)
    food[food < 12] = 0
    # Pull the plate in a pixel so no slate shows at the rim; keep food that overhangs the rim
    # slightly, but drop props and cutlery lying further out on the table.
    alpha = np.maximum(disc(photo, cx, cy, r - 1) * 255, food * disc(photo, cx, cy, r * 1.06))
    matte = photo.convert("RGBA")
    matte.putalpha(Image.fromarray(alpha.astype(np.uint8)))
    left, top, right, bottom = matte.getchannel("A").getbbox()
    side = max(right - left, bottom - top) * (1 + 2 * padding)
    cx, cy = (left + right) / 2, (top + bottom) / 2
    box = tuple(round(v) for v in (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2))
    return matte.crop(box).resize((size, size), Image.LANCZOS)


def compress(image):
    raw = io.BytesIO()
    image.save(raw, "PNG")
    result = subprocess.run(
        [PNGQUANT, "--quality=0-90", "--speed=1", "--strip", "-"],
        input=raw.getvalue(), capture_output=True, check=True,
    )
    return result.stdout


def write_imageset(recipe_id, png):
    name = f"recipe-{recipe_id}-cutout"
    imageset = ASSETS / f"{name}.imageset"
    imageset.mkdir(exist_ok=True)
    (imageset / f"{name}.png").write_bytes(png)
    contents = {"images": [{"filename": f"{name}.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def cutout_sheet(ids, thumb=160, label=20, columns=10):
    rows = -(-len(ids) // columns)
    width, height = columns * thumb, rows * (thumb + label)
    sheet = Image.new("RGB", (width, height), (128, 128, 128))
    draw = ImageDraw.Draw(sheet)
    for x in range(0, width, 16):
        for y in range(0, height, 16):
            if (x // 16 + y // 16) % 2:
                draw.rectangle((x, y, x + 15, y + 15), fill=(150, 150, 150))
    font = ImageFont.load_default(size=10)
    for index, recipe_id in enumerate(ids):
        x, y = index % columns * thumb, index // columns * (thumb + label)
        name = f"recipe-{recipe_id}-cutout"
        cutout = Image.open(ASSETS / f"{name}.imageset/{name}.png").convert("RGBA").resize((thumb, thumb))
        sheet.paste(cutout, (x, y), cutout)
        draw.text((x + 3, y + thumb + 4), recipe_id, fill="white", font=font)
    sheet.save(HERE / "cutout-sheet.jpg", "JPEG", quality=80, optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ids", nargs="*", help="recipe ids to cut out (default: all)")
    parser.add_argument("--raw", type=Path, default=HERE / "raw")
    parser.add_argument("--model", default="birefnet-general")
    parser.add_argument("--size", type=int, default=384)
    parser.add_argument("--padding", type=float, default=0.02)
    args = parser.parse_args()

    all_ids = list(json.loads(PROMPTS.read_text()))
    session = new_session(args.model)
    for recipe_id in args.ids or all_ids:
        photo = Image.open(args.raw / f"recipe-{recipe_id}.png").convert("RGB")
        png = compress(cut(session, photo, args.raw / f"mask-{recipe_id}.png", args.size, args.padding))
        write_imageset(recipe_id, png)
        print(f"{recipe_id} {len(png) // 1024} KB", flush=True)
    cutout_sheet([i for i in all_ids if (ASSETS / f"recipe-{i}-cutout.imageset").exists()])


if __name__ == "__main__":
    main()
