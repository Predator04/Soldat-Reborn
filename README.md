# Soldat Reborn

A Godot 4.7 rebuild of the classic 2D run-and-gun shooter **Soldat** — jet boots,
bunny-hop momentum, ragdoll gibs, grenades, and online multiplayer — rebuilt with
Soldat's own art and sound (CC BY 4.0) and an animated skeletal soldier.

## Features

- Run / bunny-hop / jet boots with fuel management
- 5 weapons: Deagles, AK-74, MP5, Spas-12, and the LAW rocket launcher (rocket-jumping)
- Grenades (arc throw, bounce, splash damage)
- 3 maps: Ascent / Towers / Pillars (cycled per game)
- Match system: team score, 5-minute round timer or first-to-20 wins, winner banner
- Single-player vs 3 AI bots, plus ENet multiplayer (host / join)
- Real Soldat assets: skeletal soldier animation (`.poa` rig), weapon sprites, sound effects

## Controls

| Key | Action |
|-----|--------|
| A / D | Move left / right |
| SPACE / W | Jump (ground) · jet boots (hold in air) |
| Mouse | Aim |
| Left click | Shoot |
| 1–5 | Switch weapon (5 = LAW) |
| R | Reload |
| G | Throw grenade |

## Run it

- **Easiest:** double-click `build/SoldatReborn.exe`, or download the `.exe` from the
  [latest GitHub release](https://github.com/Predator04/Soldat-Reborn/releases).
- **In the editor:** open the project in Godot 4.7.2 (GL Compatibility renderer) and press **F5**.

## Build from source

Requires Godot 4.7.2.

```sh
# Headless verify (must print ZERO lines matching error|invalid|nil|failed|attempt)
godot --headless --path . --quit-after 900

# Windows export
godot --headless --export-release "Windows Desktop" build/SoldatReborn.exe
```

CI runs the headless verify on every push (`.github/workflows/ci.yml`).

## Multiplayer

- **HOST GAME** — pick a map, then share your IP/port (default `7777`).
- **JOIN GAME** — enter host IP + port.
- LAN-scale: per-frame state sync. See *Known limitations* in `ROADMAP.md`.

## Project layout

- `scripts/` — game code (`player.gd`, `bot.gd`, `gostek.gd`, `poa_loader.gd`,
  `soldier_art.gd`, `sfx.gd`, `net.gd`, `main.gd`, `hud.gd`, `menu.gd`, `settings.gd`, …)
- `scenes/` — `.tscn` scene files
- `assets/` — ported Soldat assets: `gostek-gfx/` (soldier parts), `weapons-gfx/`,
  `sfx/` (sounds), `anims/` (`.poa` animation data), `textures/`, `sparks-gfx/`
- `references/poa-format.md` — the `.poa` animation format, verified against Soldat's MIT source
- `ROADMAP.md` — what's done, backlog, and known issues
- `CHANGELOG.md` — release history

## License

- **Code** — MIT (`LICENSE.md`)
- **Assets** — Creative Commons Attribution 4.0 (CC BY 4.0), ported from
  [github.com/Soldat/base](https://github.com/Soldat/base). Attribution in `CREDITS.md`.

## Credits

Soldat © Michał Marcinkowski / Transhuman Design and contributors. This is an
unofficial fan rebuild; the Godot port and code are original.
