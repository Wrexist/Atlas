"""Validate muscle control polygons and build a non-native geometry review page.

The page embeds unchanged production PNGs and reproduces TrainingAnatomy's
quadratic paths. It is an artwork alignment aid, not an iOS screenshot.
"""
import argparse
import base64
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def validate(regions):
    model = (ROOT / "Peptide/Models/Training/AnatomicalMuscle.swift").read_text(encoding="utf-8")
    cases = set(re.findall(r"^    case (\w+)\s*$", model, re.M))
    assert set(regions) == cases, "Region keys must match the muscle catalog"
    for name, points in regions.items():
        assert len(points) >= 3, f"{name}: too few vertices"
        assert len(set(map(tuple, points))) == len(points), f"{name}: duplicate vertices"
        assert all(len(p) == 2 and 0 <= p[0] < 512 and 0 <= p[1] <= 1536 for p in points), name
        n = len(points)
        for i in range(n):
            a, b = points[i], points[(i + 1) % n]
            for j in range(i + 1, n):
                if j == i + 1 or (i == 0 and j == n - 1):
                    continue
                c, d = points[j], points[(j + 1) % n]
                assert not (cross(a, b, c) * cross(a, b, d) < 0 and
                            cross(c, d, a) * cross(c, d, b) < 0), f"{name}: crossing edges"
        area = abs(sum(points[i][0] * points[(i + 1) % n][1] -
                       points[(i + 1) % n][0] * points[i][1] for i in range(n))) / 2
        assert area > 100, f"{name}: degenerate region"


def path_data(points):
    paths = []
    for mirrored in (False, True):
        p = [(1024 - x if mirrored else x, y) for x, y in points]
        mid = lambda a, b: ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        start = mid(p[-1], p[0])
        parts = [f"M {start[0]} {start[1]}"]
        for i, control in enumerate(p):
            end = mid(control, p[(i + 1) % len(p)])
            parts.append(f"Q {control[0]} {control[1]} {end[0]} {end[1]}")
        paths.append(" ".join(parts) + " Z")
    return " ".join(paths)


def check_alpha(regions, back):
    # Optional pixel-level check needs Pillow. Sampling the curve's interior
    # catches paths outside the cutout, including mirrored-side asymmetry.
    from PIL import Image
    images = {side: Image.open(ROOT / f"Peptide/Resources/Assets.xcassets/AnatomyV2/atlas_body_{side}.imageset/atlas_body_{side}.png")
              for side in ("front", "back")}
    failures = []
    for name, points in regions.items():
        curve = []
        for i, p in enumerate(points):
            prev, nxt = points[i - 1], points[(i + 1) % len(points)]
            a = [(prev[k] + p[k]) / 2 for k in (0, 1)]
            b = [(nxt[k] + p[k]) / 2 for k in (0, 1)]
            for n in range(16):
                t = n / 16
                curve.append(tuple((1-t)**2*a[k] + 2*(1-t)*t*p[k] + t*t*b[k] for k in (0, 1)))
        image = images["back" if name in back else "front"]
        total = outside = 0
        for x in range(int(min(p[0] for p in curve)), int(max(p[0] for p in curve)), 3):
            for y in range(int(min(p[1] for p in curve)), int(max(p[1] for p in curve)), 3):
                inside = False
                for i, (ax, ay) in enumerate(curve):
                    bx, by = curve[i - 1]
                    if (ay > y) != (by > y) and x < (bx-ax)*(y-ay)/(by-ay)+ax:
                        inside = not inside
                if inside:
                    for px in (x, 1024-x):
                        total += 1
                        outside += image.getpixel((px, y))[3] < 240
        ratio = outside / max(total, 1)
        print(f"{name}: {ratio:.2%} outside opaque body")
        if ratio >= .01:
            failures.append(name)
    assert not failures, f"Highlights extend beyond body cutout: {', '.join(failures)}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check-alpha", action="store_true")
    args = parser.parse_args()
    regions = json.loads((ROOT / "Peptide/Resources/anatomy-regions-v2.json").read_text())
    validate(regions)
    print(f"Validated {len(regions)} regions: coverage, bounds, distinct vertices, area and crossing edges")
    model = (ROOT / "Peptide/Models/Training/AnatomicalMuscle.swift").read_text(encoding="utf-8")
    back_cases = model.split("var isBack: Bool", 1)[1].split("return true", 1)[0]
    back = set(re.findall(r"\.(\w+)", back_cases))
    if args.check_alpha:
        check_alpha(regions, back)
    if not args.output:
        return
    figures = []
    for side in ("front", "back"):
        asset = ROOT / f"Peptide/Resources/Assets.xcassets/AnatomyV2/atlas_body_{side}.imageset/atlas_body_{side}.png"
        data = base64.b64encode(asset.read_bytes()).decode()
        paths = []
        for i, (name, points) in enumerate(regions.items()):
            if (name in back) != (side == "back"):
                continue
            color = f"hsl({i * 137.5 % 360:.1f} 76% 48%)"
            paths.append(f'<path data-name="{name}" d="{path_data(points)}" fill="{color}"><title>{name}</title></path>')
        figures.append(f'<section><h2>{side.title()}</h2><svg viewBox="0 0 1024 1536"><image width="1024" height="1536" href="data:image/png;base64,{data}"/>{"".join(paths)}</svg></section>')
    options = ''.join(f'<option>{name}</option>' for name in regions)
    html = '''<!doctype html><meta charset="utf-8"><title>Atlas muscle geometry review</title>
<style>body{font:16px system-ui;background:#edf2f6;color:#18202b;margin:24px}h1{font-size:24px;margin:0}p{max-width:850px}main{display:flex;gap:24px;max-width:1100px}section{flex:1;min-width:0}h2{text-align:center;font-size:18px}svg{width:100%;display:block}path{fill-opacity:.47;stroke:#fff;stroke-width:2;cursor:pointer}path:hover{fill-opacity:.85}button,select{padding:10px;font:inherit}body.dark{background:#111820;color:#edf2f6}</style>
<h1>Atlas muscle geometry review</h1><p>Production artwork and matching software paths. This is a browser alignment preview, not a native app capture. Colors distinguish regions; they are not workout intensity.</p>
<label>Region <select id="region"><option>All regions</option>OPTIONS</select></label> <button onclick="document.body.classList.toggle('dark')">Light / dark</button>
<main>FIGURES</main><script>const select=document.querySelector('select');function update(){document.querySelectorAll('path').forEach(p=>p.style.opacity=select.value==='All regions'||select.value===p.dataset.name?1:.06)}select.onchange=update;document.querySelectorAll('path').forEach(p=>p.onclick=()=>{select.value=p.dataset.name;update()});</script>'''
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(html.replace("OPTIONS", options).replace("FIGURES", "".join(figures)), encoding="utf-8")
    print(args.output)


if __name__ == "__main__":
    main()
