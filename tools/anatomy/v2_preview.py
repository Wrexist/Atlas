"""Render the AnatomyV2 muscle regions the way the app draws them.

Reproduces MuscleMapView's asset renderer in Pillow: the shaded body, then a
`colorMultiply`-tinted copy of it clipped to each lit region's smoothed,
mirrored, slightly blurred path (TrainingAnatomy.path). Use it to check region
placement against the sculpt before shipping a geometry change.

    python3 tools/anatomy/v2_preview.py regions OUT_DIR
    python3 tools/anatomy/v2_preview.py exercises OUT_DIR
    python3 tools/anatomy/v2_preview.py grid front 300 250 520 450 OUT.png [--regions a,b]

`regions` paints every region a distinct colour, `exercises` renders the
reference lifts on the light and dark training backgrounds, and `grid` crops
an enlarged, coordinate-ruled patch of the artwork for authoring vertices.
The highlight rules below are a Python twin of
`ExerciseAnatomyEngine.highlights(for:)` and `AnatomicalMuscle.headWeights`.
"""
import argparse
import colorsys
import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "Peptide/Resources/Assets.xcassets/AnatomyV2"
REGIONS = ROOT / "Peptide/Resources/anatomy-regions-v2.json"
MODEL = ROOT / "Peptide/Models/Training/AnatomicalMuscle.swift"
WIDTH, HEIGHT = 1024, 1536
# Must match TrainingAnatomy.mirrorAxis: the sculpt's midline, not the canvas centre.
MIRROR_AXIS = 509
SUPERSAMPLE = 2

THEMES = {
    "light": {"background": (0xEA, 0xF3, 0xF9), "primary": (0xB8, 0x48, 0x13), "secondary": (0x24, 0x65, 0xDF)},
    "dark": {"background": (0x15, 0x1D, 0x27), "primary": (0xFF, 0xAC, 0x73), "secondary": (0x80, 0xAD, 0xFF)},
}
# MuscleMapView.tintStrength
STRENGTH = {"primary": 0.9, "secondary": 0.5}

EXAMPLES = [
    "Barbell Squat", "Barbell Deadlift", "Barbell Bench Press - Medium Grip", "Pullups",
    "Dumbbell Bicep Curl", "Seated Cable Rows", "Standing Military Press", "Plank",
    "Barbell Lunge", "Standing Calf Raises",
]


def back_regions():
    model = MODEL.read_text(encoding="utf-8")
    cases = model.split("var isBack: Bool", 1)[1].split("return true", 1)[0]
    return set(re.findall(r"\.(\w+)", cases))


def load_regions():
    return json.loads(REGIONS.read_text())


def body(side):
    return Image.open(ASSETS / f"atlas_body_{side}.imageset/atlas_body_{side}.png").convert("RGBA")


def smooth(points, steps=12):
    """TrainingAnatomy.path: quadratic curves through edge midpoints."""
    curve = []
    n = len(points)
    for i in range(n):
        a = [(points[i - 1][k] + points[i][k]) / 2 for k in (0, 1)]
        b = [(points[i][k] + points[(i + 1) % n][k]) / 2 for k in (0, 1)]
        for s in range(steps):
            t = s / steps
            curve.append(tuple((1 - t) ** 2 * a[k] + 2 * (1 - t) * t * points[i][k] + t * t * b[k] for k in (0, 1)))
    return curve


def outlines(points):
    curve = smooth(points)
    return [curve, [(2 * MIRROR_AXIS - x, y) for x, y in curve]]


def mask(points, blur=2.0):
    """Region coverage at artwork resolution, softened like `.blur(radius: 0.65)`."""
    big = Image.new("L", (WIDTH * SUPERSAMPLE, HEIGHT * SUPERSAMPLE), 0)
    draw = ImageDraw.Draw(big)
    for outline in outlines(points):
        draw.polygon([(x * SUPERSAMPLE, y * SUPERSAMPLE) for x, y in outline], fill=255)
    small = big.resize((WIDTH, HEIGHT), Image.LANCZOS)
    return small.filter(ImageFilter.GaussianBlur(blur)) if blur else small


