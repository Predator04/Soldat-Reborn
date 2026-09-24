# Changelog

All notable changes to Soldat Reborn.

## [1.15.0] — 2026-09-24

Release-readiness pass: bots fight bots, a five-reviewer "pre-release" audit
(gameplay, networking, UX, bots, QA/build) with its fixes, and a scripted
release gate (`tools/release_gate.sh`) run three times clean.

### Gameplay
- **Bots vs bots**: in DM / Rambo / Gun Game / BR every bot is its own team (1000+), with its own colour, so bots fight each other as well as you. FFA scoreboard shows the top 4 + you.
- **Objective HUD**: status line (your team, each flag HOME / TAKEN by X / DROPPED / YOU HAVE IT, DOM point chips with capture %, BR "return to the zone"), big banners + sounds for grabs / drops / returns / captures, and off-screen edge arrows with distance to flags, carriers, your base, DOM points and the BR ring.
- Captures / DOM points / PM points no longer go through the kill feed (they double-scored and counted as kills in Stats).
- Mode logic pauses between rounds (no captures on the winner screen); flags reset home on round reset; Survival no longer adds a second body after a winner-screen death.
- Gun Game rung lookup can't run past the ladder; kill-streak banners only for you (2+) or big streaks (5+).
- Bots: Rambo bots go for the bow and hunt its carrier; melee bots close in instead of swinging at range; bots only shoot / throw grenades at targets they can see; Flamethrower, Chainsaw and Spas-12 stats fixed (Spas fires a real 8-pellet spread); bot jet no longer spams the jet sound.
- BR ring damage now also hurts clients' own soldiers, and a ring death isn't credited to yourself. Rambo bow regen works for client carriers.

