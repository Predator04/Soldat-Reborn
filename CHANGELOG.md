# Changelog

All notable changes to Soldat Reborn.

## [Unreleased]

### Added
- **Full Soldat weapon roster (10 primaries + 4 secondaries).** Steyr AUG (4),
  Ruger 77 (6), M79 (7), Barrett M82A1 (8), FN Minimi (9), XM214 Minigun (0)
  join Deagles/MP5/AK-74/Spas-12. Stats derived from `server/configs/weapons.ini`
  (60 ticks/sec → real seconds; damage ≈ `Damage × Speed`; speed ≈ `Soldat Speed × 44`).
- **Secondary weapon slot + Q swap.** Every soldier now carries one primary and one
  secondary. Secondaries: USSOCOM (semi pistol), Combat Knife (melee arc, ~55 dmg),
  Chainsaw (continuous melee, ~30 dps), M72 LAW (moved out of the primary slot).
  Q toggles the active slot; the HUD and fire logic follow.
- **Barrett / Minigun wind-up.** Both weapons need a short spin-up (0.32s / 0.42s)
  before the first shot fires while LMB is held. Releasing LMB resets the timer.
- **Melee handling.** Knife/Chainsaw scan a short forward arc (~70°) and damage
  any enemy soldier in range; per-peer authority guard mirrors bullet/rocket damage.
- **Crouch (S hold) and prone (X toggle).** Crouch shrinks the collision box
  (20×42 → 22×28) and slows the ground cap to 0.6×. Prone flattens it (36×14)
  and drops to 0.28×. W/Space or another X press stands you up from prone.
  New gostek anims: `kuca` / `kucaidzie` / `kucaidzietyl` / `lezy` / `lezyidzie`.

### Changed
- Primary hotkeys extended to `1..9,0` (was `1..5`). LAW moved from primary
  slot 5 to the secondary slot; Spas-12 is now the primary #5. HUD, menu footer,
  and README controls table all reflect the new mapping.
- `net_state` / `net_shoot` RPC signatures extended to carry the secondary
  slot + stance flags across peers.
- Soldier rescaled to exact Soldat 1:1 (POA_TO_PIXEL 2.4→1.0). The .poa loader
  already produces joint positions in Soldat's native pixel space; the extra
  2.4x multiplier was making the soldier 1.46x too big. All procedural draw
  constants (jetpack, muzzle flash, HP bar, jet flame) and collision box
  rescaled to match.
- Maps enlarged to 4800x2000 to match original Soldat scale. All 3 layouts
  redesigned with more platforms and terrain spanning the full width and
  height; camera limits updated to match.

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
