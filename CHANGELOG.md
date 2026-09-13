# Changelog

All notable changes to Soldat Reborn.

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
