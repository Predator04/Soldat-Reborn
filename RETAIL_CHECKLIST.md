# Retail readiness checklist

Status as of v1.20.0. ✅ done · ⚠️ needs you (accounts, legal, real hardware) · ❌ not done yet.

## Game
- ✅ Every mode playable vs bots on all 99 classic maps + 3 built-ins; release gate (static checks, boots, MP smokes, every mode, every map) passes.
- ✅ First-run flow: name prompt → optional Training (guided first match) → controls card for the first matches (H any time).
- ✅ Settings: audio (SFX / music / mute), video (fullscreen, VSync, FPS cap, Lo-fi, FPS overlay, damage numbers), full rebinding (keyboard / mouse / gamepad), touch layout editor, game options, mods, cosmetics.
- ✅ Pause menu; pauses by itself on alt-tab / app switch (toggle).
- ✅ Gamepad and touch support; Android back button everywhere.
- ✅ Low-FPS guard switches to Lo-fi once on weak devices.
- ✅ Stats screen, scoreboard, kill feed, spectator, round-end MVP.
- ✅ In-game Credits & licenses screen.
- ❌ Localization (English only).
- ❌ Accessibility extras (colour-blind team colours, text size) — teams are blue/red with name labels.

## Multiplayer
- ✅ Listen host and dedicated server, bots on both, 10 modes, two-client soak tests with zero errors.
- ✅ LAN discovery; optional master-server listing (Go server in `../server/master-server`); live ping + player counts (UDP query on game port + 1), Quick Join, rejoin after a drop.
- ✅ LAN needs no setup; join codes; UPnP opens the router port automatically on most home routers; Windows Firewall fix button.
- ⚠️ **Internet play without UPnP** (router refuses, CGNAT, mobile hotspots) still needs a manual port forward or a VPN (Tailscale / ZeroTier). A relay server would remove this entirely. There is no NAT punch-through or relay service. For a retail online game you'd want a relay / hosted dedicated servers (e.g. run the dedicated server on a VPS) or Steam networking.
- ⚠️ Not tested over real internet latency / packet loss — only on one machine and LAN-style loopback.

## Legal — check before selling
- ⚠️ **Name.** "Soldat" is the original game's name. Selling as "Soldat Reborn" may need permission from the Soldat authors or a different name. The in-game text already says it's an unofficial fan rebuild.
- ⚠️ **Assets.** Sounds, sprites, animations and maps come from the Soldat base content (CC BY 4.0, commercial use allowed with attribution — credited in-game and in CREDITS.md). Research notes that some original 1.x art isn't cleanly licensed; confirm every file came from the CC BY `base` repo.
- ⚠️ **Music.** `assets/music/*.ogg` (bloody, gore, necro) — confirm their source and license; they're not covered by the credits text yet. Replace them if unsure.
- ⚠️ Privacy policy (required by Google Play; the game stores nothing online and talks only to game hosts / an optional master server).

## Store packaging
- ✅ Windows .exe (icon + version info) and signed Android .apk, built by `tools/build_release.sh`; GitHub releases carry both.
- ⚠️ **Google Play needs an .aab** built with the real Android SDK (Godot gradle build, target SDK 34+). This build machine can't reach Google's SDK downloads; install Android Studio on your PC, set the SDK path in Godot → Editor Settings → Export → Android, turn on "Use Gradle Build" and export AAB. Play also needs a developer account, content rating (violence / blood), data-safety form, screenshots and a feature graphic.
- ✅ Store copy, trailer shot list and placeholder screenshots in `store/`.
- ⚠️ **Steam**: Steamworks account and app fee, store page art (capsules; reshoot screenshots on a real GPU; cut the trailer from the shot list). Steam overlay / achievements are not integrated.
- ⚠️ Windows code signing (otherwise SmartScreen warns on first run).

## QA still needed from people
- ⚠️ Play on real phones (small and large screens, low-end GPU) and real PCs (different GPUs, monitors).
- ⚠️ A few play sessions with friends online (LAN + over the internet with port forwarding).