def tint(base, color, coverage, strength):
    """Composite a colorMultiply copy of `base` through `coverage` at `strength`."""
    r, g, b, a = base.split()
    tinted = Image.merge("RGBA", (
        r.point(lambda v: v * color[0] // 255), g.point(lambda v: v * color[1] // 255),
        b.point(lambda v: v * color[2] // 255), a))
    weight = coverage.point(lambda v: int(v * strength))
    return Image.composite(tinted, base, weight)


def on_background(image, color):
    canvas = Image.new("RGBA", image.size, color + (255,))
    canvas.alpha_composite(image)
    return canvas.convert("RGB")


def distinct_color(index):
    r, g, b = colorsys.hls_to_rgb((index * 0.618034) % 1, 0.5, 0.85)
    return int(r * 255), int(g * 255), int(b * 255)


def render_regions(out_dir):
    regions, back = load_regions(), back_regions()
    for side in ("front", "back"):
        image = body(side)
        legend = []
        for index, (name, points) in enumerate(regions.items()):
            if (name in back) != (side == "back"):
                continue
            color = distinct_color(index)
            colored = Image.new("RGBA", image.size, color + (255,))
            coverage = mask(points)
            alpha = Image.eval(image.getchannel("A"), lambda v: v)
            weight = Image.composite(coverage.point(lambda v: int(v * 0.62)), Image.new("L", image.size, 0), alpha)
            image = Image.composite(colored, image, weight)
            legend.append((name, color, points))
        canvas = on_background(image, (0xEA, 0xF3, 0xF9))
        draw = ImageDraw.Draw(canvas)
        for name, color, points in legend:
            for outline in outlines(points):
                draw.line(outline + [outline[0]], fill=(255, 255, 255), width=1)
            cx = sum(p[0] for p in points) / len(points)
            cy = sum(p[1] for p in points) / len(points)
            draw.text((cx - 20, cy - 5), name[:10], fill=(20, 20, 20))
        path = out_dir / f"regions-{side}.png"
        canvas.save(path)
        print(path)


# MARK: - Highlight rules (twin of AnatomicalMuscle.headWeights)

def head_weights(raw, name=""):
    n = name.lower()

    def has(*keys):
        return any(k in n for k in keys)

    raw = raw.lower()
    if raw == "chest":
        if has("incline"):
            return {"pecClavicular": 1.0, "pecSternal": 0.55}
        if has("decline"):
            return {"pecSternal": 1.0, "pecClavicular": 0.30}
        return {"pecSternal": 1.0, "pecClavicular": 0.70}
    if raw == "shoulders":
        if has("lateral raise", "side lateral", "upright row"):
            return {"deltLateralFront": 1.0, "deltLateralBack": 1.0, "deltAnterior": 0.30, "deltPosterior": 0.30}
        if has("rear", "reverse fly", "reverse flye", "face pull", "rear delt"):
            return {"deltPosterior": 1.0, "deltLateralBack": 0.50, "deltLateralFront": 0.20, "deltAnterior": 0.10}
        if has("front raise", "overhead", "military", "arnold", "push press", "shoulder press"):
            return {"deltAnterior": 1.0, "deltLateralFront": 0.60, "deltLateralBack": 0.30, "deltPosterior": 0.20}
        if has("press"):
            return {"deltAnterior": 0.60, "deltLateralFront": 0.40, "deltLateralBack": 0.25, "deltPosterior": 0.15}
        return {"deltAnterior": 0.80, "deltLateralFront": 0.80, "deltLateralBack": 0.70, "deltPosterior": 0.60}
    if raw == "triceps":
        if has("overhead", "french", "skull", "lying triceps", "lying extension"):
            return {"tricepsLong": 1.0, "tricepsLateral": 0.60}
        if has("pushdown", "pressdown", "kickback", "close-grip", "close grip", "dip"):
            return {"tricepsLateral": 1.0, "tricepsLong": 0.60}
        return {"tricepsLong": 0.85, "tricepsLateral": 0.85}
    if raw == "calves":
        if has("seated"):
            return {"soleus": 1.0, "gastrocnemius": 0.40, "tibialis": 0.15}
        if has("tibialis", "toe raise"):
            return {"tibialis": 1.0, "gastrocnemius": 0.20, "soleus": 0.20}
        return {"gastrocnemius": 1.0, "soleus": 0.70, "tibialis": 0.20}
    if raw == "traps":
        if has("shrug"):
            return {"trapsUpper": 1.0, "trapsLower": 0.30}
        if has("row", "face pull", "y raise", "y-raise", "pulldown", "pull-up", "pullup"):
            return {"trapsLower": 0.90, "trapsUpper": 0.60}
        return {"trapsUpper": 0.90, "trapsLower": 0.70}
    if raw == "middle back":
        return {"rhomboids": 1.0, "trapsLower": 0.50, "lats": 0.40}
    if raw == "quadriceps":
        if has("hack", "front squat", "sissy", "leg extension"):
            return {"quadRectus": 1.0, "quadLateralis": 0.90, "quadMedialis": 0.90}
        return {"quadRectus": 1.0, "quadLateralis": 1.0, "quadMedialis": 1.0}
    if raw == "hamstrings":
        return {"hamstringLateral": 1.0, "hamstringMedial": 1.0}
    if raw == "abdominals":
        if has("twist", "russian", "side bend", "oblique", "woodchop", "wood chop", "side plank", "windmill"):
            return {"obliques": 1.0, "abdominals": 0.60}
        return {"abdominals": 1.0, "obliques": 0.45}
    groups = {  # custom exercises store MuscleGroup raw values
        "back": {"lats": 1.0, "rhomboids": 0.90, "trapsLower": 0.80, "trapsUpper": 0.50, "lowerBack": 0.50},
        "arms": {"biceps": 0.90, "tricepsLong": 0.90, "tricepsLateral": 0.90, "forearmFront": 0.50, "forearmBack": 0.50},
        "legs": {"quadRectus": 1.0, "quadLateralis": 1.0, "quadMedialis": 1.0, "hamstringLateral": 0.80,
                 "hamstringMedial": 0.80, "glutes": 0.70, "adductors": 0.50, "gastrocnemius": 0.50},
        "core": {"abdominals": 1.0, "obliques": 0.80, "lowerBack": 0.40},
    }
    if raw in groups:
        return groups[raw]
    simple = {
        "obliques": "obliques", "neck": "neck", "biceps": "biceps", "glutes": "glutes",
        "abductors": "gluteMedius", "adductors": "adductors", "lats": "lats", "lower back": "lowerBack",
    }
    if raw == "forearms":
        return {"forearmFront": 1.0, "forearmBack": 1.0}
    return {simple[raw]: 1.0} if raw in simple else {}


def highlights(exercise):
    """Twin of ExerciseAnatomyEngine.highlights(for:)."""
    lit, primary_weights = {}, {}
    for raw in exercise["secondaryMuscles"]:
        for muscle, weight in head_weights(raw, exercise["name"]).items():
            if weight >= 0.5:
                lit[muscle] = "secondary"
    for raw in exercise["primaryMuscles"]:
        for muscle, weight in head_weights(raw, exercise["name"]).items():
            primary_weights[muscle] = max(primary_weights.get(muscle, 0), weight)
            if weight >= 0.75:
                lit[muscle] = "primary"
            elif weight >= 0.4 and muscle not in lit:
                lit[muscle] = "secondary"
    if "primary" not in lit.values() and primary_weights:
        strongest = max(primary_weights.values())
        lit.update({m: "primary" for m, w in primary_weights.items() if w >= strongest})
    return lit


def render_highlights(side, lit, theme, regions, back):
    image = body(side)
    for role in ("secondary", "primary"):
        for name, kind in lit.items():
            if kind != role or (name in back) != (side == "back"):
                continue
            image = tint(image, THEMES[theme][role], mask(regions[name]), STRENGTH[role])
    return on_background(image, THEMES[theme]["background"])


def render_exercises(out_dir):
    regions, back = load_regions(), back_regions()
    catalog = {e["name"]: e for e in json.loads((ROOT / "Peptide/Resources/exercises.json").read_text())}
    font = ImageFont.load_default()
    for name in EXAMPLES:
        exercise = catalog[name]
        lit = highlights(exercise)
        rows = []
        for theme in ("light", "dark"):
            pair = [render_highlights(side, lit, theme, regions, back) for side in ("front", "back")]
            row = Image.new("RGB", (WIDTH * 2, HEIGHT), THEMES[theme]["background"])
            row.paste(pair[0], (0, 0))
            row.paste(pair[1], (WIDTH, 0))
            rows.append(row.resize((WIDTH, HEIGHT // 2), Image.LANCZOS))
        sheet = Image.new("RGB", (WIDTH * 2, HEIGHT // 2 + 40), (255, 255, 255))
        sheet.paste(rows[0], (0, 40))
        sheet.paste(rows[1], (WIDTH, 40))
        caption = f"{name}   primary: {', '.join(sorted(k for k, v in lit.items() if v == 'primary'))}" \
                  f"   secondary: {', '.join(sorted(k for k, v in lit.items() if v == 'secondary'))}"
        ImageDraw.Draw(sheet).text((12, 12), caption, fill=(20, 20, 20), font=font)
        path = out_dir / f"exercise-{re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')}.png"
        sheet.save(path)
        print(path)


def render_grid(side, box, out, names):
    """Enlarged, contrast-stretched crop ruled every 25 px for placing vertices."""
    regions = load_regions()
    x0, y0, x1, y1 = box
    scale = max(1, int(900 / max(x1 - x0, y1 - y0)))
    crop = on_background(body(side), (40, 40, 40)).crop(box)
    crop = ImageOps.autocontrast(crop, cutoff=(8, 0.5)).resize(((x1 - x0) * scale, (y1 - y0) * scale), Image.LANCZOS).convert("RGBA")
    rules = Image.new("RGBA", crop.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(rules)
    for gx in range((x0 // 25 + 1) * 25, x1, 25):
        major = gx % 100 == 0
        draw.line([((gx - x0) * scale, 0), ((gx - x0) * scale, crop.height)], fill=(255, 40, 40, 150) if major else (60, 160, 255, 90))
        draw.text(((gx - x0) * scale + 2, 2), str(gx), fill=(255, 255, 0, 255))
    for gy in range((y0 // 25 + 1) * 25, y1, 25):
        major = gy % 100 == 0
        draw.line([(0, (gy - y0) * scale), (crop.width, (gy - y0) * scale)], fill=(255, 40, 40, 150) if major else (60, 160, 255, 90))
        draw.text((2, (gy - y0) * scale + 2), str(gy), fill=(255, 255, 0, 255))
    for index, name in enumerate(names):
        color = distinct_color(index * 3) + (255,)
        for outline in outlines(regions[name]):
            draw.line([((x - x0) * scale, (y - y0) * scale) for x, y in outline + [outline[0]]], fill=color, width=2)
        for i, (x, y) in enumerate(regions[name]):
            draw.text(((x - x0) * scale + 3, (y - y0) * scale - 10), str(i), fill=color)
    crop.alpha_composite(rules)
    crop.convert("RGB").save(out)
    print(out, f"scale {scale}")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("regions", "exercises"):
        sub.add_parser(command).add_argument("out_dir", type=Path)
    grid = sub.add_parser("grid")
    grid.add_argument("side", choices=("front", "back"))
    grid.add_argument("box", type=int, nargs=4)
    grid.add_argument("out", type=Path)
    grid.add_argument("--regions", default="")
    args = parser.parse_args()
    if args.command == "grid":
        render_grid(args.side, tuple(args.box), args.out, [n for n in args.regions.split(",") if n])
        return
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (render_regions if args.command == "regions" else render_exercises)(args.out_dir)


if __name__ == "__main__":
    main()
