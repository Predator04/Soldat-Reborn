#!/usr/bin/env python3
"""Store / Discord art from what's in the repo (#223 / #224). Deterministic;
needs Pillow. Re-run after changing the screenshots or the icon.

  python3 tools/itch/make_art.py

Writes
  docs/itch/cover-placeholder-630x500.png   itch cover until the trailer art
                                            (docs/media/cover-630x500.png) lands
  docs/discord/tracerfall.png               Discord "large image" (1024x1024)
  docs/discord/mode_<dm|tdm|ctf|...>.png    Discord "small image" per mode (512x512)

Colours are the game's UI palette (scripts/ui_theme.gd): ember accent
#FF9429, neon #4CE0FF, near-black #07090D, text #EDF2F7.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONTS = os.path.join(ROOT, "assets", "fonts")
EMBER = (255, 148, 41)
NEON = (76, 224, 255)
BG = (7, 9, 13)
PANEL = (16, 21, 29)
TEXT = (237, 242, 247)

# Order = GameLists.MODE_NAMES / DiscordPresence.MODE_IMAGES.
MODES = [("dm", "DM"), ("tdm", "TDM"), ("ctf", "CTF"), ("inf", "INF"), ("htf", "HTF"),
         ("rm", "RM"), ("pm", "PM"), ("dom", "DOM"), ("br", "BR"), ("gg", "GG"),
         ("bomb", "BOMB"), ("zombie", "ZOMBIE")]


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def text_center(d, cx, y, s, f, fill, shadow=None):
    w = d.textlength(s, font=f)
    if shadow:
        d.text((cx - w / 2 + 3, y + 3), s, font=f, fill=shadow)
    d.text((cx - w / 2, y), s, font=f, fill=fill)


def cover():
    src = Image.open(os.path.join(ROOT, "docs", "screenshots", "helicopter-rockets.jpg")).convert("RGB")
    src = src.crop((0, 36, src.width, src.height))          # drop the caption bar
    box_h = src.height
    box_w = int(box_h * 630 / 500)
    x0 = max(0, min(src.width - box_w, 620 - box_w // 2))   # helicopter + rocket flash
    img = src.crop((x0, 0, x0 + box_w, box_h)).resize((630, 500), Image.LANCZOS)
    # Bottom fade to the UI black for the title.
    fade = Image.new("L", (1, 500))
    for y in range(500):
        fade.putpixel((0, y), int(max(0, min(255, (y - 270) * 1.25))))
    img = Image.composite(Image.new("RGB", img.size, BG), img, fade.resize(img.size))
    d = ImageDraw.Draw(img)
    text_center(d, 315, 360, "TRACERFALL", font("BarlowCondensed-ExtraBold.ttf", 96), EMBER, shadow=(0, 0, 0))
    d.rectangle((215, 462, 415, 464), fill=NEON)
    text_center(d, 315, 470, "Free 2D jetpack shooter  ·  Windows + Android", font("Barlow-SemiBold.ttf", 20), TEXT)
    out = os.path.join(ROOT, "docs", "itch", "cover-placeholder-630x500.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, optimize=True)
    return out


def rounded_tile(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius, fill=255)
    return m


def discord_large():
    icon = Image.open(os.path.join(ROOT, "icon.png")).convert("RGBA")
    big = icon.resize((1024, 1024), Image.LANCZOS)
    out = os.path.join(ROOT, "docs", "discord", "tracerfall.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    big.save(out, optimize=True)
    return out


def discord_mode(key, label):
    s = 512
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    tile = Image.new("RGBA", (s, s), PANEL + (255,))
    # Soft ember glow from the lower left, like the menu backdrop.
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-180, 220, 300, 700), fill=EMBER + (90,))
    tile = Image.alpha_composite(tile, glow.filter(ImageFilter.GaussianBlur(70)))
    img.paste(tile, (0, 0), rounded_tile(s, 96))
    d = ImageDraw.Draw(img)
    d.ellipse((40, 40, s - 40, s - 40), outline=EMBER + (255,), width=18)
    size = 230 if len(label) <= 2 else 176
    f = font("BarlowCondensed-ExtraBold.ttf", size)
    top, bottom = f.getbbox(label)[1], f.getbbox(label)[3]
    text_center(d, s / 2, s / 2 - (top + bottom) / 2, label, f, TEXT, shadow=(0, 0, 0, 160))
    out = os.path.join(ROOT, "docs", "discord", "mode_%s.png" % key)
    img.save(out, optimize=True)
    return out


def main():
    made = [cover(), discord_large()] + [discord_mode(k, l) for k, l in MODES]
    for p in made:
        print("wrote", os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
