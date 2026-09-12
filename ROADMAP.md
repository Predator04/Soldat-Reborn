# Soldat Reborn — Roadmap (overnight build queue)

**Project:** /mnt/c/Users/Admin/Desktop/soldat reborn/game
**Godot (headless verify):** `~/godot/Godot_v4.7.2-stable_linux.x86_64`
**Verify command:** `cd "/mnt/c/Users/Admin/Desktop/soldat reborn/game" && ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --quit-after 900` (must print ZERO lines matching error/invalid/nil/failed/attempt)
**Export command:** `cd "/mnt/c/Users/Admin/Desktop/soldat reborn/game" && ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --export-release "Windows Desktop" build/SoldatReborn.exe`

## Goal
A 2026-quality port of Soldat's *feel* in Godot 4 (run-and-gun, jet boots, bunny hopping, ragdoll gibs, weapon balance). Same DNA, modern juice.

## Done
- [x] Run / bunny hop / jet boots (fuel) / gibs
- [x] 3 AI bots, team-based bullets, terrain + platforms
- [x] Headless-verified + Windows .exe export

## Backlog (work top-down; do 1-2 per pass, verify after each)

### Feel & juice (P0)
- [x] Coyote time (~0.08s) + jump buffering (~0.1s)
- [x] Screen shake (shoot / explosion / death)
- [x] Muzzle flash + bullet trails
- [x] Jetpack flame as particles (CPUParticles2D), not just drawn triangle
- [x] Procedural soldier art — head (with helmet + visor), rounded torso, jetpack, running-cycle legs, front-arm holding weapon, back-arm — shared renderer `scripts/soldier_art.gd` used by both player.gd and bot.gd. Layered muzzle flash (three concentric halos) + three-color jet flame cone.

### Combat (P0)
- [x] Weapon system: Deagles / AK-74 / MP5 / Spas-12 / LAW — switch (1-5 or scroll), reload (R), ammo per mag
- [x] Grenades: arc throw, bounce, explode, area damage (Soldat's signature)
- [x] LAW rocket launcher: slow projectile, splash damage, heavy recoil (rocket-jumping). Bot loadout support (last bot spawns with LAW). Multiplayer wired via existing net_shoot.

### Presentation (P1)
- [x] Camera follow + smoothing + bigger map (3200px)
- [x] Parallax background layers (3 depth layers, camera-relative drift)
- [x] HUD: kill feed (killer ▸ victim + weapon, team-colored, auto-fade)

### Bots (P1)
- [x] Lead aim, dodge, use grenades

### Systems (P2)
- [x] Sound: generated SFX (shoot / jump / jet / gib / reload / empty / explode) — procedural PCM in scripts/sfx.gd (autoload `Sfx`)
- [x] Death ragdoll: physics gib pieces (RigidBody2D chunks + particle gore)
- [x] Multiplayer (Godot ENet high-level): host/join menu, spawn/despawn sync, bullets, grenades, kill-feed replicated. Autoload `Net` (scripts/net.gd). Headless smoke tests via `--smoke-host` / `--smoke-join`.
- [x] Multiplayer map sync: host picks a map on the HOST GAME panel; `Net.net_set_map` RPC pushes the chosen index to each joining peer BEFORE they load main.tscn, so terrain matches on both sides.
- [x] Match / score / round system: team scores on every kill, 5-min round timer OR first-to-20-kills wins, scoreboard + timer + winner banner in the HUD, auto-restart 4s after round end. Host-authoritative in MP (broadcast at 5Hz via `net_match_state`). Bots respawn on their slot after 2s so score can accumulate against them.
- [x] Main menu + settings (SFX volume / screen shake / fullscreen — persisted via autoload `Settings` to user://settings.cfg)
- [x] More maps (3 layouts — Ascent / Towers / Pillars — data-driven in main.gd, cycled per game)

## Rules (hard)
1. **Preserve the Soldat feel** — bunny-hop momentum, jet fuel management, weapon balance. Don't make it floaty.
2. After ANY code change: run the verify command. Zero errors before you move on.
3. Then export, then `git add -A && git commit`.
4. Never commit code that fails the verify command.
5. Update this file: check off what you did, add bugs you find to "Known bugs".

## Known bugs
- Multiplayer uses per-frame full-state RPCs (position/velocity/aim/etc.) at physics rate — fine for 2 players on LAN, will not scale; swap for MultiplayerSynchronizer if peer counts grow.
- Kill feed on clients only reflects networked kills — bots (SP-only) still fire the local `kill` signal.
- Round reset does not restore player HP/ammo/position; players just fight on with the timer reset. Feels fine in practice but not "clean slate".
