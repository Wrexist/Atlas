"""Build/check the exhaustive visual registry and export exact exercise briefs.

No image requests or paid services are invoked. Run --sync after adding inspected
art to tools/exercise-art/illustrations.json; --check is suitable for CI.
"""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Peptide/Resources/exercises.json"
REGISTRY = ROOT / "Peptide/Resources/exercise-visuals.json"
ART = ROOT / "Peptide/Resources/Assets.xcassets/ExerciseArt"
PRODUCTION = ROOT / "tools/exercise-art"
STYLE = (
    "One isolated transparent PNG, premium soft-studio 3D anatomical fitness "
    "illustration. Faceless gray adult mannequin, black shorts, white trainers; "
    "graphite equipment. Entire subject/equipment visible with clear margins. "
    "Primary muscles orange, secondary muscles cobalt blue, other muscles gray. "
    "No text, UI, watermark, arrows or background. Show the exact movement and "
    "equipment below, not a similar exercise. Do not invent a missing setup. "
    "Inspect pose, grip, contact points, anatomy, highlights and alpha before use."
)


def build():
    exercises = json.loads(CATALOG.read_text(encoding="utf-8"))
    approved = json.loads((PRODUCTION / "illustrations.json").read_text(encoding="utf-8"))
    ids = [e["id"] for e in exercises]
    assert len(ids) == len(set(ids)), "Duplicate exercise IDs"
    assert set(approved) <= set(ids), "Art references unknown exercise IDs"
    assets = [a["asset"] for a in approved.values()]
    assert len(assets) == len(set(assets)), "Different exercises must not silently share a pose"
    for exercise_id, record in approved.items():
        folder = ART / (record["asset"] + ".imageset")
        contents = json.loads((folder / "Contents.json").read_text(encoding="utf-8"))
        names = [x["filename"] for x in contents["images"] if "filename" in x]
        assert names, f"No image: {exercise_id}"
        for name in names:
            path = folder / name
            assert path.resolve().is_relative_to(folder.resolve()), "Unsafe asset path"
            assert path.is_file(), f"Missing asset: {exercise_id}"
            assert hashlib.sha256(path.read_bytes()).hexdigest() == record["sha256"], f"Changed art: {exercise_id}"
    registry, queue = [], []
    for exercise in exercises:
        record = approved.get(exercise["id"])
        registry.append({"id": exercise["id"], "status": "illustrated" if record else "muscleMap", "asset": record["asset"] if record else None})
        if not record:
            queue.append({
                "id": exercise["id"], "name": exercise["name"], "status": "needsIllustration",
                "category": exercise["category"], "equipment": exercise["equipment"],
                "primaryMuscles": exercise["primaryMuscles"], "secondaryMuscles": exercise["secondaryMuscles"],
                "sourceInstructions": exercise["instructions"], "sourceImages": exercise["images"],
                "prompt": STYLE + " Exercise: " + exercise["name"] + ". Equipment: " + str(exercise["equipment"]) + ". Primary: " + ", ".join(exercise["primaryMuscles"]) + ". Secondary: " + ", ".join(exercise["secondaryMuscles"]) + ". Movement: " + " ".join(exercise["instructions"]),
            })
    return registry, queue


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sync", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    registry, queue = build()
    files = {
        REGISTRY: json.dumps(registry, indent=2, ensure_ascii=False) + "\n",
        PRODUCTION / "pending.jsonl": "".join(json.dumps(x, ensure_ascii=False) + "\n" for x in queue),
    }
    for path, expected in files.items():
        if args.sync:
            path.write_text(expected, encoding="utf-8")
        else:
            assert path.exists() and path.read_text(encoding="utf-8") == expected, f"Stale {path.relative_to(ROOT)}; run --sync"
    print(f"{len(registry)} catalog entries: {dict(Counter(x['status'] for x in registry))}; {len(queue)} outstanding briefs")


if __name__ == "__main__":
    main()
