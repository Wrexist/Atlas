#!/usr/bin/env python3
"""Generate recipe photos with a local ComfyUI server and export them to the asset catalog.

    python tools/recipe-images/generate.py generate [ids...]   # render PNGs into --raw
    python tools/recipe-images/generate.py export              # JPEG image sets + contact sheet

Seeds are fixed per recipe (crc32 of the id plus the offset in rerolls.json), so a
run is reproducible; bump an id's offset in rerolls.json to re-roll a bad image.
"""
import argparse
import json
import time
import urllib.request
import uuid
import zlib
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PROMPTS = HERE / "prompts.json"
REROLLS = HERE / "rerolls.json"
ASSETS = REPO / "Peptide/Resources/Assets.xcassets/Recipes"

NEGATIVE = (
    "text, watermark, logo, signature, letters, label, hands, fingers, person, "
    "cutlery clutter, multiple plates, extra bowls, napkin, blurry, out of focus, "
    "lowres, jpeg artifacts, deformed food, oversaturated, cartoon, illustration, "
    "3d render, tilted angle, perspective view"
)


# FLUX ignores the negative prompt at CFG 1 and draws whatever the prompt names, even
# negated, so a dish that keeps drawing cutlery or props gets a positive-only nudge from
# its second re-roll on.
ISOLATE = (
    " Tight composition: the plate is centred and fills most of the square frame,"
    " surrounded only by an empty, evenly and softly lit dark slate surface."
)


def prompt_for(recipe_id, prompts, rerolls):
    return prompts[recipe_id] + (ISOLATE if rerolls.get(recipe_id, 0) >= 2 else "")


def seed_for(recipe_id, rerolls):
    return zlib.crc32(recipe_id.encode()) + 1_000_003 * rerolls.get(recipe_id, 0)


def workflow(args, prompt, seed, prefix):
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": args.checkpoint}},
        "2": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["1", 1], "text": prompt}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["1", 1], "text": NEGATIVE}},
        "4": {"class_type": "EmptyLatentImage", "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
        "5": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["1", 0], "positive": ["2", 0], "negative": ["3", 0], "latent_image": ["4", 0],
                "seed": seed, "steps": args.steps, "cfg": args.cfg,
                "sampler_name": args.sampler, "scheduler": args.scheduler, "denoise": 1.0,
            },
        },
        "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0], "vae": ["1", 2]}},
        "7": {"class_type": "SaveImage", "inputs": {"images": ["6", 0], "filename_prefix": prefix}},
    }


def api(server, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(f"{server}{path}", data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def render(args, prompt, seed, prefix):
    queued = json.loads(api(args.server, "/prompt", {"prompt": workflow(args, prompt, seed, prefix), "client_id": str(uuid.uuid4())}))
    prompt_id = queued["prompt_id"]
    while True:
        history = json.loads(api(args.server, f"/history/{prompt_id}"))
        if prompt_id in history:
            outputs = history[prompt_id]["outputs"]["7"]["images"][0]
            query = f"filename={outputs['filename']}&subfolder={outputs['subfolder']}&type={outputs['type']}"
            return api(args.server, f"/view?{query}")
        time.sleep(1)


def generate(args):
    prompts = json.loads(PROMPTS.read_text())
    rerolls = json.loads(REROLLS.read_text()) if REROLLS.exists() else {}
    args.raw.mkdir(parents=True, exist_ok=True)
    for recipe_id in args.ids or [i for i in prompts if not (args.raw / f"recipe-{i}.png").exists()]:
        seed = seed_for(recipe_id, rerolls)
        started = time.time()
        png = render(args, prompt_for(recipe_id, prompts, rerolls), seed, f"recipe-{recipe_id}")
        (args.raw / f"recipe-{recipe_id}.png").write_bytes(png)
        print(f"{recipe_id} seed={seed} {time.time() - started:.0f}s", flush=True)


def export(args):
    prompts = json.loads(PROMPTS.read_text())
    for recipe_id in prompts:
        image = Image.open(args.raw / f"recipe-{recipe_id}.png").convert("RGB").resize((768, 768), Image.LANCZOS)
        imageset = ASSETS / f"recipe-{recipe_id}.imageset"
        imageset.mkdir(exist_ok=True)
        image.save(imageset / f"recipe-{recipe_id}.jpg", "JPEG", quality=82, optimize=True, progressive=True)
        contents = {"images": [{"filename": f"recipe-{recipe_id}.jpg", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
        (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    contact_sheet(args, list(prompts))


def contact_sheet(args, ids, thumb=200, label=22, columns=8):
    rows = -(-len(ids) // columns)
    sheet = Image.new("RGB", (columns * thumb, rows * (thumb + label)), "white")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=11)
    for index, recipe_id in enumerate(ids):
        x, y = index % columns * thumb, index // columns * (thumb + label)
        sheet.paste(Image.open(args.raw / f"recipe-{recipe_id}.png").convert("RGB").resize((thumb, thumb)), (x, y))
        draw.text((x + 4, y + thumb + 5), recipe_id, fill="black", font=font)
    sheet.save(HERE / "contact-sheet.jpg", "JPEG", quality=80, optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["generate", "export"])
    parser.add_argument("ids", nargs="*", help="recipe ids to generate (default: all)")
    parser.add_argument("--server", default="http://127.0.0.1:8188")
    parser.add_argument("--raw", type=Path, default=HERE / "raw", help="where full-size PNGs are kept (not committed)")
    parser.add_argument("--checkpoint", default="flux1-schnell-fp8.safetensors")
    parser.add_argument("--steps", type=int, default=4)
    parser.add_argument("--cfg", type=float, default=1.0)
    parser.add_argument("--sampler", default="euler")
    parser.add_argument("--scheduler", default="simple")
    args = parser.parse_args()
    generate(args) if args.command == "generate" else export(args)


if __name__ == "__main__":
    main()
