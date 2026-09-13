#!/usr/bin/env python3
"""ship_assets.py — copy + convert Soldat scenery/terrain assets referenced by
the 10 ported classic maps into the project's res:// tree.

Reads _scenery_hints[].name from every map JSON under assets/maps/ plus each
map's _source.pms_texture, then resolves them case-insensitively against
the shared Soldat asset dirs. Emits every referenced sprite as a lowercase
.png inside assets/scenery/ (or assets/textures/ for terrain).

Any .bmp or uppercase .PNG source is converted to PNG via PIL. .bmp files
lose transparency; magenta (255,0,255) is treated as transparent so
Soldat's blue-screen sprites render correctly.
"""

import json
import os
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MAPS_DIR = ROOT / "assets" / "maps"
SCENERY_DST = ROOT / "assets" / "scenery"
TEX_DST = ROOT / "assets" / "textures"
SCENERY_SRC = Path("/home/predator04/soldat-base/shared/scenery-gfx")
TEX_SRC = Path("/home/predator04/soldat-base/shared/textures")

# Colors Soldat uses as chroma-key transparency in .bmp assets.
CHROMA_KEYS = ((0, 255, 0), (255, 0, 255))


def _index_src(dir_path: Path):
    """Case-insensitive index: stem_lower -> actual filename."""
    idx = {}
    for p in dir_path.iterdir():
        if p.is_dir():
            continue
        idx[p.name.lower()] = p
    return idx


def _dst_name(ref_name: str) -> str:
    """Normalize a .pms reference name to the on-disk lowercase .png filename."""
    stem, _ = os.path.splitext(ref_name)
    return stem.lower() + ".png"


def _convert(src: Path, dst: Path) -> str:
    """Copy or convert src → dst. Returns 'copy' or 'convert'."""
    ext = src.suffix.lower()
    if ext == ".png" and src.name == dst.name:
        shutil.copy2(src, dst)
        return "copy"
    img = Image.open(src)
    if ext == ".bmp":
        img = img.convert("RGBA")
        px = img.load()
        w, h = img.size
        for y in range(h):
            for x in range(w):
                r, g, b, _a = px[x, y]
                if (r, g, b) in CHROMA_KEYS:
                    px[x, y] = (0, 0, 0, 0)
    else:
        img = img.convert("RGBA")
    img.save(dst, "PNG")
    return "convert"


def _resolve_and_ship(refs, src_index, dst_dir, kind):
    dst_dir.mkdir(parents=True, exist_ok=True)
    shipped, converted, missing = 0, 0, []
    for ref in sorted(refs):
        src = src_index.get(ref.lower())
        if src is None:
            # Try matching just by stem (some maps drop extension casing).
            stem = os.path.splitext(ref)[0].lower()
            candidates = [p for k, p in src_index.items()
                          if os.path.splitext(k)[0] == stem]
            if candidates:
                src = candidates[0]
        if src is None:
            missing.append(ref)
            continue
        dst = dst_dir / _dst_name(ref)
        if dst.exists():
            shipped += 1
            continue
        mode = _convert(src, dst)
        if mode == "convert":
            converted += 1
        shipped += 1
    print(f"[{kind}] shipped={shipped} converted={converted} missing={len(missing)}")
    for m in missing:
        print(f"  MISSING {kind}: {m}")
    return shipped, converted, missing


def main():
    scenery_refs, texture_refs = set(), set()
    for f in sorted(MAPS_DIR.glob("*.json")):
        m = json.loads(f.read_text())
        for h in m.get("_scenery_hints", []) or []:
            n = h.get("name")
            if n:
                scenery_refs.add(n)
        tex = ((m.get("_source") or {}).get("pms_texture") or "").strip()
        if tex:
            texture_refs.add(tex)

    scenery_idx = _index_src(SCENERY_SRC)
    tex_idx = _index_src(TEX_SRC)

    _resolve_and_ship(scenery_refs, scenery_idx, SCENERY_DST, "scenery")
    _resolve_and_ship(texture_refs, tex_idx, TEX_DST, "texture")


if __name__ == "__main__":
    main()
