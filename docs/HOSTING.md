# Hosting a Tracerfall server

The dedicated server is a small separate download that runs without the game:
no window, no graphics, no sound. It needs no GPU and runs fine on a cheap VPS.

| | Windows | Linux (x86-64) |
|---|---|---|
| Download (GitHub release) | `TracerfallServer-windows.zip` | `TracerfallServer-linux.tar.gz` |
| Start | double-click `start-server.bat` | `./start-server.sh` |
| Run at boot | `install-service.bat` (as administrator) | `sudo ./install-service.sh` |
| Update | `update-server.bat` | `./update-server.sh` |

Releases: https://github.com/Predator04/Tracerfall/releases/latest

A match with 8 bots uses about a quarter of one CPU core and about 220 MB of
RAM (numbers at the end). With nobody connected the server pauses the match
and idles at almost no CPU.

## 1. Unpack and start

**Windows:** unzip anywhere (e.g. `C:\TracerfallServer`) and double-click
`start-server.bat`. A console window shows the log. Close it to stop the server.

**Linux:**

```sh
tar xzf TracerfallServer-linux.tar.gz
cd TracerfallServer
./start-server.sh
```

The first start copies `server.cfg.example` to `server.cfg`. Edit `server.cfg`
(name, rotation, rules, admin password …) and start again. Every setting is
explained in the file itself. A line the server doesn't understand is printed
in the log (`SERVERCFG line 12: ...`) and skipped; the server always starts.

## 2. Open the ports

Players connect over **UDP**. Open your port **and the next one** (server info
queries), by default **7777 and 7778**:

- Windows Firewall: the first start usually asks; otherwise allow
  `TracerfallServer.console.exe` / `TracerfallServer.exe`, or add inbound UDP rules
  for 7777-7778.
- Linux: e.g. `sudo ufw allow 7777:7778/udp`.
- Home router: forward UDP 7777-7778 to the server PC (or let the game's
  UPnP do it for a listen server; the dedicated server doesn't use UPnP).
- VPS / cloud: allow UDP 7777-7778 in the provider's firewall / security group.

With `register = true` in `server.cfg` the server appears in **Find Games**.
Players can always join by address with **Join** (IP and port).

## 3. Admin in the game

Set `admin_password` in `server.cfg`, join the server and type in the chat line
(`/` key):

| Command | |
|---|---|
| `/login <password>` | become admin for this visit |
| `/myid` | shows your player id; put it in `admins = ...` to be admin without a password |
| `/map <name>` `/gamemode <mode>` `/restart` | change map / mode, restart the match |
| `/next` | jump to the next map of the rotation |
| `/addbot [skill] [name]` `/bots <n>` `/kick <name>` | bots and players |
| `/say <text>` `/ff` `/votecancel` | announce, friendly fire on/off, stop a vote |
| `/reloadcfg` | read `server.cfg` again (see below) |

`/reloadcfg` applies most settings at once (name, MOTD, admins, bots, score
limits, respawn time, votes, weapon bans, rotation …). Map-level settings
(sub-modes, time limit, modifiers, vehicles, crates and kits) take effect on the
next map; `port` and `register` need a restart. The reply tells you which.

## 4. Run it as a service

**Windows** (no extra software): right-click `install-service.bat` > *Run as
administrator*. It creates the scheduled task "Tracerfall Server" that starts
with Windows (before anyone logs in), restarts the server if it stops, and
writes the log to `logs\server.log`. Remove it with `uninstall-service.bat`.

**Linux** (systemd):

```sh
sudo ./install-service.sh                 # runs as your user, starts at boot
sudo ./install-service.sh --auto-update   # also updates before every start
journalctl -u tracerfall-server -f        # the log
sudo systemctl restart tracerfall-server
sudo ./install-service.sh --uninstall
```

`tracerfall-server.service` is the unit file it installs, if you prefer to set
it up yourself.

## 5. Updating

`update-server.sh` / `update-server.bat` (needs Python 3) asks GitHub for the
latest release and only installs it if it is **newer** than `VERSION.txt`.
The download must carry the game's release signature (checked by your
installed server program, the same key the game's own updater uses); it is
refused otherwise. Your `server.cfg` and `logs` are never touched, and the
replaced files are kept in `_update/previous/`. Stop the server first (or
restart it afterwards). `--check` only tells you whether there is an update.

Players need the same game version as the server, so update when the game
updates.

## Command line

`TracerfallServer` (`.console.exe` on Windows) accepts the same flags as the
game's `--dedicated` mode, after `--`; flags win over `server.cfg`:

```
TracerfallServer.x86_64 -- --config my.cfg --port 7800 --map Nuubia --mode ctf
    --bans=Minigun,LAW --fill=6 --bots=4 --name="My server" --register=<master url>
    --no-idle --version
```

Where the server keeps its own files (logs, replays, settings): it prints the
folder at start (`Dedicated server data folder: ...`) — `~/.local/share/TracerfallServer`
on Linux, `%APPDATA%\TracerfallServer` on Windows (for the Windows service:
`C:\Windows\System32\config\systemprofile\AppData\Roaming\TracerfallServer`).
It never shares the game's settings, even on the same PC.

## Without the server download

The full game can host too: Host in the menu (listen server), or headless
`SoldatReborn.exe --headless -- --dedicated --config server.cfg`. The server
download is just that, without the 100+ MB of graphics and music.

## Numbers

Measured on a 2-core Linux x86-64 VM: Ascent CTF, 8 bots, nobody connected,
idle pause off, 90 s after the match loaded.

| | server download | full game, headless |
|---|---|---|
| Download | 47 MB zip (Windows) / 37 MB tar.gz (Linux) | 277 MB `SoldatReborn.exe` |
| Game data | 36 MB `.pck` (no textures / music) | 168 MB `.pck` |
| CPU | ~22 % of one core | ~21 % of one core |
| RAM (resident) | ~217 MB | ~225 MB |

Running headless already skips the GPU work, so CPU and RAM are about the
same; the server download is mainly smaller and needs nothing of the game.
Each connected player adds a little CPU (the server simulates and checks every
soldier and relays their state).
