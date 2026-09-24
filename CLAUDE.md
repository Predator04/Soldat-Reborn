# Soldat Reborn — project context

2D Soldat remake. Godot 4.7 (GL Compatibility renderer), GDScript, ENet multiplayer.
This directory (`game/`) is the git repo root — note the space in the parent path `"soldat reborn"`.

## Entry & boot
- `scenes/menu.tscn` is the main scene; gameplay is `scenes/main.tscn`.
- 1280×720 viewport, `canvas_items` stretch, aspect `expand`.
- Autoloads (`project.godot`): `Sfx`, `Settings`, `Net`, `GifRecorder`, `Stats`, `Music`, `MatchConfig`.

## Key files
- `main.gd` (~115 KB) — match coordinator: soldier/bot spawn, all game-mode logic, kill feed, scoreboard, round reset, RPC fan-out. Holds `player` (local node), `_players_by_id` (peer_id → node), `_bots_by_id`, `_gg_levels`, `_gg_kills`, `_scores`.
- `net.gd` — high-level ENet wrapper (autoload). `Mode { SINGLEPLAYER, HOST, CLIENT }`, `DEFAULT_PORT 7777`, `MAX_PEERS 8`, `MAP_NAMES` / `MODE_NAMES` constants (kept in sync with `menu.gd`). Owns `custom_map_json` (custom-map sync, #99) and `is_dedicated`. Also hosts the `--smoke-*` self-test entry points.
- `player.gd` (~71 KB) — player physics, weapons, F-throw, ladder climb engage/dismount (~lines 401–466).
- `bot.gd` (~38 KB) — bot AI, has ladder awareness.
- `gostek.gd` — soldier sprite rendering/animation.
- `hud.gd` — HUD + mode scoreboards (DM/CTF/Gun-Game rung readout).
- `weapon_pickup.gd`, `bonus_pickup.gd`, `bullet.gd`, `grenade.gd`, `rocket.gd`, `m2.gd` (stationary gun).
- `map_editor.gd`, `map_io.gd`, `map_gen.gd` — custom-map tooling. `poa_loader.gd` + `references/poa-format.md` = classic `.pms` map import.
- Game-mode constants (`MODE_DM`, `MODE_TDM`, `MODE_CTF`, `MODE_INF`, `MODE_HTF`, `MODE_RM`, `MODE_PM`, `MODE_DOM`, `MODE_BR`, `MODE_GG`) live in `Settings.gd`.

## Networking model (critical — don't break this)
- **Host-authoritative.** Host (peer 1) spawns and mirrors every soldier, bot, projectile, and pickup. Clients send input RPCs and render what the host replicates.
- RPC tags: `@rpc("authority", ...)` = only the node's multiplayer authority may call (server→client replication, or client→its-own-node). `@rpc("any_peer", ...)` = any peer may invoke. `call_local` = also execute on the caller; `call_remote` = remote peers only.
- Map/mode sync flows through `net_set_map(idx, mode_idx, custom_json)`; a joining client is hydrated in `net_client_ready` (host mirrors full world: bots, pickups, GG levels).
- **Preserve these guards everywhere**: `is_multiplayer_authority()` and `multiplayer.multiplayer_peer == null or ...`. Single-player must keep working identically.

## Hard rules
- Preserve ALL existing behavior — do not regress prior fixes (RPC auth guards, weapon-drop/Gun-Game correctness, etc.).
- Don't touch balance/movement constants (exception allowed only when the issue explicitly calls for it).
- `git add -A` before every commit — the `.gd.uid` files MUST be committed (Godot 4.4+).
- Read `gh issue view <n>` for full detail before fixing any issue; close each with `gh issue close <n> -c "Done in <sha>"`.

## Verify command (must print ZERO matching lines after every item)
```
~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --quit-after 700 res://scenes/main.tscn 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Cannot load|Identifier not found|Invalid call|Cannot infer"
```

## Syntax checking — the full boot is the ONLY reliable check
- `--headless --quit-after 700 res://scenes/main.tscn` (~11s) loads autoloads + the whole game and catches real parse/compile errors. Use this.
- `--headless --import` is a NO-OP on a warm cache — it does not recompile scripts, so it silently misses new syntax errors. Do not trust it.
- `--check-only --script <file>` false-positives on autoload identifiers (`Settings`, `Net`, `MatchConfig`, etc.) because autoload singletons aren't loaded in that mode. Only useful for standalone leaf scripts with no autoload references.

## Smoke tests (headless, from `net.gd`)
- `--smoke-host` — host a game, report peer/player counts, quit.
- `--smoke-join` — connect to a local host, confirm map + bot replication.
- `--smoke-botfire` — join + wait 20s, confirm remote bot fire replicates (prints `bot_shots_seen`).
- `--smoke-dedicated` — dedicated (headless) host smoke.
- Dedicated server: `--dedicated --port N --map <name|index> --mode <name|index> [--register <master-url>]`.

## Maps & anti-stuck (v1.13)
- World rect is per map: `main.gd` vars `MAP_W / MAP_H / GROUND_Y / KILL_Y` come from `_map["world"]` (ported maps) or the 4800×2000 defaults. Never hard-code 4800/2000/1900.
- Baseline floor's TOP edge = `GROUND_Y`. Ported maps hide it and kill soldiers below `KILL_Y`.
- Poly `"col"`: 0 solid, 1 bullets-only (layer 2), 2 players-only (layer 3/bit 4), 3 decorative. `"vc"` = per-vertex colours.
- After touching any map data run `python3 tools/map_audit.py` (must print `0 / N maps have problems`). Soak test: `godot --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=40 --from=0 --to=26`.
- Re-port classics: `python3 tools/pms_to_map.py --regen <opensoldat/base checkout>` (keeps names + weather; needs numpy/pillow/scipy/shapely).
- Bot nav: after ANY map geometry change run `python3 tools/build_nav.py` (graphs are rejected at runtime if poly/collision counts changed). Bot brain = `bot.gd::_think*` (goal) + `_nav_step` (path following).
- Soldiers are on physics layer bit 8 and don't collide with each other; anything that must hit soldiers masks bit 8.
- Soak test flags: `--mode=N`, `--trace=<goal label>`, `--trace-name=Blue_Bot_2`, `--log-falls`.

## In-repo references
- `references/weapons-stats.md` — weapon damage / balance figures.
- `references/poa-format.md` — classic Soldat `.pms` map format.
- `references/soldat-commands-gestures.md` — chat commands + taunts.
- `references/soldat-intro.md` — game concept notes.

## Gotchas
- GDScript uses TAB indentation — do not convert to spaces.
- Version string is in `project.godot` (`config/version`); bump it for releases together with `export_presets.cfg` (Android `version/name` + `version/code` = MAJOR*10000+MINOR*100+PATCH, Windows `file_version`/`product_version` = X.Y.Z.0) and the top `CHANGELOG.md` heading — the gate checks they agree.
- Release gate: `tools/release_gate.sh` (full, ~20 min: static, boots, MP smokes, all 10 modes bots-vs-bots, all-map CTF sweep) or `--quick` (CI). Must end `GATE PASSED`; logs in `build/gate/`.
- Host → client RPCs from bots/projectiles go only to acked peers (`ready_peer_ids()`, `_bcast`, `_net_send`); a plain `rpc()` reaches peers still loading and spams "Node not found".
- MP respawns are scheduled by `main._schedule_peer_respawn`; objective events go through `_objective_event` (never the `kill` signal).
- Path has a space (`soldat reborn/game`) — always quote it in shell commands.
