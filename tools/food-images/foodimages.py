#!/usr/bin/env python3
"""Food artwork photos: render with a local ComfyUI, cut out, export to the asset catalog.

    python tools/food-images/foodimages.py generate [ids...]   # raw/food-<id>.png via ComfyUI (FLUX)
    python tools/food-images/foodimages.py cutout [ids...]     # food-<id>.imageset + contact-sheet.jpg

Rendering reuses the recipe pipeline (tools/recipe-images/generate.py): same
model, sampler and fixed per-id seeds; bump an id in rerolls.json to re-roll.
Cutouts need rembg (BiRefNet) and pngquant on PATH, like the recipe cutouts.
"""
import argparse
import importlib.util
import io
import json
import shutil
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PROMPTS = HERE / "prompts.json"
REROLLS = HERE / "rerolls.json"
ASSETS = REPO / "Peptide/Resources/Assets.xcassets/Foods"
SIZE = 256

spec = importlib.util.spec_from_file_location("recipe_generate", REPO / "tools/recipe-images/generate.py")
recipe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recipe)


def ids(args, prompts):
    return args.ids or list(prompts)


def generate(args):
    prompts = json.loads(PROMPTS.read_text())
    rerolls = json.loads(REROLLS.read_text()) if REROLLS.exists() else {}
    args.raw.mkdir(parents=True, exist_ok=True)
    todo = args.ids or [i for i in prompts if not (args.raw / f"food-{i}.png").exists()]
    for food_id in todo:
        seed = recipe.seed_for(food_id, rerolls)
        started = time.time()
        png = recipe.render(args, prompts[food_id], seed, f"food-{food_id}")
        (args.raw / f"food-{food_id}.png").write_bytes(png)
        print(f"{food_id} seed={seed} {time.time() - started:.0f}s", flush=True)


def cut(session, photo):
    from rembg import remove

    matte = remove(photo, session=session, post_process_mask=True)
    left, top, right, bottom = matte.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
    side = max(right - left, bottom - top) * 1.08
    cx, cy = (left + right) / 2, (top + bottom) / 2
    box = tuple(round(v) for v in (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2))
    return matte.crop(box).resize((SIZE, SIZE), Image.LANCZOS)


def compress(image):
    raw = io.BytesIO()
    image.save(raw, "PNG")
    pngquant = shutil.which("pngquant")
    if not pngquant:
        return raw.getvalue()
    result = subprocess.run([pngquant, "--quality=0-90", "--speed=1", "--strip", "-"],
                            input=raw.getvalue(), capture_output=True, check=True)
    return result.stdout


def cutout(args):
    from rembg import new_session

    prompts = json.loads(PROMPTS.read_text())
    session = new_session("birefnet-general")
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for food_id in ids(args, prompts):
        image = cut(session, Image.open(args.raw / f"food-{food_id}.png").convert("RGB"))
        imageset = ASSETS / f"food-{food_id}.imageset"
        imageset.mkdir(exist_ok=True)
        (imageset / f"food-{food_id}.png").write_bytes(compress(image))
        contents = {"images": [{"filename": f"food-{food_id}.png", "idiom": "universal"}],
                    "info": {"author": "xcode", "version": 1}}
        (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
        print(food_id, flush=True)
    contact_sheet(list(prompts))


def contact_sheet(food_ids, thumb=128, label=20, columns=8):
    """Cutouts on the app's dark card colour, so a bad edge shows."""
    rows = -(-len(food_ids) // columns)
    sheet = Image.new("RGB", (columns * thumb, rows * (thumb + label)), (26, 26, 24))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=11)
    for index, food_id in enumerate(food_ids):
        path = ASSETS / f"food-{food_id}.imageset/food-{food_id}.png"
        if not path.exists():
            continue
        x, y = index % columns * thumb, index // columns * (thumb + label)
        tile = Image.open(path).convert("RGBA").resize((thumb - 16, thumb - 16))
        sheet.paste(tile, (x + 8, y + 8), tile)
        draw.text((x + 4, y + thumb + 3), food_id, fill="white", font=font)
    sheet.save(HERE / "contact-sheet.jpg", "JPEG", quality=82, optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["generate", "cutout"])
    parser.add_argument("ids", nargs="*")
    parser.add_argument("--server", default="http://127.0.0.1:8188")
    parser.add_argument("--raw", type=Path, default=HERE / "raw", help="full-size PNGs (not committed)")
    parser.add_argument("--checkpoint", default="flux1-schnell-fp8.safetensors")
    parser.add_argument("--steps", type=int, default=4)
    parser.add_argument("--cfg", type=float, default=1.0)
    parser.add_argument("--sampler", default="euler")
    parser.add_argument("--scheduler", default="simple")
    args = parser.parse_args()
    generate(args) if args.command == "generate" else cutout(args)


if __name__ == "__main__":
    main()
