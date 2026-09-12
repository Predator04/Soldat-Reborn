# Soldat Reborn — Roadmap (overnight build queue)

**Project:** /mnt/c/Users/Admin/Desktop/soldat/game
**Godot (headless verify):** `~/godot/Godot_v4.7.2-stable_linux.x86_64`
**Verify command:** `cd /mnt/c/Users/Admin/Desktop/soldat/game && ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --quit-after 900` (must print ZERO lines matching error/invalid/nil/failed/attempt)
**Export command:** `cd /mnt/c/Users/Admin/Desktop/soldat/game && ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --export-release "Windows Desktop" build/SoldatReborn.exe`

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

### Combat (P0)
- [x] Weapon system: Deagles / AK-74 / MP5 / Spas-12 — switch (1-4 or scroll), reload (R), ammo per mag
- [x] Grenades: arc throw, bounce, explode, area damage (Soldat's signature)

### Presentation (P1)
- [x] Camera follow + smoothing + bigger map (3200px)
- [x] Parallax background layers (3 depth layers, camera-relative drift)
- [x] HUD: kill feed (killer ▸ victim + weapon, team-colored, auto-fade)

### Bots (P1)
- [x] Lead aim, dodge, use grenades

### Systems (P2)
- [x] Sound: generated SFX (shoot / jump / jet / gib / reload / empty / explode) — procedural PCM in scripts/sfx.gd (autoload `Sfx`)
- [x] Death ragdoll: physics gib pieces (RigidBody2D chunks + particle gore)
- [ ] Multiplayer (Godot ENet high-level): spawn/despawn sync, bullets, grenades
- [x] Main menu + settings (SFX volume / screen shake / fullscreen — persisted via autoload `Settings` to user://settings.cfg)
- [x] More maps (3 layouts — Ascent / Towers / Pillars — data-driven in main.gd, cycled per game)

## Rules (hard)
1. **Preserve the Soldat feel** — bunny-hop momentum, jet fuel management, weapon balance. Don't make it floaty.
2. After ANY code change: run the verify command. Zero errors before you move on.
3. Then export, then `git add -A && git commit`.
4. Never commit code that fails the verify command.
5. Update this file: check off what you did, add bugs you find to "Known bugs".

## Known bugs
- (none logged yet — add here)
