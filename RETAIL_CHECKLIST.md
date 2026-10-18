# Retail readiness checklist

Re-audited 2026-10-17 against v1.34 + the unreleased trust checks (see CHANGELOG).
✅ done · ⚠️ needs you (accounts, legal, real hardware, real players) · ❌ not done yet.

## Game
- ✅ Every mode playable vs bots on all 99 classic maps + 3 built-ins; the release gate (static checks, boots, nav, MP smokes, every mode, every map) passes — last full quick gate 2026-10-17: 87/87.
- ✅ First-run flow: name prompt → optional Training (guided first match) → controls card (H any time).
- ✅ Settings: audio, video + Graphics quality (Low / Medium / High), full rebinding (keyboard / mouse / gamepad), touch layout editor, game options, mods, cosmetics.
- ✅ Pause menu (auto-pauses on alt-tab in single player; online it only locks your input).
- ✅ Gamepad and touch support; Android back button everywhere.
- ✅ Low-FPS guard drops one quality step once on weak devices.
- ✅ Stats, scoreboard, kill feed, spectator, MVP, replays, kill cam, achievements, leaderboard, friends.
- ✅ In-game Credits & licenses screen — now including the music.
- ✅ Localization: English, German, Spanish, French, Brazilian Portuguese (`assets/i18n/ui.csv`). Check new strings get translated before each release.
- ⚠️ Accessibility: colour-blind team option exists (red → orange). Still missing: UI text size / scale, subtitles-style captions for radio calls.

## Multiplayer
- ✅ Listen host, dedicated server, bots on both, 10 modes; two-client soak tests with zero errors.
- ✅ Master server (Oracle, HTTPS via Caddy) with server list, Quick Play, skill matchmaking, leaderboards, shared maps — and a **relay**, so hosting needs no port forwarding or UPnP.
- ✅ Official always-on dedicated server, auto-updating from releases; uptime watchdog + daily backups.
- ✅ Host trust checks: godmode, teleport / speed hacks, impossible health and fake kill credit are caught host-side (forced death → kick). Subtle cheats (partial damage reduction, infinite fuel, aim help) need host-decided hits — open issue, parked until real-internet playtests.
- ⚠️ **Not tested over real internet latency / packet loss with real people.** Everything above is verified on loopback. Play several sessions with friends over the relay (PC + phones) before any paid launch, and file what feels off.

## Legal — check before selling
- ⚠️ **Name.** "Soldat" is the original game's name. Decision: rename to **Tracerfall** (no existing game found by web search on 2026-10-17). Still do a real check before spending money on it: USPTO trademark search, Steam + itch search, domain + itch handle.
- ⚠️ **Assets.** Sounds, sprites, animations and maps come from the Soldat base content (CC BY 4.0, commercial use allowed with attribution — credited in-game and in CREDITS.md). The upstream credits list is self-described as very incomplete; confirm every shipped file exists in `github.com/Soldat/base`.
- ⚠️ **Music.** Traced 2026-10-17: the three tracks are renders of the tracker modules in Soldat base (`shared/sfx/modules/`, CC BY 4.0) — "Gore" and "Necromancide" by Marshall Anderson, "Bloody Soil" author unrecorded. Credited now. Residual risk: the Gore module thanks "anyone whose samples I used", so its instrument samples have no recorded origin. For a paid release, replacing the three tracks is the clean option.
- ❌ Privacy policy (Google Play requires one). The game stores settings, replays and stats locally; online it sends your name, stats and match results to the master server. One short page covers it.

## Store packaging
- ✅ Windows .exe (icon + version info, signed self-updater) and signed Android .apk, built by `tools/build_release.sh`; GitHub releases carry both + the server pack.
- ⚠️ **Google Play needs an .aab** — `export_presets.cfg` still has `use_gradle_build=false` (the build box has no Android SDK). Install Android Studio on your PC, set the SDK path in Godot → Editor Settings → Export → Android, turn on "Use Gradle Build", target SDK 34+, export AAB. Play also needs a developer account, content rating (violence / blood), data-safety form, screenshots, feature graphic.
- ✅ Store copy, trailer shot list, screenshots and an itch.io kit in `store/` (itch publish is issue #224 — needs your account).
- ⚠️ **Steam**: Steamworks account + app fee, capsule art, real-GPU screenshots, trailer. Steam overlay / achievements / networking not integrated.
- ⚠️ Windows code signing (otherwise SmartScreen warns on first run).

## QA still needed from people
- ⚠️ Real phones (small + large screens, low-end GPU) and real PCs (different GPUs, monitors, 60 / 144 Hz).
- ⚠️ Online sessions with friends over the relay, including someone on a phone hotspot.
