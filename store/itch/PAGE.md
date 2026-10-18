# itch.io page for Tracerfall

Everything to paste into itch.io when you create the project
(itch.io > Dashboard > Create new project). Files are in this folder.

## Settings
- **Title:** Tracerfall
- **Project URL:** soldat-reborn (itch.io/…/soldat-reborn)
- **Short description / tagline:** Fast 2D multiplayer shooter with jetpacks, CTF and online play. Free.
- **Classification:** Games · **Kind of project:** Downloadable
- **Release status:** In development (switch to Released when you like)
- **Pricing:** No payments (or "$0 or donate")
- **Genre:** Action · **Tags:** 2D, Multiplayer, Shooter, Online, Capture the Flag, Jetpack, Retro, Bots, Local Multiplayer, Godot
- **Platforms:** Windows, Android
- **Cover image:** cover_630x500.png
- **Screenshots:** screenshots/01…08 (upload in order)
- **Gameplay GIF:** gameplay.gif (itch shows it on the page; also good for social posts)
- **Community:** turn on Comments (players report bugs there)

## Uploads
- `SoldatReborn.exe` — mark as **Windows**. Get it from the latest GitHub release:
  https://github.com/Predator04/Soldat-Reborn/releases/latest
- `SoldatReborn.apk` — mark as **Android**.
- Tip: install itch's **butler** later to push new versions straight from publish.bat.

## Description (paste into the page body)

**Tracerfall** is a fast, free 2D multiplayer shooter: jetpacks, bunny hops,
ragdoll gibs and 16 weapons, rebuilt from the cult classic *Soldat* for today's
PCs and phones.

**Jump in with one click.** QUICK PLAY drops you into the best online game, or a
bot match if nobody's on. The official server is up 24/7 and fills empty slots
with bots, so there's always a fight.

**Features**
- 10 modes: Capture the Flag, Deathmatch, Teammatch, Infiltration, Hold the Flag, Rambomatch, Pointmatch, Domination, Battle Royale, Gun Game
- 102 maps, including the classic Soldat maps, plus a built-in map editor and a **Map Library** to share and download player-made maps
- Buggies and tanks, grenades, the Rambo Bow, medikits and power-ups
- Smart bots for offline play (and to keep servers full)
- **Leaderboard** and career ranks, achievements, and unlockable looks: helmet and vest paint, trousers, weapon skins, tracer and jetpack colors
- **Replays** of every match: watch from anyone's view at any speed
- **Kill cam**, lag compensation, end-of-round map voting, clan tags and a friends list with one-click join
- Host tools: the classic chat commands (/addbot, /kick, /map, /restart…), per-weapon bans for custom nights ("pistol only", "no sniper"), and a live admin panel
- Vehicles that reset themselves when abandoned, so a buggy never blocks the match
- Host your own game (no router setup needed with the relay) or play LAN
- Mouse + keyboard, gamepad, and touch controls on Android
- English, Español, Português, Deutsch, Français

**Controls (PC):** WASD move · W jump · right mouse jetpack · left mouse shoot ·
1-0 weapons · R reload · E grenade · Tab scores · H help. Everything is rebindable.

**System requirements:** Windows 10/11 64-bit with an OpenGL 3.3 graphics card (almost any PC from the last 10 years).
Android 7 or newer.

## Publish checklist (10 minutes, one time)

1. itch.io → Dashboard → **Create new project**; paste the Settings above.
2. Upload cover + 8 screenshots + gameplay.gif.
3. Download `SoldatReborn.exe` and `SoldatReborn.apk` from the latest GitHub
   release (https://github.com/Predator04/Soldat-Reborn/releases/latest) and
   upload both with the platform flags above.
4. Paste the Description, then the Credits block below it.
5. Save → *View page* → check the GIF plays and both downloads list correctly.
6. Optional later: install `butler` and push updates with
   `butler push build/SoldatReborn.exe user/soldat-reborn:windows`.

Every future release: re-download the two files from the newest GitHub
release and replace them (or use butler).

## Credits (keep this — required by the asset license)
Sounds, weapon and body graphics, effects, interface art and animations are from
the Soldat base distribution by Michał "MM" Marcinkowski and the Soldat
contributors (https://github.com/Soldat/base), licensed CC BY 4.0. Soldat
Reborn's code is original; see CREDITS.md in the game folder.
