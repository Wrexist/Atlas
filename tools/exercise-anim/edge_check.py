# Silhouette stability check + review sheets for the exercise loops.
# python -P edge_check.py [exercise ...]   (after render_all.sh; reads out/, writes out/edge_check.png, plus
# out/contact_sheet.png when run for all exercises)
import os, sys, subprocess
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
EXERCISES = tuple(sys.argv[1:]) or ("squat", "deadlift", "bench", "curl", "lateral_raise")
HOLD = (46, 47)               # consecutive frames inside every exercise's pause at the far end of the rep (same pose)
MOVING = (20, 21)
RING_PX = 8
ZOOM, CROP = 4, 80

sys.path.append(HERE)                 # appended, not prepended: stdlib modules win over local scripts
import composite as C


def mp4_frames(path, frames):
    """Decode 1-based frame numbers from an mp4 as uint8 RGB arrays."""
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         check=True, capture_output=True).stdout
    w, h = 1080, 1350
    video = np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3)
    return [video[f - 1].astype(int) for f in frames]


def ring(alpha):
    body = alpha > 0.5
    return ndimage.binary_dilation(body, iterations=RING_PX) & ~ndimage.binary_erosion(body, iterations=RING_PX)


def edge_point(alpha):
    """A point on the left silhouette edge at mid-height of the figure."""
    ys, xs = np.nonzero(alpha > 0.5)
    y = int((ys.min() + ys.max()) / 2)
    return y, int(xs[ys == y].min())


def crop(img, y, x):
    h = CROP // 2
    return Image.fromarray(img[y - h:y + h, x - h:x + h].astype(np.uint8)).resize((CROP * ZOOM,) * 2, Image.NEAREST)


def label(img, text):
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, img.width, 34), fill=(0, 0, 0))
    d.text((10, 6), text, fill=(235, 235, 235), font=ImageFont.load_default(22))
    return img


def frame_png(name, f):
    return os.path.join(OUT, f"frames_{name}", f"{f:04d}.png")


def luma(img):
    return img @ np.array([0.2126, 0.7152, 0.0722])


def motion_jitter(path, frames=range(8, 40)):
    """Frame-to-frame edge noise while moving: |f(t) - (f(t-1) + f(t+1)) / 2| on edge pixels (smooth motion cancels,
    shimmer doesn't). Edges come from each video's own gradients, so old and new are measured the same way."""
    vid = [luma(f) for f in mp4_frames(path, [t + k for t in frames for k in (-1, 0, 1)])]
    vals = []
    for i in range(0, len(vid), 3):
        prev, cur, nxt = vid[i:i + 3]
        g = np.hypot(*np.gradient(cur))
        edges = ndimage.binary_dilation(g > 6, iterations=2)
        vals.append(np.abs(cur - (prev + nxt) / 2)[edges])
    v = np.concatenate(vals)
    return v.mean(), np.percentile(v, 99)


def rim_dip(path, alpha, frame=1):
    """How much darker the 2 px just inside the lower-body silhouette are than the body 5-8 px further in
    (negative = dark fringe). Lower body only: its pose is the same in the old and new renders."""
    img = luma(mp4_frames(path, [frame])[0])
    body = alpha > 0.5
    body[: body.shape[0] * 55 // 100] = False
    edge = body & ~ndimage.binary_erosion(body, iterations=2)
    inner = ndimage.binary_erosion(body, iterations=5) & ~ndimage.binary_erosion(body, iterations=8)
    return img[edge].mean() - img[inner].mean()


def check():
    tiles, lines = [], []
    for name in EXERCISES:
        a, b = (C.read_rgba(frame_png(name, f)) for f in HOLD)
        r = ring(a[..., 3])
        comp = [C.composite(x).astype(int) for x in (a, b)]
        enc = mp4_frames(os.path.join(OUT, f"{name}.mp4"), HOLD)
        d_comp = np.abs(comp[0] - comp[1]).max(-1)[r]
        d_enc = np.abs(enc[0] - enc[1]).max(-1)[r]
        old = os.path.join(HERE, "share", f"{name}.mp4")          # previous delivery, for comparison
        o = mp4_frames(old, HOLD) if os.path.exists(old) else None
        d_old = np.abs(o[0] - o[1]).max(-1)[r] if o else np.zeros(1)
        m0, m1 = (C.composite(C.read_rgba(frame_png(name, f))).astype(int) for f in MOVING)
        new_j, old_j = motion_jitter(os.path.join(OUT, f"{name}.mp4")), motion_jitter(old) if o else (0, 0)
        a1 = C.read_rgba(frame_png(name, 1))[..., 3]
        new_r, old_r = rim_dip(os.path.join(OUT, f"{name}.mp4"), a1), rim_dip(old, a1) if o else 0
        lines.append(f"{name:14s} moving edge jitter mean/p99: new {new_j[0]:.2f}/{new_j[1]:.1f}, previous "
                     f"{old_j[0]:.2f}/{old_j[1]:.1f}; silhouette rim vs body: new {new_r:+.1f}, previous {old_r:+.1f}")
        lines.append(f"{name:14s} hold f{HOLD[0]}->f{HOLD[1]} ring max |diff|: composited {d_comp.max()} / mp4 "
                     f"{d_enc.max()} (mean {d_enc.mean():.2f}); previous mp4 {d_old.max()} (mean {d_old.mean():.2f})")
        y, x = edge_point(a[..., 3])
        my, mx = edge_point(C.read_rgba(frame_png(name, MOVING[0]))[..., 3])
        row = [label(crop(enc[0], y, x), f"{name} f{HOLD[0]} (mp4)"),
               label(crop(enc[1], y, x), f"f{HOLD[1]} hold, max diff {d_enc.max()}"),
               label(crop(m0, my, mx), f"f{MOVING[0]} moving"),
               label(crop(m1, my, mx), f"f{MOVING[1]} moving")]
        tiles.append(row)
    w = CROP * ZOOM
    sheet = Image.new("RGB", (w * 4 + 30, w * len(tiles) + 10 * (len(tiles) - 1)), (40, 40, 40))
    for i, row in enumerate(tiles):
        for j, t in enumerate(row):
            sheet.paste(t, (j * w + (30 if j >= 2 else 0), i * (w + 10)))
    sheet.save(os.path.join(OUT, "edge_check.png"))
    print("\n".join(lines))


def contact_sheet():
    tw, th = 432, 540
    rows = [[f"{n}_mid.png" for n in EXERCISES], [f"{n}_hands.png" for n in EXERCISES],
            ["squat_under.png", "deadlift_under.png", "bench_under.png"]]
    sheet = Image.new("RGB", (tw * 5, th * 3), (0, 0, 0))
    for i, row in enumerate(rows):
        x0 = (5 - len(row)) * tw // 2
        for j, f in enumerate(row):
            im = Image.open(os.path.join(OUT, f)).convert("RGB").resize((tw, th), Image.LANCZOS)
            sheet.paste(label(im, f[:-4].replace("_", " ")), (x0 + j * tw, i * th))
    sheet.save(os.path.join(OUT, "contact_sheet.png"))


if __name__ == "__main__":
    check()
    if len(EXERCISES) == 5:
        contact_sheet()
