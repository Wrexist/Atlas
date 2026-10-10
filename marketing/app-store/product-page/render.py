"""Render the product-page art to PNG at App Store dimensions.

    python render.py              all pages
    python render.py header-a     one page

Uses a locally installed Chrome or Edge in headless mode, so it needs no
Playwright download. Output lands in out/.
"""
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SIZES = {
    "header-a": (3840, 1646),
    "header-b": (3840, 1646),
    "search-a": (3840, 2560),
    "search-b": (3840, 2560),
}
BROWSERS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "google-chrome",
    "chromium",
]


def browser():
    for candidate in BROWSERS:
        if Path(candidate).exists() or shutil.which(candidate):
            return candidate
    sys.exit("No Chrome or Edge found")


def render(name, size):
    out = HERE / "out" / f"{name}.png"
    out.parent.mkdir(exist_ok=True)
    width, height = size
    subprocess.run([
        browser(), "--headless=new", "--hide-scrollbars", "--disable-gpu",
        "--force-device-scale-factor=1", "--force-color-profile=srgb",
        "--virtual-time-budget=8000",
        f"--window-size={width},{height}", f"--screenshot={out}",
        (HERE / f"{name}.html").as_uri(),
    ], check=True, capture_output=True)
    image = Image.open(out)
    assert image.size == size, f"{name}: rendered {image.size}, expected {size}"
    # App Store Connect rejects alpha channels on these assets.
    image = image.convert("RGB")
    image.save(out, optimize=True)
    print(f"{out.relative_to(HERE)}  {width}x{height}")
    # Search results also accept the 1920 x 1280 base size.
    if name.startswith("search-"):
        small = out.with_name(f"{name}-1920.png")
        image.resize((1920, 1280), Image.LANCZOS).save(small, optimize=True)
        print(f"{small.relative_to(HERE)}  1920x1280")


if __name__ == "__main__":
    wanted = sys.argv[1:] or list(SIZES)
    for page in wanted:
        if (HERE / f"{page}.html").exists():
            render(page, SIZES[page])
