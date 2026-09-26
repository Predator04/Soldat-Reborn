#!/usr/bin/env python3
"""Render a small preview of every bundled classic map for the menu picker.

  python3 tools/make_thumbs.py        -> assets/map_thumbs/<key>.png (320x120)

Sky gradient from the map's sky colours, then every poly filled with its
texture's average colour tinted by the average vertex colour (roughly what the
game shows), background polys dimmed, and the CTF flags as dots.
"""
import json, os, re, glob
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "assets", "map_thumbs")
TW, TH = 320, 120
_tex_cache = {}


def tex_avg(res_path):
    if res_path in _tex_cache:
        return _tex_cache[res_path]
    p = os.path.join(HERE, res_path.replace("res://", "")) if res_path else ""
    c = (150, 140, 120)
    if p and os.path.exists(p):
        im = Image.open(p).convert("RGB").resize((1, 1), Image.BOX)
        c = im.getpixel((0, 0))
    _tex_cache[res_path] = c
    return c


def key_of(name):
    return re.sub(r"[^a-z0-9]+", "_", str(name).lower()).strip("_")


def render(m):
    polys = m.get("polys", [])
    xs = [v for p in polys for v in p["points"][0::2]]
    ys = [v for p in polys for v in p["points"][1::2]]
    if not xs:
        return None
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    pad = 40.0
    sx = (TW - 8) / max(1.0, (x1 - x0 + pad * 2))
    sy = (TH - 8) / max(1.0, (y1 - y0 + pad * 2))
    s = min(sx, sy)
    ox = (TW - (x1 - x0) * s) / 2 - x0 * s
    oy = (TH - (y1 - y0) * s) / 2 - y0 * s
    sky = m.get("sky") or {}
    top = [int(255 * c) for c in sky.get("top", [0.08, 0.1, 0.2])]
    bot = [int(255 * c) for c in sky.get("bottom", [0.3, 0.22, 0.26])]
    img = Image.new("RGB", (TW, TH))
    d = ImageDraw.Draw(img)
    for y in range(TH):
        t = y / (TH - 1)
        d.line([(0, y), (TW, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    base = tex_avg(m.get("terrain_texture", ""))
    for bg in (True, False):
        for p in polys:
            col_cls = int(p.get("col", 0))
            if (col_cls == 3) != bg:
                continue
            pts = p["points"]
            xy = [(pts[i] * s + ox, pts[i + 1] * s + oy) for i in range(0, len(pts), 2)]
            if len(xy) < 3:
                continue
            vc = p.get("vc") or []
            if vc:
                r = sum(int(h[0:2], 16) for h in vc) / len(vc) / 255.0
                g = sum(int(h[2:4], 16) for h in vc) / len(vc) / 255.0
                b = sum(int(h[4:6], 16) for h in vc) / len(vc) / 255.0
                a = sum(int(h[6:8], 16) for h in vc) / len(vc) / 255.0 if len(vc[0]) >= 8 else 1.0
            else:
                r = g = b = a = 1.0
            tb = tex_avg(p.get("texture", "")) if p.get("texture") else base
            c = (int(tb[0] * r), int(tb[1] * g), int(tb[2] * b))
            if bg:
                c = tuple(int(v * 0.55) for v in c)
            if a < 0.99:
                bgc = img.getpixel((int(min(TW - 1, max(0, xy[0][0]))), int(min(TH - 1, max(0, xy[0][1])))))
                c = tuple(int(bgc[i] * (1 - a) + c[i] * a) for i in range(3))
            d.polygon(xy, fill=c)
    for i, f in enumerate(m.get("ctf_flags", [])[:2]):
        fx, fy = f[0] * s + ox, f[1] * s + oy
        col = (80, 140, 255) if i == 0 else (240, 70, 60)
        d.ellipse((fx - 3, fy - 3, fx + 3, fy + 3), fill=col, outline=(0, 0, 0))
    d.rectangle((0, 0, TW - 1, TH - 1), outline=(250, 168, 46))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for f in sorted(glob.glob(os.path.join(HERE, "assets", "maps", "*.json"))):
        m = json.load(open(f))
        img = render(m)
        if img is None:
            continue
        img.save(os.path.join(OUT, key_of(m.get("name", os.path.basename(f)[:-5])) + ".png"), optimize=True)
        n += 1
    print("thumbs:", n)


if __name__ == "__main__":
    main()
