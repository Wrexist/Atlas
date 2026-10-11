#!/usr/bin/env python3
"""Bundle every catalog exercise's start and finish photo.

Source: free-exercise-db by yuhonas (Unlicense, public domain), pinned to a
commit so a rerun reproduces the same files. Each exercise's two `images`
entries in exercises.json become Peptide/Resources/ExercisePhotos/<id>_0.jpg
and <id>_1.jpg, capped at 600 px on the longest side.

    python3 scripts/exercise-photos.py           download missing, resize all
    python3 scripts/exercise-photos.py --check   verify every pair exists
"""
import io
import json
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Peptide" / "Resources" / "exercises.json"
OUT = ROOT / "Peptide" / "Resources" / "ExercisePhotos"
SOURCE_COMMIT = "f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5"
BASE_URL = f"https://raw.githubusercontent.com/yuhonas/free-exercise-db/{SOURCE_COMMIT}/exercises/"
LONGEST_SIDE = 600
QUALITY = 68


def jobs():
    for exercise in json.loads(CATALOG.read_text(encoding="utf-8")):
        for index, rel in enumerate(exercise["images"][:2]):
            yield BASE_URL + rel, OUT / f"{exercise['id']}_{index}.jpg"


def fetch(job):
    # Imported here so `--check` runs on a bare Python without Pillow.
    from PIL import Image

    url, dest = job
    if dest.exists():
        return None
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            image = Image.open(io.BytesIO(response.read())).convert("RGB")
    except Exception as error:
        return f"{url}: {error}"
    image.thumbnail((LONGEST_SIDE, LONGEST_SIDE), Image.LANCZOS)
    image.save(dest, "JPEG", quality=QUALITY, optimize=True)
    return None


def main():
    expected = list(jobs())
    if "--check" in sys.argv:
        missing = [dest.name for _, dest in expected if not dest.exists()]
        print(f"{len(expected) - len(missing)}/{len(expected)} photos present")
        sys.exit(1 if missing else 0)
    OUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=16) as pool:
        failures = [f for f in pool.map(fetch, expected) if f]
    for failure in failures:
        print("FAIL", failure)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
