# Tracerfall (formerly Soldat Reborn) — Roadmap

> **Current status: v1.35.0 — Tracerfall** (see CHANGELOG.md for the full history).
> Feature-complete against the original's core loop and well past it: 102 maps
> (3 procedural remakes + 99 ported classics), 16 weapons, 10 game modes, bots
> (count + skill 1-5, ladder-aware), vehicles, weather, replays with playback,
> kill cam rewind, spectator, votes (map + kick), friends list, skill
> matchmaking, customization, achievements, shared map library, master server
> with relay hosting (no port forwarding needed), signed self-updater, host
> weapon bans and the classic host chat command set — and since 1.35 a cinematic
> graphics overhaul, new menus/HUD, smoother maps, a helicopter and server-side cheat checks.

**Project:** this folder (`game/`) — Godot 4.7, GL Compatibility renderer.
**Conventions:** CLAUDE.md. **History:** CHANGELOG.md. **Status of everything:**
GitHub issues (every bug/feature is filed there first).

## Shipped milestones (one line each — details in CHANGELOG)

- v1.16 — core loop, ported assets, headless-verified exports
- v1.25 — master server + relay hosting; official dedicated server
- v1.29 — customization + achievements; leaderboards end to end
- v1.30 — replays (record + playback)
- v1.31 — graphics upgrade (lights, post FX, quality presets); kill cam
- v1.32 — skill matchmaking; full-project security/stability review pass
  (crash fixes, signed updates, server hardening, perf)
- v1.33 — weapon bans + host chat commands (the community's classic asks); HTTPS master (TLS via Caddy)
- v1.34 — movement tech (tap/hold jump, prone-cancel) + auto team balance; uptime watchdog + on-server backups
- v1.35 — **Tracerfall**: rename; graphics overhaul A/B/C (cinematic look, pooled gore/FX, new menus + HUD); vehicle art + helicopter; rounded maps; movement course; news line + weekly featured server; host trust checks; code split of the god-files

## Next up

Everything is tracked in [GitHub issues](https://github.com/Predator04/Soldat-Reborn/issues); this list is the order we're taking them in.

### Ship 1.35
- Build + publish the release from the owner's PC (signing keys live there): `release-1.35.bat` → Windows exe + signed update, Android apk, server pack; the in-game updater and the official server pick it up.
- Real-hardware check: FPS overlay on, a full CTF match with 16 bots + helicopter on Industrial / Abel (the 2-core sandbox can't measure GPU frame rate).
- Playtest online with friends (PC + phones) over the relay.

### Launch
- [#263](https://github.com/Predator04/Soldat-Reborn/issues/263) Gameplay trailer rendered from the replay system
- [#224](https://github.com/Predator04/Soldat-Reborn/issues/224) itch.io page (kit in `store/itch`, screenshots refreshed for 1.35; needs the owner's account)
- [#223](https://github.com/Predator04/Soldat-Reborn/issues/223) Discord Rich Presence

### Parked, with unpark triggers
- Voice chat — the perennial community ask — unpark when there are enough
  concurrent players for it to matter
- Superman / cannonball anims — unpark when there's an art direction pass
- Host-decided hits for humans ([#266](https://github.com/Predator04/Soldat-Reborn/issues/266)): unpark after real-internet playtests or when
  real cheating shows up (the host trust checks + ranked caps hold the line until then)
- Workshop-style preset/mod sharing on the map library
