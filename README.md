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
- **Classic maps** — 99 original Soldat levels ported from `.pms` with scenery, textured terrain, weather and baked bot navigation (bots play every objective mode on every map)
- **Polish** — gestures/taunts, chat, weapon throw/pickup, ceasefire, bink, game modifiers, character customization, lo-fi mode, local stats, GIF recording, improved grenade physics
- **Multiplayer** — host-authoritative ENet (host / join), replicated bots that shoot and damage clients, dedicated headless server mode, server browser with live ping and player counts, Quick Join, automatic rejoin after a dropped connection, LAN-scale sync, authority-owned grenade/rocket transforms so shooter + victim see the same trajectory and impact spot
- **Vehicles** — two-seat buggies (driver + gunner on a mounted machine gun) on 87 of the classic maps and the built-in arenas, and armored tanks with a lobbed-shell turret on the 13 widest maps: run people over, get wrecked by rockets and grenades, respawn at their spot. Bots drive and crew both. Toggle in Settings → Game
- **Pickups** — medikits and grenade kits where the original maps put them (bots use them too), plus timed bonus crates (Predator, Berserker, Vest, Cluster)
- **Sound** — positional audio (distance + stereo), footsteps, landings, ricochets, bullet whizz-bys, distant-gunfire tails, death cries, rain / snow ambience, Soldat radio voice lines
- **Round hygiene** — clean-slate reset (full HP/ammo, spawn-slot teleport) in every mode, not just Survival
- **Gostek fidelity** — front arm tracks aim_dir; dreadlocks, dogtag, blood/damage overlays, belt grenade, and secondary-on-back render on top of the base gostek

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
| F | Throw away current weapon · get in / out of a buggy · mount an M2 |
| / | Gesture console — `/victory /smoke /tabac /takeoff /kill /brutalkill /mercy` |
| T / Y | Chat (global / team); ALT+keys for taunts |
| V | Team radio: enemy / friendly flag carrier, enemy spotted — up / mid / down |
| F9 | Record a GIF of gameplay |
| Tab | Scoreboard (hold) |
| H | Controls card (shown automatically in your first matches) |
| ESC | Pause menu — Resume / Settings / Controls / Exit |

Every action above is rebindable. Open **SETTINGS → CONTROLS** from the main menu
or the ESC pause menu, click a row, then press any key or mouse button. Bindings
persist to `user://controls.cfg`; "Reset to Defaults" restores the table above.

While you're dead the Soldat weapon panel appears on the left: pick the primary (1–0 or click) and
secondary you respawn with. Gamepads and touch screens work too (on-screen stick and buttons on phones).

## Map editor & procedural generation

- Launch from the menu (**MAP EDITOR**) or open an existing map.
- **Editor controls:** toolbar to place platforms (drag), markers (click), move/delete (right-click); middle-drag pan, wheel zoom, Ctrl+Z / Ctrl+Y undo / redo, ESC exit, F5 play-test. On touch screens two fingers pan and pinch-zoom.
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

# Windows .exe + signed Android .apk
bash tools/build_release.sh all

# Full release gate (~25 min): static checks, boots, multiplayer smokes, every mode, every map
bash tools/release_gate.sh
```

CI runs the headless verify on every push (`.github/workflows/ci.yml`).

## Multiplayer

- **HOST GAME** — pick a mode and map (your own editor maps included); bots fill the match per the Bots setting. Port `7777` by default.
- **JOIN GAME → FIND GAMES** — games on your local network show up automatically (UDP 23074); click one to join. Or type the host's IP + port. A master server (see `../server/master-server`) lists internet games — dedicated servers with `--register <url>`, listen hosts with the "List on the master server" box.
- Everyone must run the same version; the host refuses other builds with a message.
- Host-authoritative state sync, with bots replicated and fighting on all peers.
- **Dedicated server** — run a headless host with no local player:
  `SoldatReborn.exe --dedicated [--port 7777] [--map ctf_Nuubia] [--mode dm]`
  (maps: name or index; modes: `dm`/`tdm`/`ctf`/`inf`/`htf`/`rm`/`pm`/`dom`/`br`).

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
