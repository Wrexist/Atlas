# Temporal flicker score of an exercise loop: per frame, |f(t) - (f(t-1) + f(t+1)) / 2| on the body (smooth motion
# mostly cancels, frame-to-frame boiling and pops don't), split into body interior and silhouette ring.
# python -P flicker_score.py <exercise> [...]     (reads out/<exercise>.mp4 + out/frames_<exercise>/ alpha)
import os, sys, subprocess
import numpy as np
from scipy import ndimage
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")


def video(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "gray", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, 1350, 1080).astype(np.float32)


def alpha(name, f):
    return np.asarray(Image.open(os.path.join(OUT, f"frames_{name}", f"{f:04d}.png")).getchannel("A")) > 127


for name in sys.argv[1:]:
    v = video(os.path.join(OUT, f"{name}.mp4"))
    inner, ring, worst = [], [], (0, 0)
    for t in range(1, len(v) - 1):
        body = alpha(name, t + 1)
        core = ndimage.binary_erosion(body, iterations=4)
        edge = ndimage.binary_dilation(body, iterations=3) & ~core
        e = np.abs(v[t] - (v[t - 1] + v[t + 1]) / 2)
        inner.append(e[core].mean())
        ring.append(e[edge].mean())
        worst = max(worst, (inner[-1], t + 1))
    inner, ring = np.array(inner), np.array(ring)
    print(f"FLICKER {name:14s} body mean {inner.mean():.2f} p95 {np.percentile(inner, 95):.2f} (worst f{worst[1]} "
          f"{worst[0]:.2f}) | silhouette mean {ring.mean():.2f} p95 {np.percentile(ring, 95):.2f}")
