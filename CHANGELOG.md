# Changelog

All notable changes to Soldat Reborn.

## [1.30.0] — 2026-10-05

### Added
- **REPLAYS.** Every match you play is recorded (the last 20 are kept, about 2 MB for a 5-minute round). Watch any of them on its map: pause, 0.25x to 4x speed, seek, follow any player or roam with a free camera (drag on phones).
- **FRIENDS and clan tags.** Add a clan tag (up to 4 letters) to your name: it shows as «TAG» Name. FRIENDS lists everyone you've played with online, shows who's playing right now and where, and joins their game in one click. Star people to keep them on the list.
- **New unlocks:** tracer colors (Red, Green, Blue, White, Gold) for your bullets and jetpack flame colors (Blue, Green, Purple, White).
- The CUSTOMIZE preview shows your jet flame and tracers.

### Changed
- **Unlocks come faster:** something new every level or two up to level 25 (Gold weapon skin was level 40, Gold helmet 35).
- Buttons in lists (WATCH, JOIN, DOWNLOAD...) are bigger on phones.

### Fixed
- **Brand-new players didn't reach the leaderboard** until their second launch: the profile id was only created once a settings file existed. Found by playing on the live official server.
- Servers update the online game list right after someone joins or leaves (it could lag 30 s), and retry a failed update after 5 s instead of staying unlisted.
- Names can no longer inject text formatting into other players' kill feed and scoreboard (square brackets are turned into round ones on the server).

### Testing
- New release-gate checks: the leaderboard end to end with a brand-new player on a real dedicated server, clan tag + friends over the network, replays (record, save, list, play back, seek, exit), tracer and jet colors on real bullets, pickup tags never overlapping.

## [1.29.1] — 2026-10-04

Seven review passes over customization and unlocks.

### Fixed
- **Vest paint barely showed.** The vest sprite is dark, so every paint came out near-black; it now shows its real color.
- **Weapon skins were too faint** on the dark gun sprites (Desert, Woodland, Arctic looked almost stock). All six now read clearly, Gold included.
- **Skin tones** were too close together; they're more distinct now.
- Changing your look from the pause menu now updates your soldier right away (and for everyone online) instead of on the next respawn.
- Picking a vest paint turns the vest on; turning the vest off clears its paint.
- Unknown or hand-edited values in the settings file can no longer reach your soldier.
- The "UNLOCKED" message no longer hides a RANK UP or achievement message that pops at the same moment; several unlocks at once share one message.

### Added
- CUSTOMIZE shows your next unlock ("Next unlock: Weapon skin: Desert at level 2").

### Testing
- New checks: unlocking in a real match (message, equip, kept after respawn), save / reload of every look, and other players' and bots' looks arriving over the network.

## [1.29.0] — 2026-10-04

### Added
- **CUSTOMIZE** (main menu): dress your soldier from our own catalog, with a live preview. Skin tone, head (helmet, cap, four hair styles, bald), helmet paint, vest and vest paint, trousers, chain, cigar / dreadlocks / dogtag, and **weapon skins** (Desert, Woodland, Carbon, Arctic, Crimson, Gold) that tint every gun you carry.
- **Unlocks.** Many looks unlock as your career level goes up or when you earn certain achievements (Massacre, Unstoppable, Flag Runner, Long Shot, Champion). Locked items show what they need, and a message pops up in-game the moment you unlock one.
- Everyone online sees your look, and bots now wear random outfits and weapon skins too.

### Changed
- The main menu is rearranged to fit the new buttons: HOST / JOIN side by side, CUSTOMIZE and MAP LIBRARY under Deploy.
- Settings > Cosmetics uses the same options as CUSTOMIZE.

### Planned
- Match replays, Discord status and an itch.io page are filed on GitHub for a later update.

## [1.28.0] — 2026-10-04

The online update: Quick Play, a leaderboard, shared maps, kill cam, lag compensation, map voting.

### Added
- **QUICK PLAY** on the main menu: one click joins the best online game (people first, then lowest ping). If nobody's online it starts a bot match right away.
- **Servers stay full.** Dedicated servers (like the official one) keep 8 soldiers in the match: bots step aside one for one as players join and come back when they leave, and teams stay even.
- **LEADERBOARD** (main menu): the top 50 on the official server and your own rank. Kills, captures, matches and wins earn ranked XP, from Recruit to General.
- **MAP LIBRARY** (main menu): download maps other players made, or share your own editor maps with everyone.
- **Kill cam.** When you die, the camera follows whoever killed you, with their health and weapon on screen.
- **Next-map vote.** The winner screen offers three maps: press 1/2/3 (or D-pad, or tap). The most votes loads next; no votes keeps the map. The official server rotates maps.
- **Helmet finishes** to unlock with your career level: Desert (5), Urban (10), Night (20), Gold (35). Settings > Cosmetics.
- **Gamepad:** L3 opens team radio and the D-pad picks the callout, R3 votes yes, and the D-pad picks your loadout while you wait to respawn.

