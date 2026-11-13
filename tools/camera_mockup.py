#!/usr/bin/env python3
"""Camera framing mockups for the design doc. Pure Python, no dependencies.
Draws the pitch at true scale through a pinhole camera onto a 400x240 1-bit
frame and writes 2x PNGs to docs/camera/. Not game code."""
import math, struct, zlib, os

W, H = 400, 240
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

class Frame:
    def __init__(s): s.px = [[1] * W for _ in range(H)]          # 1 = white
    def set(s, x, y, v):
        if 0 <= x < W and 0 <= y < H: s.px[y][x] = v
    def poly(s, pts, v=None, shade=None):
        ys = [p[1] for p in pts]
        for y in range(max(0, int(math.ceil(min(ys)))), min(H - 1, int(math.floor(max(ys)))) + 1):
            xs = []
            for i in range(len(pts)):
                (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % len(pts)]
                if (y1 <= y < y2) or (y2 <= y < y1):
                    xs.append(x1 + (y - y1) * (x2 - x1) / (y2 - y1))
            xs.sort()
            for a, b in zip(xs[::2], xs[1::2]):
                for x in range(max(0, int(math.ceil(a))), min(W - 1, int(math.floor(b))) + 1):
                    s.px[y][x] = v if shade is None else (1 if BAYER[y % 4][x % 4] < shade else 0)
    def line(s, a, b, v=0, w=1):
        (x1, y1), (x2, y2) = a, b
        n = int(max(abs(x2 - x1), abs(y2 - y1))) + 1
        for i in range(n + 1):
            x, y = x1 + (x2 - x1) * i / n, y1 + (y2 - y1) * i / n
            for dx in range(w):
                for dy in range(w):
                    s.set(int(round(x)) + dx, int(round(y)) + dy, v)
    def outline(s, pts, v=0):
        for i in range(len(pts)): s.line(pts[i], pts[(i + 1) % len(pts)], v)
    def rect(s, x, y, w, h, v): s.poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], v)
    def save(s, path, scale=2):
        raw = b''
        for row in s.px:
            line = b'\x00' + bytes(255 * v for v in row for _ in range(scale))
            raw += line * scale
        def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
        open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W * scale, H * scale, 8, 0, 0, 0, 0))
                               + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

class Camera:
    """World: x across (-2.5..2.5), y downfield (0 = thrower's baseline, 8 = far), z up. Meters."""
    def __init__(s, pos, look, f, cy=120):
        s.pos, s.f, s.cy = pos, f, cy
        fx, fy, fz = (look[i] - pos[i] for i in range(3))
        n = math.sqrt(fx * fx + fy * fy + fz * fz); s.fw = (fx / n, fy / n, fz / n)
        rx, ry = s.fw[1], -s.fw[0]; n = math.hypot(rx, ry); s.rt = (rx / n, ry / n, 0)
        s.up = (s.rt[1] * s.fw[2] - 0, -(s.rt[0] * s.fw[2]), s.rt[0] * s.fw[1] - s.rt[1] * s.fw[0])
    def project(s, p):
        d = [p[i] - s.pos[i] for i in range(3)]
        z = sum(d[i] * s.fw[i] for i in range(3))
        if z < 0.05: return None
        return (200 + s.f * sum(d[i] * s.rt[i] for i in range(3)) / z, s.cy - s.f * sum(d[i] * s.up[i] for i in range(3)) / z)

def hull(pts):
    pts = sorted(set(pts))
    def half(ps):
        h = []
        for p in ps:
            while len(h) >= 2 and (h[-1][0] - h[-2][0]) * (p[1] - h[-2][1]) - (h[-1][1] - h[-2][1]) * (p[0] - h[-2][0]) <= 0: h.pop()
            h.append(p)
        return h
    return half(pts)[:-1] + half(pts[::-1])[:-1]