### Multiplayer
- Version handshake: a client on a different build is refused with a readable reason ("Version mismatch: host 1.15.0, you 1.14.0") and sent back to the menu, which now shows why you left (kicked / host lost / mismatch).
- Duplicate player names get a suffix; `net_client_ready` can't be replayed for a free respawn; chat author is resolved on the host (no spoofing) and capped at 200 chars.
- Respawn timing is owned by the host scene (matches the death-screen countdown); the bot-count slider no longer over-spawns while bots are dead.
- Host RPCs for bot fire, grenades and rockets go only to peers that finished loading — no more "Node not found: Main/Bot_N" spam on joiners.
- M2 mount/dismount sender check, vote majority counts only eligible voters, dedicated survival reset doesn't spawn a host ghost, custom map blob cleared on restart.
- Pausing in multiplayer only locks your own input (it used to freeze the host's whole match).

### Platform / build
- Android back button opens/closes the pause menu in game and acts as "back" in the menu instead of quitting.
- Version shown in the menu comes from project settings; git is only queried in editor runs.
- Android version 1.15.0 (code 11500), Windows file/product version 1.15.0.0; Windows export now ships the map JSON.
- Settings save is read-modify-write (keeps sections it doesn't own); loaded mode index is clamped. Map JSON loader tolerates malformed lists and warns on missing files.
- `tools/release_gate.sh`: static checks, scene boots, dedicated + listen-server smokes, all 10 modes bots-vs-bots, and a CTF sweep of all 102 maps. CI runs the `--quick` gate.

### Release gate results
- Run 1 caught a regression from this release's own speed-up: the terrain column index appended into copies of packed arrays, so spawn/ground checks saw no terrain (CTF sweep: grabs 154 → 115, captures 22 → 2). Fixed. Also hardened the harness (wait for server listen, longer objective rounds).
- Run 2 caught a deferred gib spawn running after a map switch (script error). Fixed.
- Run 3: **22/22 checks passed** — CTF sweep of all 102 maps: 202 grabs, 32 captures, 581 kills, 8 falls, 0 anti-stuck frees, 0 script/RPC errors (v1.14: 154 / 22 / 22 falls).

## [1.14.0] — 2026-09-24

Smarter bots: real navigation + objective play. Plus more stuck/placement fixes.

### Bots
- **Navigation graph** baked for every map (`tools/build_nav.py` → `assets/nav/*.json`, loaded by `scripts/nav_graph.gd`). Bots run A* over walkable surfaces and follow the path: hop at low lips, jump-then-jet up climbs, drop down ledges, jet across gaps with a full tank. Bottomless stretches and steep slopes aren't used as routes.
- **Objective brain** (re-thinks ~3x/sec): CTF attackers grab the enemy flag and run it home, defenders patrol the base, everyone chases a carrier who has our flag (and hunts it down in a flag standoff), dropped flags get returned, teammates escort carriers. INF attack/defend, HTF carriers keep moving away from enemies, DOM bots capture the nearest unowned point, PM bots collect points, Rambo bots go for the bow, BR bots stay in the ring. DM/TDM bots hunt the enemy's position (or last-seen spot) instead of pushing into walls.
- **Target choice**: visible enemies beat ones behind walls, enemy flag carriers get priority, wounded enemies a little too.
- **Fuel sense**: bots wait on the ground to refuel before a climb or gap they can't make, and don't bunny-hop away their regen.
- **Pit guard**: bots won't strafe/wander off an edge into a bottomless drop.
- Fixed a v1.13 bug that made bots burn jet fuel constantly (escape jet fired whenever airborne); bots no longer chase bonus crates they can't collect; blocked-on-a-seam hop.
- Soak test over all 102 maps (CTF, 30 s each): flag grabs 98 → 154, captures 7 → 22, falls 22 → 8; DM engagements up ~50%.

### Maps / stuck fixes
- **Seam-free collision** for ported maps: triangles are merged into clean convex outlines (`collision` key) so bodies stop snagging on the joins between Soldat's triangles. Triangles stay for rendering.
- **Soldiers no longer collide with each other** (as in Soldat) — they used to shove each other into walls and plug tunnels.
- **Every objective is placed explicitly and validated**: CTF flags, INF/HTF flag, DOM points, PM points and Rambo bow for all 102 maps (the old 4800-arena defaults put them inside rock or over pits on most classic maps — e.g. Ascent's RED flag was buried in the hill).
- **Team spawns**: each side spawns at its own base in team modes (they used a shared list, so BLUE bots often spawned in RED's base). Soldat Alpha/Bravo now map to RED/BLUE correctly, so flags stand on their own team-coloured bases.

## [1.13.0] — 2026-09-23

Map integrity pass (nobody gets stuck), classic-map re-port, flag + map graphics.

### Fixed — getting stuck / map placement
- **Baseline floor was 100 px too high.** Its top edge now sits at `GROUND_Y` (1900) like every map, the editor and map_gen assume. This had sealed the built-in tunnels shut (20 px gap) and buried the bottom rows of every ported map.
- **Built-in maps:** Ascent / Towers / Pillars tunnels are real walk-throughs now (they were sealed notches — the Towers CTF flags sat in unreachable pockets). Towers stair platforms moved out of the mountain and anchored to the slope (no wedge gap); buried platforms on Ascent/Pillars moved/removed; Towers bot spawns that were inside rock moved onto the stairs.
- **All 99 classic maps re-ported** from `opensoldat/base` at one uniform scale (1.5) with a per-map world rect, instead of being squeezed into 4800×2000 (Messner was at 0.39× — corridors shorter than a soldier). Correct Soldat polygon types: background / flag-only / team-only polys no longer act as walls; "only bullets" and "only players" polys collide with the right things (terrain layers 2/3).
- Every spawn, flag, M2 and pickup is validated by `tools/map_audit.py` (embedded in rock, isolated pocket, over a pit) and auto-moved when bad; `python3 tools/map_audit.py` reports 0 problems across all 102 maps.
- **Fell off a ported map** (below its lowest geometry) = death, like Soldat — no more wandering the empty void around the map.
- **Anti-stuck watchdog** frees any soldier embedded in terrain for >0.35 s. **Wedge fix:** a body resting between two steep surfaces now counts as grounded (can jump, fuel regenerates) instead of being trapped with an empty tank.
- **Stance headroom:** you can't stand up (or leave prone) into a low ceiling any more — you stay crouched until there's room.
- **Bots** use the same feet-anchored 14×24 box as players (they hovered ~20 px above the ground and wedged where players fit) and run an escape manoeuvre when they stop making progress against terrain. Wander edges follow the map width.
- Spawn jitter / enemy-avoid shifts never place a soldier inside a wall or over a pit; dropped flags fall to the ground (or return home if dropped off the map); flags whose carrier was freed no longer hang in the air; lost weapons below the kill line are cleaned up (Rambo bow respawns).

### Graphics
- **New animated flags**: waving shaded cloth with emblem, stone base + pulsing team glow at home, strapped to the carrier's back while carried (bots too, on clients), planted with a bobbing marker when dropped.
- Classic maps now render Soldat's **per-vertex colours** (all the map shading), **background polygons**, correct **prop size / tint / rotation**, and the map's own **sky gradient** with matching parallax.
- Platforms are textured with the map terrain and get a bevel trim; tunnels get a dark back wall.

### Tools
- `tools/map_audit.py` (static stuck audit), `tools/stuck_test.gd` (headless bot soak test), `tools/shot.gd` (screenshot helper), `tools/pms_to_map.py --regen <opensoldat-base>`.

## [1.11.0] — 2026-09-13

Vote system + bonus pickups.

### Added
- **Vote system** (`/votemap`, `/votekick`, `/votecancel`; F1/F2 rebindable; host-authoritative tally; 30s cooldown) — fixes #77.
- **Bonus pickups** (Predator / Berserker / Bulletproof Vest / Cluster Grenades crates, ~30s timed effects, MP-replicated, per-slot respawn) — fixes #78.

## [1.10.0] — 2026-09-13

Spectator mode + kill-streak announcements.

### Added
- **Spectator mode** (follow-cam + free-cam while dead, cycle living players, SP + MP) — fixes #75.
- **Kill-streak banners** (Double Kill → Ultra Godlike, streak-ended feed line) — fixes #76.

## [1.9.0] — 2026-09-13

Weapon HUD, settings/music/controls overhaul, host admin menu.

### Added
- **Weapon-selection HUD** (Soldat LimboMenu: primary/secondary list, green highlight, hover tooltip) — fixes #70.
- **Settings redesign** (glassmorphism accordion; mouse sensitivity, show-FPS, blood intensity, shake slider) — fixes #73.
- **Music** (3 Soldat tracks converted to .ogg, looping, volume/mute) — fixes #73.
- **Rebindable command + GIF keys** (`/` and `F9` promoted to real actions) — fixes #73.
- **Host admin menu** (host-authoritative gravity/friendly-fire/damage/speed/bots/mode/map, live sync, restart match) — fixes #74.

### Fixed
- **Secondary weapon anchor** — back-slung gun now hip→shoulder instead of hanging like a penis — fixes #71.
- **Floating soldiers** — collision box resized to the real sprite and feet-anchored, so soldiers stand on the ground/platforms — fixes #72.

## [1.8.0] — 2026-09-13

Classic maps, bots, weather, MP desync fix.

### Added
- **All 99 classic Soldat maps** ported (up from 10) — fixes #66.
- **Bot count + difficulty** (skill 1–5) — fixes #67.
- **Weather** (per-map rain/snow) — fixes #68.

### Fixed
- **MP RPC desync** (bot grenades + weapon pickups no longer spew node-not-found) — fixes #69.

## [1.7.0] — 2026-09-13

Round-boundary hygiene, gostek fidelity, and MP projectile parity.

### Fixed
- **Clean-slate round reset** (fixes #58). Non-survival modes (DM/TDM/CTF/…)
  now restore every living soldier to full HP/ammo and teleport them to a
  spawn slot when the round timer/score resets, instead of resuming with
  mid-fight state. Dead-and-respawning soldiers keep their existing scheduled
  timer path — no double-spawns. Host broadcasts `net_round_reset` so each
  peer resets its own locally-authoritative body; Survival's wipe-and-respawn
  and the MP `_spawn_networked_player` path are untouched.
- **MP grenade/rocket transform sync** (fixes #61). Projectile physics is now
  authority-owned: only the spawning peer integrates position/velocity and
  broadcasts pos/vel/rot at 20 Hz (unreliable_ordered). Non-authority replicas
  freeze (RigidBody2D kinematic for grenades, skipped integration for rockets)
  and lerp toward the incoming transform, so shooter and victim see the same
  trajectory and impact spot. Authority additionally fires `net_explode` at
  the exact impact position so blasts detonate together.

### Added
- **Front arm tracks aim_dir** (fixes #59). The RIGHT-arm chain (joints
  10→13→16→20) rotates around the shoulder toward aim_dir by a clamped ±16°
  offset — subtle enough that the canned .poa poses still own the base look,
  enough that the gun stops looking detached when aiming steeply up/down. The
  wrist anchor for the weapon sprite applies the same offset so the gun
  travels with the hand.
- **Missing gostek detail overlays** (fixes #60). Ships the outstanding
  detail sprites that were sitting in `assets/gostek-gfx/` but never
  rendered: dreadlocks (`dred.png`) on hair heads, dogtag (`metal.png`)
  hanging from the chain, blood/damage overlays (`ranny/*.png`) that blend
  in as HP drops below 60, a frag/cluster grenade riding on the belt while
  the soldier is carrying grenades, and the inactive secondary weapon slung
  across the back along the spine axis. Menu grows Dreadlocks + Dogtag
  CheckButton toggles alongside the existing Vest/Cigar; bots roll the two
  new looks with the existing random-cosmetics pass.

## [1.6.0] — 2026-09-12

Classic maps, dedicated server, and MP bot combat parity.

### Added
- **10 classic Soldat maps ported from `.pms`** (#53) — Nuubia, Maya,
  Aftermath, Hormone, Viet, Scorpion, Warehouse, Baire, Airpirates, Bunker.
  Terrain polygons converted 1:1 with the original geometry; spawns/flags
  translated into the map JSON schema.
- **Dedicated headless server** (#54). `SoldatReborn.exe --dedicated
  [--port 7777] [--map <name>] [--mode <dm|tdm|ctf|inf|htf|rm|pm|dom|br>]`
  boots without a local player, pre-populates bots, and waits for peers.
- **Bots over ENet** (#55). Host owns bot lifecycle + AI; every client
  spawns replicas via `net_spawn_bot`, streams `net_bot_state` at 20 Hz
  (pos/vel/facing/health/loadout/dead), and mirrors death via `net_bot_die`.
  Joining peers see the full live bot roster in the initial ready handshake.
- **Replicated bot fire** (#57). Host bots broadcast `net_bot_shoot` /
  `net_bot_grenade` so clients spawn matching tracers + rockets + grenades
  and take damage from bot fire. FFA joiners now spawn at a random
  `bot_spawns` slot (not the map corner) so they land in the action.
- **Ported scenery + textured terrain** (#56). Real Soldat scenery sprites
  and per-vertex-UV terrain textures render on top of the polygon geometry
  for the classic map roster.

## [1.5.0] — 2026-09-12

Movement + controls polish.

### Added
- **Fully rebindable controls** via `InputMap` and a new settings screen.
  Bindings persist to `user://controls.cfg`; "Reset to Defaults" restores the
  documented table. Main menu Settings → Controls exposes the rebind screen
  before a match starts.
- **Pause menu overlay** (ESC) with Resume / Settings / Controls / Exit
  without leaving the round.
- **Richer sky + parallax** — dusk gradient, clouds, and four mountain
  layers drifting at camera-relative speeds.

### Changed
- **Movement overhaul** — stance-shape collision swaps for crouch/prone,
  roll burst tuned to beat bunny-hop, jet mods now scale regen + thrust
  consistently, bot AI cleaned up on top of the M2 mount path.
- **Gameplay pacing slowed ~15%** — run 330→280, bunny 640→545, jump
  470→430, jet 1250→1050. Soldat's classic tempo, not floaty.
- **Maps** overhauled with polygon terrain, hills, and tunnels.

### Fixed
- **Jet boots** — thrust 1050→2200 so they actually climb (was weaker than
  gravity, so pressing RMB would slow the fall but never lift you).
- **mod_gravity** applied to grenade fall accel and the M79 arc so the
  gravity slider affects every ballistic path consistently.
- **Pause menu SFX volume** no longer double-attenuated.
- **Main-scene load failure** — `MAPS` couldn't be `const` because it held
  `Vector2()` / `PackedVector2Array()` calls; downgraded to `var` per the
  GDScript 4 parser rules.

## [1.4.0] — 2026-09-12

Level editor + procedural generation.

### Added
- **In-game map editor** (#31). Toolbar to place platforms (drag), spawns,
  flags, and control points (click); move/delete via right-click; middle-drag
  pan and wheel zoom; ESC exit, F5 play-test. Maps save to
  `user://maps/*.json` and are selectable in the menu alongside the built-in
  rotation.
- **Procedural map generation** (#32). Seeded generator produces playable
  layouts for every mode; re-roll from the menu, then **GENERATE + PLAY**
  drops you straight in.
- README refreshed to document the editor + procedural gen flow and the
  full feature set.

## [1.3.0] — 2026-09-12

Retail-quality pass. New modes, modifiers, cosmetics, stats, GIF
recording, plus a full sweep of MP fidelity fixes (weapon-drop desync,
M2 turret sync, bot ammo).

### Added
- **Domination mode** (issue #23). Three control points (A/B/C) on
  each map's ground row. Standing on a point for 4 s captures it for
  your team; each owned point ticks 1 pt/sec into your team's score.
  First to 90 wins. Empty points drain progress back to neutral.
- **Battle Royale mode** (issue #28). FFA with a shrinking ring
  (2200 → 180 px @ 42 px/sec). Outside the zone = 22 dps. Last
  soldier alive wins. Zone radius surfaces in the HUD mode tag so
  players can pace their moves.
- **Game modifiers** (issue #24). Menu sliders for gravity, jet fuel
  regen, weapon damage, and player speed — all 0.5×–2.0× (speed
  0.5×–1.5×). Config-driven via `settings.cfg [mods]`; stock = 1.0×.
  Applied at physics + damage sites.
- **Lo-fi mode** (issue #25). Graphics toggle disables particle
  bursts, gib sprays, ragdoll chunks, and jet flames for low-end
  hardware. Audio cues still fire.
- **Character customization** (issue #26). Menu picker for head
  cosmetic (helm / kap / hair1–4 / bald), chain (none / silver / gold),
  vest, and cigar. Bots roll a random look on spawn so the field
  reads as distinct characters.
- **GIF recording** (issue #27). F9 toggles recording; the recorder
  captures 20 fps to `user://recordings/clip_<time>.gif`, capped at
  300 frames (~15 s). Simplified LZW encoder (re-emits CLEAR to keep
  the code width fixed) — larger files than a full encoder but pure
  GDScript and portable.
- **Local statistics** (issue #29). Stats autoload tracks kills,
  deaths, suicides, shots, hits (K/D + accuracy), wins, losses,
  matches, and per-weapon kill breakdown. Persists to
  `user://stats.cfg`. Menu adds a STATS screen with reset.
- **Improved grenade physics** (issue #30). Bouncier restitution
  (0.55 → 0.72), lower friction (0.4 → 0.18), lighter mass, slightly
  reduced gravity. Grenades now clear platforms and slide down slopes
  rather than dying on first bounce.

### Changed
- **Host-authoritative weapon drops** (fixes #34). Only the host runs
  physics for WeaponPickup RigidBody2Ds; clients freeze locally
  (FREEZE_MODE_KINEMATIC) and receive 10 Hz pos/vel/ang snapshots via
  a new `net_pickup_state` broadcast from Main. Contact detection is
  host-only so both peers agree on who picks up what and when.
- **M2 stationary gun now syncs across MP** (fixes #35). Mount/dismount
  route through Main as authoritative RPCs. Each M2 gets a stable
  `m2_id`. Only the operator's peer reads input; aim streams
  unreliable_ordered at physics rate; fires broadcast reliably so
  bullets appear on all peers.
- **Bots track ammo + reload** (fixes #36). Per-loadout mag size and
  reload timer (AK-74: 30/2 s, LAW: 1/3 s). Firing drains ammo; the
  empty-mag path kicks off a reload. Pickups reset the mag to full.
- **Draw scoreboard explains why** (fixes #37). `_end_round_by_time`
  records a human-readable subtitle for empty-scoreboard, tied, and
  time-up-with-a-leader cases. Rendered as a smaller line under the
  DRAW / WINS banner.
- **Rambo Bow respawn cooldown** (fixes #38). When the carrier dies,
  the bow now waits 4 s before re-spawning at map center — prevents
  the instant re-pickup exploit.

### Deferred (open issues, milestone-scale features)
- In-game level editor (#31) — Soldat 2's crown jewel, its own release.
- Procedural level generation (#32) — large subsystem.
- Ranked matchmaking / dedicated servers (#33) — needs server infra.

## [1.2.0] — 2026-09-12

Retail-polish release. Rounds out Soldat's mode/weapon/movement surface: all
7 main game modes ship, the primary roster is complete, and Soldat's gesture /
chat / taunt loop is playable end to end.

### Added
- **Full Soldat weapon roster (10 primaries + 4 secondaries).** Steyr AUG (4),
  Ruger 77 (6), M79 (7), Barrett M82A1 (8), FN Minimi (9), XM214 Minigun (0)
  join Deagles/MP5/AK-74/Spas-12. Stats derived from `server/configs/weapons.ini`
  (60 ticks/sec → real seconds; damage ≈ `Damage × Speed`; speed ≈ `Soldat Speed × 44`).
- **Secondary slot + Q swap.** Secondaries: USSOCOM, Combat Knife, Chainsaw,
  M72 LAW. Melee (Knife / Chainsaw) sweeps a short forward arc.
- **Barrett / Minigun wind-up.** Both weapons need a short spin-up
  (0.32 s / 0.42 s) before the first shot; releasing LMB resets. Rising-edge SFX
  + shake ramp signal the tell.
- **Crouch (S hold) and prone (X toggle).** Crouch shrinks the collision box
  and slows to 0.6× ground cap; prone flattens further to 0.28×. New gostek
  anims: `kuca` / `kucaidzie` / `kucaidzietyl` / `lezy` / `lezyidzie`.
- **Roll.** Crouch while running fires a short forward burst.
- **All 7 main game modes.** Deathmatch (existing) + Teammatch, Capture the Flag,
  Infiltration, Hold the Flag, Rambomatch, Pointmatch. Realistic / Survival /
  Advance sub-modes wired into the menu chips (Realistic: no jet, no ammo/fuel
  HUD, head-shot 1HK; Survival: no respawns until round ends; Advance: weapon
  unlock ladder starting from the knife).
- **Chat + taunts.** T = global, Y = team, ALT + key = canned taunts from
  `TAUNTS.TXT`.
- **Gesture /commands.** `/victory /smoke /takeoff /kill /brutalkill /mercy` play
  their .poa anims (or gib the player, for the suicide variants).
- **Weapon throw / pickup.** F drops the active weapon as a physics item that
  other soldiers can pick up.
- **Ceasefire spawn protection.** 3 s of invulnerability with a pulsing cyan aura.
- **M2 stationary gun.** Per-map mount points with a clamped-elevation turret.
- **Extra weapons.** Flamethrower, Rambo Bow, Cluster grenade.
- **Bink.** High-Bink weapons punish a victim's aim on hit.
- **Networked hosting.** Host-authoritative teams, flag-state RPC, mode entities
  spawned on both peers so scoring stays in sync.

### Changed
- Primary hotkeys extended to `1..9,0`. LAW moved from primary #5 to the
  secondary slot; Spas-12 is now primary #5. HUD, menu footer, README updated.
- `net_state` / `net_shoot` RPC signatures extended for secondary slot + stance.
- Soldier rescaled to exact Soldat 1:1 (`POA_TO_PIXEL` 2.4→1.0); collision box,
  jetpack, muzzle flash, HP bar, jet flame all rescaled to match.
- Maps enlarged to 4800×2000; all three layouts redesigned; camera limits track.
- Kill feed colors names by their actual team, not "us vs. everyone else".

### Fixed
- Bots gate shots on line-of-sight (no more shooting through terrain).
- Bot respawn shifts horizontally if an enemy is standing on the slot.
- Death HUD shows the real respawn delay, not a hardcoded 2 s.
- Menu version and subtitle labels no longer overlap.
- Chainsaw honors its ammo count and reload.
- Survival respawns are correctly gated on `round_active` (MP + suicide paths).

## [1.1.0] — 2026-09-12

Interim scale/asset pass — see git history `574781d..5cc6e7a`. Highlights:
Soldat 1:1 sprite scale, weapon grip pivots, death screen + team arrow, mouse
crosshair, full 21-weapon roster kickoff, larger maps, RMB jet default.

## [1.0.0] — 2026-09-12

First release. A Godot 4.7 rebuild of Soldat's feel with the original game's
art and sound.

### Added
- Run / bunny-hop / jet boots with fuel, coyote time, and jump buffering
- Weapon system: Deagles, AK-74, MP5, Spas-12, LAW rocket launcher (switch 1–5, reload, per-mag ammo)
- Grenades: arc throw, bounce, area splash
- 3 AI bots with lead aim, circle-strafe, dodge, and grenade use
- Match/score/round system: team score, 5-min timer or first-to-20, winner banner, auto-restart
- ENet multiplayer: host/join menu, map sync, spawn/state RPCs, kill-feed replication
- 3 maps (Ascent / Towers / Pillars), camera follow, parallax background, HUD kill feed
- Main menu + settings (SFX volume, screen shake, fullscreen), persisted to `user://settings.cfg`
- Death ragdoll physics gibs
- **Real Soldat assets** (CC BY 4.0, from `Soldat/base`):
  - Skeletal soldier ("gostek") rendered from `.poa` animation keyframes, animated per game state (stand / run / jump / fall / jet / reload / death)
  - Weapon sprites for all 5 weapons
  - Real `.wav` sound effects
  - `.poa` format reverse-engineered and documented in `references/poa-format.md`
- Release scaffolding: MIT + CC BY 4.0 licensing (`LICENSE.md`, `CREDITS.md`), `.gitattributes`, CI headless-verify workflow

### Fixed (pre-release QA)
- Single-player camera and damage broken by `is_multiplayer_authority()` returning false with no peer
- Rocket double-splash (re-entrancy guard)
- Suicide/team-kill scoring a point for the victim's own team
- Client `net_state` only sent to host (3+ player sync)
- Bunny-hop momentum clamped on landing
- Bot dodge dot-product inverted
- Spawn points embedded in the ground
- Kill lost when the victim disconnected mid-kill
- Jet-loop audio chopped (8-bit vs 16-bit sample math)
- Exported build missing `.poa` animation files (invisible soldier)
- Plus ~40 medium/low defects across combat, AI, networking, and UI (see commit history)

### Known limitations
See `ROADMAP.md` → *Known bugs*. Highlights: LAN-scale per-frame networking,
per-peer grenade/rocket physics divergence, map tile textures not yet integrated.
