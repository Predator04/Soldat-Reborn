# Soldat Reborn

A Godot 4.7 rebuild of the classic 2D run-and-gun shooter **Soldat** — jet boots,
bunny-hop momentum, ragdoll gibs, grenades, and online multiplayer — rebuilt with
Soldat's own art and sound (CC BY 4.0) and an animated skeletal soldier. Feature-complete
past the classic, with most of Soldat 2's feature list folded in.

## Features

- **Movement** — run / bunny-hop / jet boots with fuel, crouch, prone, roll, backflip-friendly physics
- **Weapons** — 10 primaries (Deagles, MP5, AK-74, Steyr AUG, Spas-12, Ruger 77, M79, Barrett, Minimi, Minigun) + 4 secondaries (USSOCOM, Knife, Chainsaw, LAW) + Flamethrower, Rambo Bow, Frag/Cluster grenades, M2 stationary gun
- **Game modes** — Deathmatch, Pointmatch, Teammatch, Capture the Flag, Rambomatch, Infiltration, Hold the Flag, **Domination**, **Battle Royale** + Realistic/Survival/Advance sub-modes
- **Map editor** — in-game editor: place platforms, spawns, flags, control points; save/load custom maps; play-test live
- **Procedural maps** — seeded generator with re-roll, produces playable layouts for every mode
- **Classic maps** — 10 original Soldat levels ported from `.pms` (Nuubia, Maya, Aftermath, Hormone, Viet, Scorpion, Warehouse, Baire, Airpirates, Bunker) with scenery + textured terrain
- **Polish** — gestures/taunts, chat, weapon throw/pickup, ceasefire, bink, game modifiers, character customization, lo-fi mode, local stats, GIF recording, improved grenade physics
- **Multiplayer** — host-authoritative ENet (host / join), replicated bots that shoot and damage clients, dedicated headless server mode, LAN-scale sync

## Controls

| Key | Action |
|-----|--------|
| A / D | Move left / right |
| W (or SPACE) | Jump (also stands up from prone) |
| S | Crouch (hold) — rolls while moving |
| X | Prone (toggle) |
| Right click | Jet boots (hold in air) |
| Mouse / Left click | Aim / shoot |
| 1–0 | Primary: 1 Deagles · 2 MP5 · 3 AK-74 · 4 Steyr AUG · 5 Spas-12 · 6 Ruger 77 · 7 M79 · 8 Barrett · 9 Minimi · 0 Minigun |
| Q | Swap primary / secondary (USSOCOM · Knife · Chainsaw · LAW) |
| R | Reload |
| E | Throw grenade |
| G | Toggle grenade type (frag / cluster) |
| F | Throw away current weapon |
| / | Gesture console — `/victory /smoke /tabac /takeoff /kill /brutalkill /mercy` |
| T / Y | Chat (global / team); ALT+keys for taunts |
| F9 | Record a GIF of gameplay |
| ESC | Pause menu — Resume / Settings / Controls / Exit |

Every action above is rebindable. Open **SETTINGS → CONTROLS** from the main menu
or the ESC pause menu, click a row, then press any key or mouse button. Bindings
persist to `user://controls.cfg`; "Reset to Defaults" restores the table above.

## Map editor & procedural generation

- Launch from the menu (**MAP EDITOR**) or open an existing map.
- **Editor controls:** toolbar to place platforms (drag), markers (click), move/delete (right-click); middle-drag pan, wheel zoom, ESC exit, F5 play-test.
- Maps save to `user://maps/*.json` and are selectable in the menu alongside the built-in rotation.
- **GENERATE + PLAY** rolls a seeded procedural map and drops you straight in.

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
- Host-authoritative state sync, with bots replicated and fighting on all peers.
- **Dedicated server** — run a headless host with no local player:
  `SoldatReborn.exe --dedicated [--port 7777] [--map ctf_Nuubia] [--mode dm]`
  (maps: name or index; modes: `dm`/`tdm`/`ctf`/`inf`/`htf`/`rm`/`pm`/`dom`/`br`).
- Custom maps are single-player; networked play uses the built-in rotation. See *Known limitations* in `ROADMAP.md`.

## Project layout

- `scripts/` — game code (`player.gd`, `bot.gd`, `gostek.gd`, `poa_loader.gd`,
  `soldier_art.gd`, `sfx.gd`, `net.gd`, `main.gd`, `hud.gd`, `menu.gd`, `settings.gd`,
  `map_editor.gd`, `map_gen.gd`, `map_io.gd`, `stats.gd`, `gif_recorder.gd`, …)
- `scenes/` — `.tscn` scene files
- `assets/` — ported Soldat assets: `gostek-gfx/` (soldier parts), `weapons-gfx/`,
  `sfx/` (sounds), `anims/` (`.poa` animation data), `textures/`, `interface-gfx/`
- `references/` — `.poa` format, weapon stats (`weapons-stats.md`), game overview
  (`soldat-intro.md`), commands/gestures/movement (`soldat-commands-gestures.md`)
- `ROADMAP.md` — what's done, backlog, and known issues
- `CHANGELOG.md` — release history

## License

- **Code** — MIT (`LICENSE.md`)
- **Assets** — Creative Commons Attribution 4.0 (CC BY 4.0), ported from
  [github.com/Soldat/base](https://github.com/Soldat/base). Attribution in `CREDITS.md`.

## Credits

Soldat © Michał Marcinkowski / Transhuman Design and contributors. This is an
unofficial fan rebuild; the Godot port and code are original.