def box(fr, cam, cx, cy, w, h, yaw=0.0, lying=False):
    """Standing box (or lying on its side along yaw). Shadow, white body, black outline, top face."""
    c, s_ = math.cos(yaw), math.sin(yaw)
    if lying: dims = (h, w, w)
    else: dims = (w, w, h)
    cs = []
    for dz in (0, dims[2]):
        for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            x, y = dx * dims[0] / 2, dy * dims[1] / 2
            cs.append((cx + x * c - y * s_, cy + x * s_ + y * c, dz))
    P = [cam.project(p) for p in cs]
    if any(p is None for p in P): return
    sh = [cam.project((x + 0.10 + 0.5 * z, y + 0.04, 0)) for x, y, z in cs]
    fr.poly(hull(sh), 0)
    fr.poly(hull(P), 1); fr.outline(hull(P), 0)
    fr.outline(P[4:], 0)
    for i in range(4):
        fr.line(P[i], P[i + 4], 0)

def scene(fr, cam, field, base_far=(-2, -1, 0, 1, 2), baton=None, near_base=True):
    # grass: far half slightly lighter than near half, sky/backdrop plain
    def ground(y0, y1, shade, x0=-40, x1=40):
        q = [cam.project(p) for p in ((x0, y0, 0), (x1, y0, 0), (x1, y1, 0), (x0, y1, 0))]
        if all(q): fr.poly(q, shade=shade)
    hz = cam.project((cam.pos[0] + cam.fw[0] * 1e4, cam.pos[1] + cam.fw[1] * 1e4, 0))
    fr.rect(0, 0, W, H, 1)
    if hz: fr.rect(0, max(0, hz[1]), W, H, 1)
    near = max(cam.pos[1] + 0.6, -6)
    ground(near, 60, 11); ground(max(near, 0), 8, 13, -2.5, 2.5)
    # pitch lines and stakes
    for a, b in (((-2.5, 0), (-2.5, 8)), ((2.5, 0), (2.5, 8)), ((-2.5, 8), (2.5, 8)), ((-2.5, 0), (2.5, 0))):
        A, B = cam.project((*a, 0)), cam.project((*b, 0))
        if A is None or B is None:
            a2 = (a[0], near) if a[1] < near else a; A = cam.project((*a2, 0)); B = cam.project((b[0], max(b[1], near), 0))
        if A and B: fr.line(A, B, 0)
    for i in range(26):   # dashed centerline
        A, B = cam.project((-2.5 + i * 0.2, 4, 0)), cam.project((-2.4 + i * 0.2, 4, 0))
        if A and B: fr.line(A, B, 0)
    for x, y in ((-2.5, 0), (2.5, 0), (-2.5, 4), (2.5, 4), (-2.5, 8), (2.5, 8)):
        A, B = cam.project((x, y, 0)), cam.project((x, y, 0.25))
        if A and B: fr.line(A, B, 0, 2)
    items = [('k', x, 8.0, 0.0, False) for x in base_far] + [('k', *f) for f in field] + [('K', 0, 4, 0.0, False)]
    if near_base: items += [('k', x, 0.0, 0.0, False) for x in (-2, -1, 0, 1, 2)]
    for kind, x, y, yaw, lying in sorted(items, key=lambda t: -t[2]):
        if kind == 'K': box(fr, cam, x, y, 0.09, 0.30)
        else: box(fr, cam, x, y, 0.07, 0.15, yaw, lying)
    if baton:
        (x, y, z), ang = baton
        a = cam.project((x, y - 0.15 * math.cos(ang), z - 0.15 * math.sin(ang))); b = cam.project((x, y + 0.15 * math.cos(ang), z + 0.15 * math.sin(ang)))
        sa, sb = cam.project((x - .02, y - 0.15 * math.cos(ang), 0)), cam.project((x + .02, y + 0.15 * math.cos(ang), 0))
        w = max(2, int(round(0.044 * cam.f / math.dist(cam.pos, (x, y, z)))))
        fr.line(sa, sb, 0, 2)
        fr.line((a[0] - 1, a[1] - 1), (b[0] - 1, b[1] - 1), 0, w + 2); fr.line(a, b, 1, w)

