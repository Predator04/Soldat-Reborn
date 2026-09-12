# Soldat Reborn — Godot 4 prototype

A Godot 4.7 rebuild of the classic Soldat *feel*: run-and-gun with jet boots, bunny hopping, and gibs.

## Run it

**Easiest — double-click the build:**
`game\build\SoldatReborn.exe`

**Or in the editor (to iterate):**
1. Open `game\GodotEngine\Godot_v4.7.2-stable_win64.exe` (the editor, in the GodotEngine folder)
2. Import/Open the `game` folder as a project
3. Press **F5** to run

## Controls

| Key | Action |
|-----|--------|
| A / D | Move left / right |
| SPACE / W | Jump (ground) · jet boots (hold in air) |
| Mouse | Aim |
| Left click | Shoot |
| 1–5 | Switch weapon (Deagles / AK-74 / MP5 / Spas-12 / LAW rocket) |
| R | Reload |
| G | Throw grenade |

## Main menu

- **PLAY vs BOTS** — offline arena vs bots (map cycles Ascent → Towers → Pillars each round). Bots respawn on their spawn slot 2s after death so the match keeps flowing.
- **HOST GAME** — pick a map, then start a listen server on port `7777`. The chosen map is pushed to every joining client so both sides play the same terrain.
- **JOIN GAME** — enter host IP + port, connect. Client waits for the host's map RPC and then loads the arena.
- **SETTINGS** — SFX volume, screen shake, fullscreen (persisted to `user://settings.cfg`).
- **QUIT** — exit.

## Multiplayer (LAN / direct IP)

Uses Godot's high-level ENet multiplayer.

1. On the host: launch, click **HOST GAME**. You'll load the Ascent map immediately.
2. On each client: launch, click **JOIN GAME**, enter the host's IP (default `127.0.0.1` for same machine) and port `7777`, click **CONNECT**.
3. Up to 8 players (host + 7 clients). Everyone spawns as their own team so bullets damage everyone else (FFA).
4. To leave: quit and relaunch — this returns you to the menu and clears the network state.

**Headless smoke test:**

```
~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -- --smoke-host   # in one terminal
~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . -- --smoke-join   # in another
```

Prints `SMOKE-HOST peers=N players=M` / `SMOKE-JOIN id=... mode=2 players=M` and quits.

## What's in it

- **Soldier** — run, jump, bunny hop (ground jumps give a speed boost), jet boots with a fuel bar that regens on ground. Body is assembled from the real Soldat `gostek-gfx` PNGs (klata / morda / helm / biodro / udo / noga / stopa / ramie / reka / dlon / kamizelka) via `scripts/gostek.gd`; mirror-image `*2.png` variants are used when facing left. Weapon is the real sprite from `assets/weapons-gfx/` rotated along aim.
- **Weapons** — Deagles, AK-74, MP5, Spas-12, LAW rocket (heavy recoil enables rocket-jumping); per-weapon damage / rate / spread / mag / reload. Each fires and reloads with its authentic Soldat sample (`deserteagle-fire.wav`, `ak74-fire.wav`, `mp5-fire.wav`, `spas12-fire.wav`, `m79-fire.wav`).
- **Grenades** — arc throw, bounce, fuse, area damage
- **3 AI bots** (SP only) — lead aim, dodge-jump, jet up to reach you, lob grenades
- **Bullets** — hit opposing team, die on terrain, muzzle recoil
- **Gibs & ragdoll** — blood particle burst + rigid-body gib chunks on death, auto-respawn
- **Arena** — 3200-wide arena, gradient sky + stars, parallax hill layers, ground, platforms, walls
- **Match** — team scoring on every kill (5-min round timer OR first-to-20 wins), scoreboard + timer + winner banner in the HUD, auto-restart 4s after the round ends. Host-authoritative in multiplayer.
- **HUD** — health / fuel / ammo / weapon / grenades, team-colored kill feed, scoreboard, round timer, map name, net status
- **Networking** — ENet host/join, per-peer authority, state-sync + spawn/despawn RPCs, host-picked map replicated to clients on join

## Project layout

- `scenes/` — menu, main, player, bullet, bot, grenade scenes
- `scripts/`
  - `menu.gd` — main menu + host/join UI
  - `main.gd` — arena builder + spawn/despawn (SP and networked paths)
  - `player.gd` — soldier controller + weapon system + net-state RPCs
  - `bot.gd` — SP-only AI
  - `bullet.gd`, `grenade.gd` — projectiles
  - `hud.gd`, `sky.gd`, `parallax.gd` — presentation
  - `net.gd` — autoload ENet wrapper (`Net`) + `--smoke-host`/`--smoke-join` harness
  - `sfx.gd` — autoload SFX (`Sfx`); real `.wav` playback from `assets/sfx/`
  - `soldier_art.gd` — shared soldier renderer (delegates the body to `gostek.gd`)
  - `gostek.gd` — static body assembly from `assets/gostek-gfx/*.png`
  - `settings.gd` — autoload persisted user prefs (`Settings`)
- `assets/` — Soldat base assets (see [CREDITS.md](CREDITS.md))
  - `sfx/` — weapon fire / reload, jump, gib, explosion, jet loop
  - `weapons-gfx/` — weapon sprites drawn along aim direction
  - `gostek-gfx/` — body parts assembled into the standing soldier
  - `anims/` — 51 `.poa` animation files (format documented in `references/poa-format.md`; not yet driving live animation)
- `references/` — engineering notes (`.poa` reverse-engineering, etc.)
- `build/` — exported Windows .exe

## Asset pipeline

Assets ship in the source layout under `assets/`. On first project open
the Godot editor generates `.import` sidecars; after that `load()` in
GDScript resolves the resource path directly. Sound playback uses a
cached `AudioStreamPlayer` pool in `scripts/sfx.gd` — samples are
lazy-loaded, not preloaded, so startup stays quick. Weapon and gostek
textures are cached statically the first time they draw.

## Next steps (ideas)

- Drive the gostek from `.poa` frames (walk / aim / reload / jump)
- Terrain textures from `assets/textures/`, sparks from `assets/sparks-gfx/`
- MultiplayerSpawner / MultiplayerSynchronizer to replace hand-rolled state RPCs
- Dedicated server mode + server browser
