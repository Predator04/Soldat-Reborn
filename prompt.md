You are continuing "Soldat Reborn" (Godot 4.7 rebuild of Soldat, real assets, at /mnt/c/Users/Admin/Desktop/soldat reborn/game). It builds clean at v1.7.1. Work through 4 items IN ORDER. After EACH item: run the verify commands, export, `git add -A && git commit` (include new .uid files), `git push`, and close that item's issue. READ the existing code first — this is a large working codebase, match its conventions, don't rewrite subsystems.

## Item 1 — Port the remaining classic Soldat maps (#66)
99 `.pms` maps exist at `/home/predator04/soldat-base/shared/maps/`; only 10 are ported (assets/maps/*.json). Port the rest.
1. For every `.pms` not already in `assets/maps/`, run `python3 tools/pms_to_map.py <path-to.pms>` (read that script first to learn its exact CLI). It emits `assets/maps/<stem>.json` with `_scenery_hints` + `_source.pms_texture` references.
2. After porting, run `python3 tools/ship_assets.py` to pull any NEW scenery/texture sprites those maps reference into `assets/scenery/` and `assets/textures/` (this reads the map JSONs; it needs PIL — `pip install pillow` if missing). These dirs are COMMITTED now (not gitignored) — `git add -A` the new assets.
3. Add the new map stems to `BUNDLED_CLASSICS` in `scripts/map_io.gd` AND to `MAP_NAMES` in `scripts/menu.gd` (keep the existing order; append new ones alphabetically).
4. Verify each new map JSON is valid: `python3 -c "import json,glob; [json.load(open(f)) for f in glob.glob('assets/maps/*.json')]"`.
5. Any `.pms` that fails to parse or produces an empty/invalid map: SKIP it, and print a list of skipped maps in your final report (do not silently drop them — list the filenames).
Close #66.

## Item 2 — Bot count + difficulty (#67)
Add a menu setting for bot count (0–8) and bot skill (1–5), persisted via the existing `Settings` autoload (settings.cfg) the way the game modifiers already are.
- Bot count controls how many bots `main.gd` `_spawn_bots()` spawns (default keeps the current behavior).
- Skill scales bot aim lead error, reaction time, and aggression. Bots are in `scripts/bot.gd` — read how it aims/decides to shoot and add a difficulty factor that widens aim spread and slows target acquisition at low skill, tightens at high skill. Do NOT make bots teleport or break pathfinding.
- Surface both as menu controls in `scripts/menu.gd` alongside the existing mods/cosmetics panels.
Close #67.

## Item 3 — Weather effects (#68)
Add per-map weather (rain/snow) rendered as a CPUParticles2D overlay that follows the camera.
- Tag weather on maps via the map JSON (`"weather": "rain"|"snow"` or empty), defaulting to none. Add `weather` to a few classic maps for variety (e.g. Aftermath = rain, Viet = rain, Warehouse = none). Read how `main.gd` spawns the parallax/sky so the weather overlay lives at the right z-order and follows the camera the same way.
- Rain = thin fast falling streaks; snow = slow drifting flakes with horizontal sway. One CPUParticles2D each, camera-relative, spawned/despawned in `main.gd` when the map loads.
- Respect the existing lo-fi mode (skip weather when lo-fi is on, like other particles).
Close #68.

## Item 4 — Fix MP RPC desync (#69)
A headless host+join smoke test prints repeated `ERROR: Node not found: "Main/BotGrenade_1_1"` and `"Main/@RigidBody2D@430"` (plus "Invalid packet received / Failed to get cached node"). Two causes to fix:
- **Bot grenades**: when a bot throws a grenade in MP, the host broadcasts its state via an RPC targeted at a node path that the client never spawned (client-side spawn is missing or named differently). Make the bot-grenade spawn itself replicate (mirror how `net_spawn_bot` / `net_bot_shoot` replicate bot fire) so every peer has the node before the state RPC fires.
- **Weapon-pickup RigidBody2D**: the host sends per-frame/10Hz state RPCs to pickup bodies the client hasn't created with a matching path. Give dropped weapons a stable, deterministic name on all peers (like the #61 rocket naming) so the RPC path resolves, or gate the RPC on the peer having the node.
After fixing, PROVE it: run the smoke test (see Verify below) and confirm the two error classes are GONE and `SMOKE-BOTFIRE ... bot_shots_seen>0` still holds.
Close #69.

## Verify (must print ZERO matching lines; "1 resources still in use at exit" is benign)
```
cd "/mnt/c/Users/Admin/Desktop/soldat reborn/game"
~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --quit-after 600 2>&1 | grep -iE "error|invalid|nil|failed|attempt|SCRIPT ERROR|Parse Error|Cannot load"
~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --quit-after 600 res://scenes/main.tscn 2>&1 | grep -iE "error|invalid|nil|failed|attempt|SCRIPT ERROR|Parse Error|Cannot load"
```
MP smoke test (Item 4 proof): start `~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless -- --dedicated --port 7777 --map 0 --mode 0` in one shell, then in another `~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless -- --smoke-botfire`, and confirm no `BotGrenade`/`RigidBody2D` node-not-found errors and `bot_shots_seen>0`.

## Export
```
cd "/mnt/c/Users/Admin/Desktop/soldat reborn/game"
~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --export-release "Windows Desktop" build/SoldatReborn.exe
```

## Hard rules
1. Preserve Soldat feel — do NOT re-tune movement/weapon balance (those were just set).
2. Do NOT change soldier scale, camera zoom, or sprite draw scale.
3. GDScript 4 gotchas: `const` holding `Vector2()`/`PackedVector2Array()` won't parse (use `var`); authority checks must be `if multiplayer.multiplayer_peer == null or is_multiplayer_authority():`; Variant math needs explicit `float()`/`int()` casts.
4. After EACH item: verify → export → `git add -A && git commit` → `git push` → close the issue with the sha. Never commit failing code.
5. DEFER (do not build, leave open): server browser/lobby, ranked matchmaking (#33), vote system, spectator.

## Final report (required)
Per item: files changed, verify result, export result (did the exe rebuild), commit sha, issue closed + pushed (`git log origin/main..HEAD` empty). List skipped maps by filename. Bump `project.godot` `config/version` and the menu version label to `1.8.0` (build = `git rev-list --count HEAD` at commit time) as a final commit. Be honest about anything you couldn't verify headless (visuals).
