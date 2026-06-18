#!/usr/bin/env python3
"""Copy a rendered anatomy pack into the asset catalog.

Reads PNGs from $ATLAS_ANATOMY_OUT (default /tmp/atlas_pack) produced by
`render_zanatomy.py` and writes each into
`Peptide/Resources/Assets.xcassets/Anatomy/<name>.imageset/`, creating the
imageset + Contents.json as needed. Names already match `AnatomyAssets`.
"""
import json
import os
import shutil
import sys

SRC = os.environ.get("ATLAS_ANATOMY_OUT", "/tmp/atlas_pack")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST = os.path.join(ROOT, "Peptide/Resources/Assets.xcassets/Anatomy")


def main():
    pngs = [f for f in os.listdir(SRC) if f.endswith(".png")]
    if not pngs:
        sys.exit(f"no PNGs in {SRC} — run render_zanatomy.py first")
    for png in sorted(pngs):
        name = png[:-4]
        imageset = os.path.join(DST, f"{name}.imageset")
        os.makedirs(imageset, exist_ok=True)
        shutil.copy2(os.path.join(SRC, png), os.path.join(imageset, png))
        with open(os.path.join(imageset, "Contents.json"), "w") as f:
            json.dump({
                "images": [{"filename": png, "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }, f, indent=2)
    print(f"installed {len(pngs)} imagesets into {DST}")


if __name__ == "__main__":
    main()
