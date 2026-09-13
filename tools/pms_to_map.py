#!/usr/bin/env python3
"""pms_to_map.py — Convert Soldat .pms binary maps into Soldat Reborn JSON maps.

Emits map dictionaries matching the schema Godot MapIO expects (see
scripts/map_io.gd), with an added "polys" array carrying flat float lists for
polygon terrain. Extra keys the runtime tolerates but ignores if missing:
scenery, m2_mounts, ctf_flags, inf_flag, htf_flag, rambo_pos, dom_points.

Usage:
    python3 tools/pms_to_map.py <input.pms> <output.json> [--name Display]

Coordinate system: .pms coordinates are centered on origin (Y grows down),
while the Reborn runtime uses a positive Godot 2D grid. We translate so bounds
map to a target rect within MAP_W=4800, MAP_H=2000, at a shared scale chosen
so a Soldat soldier (~30 px) matches Reborn's 46-px sprite (~1.5x).
"""

import argparse
import json
import os
import struct
import sys

# Target render window (mirrors main.gd MAP_W / MAP_H).
MAP_W = 4800.0
MAP_H = 2000.0
GROUND_Y = 1900.0  # main.gd's baseline floor

# Fixed scale keeps every ported map at the same soldier-to-terrain ratio.
# 1.5x roughly matches original Soldat (soldier ~30 px on-screen) to Reborn
# (soldier 46 px). Wider maps get x-clamped; taller ones y-clamped.
DEFAULT_SCALE = 1.5

# Soldat polygon types worth colliding with. 0=normal ground, 4=ice,
# 5=deadly, 6=bloody, 7=hurts, 8=regenerates. We skip types 1 (bullets only),
# 2 (players only pass-through), and 3 (non-collide background).
SOLID_POLY_TYPES = {0, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13}
NON_SOLID_POLY_TYPES = {1, 3, 16}


def _read_bstr(b, o, fixed):
    ln = b[o]
    s = b[o + 1 : o + 1 + ln].decode("cp1252", "ignore")
    return s, o + 1 + fixed


def parse_pms(path):
    with open(path, "rb") as f:
        b = f.read()
    o = 0
    version = struct.unpack_from("<i", b, o)[0]
    o += 4
    name, o = _read_bstr(b, o, 38)
    texture, o = _read_bstr(b, o, 24)
    bg_top = struct.unpack_from("<I", b, o)[0]
    o += 4
    bg_bot = struct.unpack_from("<I", b, o)[0]
    o += 4
    jet = struct.unpack_from("<i", b, o)[0]
    o += 4
    grenades = b[o]
    medkits = b[o + 1]
    weather = b[o + 2]
    steps = b[o + 3]
    o += 4
    _rid = struct.unpack_from("<I", b, o)[0]
    o += 4

    # Polygons: 3 vertices (28b each) + 3 perpendiculars (12b each) + type byte.
    poly_count = struct.unpack_from("<i", b, o)[0]
    o += 4
    polys = []
    for _ in range(poly_count):
        verts = []
        for v in range(3):
            vb = o + v * 28
            x, y = struct.unpack_from("<ff", b, vb)
            verts.append((x, y))
        ptype = b[o + 84 + 36]
        polys.append({"verts": verts, "type": ptype})
        o += 121

    # Sectors: variable-length (count word + count*word poly indices).
    _sdiv = struct.unpack_from("<i", b, o)[0]
    o += 4
    n_sect = struct.unpack_from("<i", b, o)[0]
    o += 4
    for _ in range((2 * n_sect + 1) ** 2):
        cnt = struct.unpack_from("<H", b, o)[0]
        o += 2 + cnt * 2

    # Sceneries: props (44 bytes each) reference types by index.
    prop_count = struct.unpack_from("<i", b, o)[0]
    o += 4
    props = []
    for _ in range(prop_count):
        active = b[o]
        style = struct.unpack_from("<H", b, o + 2)[0]
        x, y = struct.unpack_from("<ff", b, o + 12)
        rotation = struct.unpack_from("<f", b, o + 20)[0]
        sx, sy = struct.unpack_from("<ff", b, o + 24)
        alpha = struct.unpack_from("<I", b, o + 32)[0]
        color = struct.unpack_from("<I", b, o + 36)[0]
        level = struct.unpack_from("<i", b, o + 40)[0]
        props.append(
            dict(active=active, style=style, x=x, y=y,
                 rot=rotation, sx=sx, sy=sy,
                 alpha=alpha, color=color, level=level)
        )
        o += 44

    type_count = struct.unpack_from("<i", b, o)[0]
    o += 4
    types = []
    for _ in range(type_count):
        ln = b[o]
        types.append(b[o + 1 : o + 1 + ln].decode("cp1252", "ignore"))
        o += 55

    coll_count = struct.unpack_from("<i", b, o)[0]
    o += 4
    o += coll_count * 16  # (active i32, x f32, y f32, radius f32)

    spawn_count = struct.unpack_from("<i", b, o)[0]
    o += 4
    spawns = []
    for _ in range(spawn_count):
        active, sx, sy, team = struct.unpack_from("<Iii I", b, o)
        spawns.append(dict(active=active, x=sx, y=sy, team=team))
        o += 16

    return dict(
        version=version, name=name, texture=texture,
        bg_top=bg_top, bg_bot=bg_bot, jet=jet,
        grenades=grenades, medkits=medkits, weather=weather, steps=steps,
        polys=polys, props=props, types=types, spawns=spawns,
    )