### Changed
- **Lag compensation.** Hits from other players count where the shooter saw you (based on both players' ping, at most 0.2 s back), so shots that land on their screen land on yours.

### Fixed
- The Rambo Bow killed the archer: since it became a one-shot kill, an arrow could drop back onto whoever fired it. Your own rounds never hit you now.
- Other players were drawn wearing your outfit (helmet, chain, vest...). Everyone now shows their own.

### Testing
- New release-gate checks: bot fill, leaderboard reporting and screens, map library upload / download, Quick Play fallback, lag compensation, kill cam, gamepad radio / loadout, map vote, and players seeing each other's outfits.

## [1.27.0] — 2026-10-03

Five more studio passes: localization, performance, bot AI, touch, game feel.

### Changed
- **Hits feel like hits.** Rocket and grenade splash, and Knife/Chainsaw melee, now play the hit sound and show damage numbers, like bullets always did.
- **Bots get unstuck.** Bots that keep failing to reach a spot route around it for a while (shared by all bots), no longer get shoved sideways mid-climb, find a jet-reachable way back to the path when they fall off it, and respawn if trapped in a pit for 30 seconds. In a CTF test on all 102 maps they grabbed the flag 17% more often and fell to their death less than half as often.
- **Touch:** the left/right zone tint and centre line fade out after the first few seconds so they don't cover the action.

### Fixed
- A ~150 ms stutter the first time anyone got hurt in a match (and smaller ones on first kill icons and first sounds). Everything is now loaded up front, in the background. Frame time with 16 bots: about 3 ms average, worst frame under 5 ms.
- Radio calls, killing-spree titles, vote prompts and bonus pickups are now translated in Español, Português, Deutsch and Français.
- Hit accuracy in stats could show above 100%.

### Testing
- New performance test (16 bots, CTF) in the release gate.

## [1.26.0] — 2026-10-03

Studio polish: six passes (QA, design, art, AI, localization, onboarding).

### Changed
- **Smarter spawns.** You, online players and respawning bots now come back at the spawn points farthest from enemies (picked at random among the best few), always on your own team's side in team modes. Bots used to respawn on the exact same spot every time.
- **Rambo Bow kills in one arrow**, like the original. It needed 9 hits before, which made the Rambomatch power weapon the weakest gun in the game. Arrows still sag and reload slowly, so it's a skill shot.
- **Chainsaw is deadly up close** (about a second of contact instead of over three).
- **What's new** now lists every version you missed when you update across several releases, one line per change.

### Fixed
- Light and shadow patches on 29 classic maps (Arena3, and others) were drawn as hard white or black boxes floating over the level. They now blend in as soft glows and shade.
- In-match text is translated in Español, Português, Deutsch and Français: death screen, respawn countdown, kill confirmations, winner banner, scoreboard, flag status and spectator hints.

### Testing
- Full release gate: every stage passed, including the CTF sweep on all 102 maps (0 errors). A flaky check in the feature test (a bot killing you right before the limbo-menu step) now waits for the respawn.

## [1.25.4] — 2026-10-03

### Fixed
- Team modes start each side on its own half of the map (reported). On about 30 of the classic maps BLUE spawned at RED's flag and RED at BLUE's (the original maps label their spawn groups the other way round, or mix them in the middle), and you always started at the map's one player spawn, which on maps like Airpirates is right next to the RED flag. Now every spawn point is given to the team whose flag it's nearer to, you (and every online player) spawn on your own team's side, and a side with no spawn points of its own starts at its flag base. Checked on all 102 maps.

## [1.25.3] — 2026-10-01

### Fixed
- Buggies and tanks no longer jump (reported: W launched the whole buggy into the air). Vehicles stay on the ground; instead the wheels roll up curbs and small lips (up to about a tire's height) when you drive into them, while real walls and steep slopes still stop you. W does nothing while driving.

## [1.25.2] — 2026-10-01

### Added
- Dedicated servers: `--name="..."` sets the name shown in Find Games, and with nobody connected the match pauses and the server drops to a few frames a second (about 3% CPU instead of 20%), waking the moment a player joins. Turn it off with `--no-idle`.
- Each release now includes `SoldatReborn.pck`, the game pack a headless dedicated server runs. The official always-on server uses it and updates itself within an hour of a new release.

## [1.25.1] — 2026-10-01

### Added
- **Official online server**: the game now comes set up with the Soldat Reborn master server (161.153.9.69:8080), so Find Games shows internet games, "List on the master server" works, and **Host through the relay** works out of the box with no port forwarding and nothing to type. You can still point it at your own server under Join.

## [1.25.0] — 2026-09-30

### Added
- **Host through the relay** (Host screen checkbox): play online with friends anywhere with no port forwarding or router setup at all. Everyone connects out to the master server, which passes the game along, and you get a short **R-** code (like R-7K2QXM) to share; friends type it in Join → Connect. Relay games show as RELAY in Find Games. It needs a master server URL set under Join (the master server now includes the relay; see server/master-server/README.md to run one).
- **Languages**: the menus, settings and host/join screens come in **Español, Português (Brasil), Deutsch and Français** (Settings → Game → Language; default follows your system). In-match HUD text is still English for now.

## [1.24.0] — 2026-09-30

### Added
- **Achievements**: 21 goals (First Blood to Veteran, Sharpshooter, Long Shot, Rocket Man, Grenadier, Roadkill, Tank Ace, Double Trouble, Massacre, Unstoppable, Flag Runner, Winner, Champion, All-Rounder, Last One Standing, Marathon, Recruit, online play). A gold toast pops when you unlock one, and the Stats screen lists them all with progress (e.g. 12/25). Ones your past play already earned unlock quietly; rocket, grenade, melee and headshot tallies are filled in from your existing stats.
- **Rank**: XP for kills (+10, headshot +5), captures (+50), finished matches (+20) and wins (+80) raises your level; it shows next to your name in the menu corner ("William · LV 12"), on the Stats screen with progress to the next level, and a RANK UP toast in game. Your level starts from your career so far.
- **Recent games** in Find Games: the last 5 servers you joined, with live ping, one click to rejoin.

### Fixed
- Gun Game is always a free-for-all won by climbing the whole weapon ladder (or the top rung when time runs out). With Survival switched on it used to end the round and declare a winner after the first kill (reported); Survival and Advance are now ignored in Gun Game and their checkboxes are greyed out while it's selected (your choice is kept for the other modes).
- The controls line at the bottom of the menu overlapped the BACK button on the Host screen (reported). It now only shows on the main menu list; START HOSTING and BACK share a row; and any menu panel taller than the window scales down to fit instead of running off the bottom.

## [1.23.0] — 2026-09-29

Polish pass: ten rounds of fix → test. Gate run 37: all 57 checks passed (CTF sweep with buggies and tanks: 220 grabs, 32 captures, 688 kills, 3 falls, 0 errors).

### Added
- **Colour-blind friendly teams** (Settings → Video): the red team is drawn orange everywhere (soldiers, flags, domination points, HUD, scoreboard, kill feed). Team colours now come from one place.
- **PING column** on the scoreboard in online games (the host measures everyone's round trip and shares it every 2 s; colour-coded).
- **What's new** panel: the first time you start a new version, the menu shows that version's changes once. The update panel formats release notes the same way.
- **REPORT A BUG** and **OPEN LOG FOLDER** buttons (Settings → Game): opens a GitHub issue with your version, OS and graphics card filled in, and the folder with the game's logs to attach.
- The top-left corner of the main menu always shows your version and update status: "v1.23.0 · UP TO DATE", CHECKING..., CHECK FOR UPDATES (click to check again), or UPDATE AVAILABLE when there's a newer one. The pause menu shows the version too.
- On touch screens the THROW button says what a tap does right now: DRIVE, GUNNER, MOUNT, GET OUT or DISMOUNT near vehicles and M2 guns.

### Fixed
- Frame hitch on kills and deaths: the stats file was rewritten on every kill / death (and every 5 hits); changes are now saved a few seconds later, at match end and when the game closes.
- Online: rocket and grenade sync messages go through one handler that drops messages for projectiles that already exploded or were fired before you joined, instead of logging "Node not found" (the one flaky network case in the last full test run).
- Bots with the Barrett or Ruger take careful aim (60% less aim wobble); with one shot every 2.2 s a Barrett bot used to miss almost everything.
- Two identical pickups side by side (e.g. two grenade kits on Voland) print one name tag; different tags that would overlap are stacked.
- Esc opens the pause menu for input tools that send virtual keys without a scancode (remote play / streaming / automation).
- The mountain backdrop could log "triangulation failed" when a ridge dipped to the bottom edge of the screen.
- The rejoin network test read the player's name a second after rejoining, when a bot had sometimes already killed them (false failure); it now reads it the moment the new body exists.

## [1.22.2] — 2026-09-29

### Fixed
- Starting a match (Play vs Bots, Host, Join, Training, Random Map) no longer looks like it does nothing: the menu shows LOADING MATCH... while the match builds, and if the match can't be loaded it says so and what to do (restart the game) instead of silently staying on the menu.
- Builds are flushed to disk before the build script reports them done (starting a build that was still being written could fail to load the match).

## [1.22.1] — 2026-09-29

### Changed
- Main menu fits without scrolling: PLAY vs BOTS and RANDOM MAP (was "Generate + Play", same button) share a row above TRAINING and MAP EDITOR, so nothing is hidden below the fold any more.
- First release delivered through the auto-updater: players on 1.22.0 get it from the UPDATE AVAILABLE button.

## [1.22.0] — 2026-09-29

### Added
- **Auto-updater.** When the game starts it asks GitHub for the latest release. If there's a newer version, an **UPDATE AVAILABLE** button appears in the top-left corner of the main menu; it shows what's new and offers **UPDATE NOW**.
  - Windows: the new version downloads in the background (you can keep playing; the button shows the progress), its size is checked, and **RESTART TO UPDATE** closes the game, swaps the exe (the old one is kept as `SoldatReborn.previous.exe`) and starts the new version. If the swap fails, the old exe is put back.
  - Android: an app can't replace itself, so **DOWNLOAD** opens the new .apk in the browser; install it over the old one.
  - Settings, stats and maps are kept (they live in your user folder, not next to the exe). Settings → Game → "Check for updates when the game starts" turns it off. It never checks in dedicated servers or the editor.

### QA
- `tools/updater_test.gd` (gate stage F) against a local fake GitHub: version comparison, the release check, the download with its size check, and the Windows swap script.

## [1.21.1] — 2026-09-29

### Changed
- **A name is required before Training and online play.** The first-launch prompt no longer has a Skip; Start with Training and To the Menu stay greyed out until you type a name (not "Player"). Training, Host, Join and Quick Join ask for a name first if you still don't have one, then carry on where you were going.
- **Changing your name is one click:** your name sits in the top-right corner of the main menu ("William · CHANGE NAME"). Settings → Game still has the field too.

### QA
- `tools/name_test.gd` (gate stage F): buttons stay disabled with no name or "Player", the action runs after saving a name, renaming from the menu works and updates the corner button, and a named player isn't asked again.

## [1.21.0] — 2026-09-29

Easy joining. Gate 28 (A, B, all C network cases, F join codes / labels / editor / training) passed.

### Added
- **Join codes.** A host's address and port packed into a 10-character code like `60N00-HE7K1`. Type or paste it into Join Game (the box takes a code or an IP); lower case, spaces and O/0 or I/1 mix-ups still work.
- **Automatic router setup (UPnP).** When you host, the game asks your router to open the game port (and port + 1 for pings), finds your public address and gives you an internet join code; the ports close again when you stop hosting. If the router refuses, or your provider shares one IP between customers (CGNAT), the pause menu says so and what to do instead. Host screen checkbox to turn it off.
- **COPY JOIN CODE** in the pause menu for the host: copies a ready-to-paste message ("Join Game > code ... (same Wi-Fi: ...)").
- **FIX FIREWALL** on the Host screen (Windows): adds an inbound Windows Firewall rule for the game after one admin prompt, the usual reason friends on the same Wi-Fi can't see or join a game.
- The pause menu and status line show the LAN code and internet status while hosting.

### QA
- `tools/join_code_test.gd` (gate stage F): codes round-trip for five addresses, tolerate sloppy typing, reject garbage, and a host's status carries its LAN code.

## [1.20.0] — 2026-09-28

Gate run 27: 54/54 passed (CTF sweep with buggies and tanks on the maps: 225 grabs, 32 captures, 683 kills, 3 falls, 0 errors). Two cases (a bot rocket packet racing a fresh join, and a bot Barrett missing its one test shot) failed once and passed on re-run; both are filed.

### Added
- **Bots drive.** A bot heading somewhere far (1100+ px) takes an empty buggy or tank on the way, drives toward its goal, hops over bumps, and gets out at the destination, in front of a drop into the void, when it's stuck, or when the vehicle is nearly wrecked. A bot driving alone fires the gun at targets in reach.
- **Tanks** on the 13 widest classic maps (one per team base on team maps) and the Towers arena. Two seats like the buggy, but slow (230 top speed), 900 HP and armored: bullets do a fifth of their damage, so bring a LAW, M79 or grenades. The turret lobs a high-explosive shell every 2.4 s (aim high for range; the HUD shows SHELL READY / RELOADING); its own shells never hurt the tank or its crew. It crushes people it rolls over and respawns 40 s after it's wrecked. Bots drive and gun tanks too (they work out the shell arc). Map editor **Tank** tool; listed on the H card.
- **Server browser: live ping and player counts.** Every host answers a small UDP query on its game port + 1, so LAN and master-server rows show ping (green / yellow / red), the current players and map, and grey out full servers and other versions. Joinable, busy, low-ping servers sort first. REFRESH button.
- **Quick Join** (main menu, Join screen and Browse): looks at LAN and master-server games for a couple of seconds and joins the best open one on your version (people in it beats empty, then lowest ping).
- **Rejoin after a drop.** If the connection to the host is lost (not a kick), the menu shows CONNECTION LOST and rejoins by itself after 5 s (or press REJOIN). The host recognises the same player coming back from the same address, retires the stale connection, and gives you back your name, score and team.
- Store kit in `store/`: store page copy (short / long description, features, tags, rating notes, requirements), a trailer shot list, and placeholder 1920×1080 screenshots.

### Changed
- Run-over kills by a tank are credited as "Tank".

### QA
- `tools/tank_test.gd` (gate stage F): tank spawns with 900 HP, drives slower than a buggy, a lobbed shell hits a bot 650 px away without hurting the tank or crew, bullets do 20% and rockets full damage, a wreck kills the crew, and it respawns at full health; 13 classic maps carry tank spawns.
- Gate stage C: `rejoin` — a client drops hard, the menu's countdown rejoins it, same name and team, no errors on either side; the `lan` case also checks the server query (ping + players).
- `tools/vehicle_drive_test.gd` (stage F): a bot boards a buggy and drives 3000+ px to a far goal, getting out near it.

## [1.19.0] — 2026-09-28

Gate run 26: all stages passed (CTF sweep with buggies on the maps: 218 grabs, 30 captures, 608 kills, 7 falls, 0 errors).

### Added
- **Buggies.** A two-seat ground vehicle on 87 of the 99 classic maps (on long stretches of open ground near each team's base, found by `tools/place_vehicles.py`) and on the three built-in arenas.
  - Walk up and press **F**: the first person in drives (A/D, W hops over bumps), the second mans the machine gun on the roll bar. A driver on their own can also fire the gun (mouse / right stick / touch aim). **F** again gets you out.
  - It runs over enemies at speed (enough to kill at top speed), the gun overheats after about two seconds of continuous fire, and the engine note follows your speed.
  - 350 HP. Bullets hurt it, rockets and grenades hurt it more; when it's wrecked it explodes, killing anyone still inside and hurting people nearby, then comes back at its spot 25 s later.
  - Works online: the host decides who sits where and owns health / wrecks / respawns; the driver's machine drives it and everyone else follows. Late joiners see the buggies, their damage and who is in them.
  - The map editor has a **Buggy** tool; Settings → Game has a Vehicles switch (the host's setting counts online). Not in Gun Game.
- **Crew play.** Driving and shooting at once is possible but costly: while a lone driver holds the trigger the buggy is held to half speed and the gun is about twice as inaccurate. In team modes a teammate bot near a buggy you're driving walks over and takes the gun — it leads its targets, fires in bursts to keep the barrel from overheating, and hops out when you do.
- While you're in a buggy the HUD shows its health, the gun's heat (and OVERHEATED), who's on the gun, and a reminder when you're driving solo.
- Bots don't drive yet; they ride as gunners, shoot the people in enemy buggies and get run over by them.

### QA
- `tools/vehicle_crew_test.gd` (gate stage F): a solo driver who fires tops out at half speed (260 vs 520); a teammate bot boards as gunner within a second, hits an enemy, and leaves 1.5 s after the driver does.
- `tools/vehicle_test.gd` (gate stage F): on a test range — F gets you in as driver, D drives it, it runs a bot over, the gun hits, F gets you out, a rocket blast damages it, wrecking it kills the driver, and it respawns at its spot.
- Gate stage C: `drive` — a client joins a dedicated server, the host gives it the driver's seat, and it drives 1000+ px with no network errors on either side.
- A probe of every map with buggies (0–101): every buggy spawns on the ground and stays put until someone drives it.

### Fixed
- A listen host could log "Trying to assign invalid previously freed instance" when someone joined right as the host's own body was being replaced (typed dictionary reads in Main); those reads are untyped and checked now.
- Pickups crashed ("Nonexistent 'bool' constructor") when something that isn't a soldier drove through them.

## [1.18.0] — 2026-09-28

Content and sound pass, plus a Barrett fix. Gate run 24: 48/48 passed (CTF sweep 224 grabs, 39 captures, 635 kills, 4 falls, 0 errors).

### Added
- **Medikits and grenade kits** on all 99 classic maps, at the spots the original map makers placed them (read from the Soldat `.pms` files). A medikit heals you to full, a grenade kit refills you to 3 grenades; each comes back 25 s after it's taken. You can't waste one: at full health you walk past a medikit. Bots use them too and head for one when they're hurt or out of grenades. Bonus crates now use Soldat's own kit sprites.
- **Everything is labelled and explained.**
  - Modes: the main-menu and Host pickers show how to win under the picker, and each entry has a hover tooltip with the details. Every match opens with a banner (mode + how to win + any Realistic / Survival / Advance rules), the top bar spells out the mode name, and the pause menu repeats the goal.
  - Items: power-up crates, medikits, grenade kits, weapons lying on the ground, Pointmatch diamonds and M2 guns carry a name tag that fades in as you get close. Picking one up explains it at the bottom of the screen ("BULLETPROOF VEST — you take half damage for 30 s", "AK-74 — assault rifle, all-rounder"), and the power-up countdown keeps a short reminder ("VEST 24s · half damage").
  - The H card shows the current mode's goal and a PICKUPS list; weapon-menu tooltips open with what the gun is for.
  - Tooltips on the main-menu buttons (Generate + Play explains it makes a new random map each time and where it's saved) and on every Map Editor button.
- **Team radio** (V, rebindable): pick what — enemy flag carrier, friendly flag carrier, enemy spotted — then where — up / mid / down — with 1–3. Your team hears Soldat's radio voice line and sees an amber "(RADIO)" chat line. Bots call out the enemy flag carrier when someone steals their flag.
- **Positional sound**: other soldiers' gunfire, reloads, jumps, explosions and deaths come from where they happen — quieter with distance and panned left/right. Far-off fights use Soldat's muffled distant-gunfire / distant-explosion samples.
- New sounds from the Soldat set that were sitting unused: footsteps (running and crouched), landing thuds (heavier after big drops), bullet ricochets off walls, bullet whizz-bys when an enemy round passes your head, death cries (plus a crunch on headshot kills), grenade pin pull when you start cooking, grenade bounces, weapon switch, weapon pickup and throw, roll, going prone / standing up, respawn, kit and bonus pickups.
- Rain and snow maps play a looping rain / wind bed. Six more classic maps get the weather their `.pms` file asks for (April, Bigfalls, Biologic, Mossy: rain; B2B, Messner: snow).

### Fixed
- **The Barrett never fired.** It spun up, clicked and nothing came out: it's semi-auto with a 0.32 s wind-up, and the "release the trigger before the next shot" check was already tripped by the time the wind-up finished. A click now queues the shot, which goes off after the wind-up (even if you let go), one round per click.

### Fixed (full audit: every map, every gun, graphics)
- **Bots slid off HH (and similar maps) on respawn.** When an enemy stood on a spawn, the spawn was nudged sideways up to 440 px — straight through HH's building wall onto the steep outside face, and the bot slid off the map. Nudged spawns now have to be in the same room (no wall in between) on ground you can stand on.
- **Bots walked off ledges with a full jet tank.** A bot falling toward the kill line now burns fuel and steers back over the last ground it stood on. Across all 102 maps (8 bots, 30 s each, deathmatch) falls went from 50 to 9, and kills rose ~10% because bots stay in the fight.
- **Fast bullets passed through people.** A Barrett round travels 40 px a frame and a soldier is ~14 px wide; hits were checked by overlap only, so bots with the Barrett could empty a mag into a standing target without a hit. Bullets now sweep their whole path each frame.
- **Bot M79 fired a straight bullet** (a slow 90-damage rifle with no blast). It now lobs a real grenade shell on a computed arc and only fires when the target is in reach.
- **LAW / M79 bots that got close stood still and never fired** (too close to rocket safely). They now switch to the pistol up close and back to the launcher at range.
- Engine errors in the logs: grenades spawned during a physics callback ("Can't change this state while flushing queries") and timers holding freed nodes ("Lambda capture ... was freed", from the bot radio call-out and player despawn). Both fixed, and the release gate now fails on either message.
- The sky and horizon glow showed faint horizontal lines (stacked translucent strips); both are smooth gradients now.

### QA
- `tools/weapon_test.gd` (gate stage F): on a test range the player fires every primary and secondary at a target — each must hit, use ammo and reload back to a full mag — then a bot armed with each bot weapon must hurt the player.
- Full audit run: deathmatch sweep of all 102 maps with an autopiloted player (falls, stuck spots, player deaths), screenshots of all 102 maps, menus and HUD at 960×540 and 1920×1080. The sweep's player-death counter was stuck at 0 (single-player respawns reuse the body); it now counts properly.
- `tools/fire_test.gd` (gate stage F): every primary must fire from a click; the Barrett exactly one round per click. Fails on 1.17.1.
- `tools/label_test.gd` (gate stage F): every mode / weapon / pickup has text, the win numbers in it match the game rules, matches open with the banner, crates are tagged, pickups explain themselves.
- Gate stage F gains four more checks: `tools/sound_test.gd` (every family of world sound fires in a bot match and every requested sample exists), `tools/radio_test.gd` (V → 2 → 3 posts "Friendly flag carrier — down" with its voice line and doesn't switch weapons; a bot calls out the flag carrier), `tools/kit_test.gd` (a full-health soldier leaves a medikit; hurt → healed; no grenades → refilled).

## [1.17.1] — 2026-09-28

### Changed
- **Grenades cook like in Soldat.** Pressing the grenade key pulls the pin and starts the fuse; holding winds up a harder throw (a tap lobs it, ~0.9 s gives the full throw); letting go throws it with whatever fuse is left. Hold it past the fuse (2.2 s frag, 1.9 s cluster) and it goes off in your hand. A ring over your head shows the fuse and flashes red near the end. Die while holding one and it drops live at your feet. The touch GRENADE button now works as a hold button. Gate stage F checks tap / wind-up / in-hand. Gate run 20: all stages passed.

## [1.17.0] — 2026-09-28

Retail-readiness pass: Training mode, first-launch name prompt, credits screen, pause on focus loss, VSync / FPS cap. See RETAIL_CHECKLIST.md for what's left (mostly legal, store accounts and real-device testing). Gate run 19: all stages passed (CTF sweep 220 grabs, 33 captures, 626 kills, 5 falls, 0 errors; Training played through).

### Added
- The game pauses (pause menu opens) when it loses focus — alt-tab on PC, home button / incoming call on phones — so a single-player match doesn't keep running without you. Toggle: Settings → Game.
- **Training** (main menu, and offered right after the first-launch name prompt): a guided first match on Arena2 — move, jump, jet boots, shoot, reload, switch weapons, grenade, crouch — each step waits until you've done it, then a training bot joins for the last one. Prompts use your actual key bindings (button names on touch screens). Your match settings are put back afterwards and are never overwritten while training runs. Gate stage F plays it through.
- First launch asks for your player name (skippable; Settings → Game changes it). Existing players who already set a name aren't asked.
- **Credits & licenses** screen in the main menu (Soldat authors, CC BY 4.0 attribution for the Soldat base content, Godot). The CC BY license expects the attribution to be visible to players, not only in the source.
- The desktop window can't be resized below 960×540 (menus and HUD overlapped).
- Settings → Video: VSync toggle and a frame-rate limit (Unlimited / 30 / 60 / 120 / 144 / 240).

## [1.16.2] — 2026-09-27

### Added
- Hovering the Realistic / Survival / Advance boxes in the main menu explains what each one does (Survival: no respawns until one side is wiped out).
- Survival: while you wait for the next round the death screen shows who's still in it ("BLUE 4 alive · RED 1 alive", or "3 left" in free-for-all).

### Fixed
- Objective arrow labels ("FLAG 214m") sit fully inside the arrow instead of running under the arrow head at the left / right screen edges.
- Team modes always show both team scores in the top bar; in Survival a team with nobody alive and no points dropped out of it (the report screenshot showed only "BLUE 0").
- The death text ("You were killed by … / Waiting for next round") no longer prints over the round-end "BLUE WINS" / MVP banner; it steps aside while the banner is up.

### QA
- Gate run 18: 40/40 passed (CTF sweep 228 grabs, 32 captures, 646 kills, 7 falls, 0 errors). The multiplayer respawn check now looks for the first respawn instead of "alive at the end" — bots sometimes killed the client again first, which made it flaky.
- `tools/respawn_test.gd` (gate stage R): kill the player, wait for the next life (timed respawn and Survival round reset) and check the death screen is gone. It fails on the 1.16.0 Survival bug.

## [1.16.1] — 2026-09-27

### Fixed
- Survival: after you died and the next round respawned you, "You were killed by … / Waiting for next round" and the grey overlay stayed on screen over your new life. The single-player spawn now clears the death screen (the timed respawn only hid it by counting down, and Survival has no countdown).
- Multiplayer: 1.16.1 and 1.16.0 refuse each other (exact version match), so update every copy.

## [1.16.0] — 2026-09-27

Limbo weapon menu, LAN game discovery, map-editor undo, Domination bot fixes and a round of multiplayer hardening (every mode soaked with two autopiloted clients, zero errors).

### Gameplay & UI
- **Limbo weapon menu works**: while you're dead the Soldat weapon panel shows on the left (bigger rows beside the touch buttons on phones); pick a primary (1–0, click or tap) and a secondary (click / tap) and you respawn with them. Your last number-key pick carries over too, and the choice is saved. (The panel existed but never appeared, and every respawn reset you to the AK-74.) Off in Advance and Gun Game.
- **Low-FPS guard**: if a match runs under ~35 fps for 8 seconds, Lo-fi mode switches on once and a chat line says so (Settings → Video turns it back off). Aimed at weaker phones.
- On touch devices the menu's bottom hint line explains the touch controls instead of listing keyboard keys.
- **Controls card**: the first three matches open with a small bottom-centre card of the controls (read from your current bindings, pad buttons too when a controller is plugged in); it fades after 12 s and **H** brings it back any time (rebindable, "Controls Help"). Not shown on touch screens.
- Objective edge arrows stay below the top HUD row (they could land on the timer / score strip), and while you're dead objective banners show below the death text instead of over the spectator lines.
- Spectating while dead: tap the left / right half of the screen (touch) or LB / RB / D-pad (gamepad) to switch who you follow; the hint says so.
- Kill confirmation: when you score a kill a short "KILLED <name>" line (red with · HEADSHOT) pops under the action for a second.
- Death screen says "You died" for suicides instead of "killed by <you>"; the empty HP/JET box hides while you're dead.
- The single-player map picker no longer shows "Rotation" while PLAY would load the editor's last play-test map.

### Bots
- **Bots: Domination fixes.** Standing on a point to capture it no longer trips the anti-stuck escape (bots used to walk off after ~2 s, before the 4 s capture finished); after jetting up a shaft, bots hold altitude while stepping sideways onto the ledge instead of dropping back down (Equinox's blue spawn was a trap); Kampf's third DOM point moved off a ledge bots couldn't reach. On tall slanted climbs bots now follow the nav link's line instead of cutting the corner into the underside of the ledge (MFM). All-map DOM sweep: 330 captures (was 204), falls 2 (was 10).

### Multiplayer
- Network protocol changed (bot shots, ready list): 1.15 and 1.16 builds can't play together — the host refuses the other version with a message, so update every PC / phone.
- **Hosting from the menu now fills the match with bots** (the Bots setting, same as single player; 0 = none, Host Settings changes it live). Before, only dedicated servers had bots, so two friends on a listen server played alone.
- Host Game: "List on the master server" (uses the master URL from the Join screen) registers a listen host the same way dedicated servers do, so it shows up in FIND GAMES over the internet (the game port still has to be forwarded). Checked against the bundled Go master server.
- Host Game lists your own maps too (editor saves / Generate, shown as "Custom: name"); they're sent to clients as JSON. LAN listings show the custom map's name.
- Fixed: hosting (or a dedicated server with `--map`) after an editor play-test loaded the play-test map instead of the map you picked.
- Host-side broadcasts (spawns, despawns, kill feed, objective events, Gun Game rungs, votes, round resets) now only go to peers that have loaded the match; a second client joining mid-match no longer logs "Node not found: Main". Gate run 12: all stages passed (CTF sweep 245 grabs, 41 captures, 662 kills, 3 falls).
- **LAN games show up by themselves**: a listen or dedicated host broadcasts a small beacon every second, and Join → FIND GAMES lists games on your network (name, players, map, mode) live — click to join, no IP typing. Different builds are shown greyed out. The master-server list sits below it as before. (UDP port 23074.)
- Pause menu shows the map and mode, and in multiplayer the connection line (the host sees the address it's hosting on and how many players are connected).
- The Join panel remembers the last address and port you connected to.
- Host Game panel: game mode picker next to the map (mirrors the main menu's), and it tells you how LAN players find you (plus your LAN IP when there is one). The in-game status line shows the address you're hosting on.
- Multiplayer: a dead (or disconnected) soldier's body lingers 1.5 s as an inert, hidden husk so shots / state already in flight from its owner don't log "Node not found" on every peer.
- Multiplayer: bonus grants / Predator breaks and client-owned grenades and rockets no longer broadcast to everyone — they go to peers that have loaded the match (the host now tells clients who that is). A second player joining mid-match sometimes logged "Node not found: Main/Player_…" from these. Ten per-mode two-client soaks: zero errors.
- Multiplayer: bot shots carry the weapon they were fired with. A replica whose loadout / secondary flag lagged the host (they sync unreliably at state rate) fired a bullet where the host fired a LAW, so the host's rocket updates hit a node the client never made ("Node not found: BotRocket").

### Map editor
- **Map editor undo / redo**: Ctrl+Z, Ctrl+Y (or Ctrl+Shift+Z) and toolbar buttons, 60 steps; a drag-move is one step. The toolbar now uses the game's UI style, highlights the active tool, and its backing strip grows to fit all three rows. On touch screens two fingers pan and pinch-zoom the editor view, and Android back leaves the editor (or closes the load list).

### QA
- Gate run 17 (v1.16.0, final build): 38/38 passed — adds the listen-host + client case; CTF sweep 243 grabs, 34 captures, 639 kills, 5 falls, 0 errors.
- Gate run 16 (v1.16.0): 37/37 passed — stage C adds a two-client autopilot soak; CTF sweep 230 grabs, 42 captures, 630 kills, 5 falls; mode matrix DOM 53 captures.
- QA: the autopiloted player ran every map in PM, HTF, INF, GG, Rambo and BR (15 s each, 612 map runs): zero script errors.
- QA: gate stage C adds a listen-host + autopiloted-client case.
- QA: `--smoke-auto` drives a network smoke client with random input; `--net "m0 … m9"` runs a dedicated server + autopiloted client per mode (all 10 modes: zero errors on either side, and the client runs the server's mode). The gate now starts every Godot run from default settings and restores this machine's files afterwards; the feature test checks the limbo pick.
- Gate run 15: 36/36 passed (adds LAN discovery; CTF sweep 230 grabs, 43 captures, 628 kills, 2 falls; mode matrix DOM 55 captures).
- Gate run 14: 35/35 passed (stage C now includes INF / DOM / Gun Game with an autopiloted client; CTF sweep 222 grabs, 34 captures, 648 kills, 6 falls).

## [1.15.0] — 2026-09-24

Release-readiness pass: bots fight bots, a five-reviewer "pre-release" audit
(gameplay, networking, UX, bots, QA/build) with its fixes, and a scripted
release gate (`tools/release_gate.sh`) run three times clean.

### Gameplay
- **Bots vs bots**: in DM / Rambo / Gun Game / BR every bot is its own team (1000+), with its own colour, so bots fight each other as well as you. FFA scoreboard shows the top 4 + you.
- **Objective HUD**: status line (your team, each flag HOME / TAKEN by X / DROPPED / YOU HAVE IT, DOM point chips with capture %, BR "return to the zone"), big banners + sounds for grabs / drops / returns / captures, and off-screen edge arrows with distance to flags, carriers, your base, DOM points and the BR ring.
- Captures / DOM points / PM points no longer go through the kill feed (they double-scored and counted as kills in Stats).
- Mode logic pauses between rounds (no captures on the winner screen); flags reset home on round reset; Survival no longer adds a second body after a winner-screen death.
- Gun Game rung lookup can't run past the ladder; kill-streak banners only for you (2+) or big streaks (5+).
- Bots: Rambo bots go for the bow and hunt its carrier; melee bots close in instead of swinging at range; bots only shoot / throw grenades at targets they can see; Flamethrower, Chainsaw and Spas-12 stats fixed (Spas fires a real 8-pellet spread); bot jet no longer spams the jet sound.
- BR ring damage now also hurts clients' own soldiers, and a ring death isn't credited to yourself. Rambo bow regen works for client carriers.

### Multiplayer
- Version handshake: a client on a different build is refused with a readable reason ("Version mismatch: host 1.15.0, you 1.14.0") and sent back to the menu, which now shows why you left (kicked / host lost / mismatch).
- Duplicate player names get a suffix; `net_client_ready` can't be replayed for a free respawn; chat author is resolved on the host (no spoofing) and capped at 200 chars.
- Respawn timing is owned by the host scene (matches the death-screen countdown); the bot-count slider no longer over-spawns while bots are dead.
- Host RPCs for bot fire, grenades and rockets go only to peers that finished loading — no more "Node not found: Main/Bot_N" spam on joiners.
- M2 mount/dismount sender check, vote majority counts only eligible voters, dedicated survival reset doesn't spawn a host ghost, custom map blob cleared on restart.
- Pausing in multiplayer only locks your own input (it used to freeze the host's whole match).

### Platform / build
- Android back button opens/closes the pause menu in game and acts as "back" in the menu instead of quitting.
- Version shown in the menu comes from project settings; git is only queried in editor runs.
- Android version 1.15.0 (code 11500), Windows file/product version 1.15.0.0; Windows export now ships the map JSON.
- Settings save is read-modify-write (keeps sections it doesn't own); loaded mode index is clamped. Map JSON loader tolerates malformed lists and warns on missing files.
- `tools/release_gate.sh`: static checks, scene boots, dedicated + listen-server smokes, all 10 modes bots-vs-bots, and a CTF sweep of all 102 maps. CI runs the `--quick` gate.

### Release gate results
- Run 1 caught a regression from this release's own speed-up: the terrain column index appended into copies of packed arrays, so spawn/ground checks saw no terrain (CTF sweep: grabs 154 → 115, captures 22 → 2). Fixed. Also hardened the harness (wait for server listen, longer objective rounds).
- Run 2 caught a deferred gib spawn running after a map switch (script error). Fixed.
- Run 3: **22/22 checks passed** — CTF sweep of all 102 maps: 202 grabs, 32 captures, 581 kills, 8 falls, 0 anti-stuck frees, 0 script/RPC errors (v1.14: 154 / 22 / 22 falls).
- Run 4 (after the polish below): **22/22 passed** — 206 grabs, 33 captures, 594 kills, 5 falls, 0 errors.

### Polish after the gate
- Main menu is a two-column card that fits 720p (the single column ran off the top and put QUIT under the footer); the wordmark hides behind the Host / Join / Settings / Stats panels instead of showing through them; Realistic / Survival / Advance now have visible tick boxes.
- Nav bake: climbs to a platform right above you now route out past its edge and up beside it (new air waypoints), near-vertical climbs up to 560 px are allowed, long safe drops up to 1300 px count, and sizeable islands are kept instead of only the biggest one (Outpost's blue base was missing from the graph). Roam targets stay on the bot's own island. Moonshine went from 0 captures and 2 falls to 1–2 captures and no falls in a 150 s test.
- Nav "bridges": for every objective leg (team spawn → enemy flag, enemy flag → own flag) the bake can't route with straight links, it now searches the standing free space for the bending route (out of spawn towers, round slabs, through floor gaps), avoiding bottomless drops and climbs longer than a full tank, and lays waypoints along it. New `tools/nav_check.gd` checks those legs in-game for all 102 maps: broken maps 16 → 3 (Dusk, Nuclear, Triumph — their routes need a jet longer than a tank or a gap over the void; they need a map edit). Niall went from bots stuck in spawn to 12 captures in 2 minutes.
- **Every map playable for bots in every objective mode.** Nav bridges now use a cost-weighted search (prefers routes with footholds, avoids void), hug the floor instead of floating mid-air, and also cover INF/HTF flags, the Rambo bow and DOM points (spawn → objective → back). Bad generated objectives fixed with per-map overrides in `tools/pms_to_map.py` (survive `--regen`): Dusk's flags were on the sky arch above the map (now by the left/right towers: 0 → 21 grabs, 3 captures in 150 s), DOM points moved off roofs/ship tips on Bunker, Outpost, Veoto and Airpirates (Airpirates DOM: 47 falls → 1). Nuclear now bridged (0 → 22 grabs, 4 captures). `nav_check.gd` broken maps: 16 → 1 (Triumph — its only home route crosses the central pit; bridging it just fed bots into the pit, so it's excluded).
- Release gate: stage M (opt-in all-map sweeps for INF / HTF / DOM). Run 6: 26/26 passed — CTF 213 grabs / 36 captures / 5 falls; INF 121 captures / 2 falls; HTF 174 grabs / 4 falls; DOM 177 point captures.
- **Triumph bot routes** (last broken map): bots now jet from the lip on downhill gaps instead of after they've started falling, and never patrol to mid-air waypoints (the bake marks them as `air`). Triumph with its route bridged: falls 16–18 → 5–8 per 150 s, grabs up; `nav_check`: 0 broken maps.
- **Multiplayer smoothness**: remote players and bots glide between network updates (short velocity extrapolation, snap only on teleports) instead of snapping to each packet; player state stream 60 → 30 Hz (half the bandwidth).
- **Cluster grenades in MP**: fragments use a fan seeded from the synced blast point (same on every screen) and actually fly on clients (they used to hang frozen in the air for 8 s).
- **Run cycle** stride follows ground speed, so feet don't skate at bunny-hop speed or shuffle when slow.
- Release gate run 7: 23/23 passed — CTF 234 grabs / 28 captures / 3 falls, 0 broken nav routes.
- App icon (jet-pack soldier) for the window, the Windows .exe (embedded, with version info) and the Android launcher. `tools/build_release.sh` exports the Windows .exe and a signed Android .apk.
- Visuals: Domination points are now a floor ring + light column + pole with an owner pennant and a letter badge whose ring fills with the capture progress (was a flat disc); sky clouds are soft layered puffs instead of rows of hard circles.
- HUD: health, jet fuel and magazine bars beside the readouts (health shifts green → red and pulses when low; the ammo bar flashes while reloading).
- **Scoreboard**: hold Tab (pad: Back/Select, rebindable; touch: tap the score strip) for per-player kills / deaths / captures, grouped by team or ranked in FFA; it also shows under the winner banner at round end. Suicides cost a kill, as in Soldat. Counted on every peer from the replicated feed; joiners get a snapshot.
- **Hit feedback**: your hits pop a damage number and a small impact X (Settings > Video > Damage numbers).
- **Map previews** in the main menu: pick a map and a thumbnail (sky, terrain, both flag bases) shows under the System row. Baked for all 99 classic maps by `tools/make_thumbs.py`. Settings / Stats / Quit now share one row.
- **Bot chatter**: bots now and then taunt the player they killed or grumble when you get them (mostly when a human is involved, 12 s per-bot cooldown). Toggle in Settings > Game.
- **Camera look-ahead** (Soldat style): the view slides toward where you aim — by the cursor's distance from screen centre with a mouse, along the aim with a stick or touch (max 260 px, smoothed). Toggle in Settings > Controls.
- Round end names the **MVP** (most kills + 3× captures) under the winner banner; the Host Game panel shows the map preview too.
- **Kill feed weapon icons** (Soldat's own gun icons; grenade / cluster icons; headshots tinted red), text fallback for anything without one.
- **Impact effects**: bullets kick up dust + sparks where they hit terrain and a short blood spray on soldiers (respects Lo-fi and blood intensity; capped so a minigun can't flood it). The HUD shows the current gun icon.
- Fixed error spam at boot from settings / controls files saved by older builds.
- **Menu backdrop**: a real in-game view (one of four baked scenes, picked at random) drifts slowly behind the menu instead of a flat dark background.
- **Fixed: kills no longer add to the team score in CTF / INF / HTF / DOM / PM.** They shared the objective score, so a CTF team with two kills won on its first capture (limit 3). DM / TDM / Rambo still score kills.
- Touch: default button stacks start below the HUD (they covered HP/JET and the kill feed). Saved custom positions are kept. `--force-touch` previews the overlay on desktop.
- QA: `stuck_test.gd --autopilot` drives the human player with random input (move / jet / aim / fire / nades / weapon swaps / stances / throws); the gate's mode matrix now runs with it, and a 102-map autopilot sweep (CTF / INF / GG) came back with zero script errors.
- **Fixed a multiplayer desync with 2+ players**: when a body was spawned twice on a peer (join mirror + broadcast, or a respawn in the same frame), the new body got auto-renamed (`@CharacterBody2D@N`) because the old one was still in the tree, so every later state / shot RPC for that player failed on that peer (the joiner saw the other player frozen). Old bodies are renamed first; players and bots keep their exact node names.
- Player state, shots, grenades, deaths and gestures from a client now go to the host, which relays them to peers that have finished loading (no RPCs into a loading peer). Release gate stage C adds a two-client test (second client joins mid-match: exact names, zero errors).
- **Fixed error spam in single player**: leaving multiplayer / starting from the menu set the multiplayer peer to null, so every authority check logged "No multiplayer peer is assigned" (~50 errors a second in a menu-started match). Single player now runs on Godot's offline peer — the same configuration the tests use; the gate's mode matrix now starts matches through the menu path (`--sp`) and fails on that message.
- **Fixed Realistic mode**: every bullet that hit a bot threw a script error (the headshot check read a `prone` field bots don't have), so bots took no bullet damage in Realistic. Gate stage R now plays Realistic / Survival / Advance with the autopilot.
- QA: `tools/feature_test.gd` (gate stage F) scripts a single-player session through gestures, every weapon slot, both grenade types, weapon throw, extreme mods, live bot-count changes, a vote, the GIF recorder and /kill. GIF recording is skipped on headless / dedicated instances (it logged an engine error every frame).
- Controls: gamepad defaults are installed before saved rebinds are applied, so saved binds for aim / pause stick and a removed pad default stays removed (configs from before pads were saved keep their pad defaults).
- Release gate gained stage N (nav routes). Run 5: 23/23 passed — CTF sweep 211 grabs, 28 captures, 586 kills, 4 falls.
## [1.14.0] — 2026-09-24

Smarter bots: real navigation + objective play. Plus more stuck/placement fixes.

### Bots
- **Navigation graph** baked for every map (`tools/build_nav.py` → `assets/nav/*.json`, loaded by `scripts/nav_graph.gd`). Bots run A* over walkable surfaces and follow the path: hop at low lips, jump-then-jet up climbs, drop down ledges, jet across gaps with a full tank. Bottomless stretches and steep slopes aren't used as routes.
- **Objective brain** (re-thinks ~3x/sec): CTF attackers grab the enemy flag and run it home, defenders patrol the base, everyone chases a carrier who has our flag (and hunts it down in a flag standoff), dropped flags get returned, teammates escort carriers. INF attack/defend, HTF carriers keep moving away from enemies, DOM bots capture the nearest unowned point, PM bots collect points, Rambo bots go for the bow, BR bots stay in the ring. DM/TDM bots hunt the enemy's position (or last-seen spot) instead of pushing into walls.
- **Target choice**: visible enemies beat ones behind walls, enemy flag carriers get priority, wounded enemies a little too.
- **Fuel sense**: bots wait on the ground to refuel before a climb or gap they can't make, and don't bunny-hop away their regen.
- **Pit guard**: bots won't strafe/wander off an edge into a bottomless drop.
- Fixed a v1.13 bug that made bots burn jet fuel constantly (escape jet fired whenever airborne); bots no longer chase bonus crates they can't collect; blocked-on-a-seam hop.
- Soak test over all 102 maps (CTF, 30 s each): flag grabs 98 → 154, captures 7 → 22, falls 22 → 8; DM engagements up ~50%.

### Maps / stuck fixes
- **Seam-free collision** for ported maps: triangles are merged into clean convex outlines (`collision` key) so bodies stop snagging on the joins between Soldat's triangles. Triangles stay for rendering.
- **Soldiers no longer collide with each other** (as in Soldat) — they used to shove each other into walls and plug tunnels.
- **Every objective is placed explicitly and validated**: CTF flags, INF/HTF flag, DOM points, PM points and Rambo bow for all 102 maps (the old 4800-arena defaults put them inside rock or over pits on most classic maps — e.g. Ascent's RED flag was buried in the hill).
- **Team spawns**: each side spawns at its own base in team modes (they used a shared list, so BLUE bots often spawned in RED's base). Soldat Alpha/Bravo now map to RED/BLUE correctly, so flags stand on their own team-coloured bases.

## [1.13.0] — 2026-09-23

Map integrity pass (nobody gets stuck), classic-map re-port, flag + map graphics.

### Fixed — getting stuck / map placement
- **Baseline floor was 100 px too high.** Its top edge now sits at `GROUND_Y` (1900) like every map, the editor and map_gen assume. This had sealed the built-in tunnels shut (20 px gap) and buried the bottom rows of every ported map.
- **Built-in maps:** Ascent / Towers / Pillars tunnels are real walk-throughs now (they were sealed notches — the Towers CTF flags sat in unreachable pockets). Towers stair platforms moved out of the mountain and anchored to the slope (no wedge gap); buried platforms on Ascent/Pillars moved/removed; Towers bot spawns that were inside rock moved onto the stairs.
- **All 99 classic maps re-ported** from `opensoldat/base` at one uniform scale (1.5) with a per-map world rect, instead of being squeezed into 4800×2000 (Messner was at 0.39× — corridors shorter than a soldier). Correct Soldat polygon types: background / flag-only / team-only polys no longer act as walls; "only bullets" and "only players" polys collide with the right things (terrain layers 2/3).
- Every spawn, flag, M2 and pickup is validated by `tools/map_audit.py` (embedded in rock, isolated pocket, over a pit) and auto-moved when bad; `python3 tools/map_audit.py` reports 0 problems across all 102 maps.
- **Fell off a ported map** (below its lowest geometry) = death, like Soldat — no more wandering the empty void around the map.
- **Anti-stuck watchdog** frees any soldier embedded in terrain for >0.35 s. **Wedge fix:** a body resting between two steep surfaces now counts as grounded (can jump, fuel regenerates) instead of being trapped with an empty tank.
- **Stance headroom:** you can't stand up (or leave prone) into a low ceiling any more — you stay crouched until there's room.
- **Bots** use the same feet-anchored 14×24 box as players (they hovered ~20 px above the ground and wedged where players fit) and run an escape manoeuvre when they stop making progress against terrain. Wander edges follow the map width.
- Spawn jitter / enemy-avoid shifts never place a soldier inside a wall or over a pit; dropped flags fall to the ground (or return home if dropped off the map); flags whose carrier was freed no longer hang in the air; lost weapons below the kill line are cleaned up (Rambo bow respawns).

### Graphics
- **New animated flags**: waving shaded cloth with emblem, stone base + pulsing team glow at home, strapped to the carrier's back while carried (bots too, on clients), planted with a bobbing marker when dropped.
- Classic maps now render Soldat's **per-vertex colours** (all the map shading), **background polygons**, correct **prop size / tint / rotation**, and the map's own **sky gradient** with matching parallax.
- Platforms are textured with the map terrain and get a bevel trim; tunnels get a dark back wall.

### Tools
- `tools/map_audit.py` (static stuck audit), `tools/stuck_test.gd` (headless bot soak test), `tools/shot.gd` (screenshot helper), `tools/pms_to_map.py --regen <opensoldat-base>`.

## [1.11.0] — 2026-09-13

Vote system + bonus pickups.

### Added
- **Vote system** (`/votemap`, `/votekick`, `/votecancel`; F1/F2 rebindable; host-authoritative tally; 30s cooldown) — fixes #77.
- **Bonus pickups** (Predator / Berserker / Bulletproof Vest / Cluster Grenades crates, ~30s timed effects, MP-replicated, per-slot respawn) — fixes #78.

## [1.10.0] — 2026-09-13

Spectator mode + kill-streak announcements.

### Added
- **Spectator mode** (follow-cam + free-cam while dead, cycle living players, SP + MP) — fixes #75.
- **Kill-streak banners** (Double Kill → Ultra Godlike, streak-ended feed line) — fixes #76.

## [1.9.0] — 2026-09-13

Weapon HUD, settings/music/controls overhaul, host admin menu.

### Added
- **Weapon-selection HUD** (Soldat LimboMenu: primary/secondary list, green highlight, hover tooltip) — fixes #70.
- **Settings redesign** (glassmorphism accordion; mouse sensitivity, show-FPS, blood intensity, shake slider) — fixes #73.
- **Music** (3 Soldat tracks converted to .ogg, looping, volume/mute) — fixes #73.
- **Rebindable command + GIF keys** (`/` and `F9` promoted to real actions) — fixes #73.
- **Host admin menu** (host-authoritative gravity/friendly-fire/damage/speed/bots/mode/map, live sync, restart match) — fixes #74.

### Fixed
- **Secondary weapon anchor** — back-slung gun now hip→shoulder instead of hanging like a penis — fixes #71.
- **Floating soldiers** — collision box resized to the real sprite and feet-anchored, so soldiers stand on the ground/platforms — fixes #72.

## [1.8.0] — 2026-09-13

Classic maps, bots, weather, MP desync fix.

### Added
- **All 99 classic Soldat maps** ported (up from 10) — fixes #66.
- **Bot count + difficulty** (skill 1–5) — fixes #67.
- **Weather** (per-map rain/snow) — fixes #68.

### Fixed
- **MP RPC desync** (bot grenades + weapon pickups no longer spew node-not-found) — fixes #69.

## [1.7.0] — 2026-09-13

Round-boundary hygiene, gostek fidelity, and MP projectile parity.

### Fixed
- **Clean-slate round reset** (fixes #58). Non-survival modes (DM/TDM/CTF/…)
  now restore every living soldier to full HP/ammo and teleport them to a
  spawn slot when the round timer/score resets, instead of resuming with
  mid-fight state. Dead-and-respawning soldiers keep their existing scheduled
  timer path — no double-spawns. Host broadcasts `net_round_reset` so each
  peer resets its own locally-authoritative body; Survival's wipe-and-respawn
  and the MP `_spawn_networked_player` path are untouched.
- **MP grenade/rocket transform sync** (fixes #61). Projectile physics is now
  authority-owned: only the spawning peer integrates position/velocity and
  broadcasts pos/vel/rot at 20 Hz (unreliable_ordered). Non-authority replicas
  freeze (RigidBody2D kinematic for grenades, skipped integration for rockets)
  and lerp toward the incoming transform, so shooter and victim see the same
  trajectory and impact spot. Authority additionally fires `net_explode` at
  the exact impact position so blasts detonate together.

### Added
- **Front arm tracks aim_dir** (fixes #59). The RIGHT-arm chain (joints
  10→13→16→20) rotates around the shoulder toward aim_dir by a clamped ±16°
  offset — subtle enough that the canned .poa poses still own the base look,
  enough that the gun stops looking detached when aiming steeply up/down. The
  wrist anchor for the weapon sprite applies the same offset so the gun
  travels with the hand.
- **Missing gostek detail overlays** (fixes #60). Ships the outstanding
  detail sprites that were sitting in `assets/gostek-gfx/` but never
  rendered: dreadlocks (`dred.png`) on hair heads, dogtag (`metal.png`)
  hanging from the chain, blood/damage overlays (`ranny/*.png`) that blend
  in as HP drops below 60, a frag/cluster grenade riding on the belt while
  the soldier is carrying grenades, and the inactive secondary weapon slung
  across the back along the spine axis. Menu grows Dreadlocks + Dogtag
  CheckButton toggles alongside the existing Vest/Cigar; bots roll the two
  new looks with the existing random-cosmetics pass.

## [1.6.0] — 2026-09-12

Classic maps, dedicated server, and MP bot combat parity.

### Added
- **10 classic Soldat maps ported from `.pms`** (#53) — Nuubia, Maya,
  Aftermath, Hormone, Viet, Scorpion, Warehouse, Baire, Airpirates, Bunker.
  Terrain polygons converted 1:1 with the original geometry; spawns/flags
  translated into the map JSON schema.
- **Dedicated headless server** (#54). `SoldatReborn.exe --dedicated
  [--port 7777] [--map <name>] [--mode <dm|tdm|ctf|inf|htf|rm|pm|dom|br>]`
  boots without a local player, pre-populates bots, and waits for peers.
- **Bots over ENet** (#55). Host owns bot lifecycle + AI; every client
  spawns replicas via `net_spawn_bot`, streams `net_bot_state` at 20 Hz
  (pos/vel/facing/health/loadout/dead), and mirrors death via `net_bot_die`.
  Joining peers see the full live bot roster in the initial ready handshake.
- **Replicated bot fire** (#57). Host bots broadcast `net_bot_shoot` /
  `net_bot_grenade` so clients spawn matching tracers + rockets + grenades
  and take damage from bot fire. FFA joiners now spawn at a random
  `bot_spawns` slot (not the map corner) so they land in the action.
- **Ported scenery + textured terrain** (#56). Real Soldat scenery sprites
  and per-vertex-UV terrain textures render on top of the polygon geometry
  for the classic map roster.

## [1.5.0] — 2026-09-12

Movement + controls polish.

### Added
- **Fully rebindable controls** via `InputMap` and a new settings screen.
  Bindings persist to `user://controls.cfg`; "Reset to Defaults" restores the
  documented table. Main menu Settings → Controls exposes the rebind screen
  before a match starts.
- **Pause menu overlay** (ESC) with Resume / Settings / Controls / Exit
  without leaving the round.
- **Richer sky + parallax** — dusk gradient, clouds, and four mountain
  layers drifting at camera-relative speeds.

### Changed
- **Movement overhaul** — stance-shape collision swaps for crouch/prone,
  roll burst tuned to beat bunny-hop, jet mods now scale regen + thrust
  consistently, bot AI cleaned up on top of the M2 mount path.
- **Gameplay pacing slowed ~15%** — run 330→280, bunny 640→545, jump
  470→430, jet 1250→1050. Soldat's classic tempo, not floaty.
- **Maps** overhauled with polygon terrain, hills, and tunnels.

### Fixed
- **Jet boots** — thrust 1050→2200 so they actually climb (was weaker than
  gravity, so pressing RMB would slow the fall but never lift you).
- **mod_gravity** applied to grenade fall accel and the M79 arc so the
  gravity slider affects every ballistic path consistently.
- **Pause menu SFX volume** no longer double-attenuated.
- **Main-scene load failure** — `MAPS` couldn't be `const` because it held
  `Vector2()` / `PackedVector2Array()` calls; downgraded to `var` per the
  GDScript 4 parser rules.

## [1.4.0] — 2026-09-12

Level editor + procedural generation.

### Added
- **In-game map editor** (#31). Toolbar to place platforms (drag), spawns,
  flags, and control points (click); move/delete via right-click; middle-drag
  pan and wheel zoom; ESC exit, F5 play-test. Maps save to
  `user://maps/*.json` and are selectable in the menu alongside the built-in
  rotation.
- **Procedural map generation** (#32). Seeded generator produces playable
  layouts for every mode; re-roll from the menu, then **GENERATE + PLAY**
  drops you straight in.
- README refreshed to document the editor + procedural gen flow and the
  full feature set.

## [1.3.0] — 2026-09-12

Retail-quality pass. New modes, modifiers, cosmetics, stats, GIF
recording, plus a full sweep of MP fidelity fixes (weapon-drop desync,
M2 turret sync, bot ammo).

### Added
- **Domination mode** (issue #23). Three control points (A/B/C) on
  each map's ground row. Standing on a point for 4 s captures it for
  your team; each owned point ticks 1 pt/sec into your team's score.
  First to 90 wins. Empty points drain progress back to neutral.
- **Battle Royale mode** (issue #28). FFA with a shrinking ring
  (2200 → 180 px @ 42 px/sec). Outside the zone = 22 dps. Last
  soldier alive wins. Zone radius surfaces in the HUD mode tag so
  players can pace their moves.
- **Game modifiers** (issue #24). Menu sliders for gravity, jet fuel
  regen, weapon damage, and player speed — all 0.5×–2.0× (speed
  0.5×–1.5×). Config-driven via `settings.cfg [mods]`; stock = 1.0×.
  Applied at physics + damage sites.
- **Lo-fi mode** (issue #25). Graphics toggle disables particle
  bursts, gib sprays, ragdoll chunks, and jet flames for low-end
  hardware. Audio cues still fire.
- **Character customization** (issue #26). Menu picker for head
  cosmetic (helm / kap / hair1–4 / bald), chain (none / silver / gold),
  vest, and cigar. Bots roll a random look on spawn so the field
  reads as distinct characters.
- **GIF recording** (issue #27). F9 toggles recording; the recorder
  captures 20 fps to `user://recordings/clip_<time>.gif`, capped at
  300 frames (~15 s). Simplified LZW encoder (re-emits CLEAR to keep
  the code width fixed) — larger files than a full encoder but pure
  GDScript and portable.
- **Local statistics** (issue #29). Stats autoload tracks kills,
  deaths, suicides, shots, hits (K/D + accuracy), wins, losses,
  matches, and per-weapon kill breakdown. Persists to
  `user://stats.cfg`. Menu adds a STATS screen with reset.
- **Improved grenade physics** (issue #30). Bouncier restitution
  (0.55 → 0.72), lower friction (0.4 → 0.18), lighter mass, slightly
  reduced gravity. Grenades now clear platforms and slide down slopes
  rather than dying on first bounce.

### Changed
- **Host-authoritative weapon drops** (fixes #34). Only the host runs
  physics for WeaponPickup RigidBody2Ds; clients freeze locally
  (FREEZE_MODE_KINEMATIC) and receive 10 Hz pos/vel/ang snapshots via
  a new `net_pickup_state` broadcast from Main. Contact detection is
  host-only so both peers agree on who picks up what and when.
- **M2 stationary gun now syncs across MP** (fixes #35). Mount/dismount
  route through Main as authoritative RPCs. Each M2 gets a stable
  `m2_id`. Only the operator's peer reads input; aim streams
  unreliable_ordered at physics rate; fires broadcast reliably so
  bullets appear on all peers.
- **Bots track ammo + reload** (fixes #36). Per-loadout mag size and
  reload timer (AK-74: 30/2 s, LAW: 1/3 s). Firing drains ammo; the
  empty-mag path kicks off a reload. Pickups reset the mag to full.
- **Draw scoreboard explains why** (fixes #37). `_end_round_by_time`
  records a human-readable subtitle for empty-scoreboard, tied, and
  time-up-with-a-leader cases. Rendered as a smaller line under the
  DRAW / WINS banner.
- **Rambo Bow respawn cooldown** (fixes #38). When the carrier dies,
  the bow now waits 4 s before re-spawning at map center — prevents
  the instant re-pickup exploit.

### Deferred (open issues, milestone-scale features)
- In-game level editor (#31) — Soldat 2's crown jewel, its own release.
- Procedural level generation (#32) — large subsystem.
- Ranked matchmaking / dedicated servers (#33) — needs server infra.

## [1.2.0] — 2026-09-12

Retail-polish release. Rounds out Soldat's mode/weapon/movement surface: all
7 main game modes ship, the primary roster is complete, and Soldat's gesture /
chat / taunt loop is playable end to end.

### Added
- **Full Soldat weapon roster (10 primaries + 4 secondaries).** Steyr AUG (4),
  Ruger 77 (6), M79 (7), Barrett M82A1 (8), FN Minimi (9), XM214 Minigun (0)
  join Deagles/MP5/AK-74/Spas-12. Stats derived from `server/configs/weapons.ini`
  (60 ticks/sec → real seconds; damage ≈ `Damage × Speed`; speed ≈ `Soldat Speed × 44`).
- **Secondary slot + Q swap.** Secondaries: USSOCOM, Combat Knife, Chainsaw,
  M72 LAW. Melee (Knife / Chainsaw) sweeps a short forward arc.
- **Barrett / Minigun wind-up.** Both weapons need a short spin-up
  (0.32 s / 0.42 s) before the first shot; releasing LMB resets. Rising-edge SFX
  + shake ramp signal the tell.
- **Crouch (S hold) and prone (X toggle).** Crouch shrinks the collision box
  and slows to 0.6× ground cap; prone flattens further to 0.28×. New gostek
  anims: `kuca` / `kucaidzie` / `kucaidzietyl` / `lezy` / `lezyidzie`.
- **Roll.** Crouch while running fires a short forward burst.
- **All 7 main game modes.** Deathmatch (existing) + Teammatch, Capture the Flag,
  Infiltration, Hold the Flag, Rambomatch, Pointmatch. Realistic / Survival /
  Advance sub-modes wired into the menu chips (Realistic: no jet, no ammo/fuel
  HUD, head-shot 1HK; Survival: no respawns until round ends; Advance: weapon
  unlock ladder starting from the knife).
- **Chat + taunts.** T = global, Y = team, ALT + key = canned taunts from
  `TAUNTS.TXT`.
- **Gesture /commands.** `/victory /smoke /takeoff /kill /brutalkill /mercy` play
  their .poa anims (or gib the player, for the suicide variants).
- **Weapon throw / pickup.** F drops the active weapon as a physics item that
  other soldiers can pick up.
- **Ceasefire spawn protection.** 3 s of invulnerability with a pulsing cyan aura.
- **M2 stationary gun.** Per-map mount points with a clamped-elevation turret.
- **Extra weapons.** Flamethrower, Rambo Bow, Cluster grenade.
- **Bink.** High-Bink weapons punish a victim's aim on hit.
- **Networked hosting.** Host-authoritative teams, flag-state RPC, mode entities
  spawned on both peers so scoring stays in sync.

### Changed
- Primary hotkeys extended to `1..9,0`. LAW moved from primary #5 to the
  secondary slot; Spas-12 is now primary #5. HUD, menu footer, README updated.
- `net_state` / `net_shoot` RPC signatures extended for secondary slot + stance.
- Soldier rescaled to exact Soldat 1:1 (`POA_TO_PIXEL` 2.4→1.0); collision box,
  jetpack, muzzle flash, HP bar, jet flame all rescaled to match.
- Maps enlarged to 4800×2000; all three layouts redesigned; camera limits track.
- Kill feed colors names by their actual team, not "us vs. everyone else".

### Fixed
- Bots gate shots on line-of-sight (no more shooting through terrain).
- Bot respawn shifts horizontally if an enemy is standing on the slot.
- Death HUD shows the real respawn delay, not a hardcoded 2 s.
- Menu version and subtitle labels no longer overlap.
- Chainsaw honors its ammo count and reload.
- Survival respawns are correctly gated on `round_active` (MP + suicide paths).

## [1.1.0] — 2026-09-12

Interim scale/asset pass — see git history `574781d..5cc6e7a`. Highlights:
Soldat 1:1 sprite scale, weapon grip pivots, death screen + team arrow, mouse
crosshair, full 21-weapon roster kickoff, larger maps, RMB jet default.

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
