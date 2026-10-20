# Discord Rich Presence setup (#223)

The game already has it (scripts/discord/). It stays switched off until the
Discord application id is pasted into the game. About 5 minutes.

What players' friends see on their Discord profile:

- **Playing Tracerfall** · "Playing Capture the Flag on Ascent" · "Blue 3 – 2 Red"
  (or "Score 12", "Rung 4 / 16", "Bots: 7") · elapsed time · "(3 of 9)" in online games
- "In the Maker editor" / "Play-testing a level" · "Browsing levels" · "In menus"
  · "In training" · "Watching a replay"
- the Tracerfall picture, a small mode badge (CTF, DM, ...) during matches,
  and a **Get Tracerfall** button linking the latest GitHub release.

Windows and Linux desktop only. Phones, dedicated servers and headless runs never
start it. Players can turn it off: Settings → Game → **Discord status**.

## 1. Create the Discord application

1. Open https://discord.com/developers/applications and log in.
2. **New Application** → name it **Tracerfall** (this name is the "Playing ..." line) → Create.
3. General Information: upload `icon.png` (repo root) as the App Icon. Copy the
   **Application ID** (a long number; it isn't a secret).

## 2. Upload the art

Rich Presence → **Art Assets** → **Add Image(s)**, upload these from `docs/discord/`.
The key is the file name without `.png`; keep it exactly as below:

| File | Key | Used for |
|---|---|---|
| `tracerfall.png` | `tracerfall` | large picture (always) |
| `mode_dm.png` … `mode_gg.png` | `mode_dm`, `mode_tdm`, `mode_ctf`, `mode_inf`, `mode_htf`, `mode_rm`, `mode_pm`, `mode_dom`, `mode_br`, `mode_gg` | small badge per mode |

Save. New art can take a few minutes to show up in Discord. A missing key just
shows no picture; nothing breaks. (`python3 tools/itch/make_art.py` redraws
these PNGs from the repo.)

## 3. Paste the id

In `scripts/game_info.gd` set

```gdscript
const DISCORD_APP_ID := "123456789012345678"   # your Application ID
```

commit, and release as usual. That's the only code change.

To try it before releasing: start Discord (the desktop app, not the browser),
then run the game with the id on the command line, e.g.
`SoldatReborn.exe -- --discord-app-id=123456789012345678` (or set the same
"Main Run Args" in the Godot editor). Within a few seconds your Discord profile
shows "In menus". Discord → User Settings → Activity Privacy → "Share your
detected activities" must be on.

## If nothing shows up

- The game's log says what happened: `%APPDATA%\Godot\app_userdata\Soldat Reborn\logs\godot.log`
  (Linux: `~/.local/share/godot/app_userdata/Soldat Reborn/logs/`). Look for
  `Discord: connected (\\?\pipe\discord-ipc-0)` or `Discord: Discord refused: Invalid Client ID`
  (wrong id pasted).
- Settings → Game → Discord status must be ticked.
- Linux with Flatpak / Snap Discord works (the game also looks in
  `$XDG_RUNTIME_DIR/app/com.discordapp.Discord` and `snap.discord`).

## How it works (for maintainers)

Pure GDScript over Discord's local IPC, no GDExtension or native library: on
Windows the named pipe `\\?\pipe\discord-ipc-N` opened with `FileAccess`
(READ_WRITE; Godot's path clean-up mangles the usual `\\.\pipe\` spelling), on
Linux the Unix socket `$XDG_RUNTIME_DIR/discord-ipc-N` with `StreamPeerUDS`.
All I/O runs on one low-priority worker thread; the main thread builds the
status once a second and hands it over only when it changed, at most one update
per 4.1 s (Discord's limit is 5 per 20 s). See CLAUDE.md "Discord Rich
Presence (#223)" and gate F `discord` (`tools/discord_test.gd`).
