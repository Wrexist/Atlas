# Black background + soft white glow behind the figure, composited in linear light with straight alpha.
# python composite.py still <in.png> <out.png>
# python composite.py video <frames_dir> <out.mp4> <fps>
#
# The glow comes from the coverage mask dilated a few px before blurring, so it is already at full strength
# where the figure's edge pixels blend into it (no dark trough at the silhouette), and edge pixels are mixed in
# linear light (an sRGB-space mix of a dark rim and a bright glow dips darker than either).
import os, sys, subprocess
import numpy as np
from scipy import ndimage
from PIL import Image

DILATE_PX = 3
GLOW = ((9, 0.42), (32, 0.30))           # (blur sigma px, weight): a tight rim glow, not a fog
REF_WIDTH = 1080                         # the px sizes above are for this width; other sizes scale them
SHADOW = 0.9                             # how much the floor's contact shadow darkens the glow
POOL = 0.007                             # linear intensity of the faint pool of light on the floor round the feet


def read_rgba(path):
    """16- or 8-bit RGBA PNG -> float32 HxWx4 in [0, 1] (display-encoded colour, straight alpha)."""
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgba64le", "-"],
                         check=True, capture_output=True).stdout
    w, h = Image.open(path).size
    return (np.frombuffer(raw, dtype="<u2").astype(np.float32) / 65535.0).reshape(h, w, 4)


def to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_display(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def glow_from(alpha):
    k = alpha.shape[1] / REF_WIDTH
    d = max(1, round(DILATE_PX * k))
    mask = ndimage.grey_dilation(alpha, size=(2 * d + 1, 2 * d + 1))
    g = sum(w * ndimage.gaussian_filter(mask, sigma * k) for sigma, w in GLOW)
    return np.clip(g, 0.0, 1.0)


PRIMARY = np.array((0xFF, 0xAC, 0x73)) / 255         # AppColor.trainingPrimaryMuscle (dark)
SECONDARY = np.array((0x80, 0xAD, 0xFF)) / 255       # AppColor.trainingSecondaryMuscle (dark)
TINT = ((1, SECONDARY, 0.85), (0, PRIMARY, 0.92))     # tier channel, colour, strength (app: 0.75 / 0.88 over a grey photo)
LIT = 0.72                                           # display grey of the lit clay: multiply gain so lit muscle = the hex


def tint(rgba, tiers):
    """The app's muscle-map look: shaded grey multiplied by the tier colour, secondary first, primary over it."""
    rgb = rgba[..., :3]
    for ch, col, k in TINT:
        f = tiers[..., ch:ch + 1] * k
        rgb = rgb * (1 - f) + np.clip(rgb.mean(-1, keepdims=True) / LIT * col, 0, 1) * f
    return np.concatenate([rgb, rgba[..., 3:]], -1)


def read_tiers(path):
    """Tier map rendered alongside `path`: tiers/<name> for stills, tiers/tiers<frame>.png for animation frames."""
    d, name = os.path.join(os.path.dirname(path), "tiers"), os.path.basename(path)
    for t in (os.path.join(d, name), os.path.join(d, "tiers" + name)):
        if os.path.exists(t):
            return read_rgba(t)
    return None


def floor_shadow(rgba, tiers):
    """Shadow-catcher coverage (0..1): the floor pixels the render marked, minus the solid figure/equipment."""
    if tiers is None or tiers[..., 2].max() == 0:
        return None
    return rgba[..., 3] * (1 - tiers[..., 2])


def pool_from(shadow):
    """Elliptical pool of floor light centred on the shadows (computed once per clip, so it never wanders)."""
    ys, xs = np.nonzero(shadow > 0.05)
    if len(xs) < 50:
        return None
    w = shadow[ys, xs]
    cx, cy = np.average(xs, weights=w), np.average(ys, weights=w)
    rx = 1.1 * np.sqrt(np.average((xs - cx) ** 2, weights=w)) + 40
    ry = 1.1 * np.sqrt(np.average((ys - cy) ** 2, weights=w)) + 15
    yy, xx = np.mgrid[:shadow.shape[0], :shadow.shape[1]]
    return POOL * np.exp(-(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2))[..., None]


def composite(rgba, tiers=None, pool=None):
    shadow = np.zeros_like(rgba[..., 3:4])
    if tiers is not None:
        rgba = tint(rgba, tiers)
        solid = tiers[..., 2:3]
        if solid.max() > 0:                          # renders with the shadow-catcher floor
            shadow = rgba[..., 3:4] * (1 - solid)
            rgba = np.concatenate([rgba[..., :3], rgba[..., 3:4] * solid], -1)
    a = rgba[..., 3:4]
    glow = to_linear(glow_from(rgba[..., 3]))[..., None]
    if pool is not None:
        glow = glow + pool                          # faint lit floor, so the contact shadows have something to darken
    glow = glow * (1 - SHADOW * shadow)
    out = to_linear(rgba[..., :3]) * a + glow * (1 - a)
    rng = np.random.default_rng(0)                # fixed dither: breaks banding in the glow, identical every frame
    return np.clip(to_display(out) * 255 + rng.uniform(-0.5, 0.5, out.shape), 0, 255).round().astype(np.uint8)


def still(src, dst):
    rgba, tiers = read_rgba(src), read_tiers(src)
    shadow = floor_shadow(rgba, tiers)
    Image.fromarray(composite(rgba, tiers, pool_from(shadow) if shadow is not None else None)).save(dst)


def video(frames_dir, mp4, fps):
    import glob
    frames = sorted(glob.glob(os.path.join(frames_dir, "*.png")))
    w, h = Image.open(frames[0]).size
    enc = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                            "-s", f"{w}x{h}", "-framerate", str(fps), "-i", "-", "-pix_fmt", "yuv420p",
                            "-c:v", "libx264", "-crf", "14", "-preset", "slow", "-tune", "animation",
                            "-movflags", "+faststart", mp4], stdin=subprocess.PIPE)
    first = floor_shadow(read_rgba(frames[0]), read_tiers(frames[0]))
    pool = pool_from(first) if first is not None else None
    for f in frames:
        enc.stdin.write(composite(read_rgba(f), read_tiers(f), pool).tobytes())
    enc.stdin.close()
    if enc.wait():
        sys.exit("ffmpeg failed")


if __name__ == "__main__":
    if sys.argv[1] == "still":
        still(sys.argv[2], sys.argv[3])
    else:
        video(sys.argv[2], sys.argv[3], int(sys.argv[4]))
