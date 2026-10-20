# Tracerfall on itch.io (#224)

Everything for the itch.io page: what to type into each field, the page text,
the art, and the one-command uploads with butler. Steps 1–4 happen once on
itch.io; after that every release goes up on its own when `publish.bat` runs.

Files in this folder:

| File | What it is |
|---|---|
| `description.html` | The page body. Paste it with the description editor's HTML button (`</>`). |
| `release-notes-template.html` | Devlog template. `python tools/itch/push.py --notes` fills it from CHANGELOG.md. |
| `cover-placeholder-630x500.png` | Stand-in cover until the trailer art lands (see Media). |

Scripts: `tools/itch/push.py` (butler uploads), `tools/itch/itch.json` (where
they go), `tools/itch/make_art.py` (redraws the placeholder cover and the
Discord art from the repo).

## 1. Create the project (about 10 minutes)

itch.io → avatar menu → **Upload new project**, then fill in:

| Field | Value |
|---|---|
| Title | `Tracerfall` |
| Project URL | `tracerfall` (gives `https://<you>.itch.io/tracerfall`) |
| Short description or tagline | `Fast 2D jetpack shooter in the spirit of Soldat: 10 modes, bots, a level builder and online play. Free.` |
| Classification | Games |
| Kind of project | Downloadable |
| Release status | Released (or In development) |
| Pricing | No payments, or $0 or donate |
| Uploads | Leave empty: butler fills them in step 3. To upload by hand instead, take `SoldatReborn.exe` (tick **Windows**) and `SoldatReborn.apk` (tick **Android**) from the latest GitHub release. |
| Description | Paste `description.html` (HTML button). |
| Genre | Shooter |
| Tags (itch allows 10) | `Multiplayer`, `2D`, `Jetpack`, `Online`, `Bots`, `Level Editor`, `Physics`, `Open Source`, `Capture the Flag`, `Godot` (spares: `Action`, `PvP`, `Retro`, `Local Multiplayer`) |
| App store links | Leave empty (the APK is on the page). |
| Custom noun | Leave empty. |
| Community | **Comments** (players report bugs there; turn on "Show comments on the game page"). |
| Visibility & access | Draft while you set it up, then **Public**. |

itch also asks whether the project uses AI-generated content. Answer that one
yourself: the art and sound are Soldat's (CC BY 4.0) and the HD art is drawn by
the generator scripts in `tools/`, but you know best how the code was written.

## 2. Media

- **Cover image (630×500):** `docs/media/cover-630x500.png` once the trailer branch
  (`trailer-263`) is merged. Until then, upload `docs/itch/cover-placeholder-630x500.png`.
- **Screenshots (upload up to 5–8, in this order):** the trailer stills
  `docs/screenshots/trailer-*.jpg` when they exist. Until then:
  `docs/screenshots/ctf-vortex.jpg`, `helicopter-rockets.jpg`, `maker-mode-1.jpg`,
  `levels-browser.jpg`, `teammatch-scorpion.jpg`, `domination-jungle.jpg`,
  `soldiers-closeup.jpg`, `menu.jpg`. (Skip the `*-before-after` comparisons;
  they're for the changelog.)
- **Gameplay video or trailer:** paste the YouTube link of the #263 trailer when it's up.
- `store/itch/gameplay.gif` still works as an extra image in the description.

## 3. Theme (Edit theme on the page)

Match the game's menus (`scripts/ui_theme.gd`):

| Theme field | Colour |
|---|---|
| Background | `#07090D` |
| Inner column (BG 2) | `#10151D` |
| Text | `#EDF2F7` |
| Link | `#4CE0FF` |
| Button | `#FF9429` (button text `#120D08`) |
| Border / dividers | `#1C232D` |

Fonts: header **Barlow Condensed** (or Oswald if it isn't in the list), body
**Barlow** (or Lato). Layout: wide column, banner off (or a 960 px wide crop of a
trailer still), screenshots in the right sidebar.

**Embed widget** (project → Distribute → Embed game): background `#07090D`,
foreground `#EDF2F7`, link `#FF9429`, border `#1C232D`, width 552.

## 4. butler: one command per release

1. Install butler: https://itch.io/docs/butler/installing.html (unzip it somewhere
   and add that folder to PATH, or set the `BUTLER` environment variable to the
   full path of `butler.exe`). If the itch desktop app is installed, its copy is
   found automatically.
2. Log in once: run `butler login` (opens the browser; the key is stored in your
   user profile, not the repo). On a build machine, set `BUTLER_API_KEY` instead
   (key from https://itch.io/user/settings/api-keys). Never commit a key.
3. Edit `tools/itch/itch.json`: set `"target"` to `"<your itch username>/tracerfall"`
   and commit it. Empty target = uploads off.
4. First push (after `tools/build_release.sh` built the files):
   ```
   python tools/itch/push.py
   ```
   It runs `butler push build/SoldatReborn.exe <you>/tracerfall:windows` and
   `... SoldatReborn.apk <you>/tracerfall:android`, both with
   `--userversion <version from project.godot>` and `--if-changed`.
   `--dry-run` prints the commands without running them.
5. Back on the itch edit page, check the two uploads are tagged **Windows** and
   **Android** (itch tags them from the channel names) and give them display
   names, e.g. "Tracerfall for Windows" / "Tracerfall for Android (APK)". Save.

From then on `publish.bat` (`python tools/github/sync.py all`) pushes to itch
right after the GitHub release, whenever butler + a key + the target exist. If
anything is missing it prints one line and carries on: itch can never fail the
GitHub release. `SKIP_ITCH=1` leaves it out for one run.

The dedicated-server pack is optional: `python tools/itch/push.py --pck` (or
`"push_pck": true` in itch.json) pushes `SoldatReborn.pck` to a `server` channel.
Servers pull it from GitHub anyway, so only do this if you want it on itch too
(give it a clear display name like "Dedicated server pack (advanced)").

Check what's live: `butler status <you>/tracerfall`.

## 5. Every release

1. Build + publish as usual (`release-*.bat` / `publish.bat`); itch updates itself.
2. Optional devlog: `python tools/itch/push.py --notes`, then on itch: Devlog →
   Create devlog post → title "Tracerfall X.Y.Z — Name", paste
   `build/itch_devlog_X.Y.Z.html` with the HTML button, add a screenshot, Publish.
