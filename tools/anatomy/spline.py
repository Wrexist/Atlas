"""Shared spline/polygon helpers for the anatomy asset generator.

Mirrors BodyAnatomy.smoothClosed (closed Catmull-Rom, tension 0) so the
generated meshes/masks match the in-app vector geometry exactly.
"""
import math


def catmull_closed(points, samples_per_seg=24):
    """Closed Catmull-Rom through points (tension 0, s=1/6), sampled."""
    n = len(points)
    out = []
    s = 1.0 / 6.0
    for i in range(n):
        p0 = points[(i - 1) % n]
        p1 = points[i]
        p2 = points[(i + 1) % n]
        p3 = points[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) * s, p1[1] + (p2[1] - p0[1]) * s)
        c2 = (p2[0] - (p3[0] - p1[0]) * s, p2[1] - (p3[1] - p1[1]) * s)
        for t_i in range(samples_per_seg):
            t = t_i / samples_per_seg
            mt = 1 - t
            x = mt**3 * p1[0] + 3 * mt**2 * t * c1[0] + 3 * mt * t**2 * c2[0] + t**3 * p2[0]
            y = mt**3 * p1[1] + 3 * mt**2 * t * c1[1] + 3 * mt * t**2 * c2[1] + t**3 * p2[1]
            out.append((x, y))
    return out


def mirror_pts(points):
    return [(1 - x, y) for (x, y) in points]


def rounded_rect_poly(x, y, w, h, r, seg=8):
    pts = []
    corners = [
        (x + w - r, y + r, -90, 0), (x + w - r, y + h - r, 0, 90),
        (x + r, y + h - r, 90, 180), (x + r, y + r, 180, 270),
    ]
    for cx, cy, a0, a1 in corners:
        for i in range(seg + 1):
            a = math.radians(a0 + (a1 - a0) * i / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts
