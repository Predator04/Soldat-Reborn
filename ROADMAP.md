# Soldat Reborn — Roadmap

> **Current status: v1.34.0** (see CHANGELOG.md for the full history).
> Feature-complete against the original's core loop and well past it: 102 maps
> (3 procedural remakes + 99 ported classics), 16 weapons, 10 game modes, bots
> (count + skill 1-5, ladder-aware), vehicles, weather, replays with playback,
> kill cam rewind, spectator, votes (map + kick), friends list, skill
> matchmaking, customization, achievements, shared map library, master server
> with relay hosting (no port forwarding needed), signed self-updater, host
> weapon bans and the classic host chat command set.

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

## Next up

### Infrastructure (blocking nothing, improving everything)
- [ ] TLS for the master server (#252) — needs a domain; everything else is
      scripted (see the issue). Plaintext HTTP is the last trust gap.
- [ ] itch.io page (#224) — mirror the download + screenshots.
- [ ] Discord Rich Presence (#223) — needs a Discord GDExtension.

### Structure (pay down the god-files — the M2 bug shipped twice because of this)
- [ ] Split menu.gd (~2.2k lines): server browser, update UI, name prompt
- [ ] Split hud.gd (~1.5k lines): vote panel, next-map panel, feeds
- [ ] Split main.gd (~5.3k lines) per system: modes, net sync, votes, vehicles
- [ ] draw_soldier's 24 positional parameters → a state object
- [ ] Player::_physics_process (~500 lines) → per-mode state handlers

### Filed and ready (see issues)
- #261 in-game news line (MOTD) — talk to the players you already have
- #262 movement tutorial course — teach v1.34's movement tech
- #263 gameplay trailer rendered from the replay system (feeds #224's itch page)
- #264 weekly featured mode/map on the official server + #261 tie-in
- #224 itch.io publish (kit ready — needs the owner's account)
- #223 Discord Rich Presence (needs an app registration)

### Parked, with unpark triggers
- Voice chat — the perennial community ask — unpark when there are enough
  concurrent players for it to matter
- Superman / cannonball anims — unpark when there's an art direction pass
- Server-authoritative ranked — unpark when real cheating appears (the
  current caps + streak freezes hold the line until then)
- Workshop-style preset/mod sharing on the map library