def minimap(fr, field, base_far=(-2, -1, 0, 1, 2), aim=None, ox=352, oy=6):
    s = 9  # px per meter: 45 x 72
    fr.rect(ox - 3, oy - 3, 5 * s + 7, 8 * s + 7, 1); fr.outline([(ox - 3, oy - 3), (ox + 5 * s + 3, oy - 3), (ox + 5 * s + 3, oy + 8 * s + 3), (ox - 3, oy + 8 * s + 3)], 0)
    fr.outline([(ox, oy), (ox + 5 * s, oy), (ox + 5 * s, oy + 8 * s), (ox, oy + 8 * s)], 0)
    for x in range(0, 5 * s, 3): fr.set(ox + x, oy + 4 * s, 0)
    def dot(x, y, r=2): fr.rect(ox + (x + 2.5) * s - r / 2, oy + (8 - y) * s - r / 2, r, r, 0)
    for x in base_far: dot(x, 7.85)
    for x in (-2, -1, 0, 1, 2): dot(x, 0.15)
    for f in field: dot(f[0], f[1])
    dot(0, 4, 3)
    if aim: fr.line((ox + (aim[0] + 2.5) * s, oy + 8 * s), (ox + (aim[1] + 2.5) * s, oy + (8 - aim[2]) * s), 0)

FIELD = [(1.75, 4.45, 0.3, False), (1.95, 4.6, 1.1, False), (2.1, 4.9, 0.6, False), (1.6, 4.85, 0.0, False), (-0.6, 6.9, 0.4, False)]
out = os.path.join(os.path.dirname(__file__), '..', 'docs', 'camera')

# A. The problem: a natural eye-level view from the baseline, 60 degree lens.
fr = Frame(); scene(fr, Camera((0, -1.0, 1.6), (0, 5, 0.3), 346), FIELD); fr.save(f'{out}/a-eye-level-true-scale.png')
# B. Aim camera on the field kubbs: crane behind the thrower, long lens, pans with the aim.
fr = Frame(); scene(fr, Camera((0.9, -3.0, 3.4), (1.5, 5.6, 0), 880, cy=112), FIELD, near_base=False)
minimap(fr, FIELD, aim=(0.9, 1.8, 4.6)); fr.save(f'{out}/b-aim-camera-field.png')
# C. Aim camera on the base kubbs, 8 m: same camera, tilts up and tightens.
F2 = [(-0.6, 6.9, 0.4, False)]
fr = Frame(); scene(fr, Camera((0, -3.0, 3.4), (0, 7.3, 0), 1000, cy=120), F2, near_base=False)
minimap(fr, F2, aim=(0, 0, 8)); fr.save(f'{out}/c-aim-camera-baseline.png')
# D. Impact camera: low and close to the group as the baton arrives.
F3 = [(1.75, 4.45, 0.3, False), (1.95, 4.6, 1.1, False), (2.1, 4.9, 0.6, False), (1.6, 4.85, 0.0, False)]
fr = Frame(); scene(fr, Camera((0.6, 1.9, 0.9), (1.85, 4.7, 0.1), 700, cy=130), F3, near_base=False, baton=((1.5, 3.9, 0.32), 1.0)); fr.save(f'{out}/d-impact-camera.png')
# E. Raising view: top-down close-up, two fallen kubbs with footprints to choose.
fr = Frame(); scene(fr, Camera((1.8, 4.2, 3.0), (1.8, 4.75, 0), 520, cy=120), [(1.6, 4.5, 0.4, True), (2.05, 4.85, 1.9, True), (1.5, 5.0, 0.0, False)], near_base=False); fr.save(f'{out}/e-raising-view.png')
print('ok')