def _bounds(polys):
    xs = [v[0] for p in polys for v in p["verts"]]
    ys = [v[1] for p in polys for v in p["verts"]]
    return min(xs), max(xs), min(ys), max(ys)


def to_reborn_map(pms, display_name=None, scale=DEFAULT_SCALE):
    minx, maxx, miny, maxy = _bounds(pms["polys"])
    w = maxx - minx
    h = maxy - miny

    # Clamp scale so the map fits within (0, MAP_W-margin) x (0, MAP_H-margin).
    x_margin = 200.0
    y_margin = 100.0
    max_sx = (MAP_W - 2 * x_margin) / max(w, 1.0)
    max_sy = (MAP_H - 2 * y_margin) / max(h, 1.0)
    s = min(scale, max_sx, max_sy)

    # Center within the map rect, keeping the ground row visually near GROUND_Y.
    scaled_w = w * s
    scaled_h = h * s
    off_x = (MAP_W - scaled_w) / 2.0 - minx * s
    # Place the map's bottom edge just above GROUND_Y so the map rides on the
    # baseline floor main.gd draws automatically.
    off_y = GROUND_Y - 20.0 - maxy * s

    def tx(x): return x * s + off_x
    def ty(y): return y * s + off_y

    out_polys = []
    for p in pms["polys"]:
        if p["type"] in NON_SOLID_POLY_TYPES:
            continue
        pts_flat = []
        for (vx, vy) in p["verts"]:
            pts_flat.append(round(tx(vx), 2))
            pts_flat.append(round(ty(vy), 2))
        out_polys.append({"points": pts_flat})

    # Bucket spawns by team.
    by_team = {}
    for s_ in pms["spawns"]:
        if not s_["active"]:
            continue
        by_team.setdefault(s_["team"], []).append((tx(s_["x"]), ty(s_["y"])))

    ctf_flags = []
    if by_team.get(5):
        ctf_flags.append([round(by_team[5][0][0], 2), round(by_team[5][0][1], 2)])
    if by_team.get(6):
        ctf_flags.append([round(by_team[6][0][0], 2), round(by_team[6][0][1], 2)])

    inf_flag = htf_flag = rambo_pos = None
    # Team 14 = neutral flag (INF yellow / HTF neutral). Team 15 = Rambo bow.
    if by_team.get(14):
        p = by_team[14][0]
        inf_flag = [round(p[0], 2), round(p[1], 2)]
        htf_flag = inf_flag[:]
    if by_team.get(15):
        p = by_team[15][0]
        rambo_pos = [round(p[0], 2), round(p[1], 2)]

    m2_mounts = []
    for p in by_team.get(16, []):
        m2_mounts.append([round(p[0], 2), round(p[1], 2)])

    # Player + bot spawns. Use team 1 (Alpha) as player, teams 1+2 as bots
    # (mode-agnostic: works for DM/CTF/INF alike). Fall back to team 0
    # (general) if no team spawns exist.
    alpha = by_team.get(1, [])
    bravo = by_team.get(2, [])
    general = by_team.get(0, [])

    # Prefer an Alpha spawn for the player so BLUE (which the local player joins
    # in team modes per main.gd) starts on the correct side.
    if alpha:
        player_spawn = list(alpha[0])
    elif general:
        player_spawn = list(general[0])
    else:
        player_spawn = [200.0, 1775.0]

    bot_spawns = []
    seen = set()
    # Use up to 6 spawns from Alpha (skipping the one used by the player) + Bravo + general.
    def _push(p):
        key = (round(p[0], 1), round(p[1], 1))
        if key in seen:
            return
        seen.add(key)
        bot_spawns.append([round(p[0], 2), round(p[1], 2)])

    for p in alpha[1:]:
        _push(p)
        if len(bot_spawns) >= 3:
            break
    for p in bravo:
        _push(p)
        if len(bot_spawns) >= 6:
            break
    for p in general:
        _push(p)
        if len(bot_spawns) >= 6:
            break
    if not bot_spawns:
        # Bare minimum: give the bot something walkable.
        bot_spawns = [[MAP_W * 0.7, 1775.0], [MAP_W * 0.8, 1775.0]]

    # Scenery: only levels 0 (behind sprites) and 1 (middle). We map to z-index
    # -3 (behind) or -2 (front-of-parallax but behind soldiers).
    scenery = []
    types = pms["types"]
    for prop in pms["props"]:
        if not prop["active"]:
            continue
        if prop["style"] == 0 or prop["style"] > len(types):
            continue
        # Style is 1-indexed into types.
        name = types[prop["style"] - 1]
        if not name:
            continue
        # Only pass through pos+scale — we won't ship the original bmp textures.
        # Runtime tolerates unknown tex paths (skips missing scenery).
        scenery.append({
            "name": name,
            "pos": [round(tx(prop["x"]), 2), round(ty(prop["y"]), 2)],
            "scale": round(prop["sx"], 3),
            "rot": round(prop["rot"], 4),
            "alpha": prop["alpha"],
            "level": prop["level"],
        })

    round_pts = []
    for poly in out_polys:
        round_pts.append({"points": poly["points"]})

    m = {
        "name": display_name or pms["name"] or "Classic",
        "polys": round_pts,
        "platforms": [],
        "player_spawn": [round(player_spawn[0], 2), round(player_spawn[1], 2)],
        "bot_spawns": bot_spawns,
        "ctf_ground_y": round(GROUND_Y - 20.0, 2),
    }
    if ctf_flags:
        m["ctf_flags"] = ctf_flags
    if inf_flag:
        m["inf_flag"] = inf_flag
    if htf_flag:
        m["htf_flag"] = htf_flag
    if rambo_pos:
        m["rambo_pos"] = rambo_pos
    if m2_mounts:
        m["m2_mounts"] = m2_mounts
    if scenery:
        m["_scenery_hints"] = scenery  # Runtime ignores unknown keys.

    # Bookkeeping useful during debugging.
    m["_source"] = {
        "pms_name": pms["name"],
        "pms_texture": pms["texture"],
        "scale": round(s, 4),
        "pms_bounds": [round(minx, 1), round(miny, 1), round(maxx, 1), round(maxy, 1)],
    }
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="Path to input .pms")
    ap.add_argument("output", help="Path to output .json")
    ap.add_argument("--name", help="Display name (default: strip prefix from filename)")
    ap.add_argument("--scale", type=float, default=DEFAULT_SCALE)
    args = ap.parse_args()

    pms = parse_pms(args.input)
    display = args.name
    if not display:
        stem = os.path.splitext(os.path.basename(args.input))[0]
        for prefix in ("ctf_", "inf_", "htf_"):
            if stem.startswith(prefix):
                stem = stem[len(prefix):]
                break
        display = stem
    m = to_reborn_map(pms, display_name=display, scale=args.scale)
    with open(args.output, "w") as f:
        json.dump(m, f, indent=2)
    print(f"Wrote {args.output}  polys={len(m['polys'])}  spawns={len(m['bot_spawns'])+1}  scale={m['_source']['scale']}")


if __name__ == "__main__":
    main()
