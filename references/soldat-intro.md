# Soldat — Introduction reference

Source: https://wiki.soldat.pl/index.php/Introduction (CC-BY 3.0)

## What Soldat is
2D side-view multiplayer shooter for Windows. Influenced by Liero, Worms, Quake,
Counter-Strike. Fast-paced, heavy on blood/gibs. Free to play; optional paid
registration unlocks cosmetics (colored jet flames, custom interfaces).

- Developer: Michał Marcinkowski (MM), started Nov 2001, at Transhuman Design.
- Language: Delphi (JEDI libraries). First public beta v0.9.4b on 09.05.2002.

## Requirements (minimum)
- OS Windows XP, 333 MHz CPU, 32 MB RAM, OpenGL 2.1+, broadband, 250 MB storage.

## Game modes (7 main)
1. Deathmatch
2. Pointmatch
3. Teammatch
4. Rambomatch
5. Capture the Flag (CTF)
6. Infiltration
7. Hold the Flag

### Sub modes (3)
- Realistic mode
- Survival mode
- Advance mode

### Community/custom modes
Climb, Dodgeball (DB), Domination (DOM), Hide and Seek, Knife Only (KO),
OneShots (OS), Pirates vs Ninjas, Realistic Soldat/CS (RS/CS), Trench Wars (TW),
Tactical Trench Wars (TTW), Zombie.

## Weapons
Full per-weapon stats are on the separate wiki page **Weapons**
(https://wiki.soldat.pl/index.php/Weapons) and its per-weapon subpages. 21 weapons
in 3 groups:

### Primary (keys 1–9, 0)
1 Desert Eagles · 2 HK MP5 · 3 AK-74 · 4 Steyr AUG · 5 Spas-12 · 6 Ruger 77 ·
7 M79 · 8 Barrett M82A1 · 9 FN Minimi · 0 XM214 Minigun

### Secondary (CTRL+1..4)
USSOCOM · Combat Knife · Chainsaw · M72 LAW

### Additional
Frag Grenade · Cluster Grenade · Flamethrower · Rambo Bow · Flamed Arrows ·
Stationary Gun (M2 MG) · Punch

### Weapon mechanics notes
- Carry two weapons (Primary + Secondary, or Primary + Primary). You can throw a
  weapon and pick up another.
- Default secondary is set from the Player menu.
- Rapid select with 1–9/0 (primary) or CTRL+1/2/3/4 (secondary) while waiting to respawn.

## Notes for the rebuild
- Our Soldat Reborn currently ships Deathmatch-style play only. The other modes
  (CTF/Infiltration/Hold the Flag/Rambomatch/Pointmatch/Teammatch) are future work.
- We implement 5 of the primaries (Deagles, MP5, AK-74, Spas-12) + LAW (as primary #5
  for now; it's a secondary in real Soldat). Missing: Steyr, Ruger, M79, Barrett,
  Minimi, Minigun + the full secondary set + grenade variants + stationary gun.
- Registration cosmetics (colored jet flames, custom UI) map to our jet-flame
  color and interface theming — future polish.

