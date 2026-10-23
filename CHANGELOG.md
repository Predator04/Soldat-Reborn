# Changelog

All notable changes to Soldat Reborn.

## [Unreleased]

### Added — reserved names (#318)
- **Nobody can play under your name any more.** Settings → Game has a **RESERVE MY NAME** button: your name is reserved on the master server against your player profile, with a clear status (reserved / not reserved yet / taken by someone else / offline). Online servers that list on the master check every joining name; someone else joining under a reserved name — also spelled differently, like "4l1ce" for "Alice" or with other capitals — plays as **Player####** and is told why in chat. No more AntiFake scripts.
- One reserved name per player, changeable every 3 days. Offensive names and the names the game uses itself (Player…, Bot…, SERVER) can't be reserved. Clan tags don't count towards the name.
- If the master server can't be reached, players get in under their own name (nothing is blocked by an outage). Server admins can turn the check off with `reserved_names = false` in server.cfg.
- Needs the updated master server (the `/names` API); older master servers simply have no reserved names.

### Added — new-player protection (#315)
- **A light catch-up for players who keep getting crushed:** after **3 deaths in a row without a kill** you take **10 % less damage** (15 % after 4, 20 % from 5 on — at most a quarter more staying power) until you score your next kill. A toast tells you when it's on. Decided by the host, so it's the same for everyone and can't be faked.
- **Measured with bots** (catch-up switched on for bots just for the test, 8 classic maps x 3 runs x 3 minutes, each run played with it off and on): between equal sides nothing changes — blue's share of the kills in Teammatch 52.1 % off / 51.8 % on (paired difference +0.8 ± 4.1 points), kills per minute 22.8 / 23.8 (paired +0.1 ± 3.0). A clearly outclassed player (a Deathmatch bot with skill-1 reactions, a wide aim cone and a slower trigger) goes from 0.11 to 0.19 kills per death and from 1.8 % to 2.9 % of the kills, better in 15 of 22 paired runs; everyone else's K:D stays 1.08 / 1.07. It softens a beating; it doesn't turn one around.
- Never for bots, never in Gun Game. On by default for hosted games and dedicated servers; turn it off with "Catch-up for new players" on the Host screen or `catchup = false` in server.cfg (for competitive events).

### Added — standalone dedicated server download (#320)
- **Run a server without the game.** Every release now also has `TracerfallServer-windows.zip` (47 MB) and `TracerfallServer-linux.tar.gz` (37 MB): a headless server with the graphics and music stripped out (36 MB of game data instead of 168 MB; the full game exe is 277 MB). Unpack, run `start-server.bat` / `./start-server.sh`, done — see `HOSTING.md` inside (ports, admin, service, updating). The game's own downloads (`SoldatReborn.exe/.apk/.pck`) are unchanged.
- **Runs at boot:** `install-service.bat` (a Windows scheduled task, nothing extra to install; output in `logs\server.log`) or `sudo ./install-service.sh` (systemd unit, `--auto-update` optional).
- **Updates itself safely:** `update-server` downloads the latest server archive from GitHub only when it is newer, refuses anything not signed with the game's release key (checked by the installed server), checks the new version really is that version, keeps your `server.cfg` and the old files (`_update/previous`). Needs Python 3.
- The server keeps its own data folder (`TracerfallServer`, printed at start), so hosting on your gaming PC never touches your game settings.
- Measured, Ascent CTF with 8 bots: about 22 % of one core and 217 MB RAM on the server download vs 21 % / 225 MB for the full game run headless — headless already skipped the graphics work, the gain is the download and needing nothing of the game.

### Added — server.cfg for dedicated servers (#317)
- **One config file for a dedicated server:** name, port, master-server listing, message of the day, admin password + admin list, map / mode **rotation** (`rotation = Ascent:ctf, Nuubia:ctf, Arena:dm`, optional random order), end-of-match vote on/off, time limit, score limit per mode, respawn times (incl. Infiltration attackers), Realistic / Survival / Advance, friendly fire, bots / skill / fill, power-up crates and kits (count, respawn), weapon bans, vehicles, modifiers, vote settings. Every key is explained in `server.cfg.example`. `--config <file>` picks another file; command-line flags still win.
- A line the server doesn't understand (unknown key, bad value) is printed in the log and skipped — the server always starts.
- **In-game admin on dedicated servers:** `/login <password>` (or be listed by `/myid` in `admins`), then the host commands work remotely: `/map`, `/gamemode`, `/restart`, `/next` (next rotation map), `/addbot`, `/bots`, `/kick`, `/say`, `/ff`, `/votecancel`, and **`/reloadcfg`** — applies most settings at once and the map-level ones on the next map, and says which.
- Fixed: a dedicated server's `/say` lines never reached players, and joined players ran their own Realistic / Survival / Advance choice instead of the server's (the host's sub-modes and respawn delay now reach every player).

## [1.40.0] — 2026-10-22 — Bomb Defusal

### Changed — game mode limits and map balance (#311)
- **Matches last longer and are decided on score.** Measured with bots, every mode hit its old limit in 1–3 minutes, so a 5-minute match was 2–5 short rounds and usually ended on the clock. New limits: Deathmatch **50** kills (was 20), Team Deathmatch **120** (was 20), Hold the Flag **300** (was 60), Pointmatch **200** (was 20), Domination **800** (was 90), Rambomatch **25** (was 20); Capture the Flag and Infiltration stay at 3. The match clock is now **15 minutes** (10 for Battle Royale and Gun Game; was 5 for every mode). Bot test matches (8 bots) now end on score after about 8–12 minutes (Gun Game 5–7, a ladder or two); fewer players take longer. Capture the Flag ends on score where bots capture, and on the clock on maps where they rarely do.
- **One round is the match:** a round that used at least half the clock ends the match (winner screen + next-map vote). A quick blowout still gets a rematch on the same map with the time that's left.
- **Bots: one rocket launcher per team.** In team modes only the last bot spawned (always a red one) carried the LAW, which tilted every bot match towards red (red won 26 of 32 Team Deathmatch rounds over 15 maps); now the last bot of each side has one (16 / 13).
- **Fairer objectives on side-heavy maps** (spots only, no terrain changes): the Hold the Flag flag on **Shau**, **Outpost**, **Fortress** and **Viet** (bots scored 100 % / 28 % / 14 % / 22 % for blue before, 60 % / 44 % / 38 % / 48 % after), the blue Capture the Flag flag on **Fortress** (captures 7–38 → 6–6) and the Domination points on **Blox** (blue scored 81 % → 42 %).

### Changed — weapon & vehicle balance (#310)
Measured first: thousands of duels at fixed distances against standing and strafing targets, plus 60 minutes of bot matches with every gun in equal use (Deathmatch, Teammatch, CTF and Bomb Defusal on classic and featured maps). Only the guns and vehicles that stood out for their role changed, each by a small step; movement, jets and soldier health are untouched.
- **LAW: 90 → 115 damage.** A rocket into the body now kills, like the classic LAW; before, a direct hit left the target alive (~83 damage) and it was the slowest gun to get a kill at any range. The blast still falls off, so a near miss doesn't kill.
- **M79: 90 → 115 damage, shell speed 470 → 640 (the classic speed).** A direct hit kills, and the grenade now reaches mid range: before, it couldn't land a shell 230 px away on flat ground.
- **Spas-12 reworked: a real close-range killer (#310, #322).** A tighter pellet fan (±0.26 → ±0.10 rad) and 9 → 17 damage per pellet, with pellets losing damage past ~160 px (down to 35 % at 420 px and beyond). Up close one shot now kills (out to ~150 px), at 200 px it still beats the rifles, and from 300 px on the rifles win. Before, most pellets missed anyone more than a few steps away — it took two or three shots even point-blank.
- **Steyr AUG: spread 0.075 → 0.05.** It's the accurate rifle now (as in classic) and beats the AK-74 at long range; the AK still wins up close. Before, the AUG was worse than the AK at every distance.
- **MP5: 13 → 15 damage.** The SMG holds its own up close (it lost to the AK-74 even at 100 px).
- **Minigun: spread 0.3 → 0.24.** Still a hose with a spin-up, but it kills at close range instead of spraying past the target.
- **Tank: explosives now do full damage (were 80 %).** It still shrugs off bullets (20 %), but it now takes 8 LAW hits instead of ~13 — in the test matches no tank was ever destroyed.
- Bots use exactly the same gun numbers as players now (damage, speed, magazine, reload come from one table).

### Added — Bomb Defusal (#304)
- **New game mode: Bomb Defusal** (mode 10, at the end of every mode list; dedicated `--mode bomb`). RED attacks, BLUE defends, and the sides swap at halftime (after round 6). The attackers carry one bomb to site A or B and plant it (hold **Use** 3 s in the site, standing still — moving or jetting starts it over, getting shot doesn't); the defenders stop them, or defuse a planted bomb (hold Use 7 s on it). A planted bomb beeps faster and faster and blows after 40 s with a big blast around it. A round ends on a detonation (attackers), a defuse (defenders) or the 2:30 clock running out with no plant (defenders); first to 7 rounds wins the match (then the usual winner screen + map vote). The dead come back together in **waves every 10 s** (the death screen counts down to the next one); a new round respawns everyone at once. The carrier drops the bomb where they die; any attacker picks it up, defenders can't.
- **New control: Use / Plant / Defuse** — C on the keyboard, Y on a gamepad (shared with Reload — reloading while you plant is harmless), remappable in Settings → Controls; on touch screens a USE button appears only when it can do something.
- **HUD:** site markers A / B in the world and as off-screen arrows, the bomb's position (carried / dropped / planted), the round + side line, the fuse countdown, a plant / defuse progress bar, the "hold Use" hint, the next-wave clock and big banners for plants, defuses, detonations, round results and halftime. Sounds from the existing set (plant, beep, defuse, explosion).
- **3 featured levels built for it** (FEATURED tab, PLAY / HOST ONLINE / EDIT A COPY): **Downtown** (street site + market-roof site, jump pads, a jet across to the attackers' plateau), **Dust Yard** (loading-dock site + covered-warehouse site, containers, a silo) and **Whiteout** (trench site + ridge site in the snow, an ice tower). Bots carry the bomb to a site, plant, guard it, retake, clear the site and defuse; every map gets two sites placed automatically along the bots' route when it has none of its own.
- **Maker: Bomb site A / Bomb site B** pieces (Objectives tab, resizable areas). The checks before PLAY / SAVE want both for Bomb Defusal, inside the map and over ground you can stand on; the Maker's test mode can be Bomb Defusal. Maps store them as `bomb_sites`; shared levels with both are tagged BOMB.
- Online: the host decides everything (who carries the bomb, plant / defuse progress, the fuse); a player only says "I'm holding Use" for their own soldier, so a modified client can't plant or defuse for anyone. Players joining mid-round see the planted bomb and its fuse right away.

### Changed — Bomb Defusal balance (#307)
- **Attack and defense are much closer to even.** Bot matches showed the defenders winning most rounds: they respawned close to the sites every 10 s and retook almost every planted bomb (Downtown and Dust Yard: about 1 round in 6 for the attackers). Once the bomb is planted, the **defenders' respawn waves now come every 15 s** (the attackers' stay at 10 s), and the NEXT WAVE clock shows your own team's wave.
- **Downtown:** site A is 300 px further down the street (cover and the roof pad moved with it) and site B is on the far half of the market roof. **Dust Yard:** the loading dock (site A) moved 560 px toward the middle and is now a step up on both sides, and the warehouse (site B) moved 300 px. **Whiteout:** the ridge with site B moved 150 px toward the defenders. Bot matches now go from roughly 1-in-6 to 2-in-5 or better for the attackers on Downtown and Dust Yard, and Whiteout stays around even.
- **Arena2 / Arena3:** the site that sat on top of the defenders' spawn moved off it (bots could hold it against defenders spawning into the bomb).

### Fixed — Bomb Defusal
- **Bots reach the bomb sites on every map (#308).** Maps without their own sites now get them on spots both teams can actually walk to from every spawn, on the way between the bases, not on top of either base, and placed by walking distance so neither side is next door. Argy got hand-placed sites in the lower tunnel the attackers really use (the old ones sent the bomb carrier through a cave nobody climbed back out of).
- **Replays show the bomb (#309).** Bomb Defusal replays now record the sites, who carries the bomb, where it was dropped or planted, the fuse and the plant / defuse progress, and the replay viewer draws them like the live game: the A / B sites (red when the bomb is planted there), the bomb on the carrier's back / on the ground / planted with its blinking light, a status line (round, carrier, fuse) and a progress ring over the soldier planting or defusing. Older replays play as before.

### Fixed — online
- **Joining a match in progress now shows other players' active power-ups (#305).** A Predator was not see-through, a Berserker not red, etc. for someone who joined after it was picked up, until it ran out; the server now sends each player's active power-up and the time left as part of joining.
- **Dedicated servers no longer crash now and then (#313).** About one headless run in a hundred (dedicated servers, test runs) died with a segfault on the audio thread, logged as "caller thread can't call propagate_notification on /root". It was a race inside Godot's sound mixer while sounds play; a server has no speakers, so headless runs now play no sounds at all (they are still counted for the tests). Nothing changes for players with sound.

### Improved — telling the teams apart (#306)
- **Friend and foe now read at a glance (#306).** In team modes every soldier wears big panels of strong team paint — helmet, plate carrier, shoulder pads and an arm band, neck gaiter, cap, vest front, jetpack cover — in a clear cyan-blue or red-orange (the blue side lighter, the red side deeper), so the teams stay distinct on night maps, in smoke and explosions, on the HD terrain and on a phone screen. Your helmet and vest paint still show on the rest of the helmet / vest, and in free-for-all modes (Deathmatch, Rambo, Battle Royale, Gun Game) everyone keeps their own colours.
- **Thin team-coloured outline on every soldier in team modes** — a bit stronger on enemies than on your teammates. It works on every graphics preset, Low included, and in the classic soldier look, where the helmet and vest now also take the team colour.
- **Teammate markers:** a small chevron in your team's colour floats over each teammate, with their name while they're near you. Enemy names only pop up when you aim at them or they get close (never for someone cloaked by the Predator power-up).
- **Settings → Video → Team colours:** Classic (blue vs red), Colour-blind (blue vs orange) or High contrast (cyan vs magenta-red, stronger outlines). It applies at once, mid-match, to soldiers, outlines, markers, vehicles, flags, the score strip, the kill feed and objective markers. (Replaces the old "Colour-blind friendly teams" switch; your choice carries over.)

### Changed — online hits are decided by the host (#266)
- **Online hits are now decided by the host** (the server), not by the game of the player being shot. Your shots, tracers, sounds and hit markers still show instantly on your screen; the host checks each shot against where its target was *on your screen* when you fired (it rewinds by your connection's delay, measured shot by shot), so your hits land just like before — the release tests play scripted duels at 50–250 ms ping with jitter, packet loss and lag spikes, with every kind of weapon (rifles, shotgun pellets, knife, rockets, grenade launcher, grenades, the buggy gun) against strafing, jetting and driving targets, and require the host to refuse nothing an honest player does and to confirm what the shooter saw (typically 90–99 % of the hits, every one for the weapon's normal damage). Weapons, damage, fire rates, movement, bots and single player are unchanged.
- **Closes the cheats that used to slip through:** a modified game can no longer take only part of the damage (or none), deal more damage than the weapon does, fire faster than the weapon or past an empty magazine, spawn its bullets next to someone or through a wall, shoot in a direction it isn't aiming, or jet on an empty tank. The host refuses or corrects each of these, logs it, and after repeated offences removes the cheater's soldier (three times in five minutes is a kick). One odd event never kicks anyone.
- Your health on screen comes from the host: a hit shows when the host confirms it (about the same moment the old system applied it), and medikits / the Rambo bow's regeneration keep working as before. The Battle Royale ring's damage is applied by the host too.
- Online games need the same update on both sides: an older build gets a clear "Version mismatch … online protocol" message when it tries to join (and the other way round), instead of joining and misbehaving.
- A small fix along the way: the old fire-rate check on the host (#243) could drop real shots when the network delivered several at once; shots now carry their own timing, so a lag spike no longer eats them. The same goes for vehicle guns, turrets and helicopter rockets (a lag spike could swallow a rocket salvo), and a fast-moving buggy's gun is no longer refused for being "away from the gun".
- Shooting at someone driving or riding a vehicle: the host now tests the vehicle where you saw it as well as its crew, so your rounds no longer stop on a hull that, on your screen, wasn't there yet.

## [1.39.0] — 2026-10-21 — Featured levels

### Added — drop your power-up (#303)
- **You can now drop the power-up you're carrying (#303).** Press **B** (gamepad: the **Share** button; Android: the small **DROP** button that shows up next to PRONE while you have one). Dropping simply ends it — nothing is left on the ground, so nobody (you included) can pick it back up for a fresh 30 s. Predator and Berserker stop at once (no more see-through look or knife lock, your previous weapon comes back), the Bulletproof Vest stops halving damage, and Cluster Grenades go back to the grenade type you had before. The box you took it from still comes back on its usual timer. You carry one power-up at a time, so drop ends that one; with none active the key does nothing. A short "PREDATOR dropped" toast confirms it and the power-up timer disappears. Rebind it under Settings → Controls (Combat); it's also listed in the in-match controls help (H).
- Online it's the server's call, like picking one up: it checks the request is for your own soldier and only while you have a power-up, then ends it for everyone.

### Fixed — vehicles (#302)
- **Bot drivers stop at the end of the road instead of driving into the trap there (#302).** A bot at the wheel now looks ahead along the ground for a slope too steep for the wheels, a crack the wheels would drop into, a drop the vehicle would wedge in or couldn't drive back up from, or the void, brakes in time and gets out to carry on on foot — the vehicle stays parked there, ready for someone heading the other way. Bots also only take a vehicle that has a real stretch of road toward where they are going. Before, they drove into the same spots on Viet, Warehouse, Laos, Lanubya, Shau, Star, Triumph and Outpost every life, got stuck, gave up and the vehicle was sent home.
- **More vehicles bots actually use (#302).** Dusk's blue buggy now waits on the lower floor by the blue base instead of the high arc no bot could reach; Moonshine's red tank and Outpost's blue tank moved off the unreachable ridges to the long stretches near their bases; Rescue's blue buggy moved from the tower roof (a dead end) down to the valley; Laos's red buggy moved from the ledge in front of the shaft (its road ended 240 px later) down into the lower tunnel, where it can drive almost to the blue base. Blade's bottom lane, Dusk's two arc tanks and Warehouse's tunnel / roof buggies stay where they are: they are player routes (bots never pass there and couldn't drive anywhere useful from them).
- **Bot plane pilots no longer loop into the side of the world when slow (#302).** A slow pilot turning back at the edge of the map pulled up over the top instead of diving under as planned, stalled short of the loop and fell back into the side wall; it now rolls the nose the way the turn was planned, looks further ahead the slower it flies, and only climbs over a wall ahead when it has the speed to. Pilots also no longer make strafing runs at soldiers standing right in front of a wall (on Industrial they dived at bots by the tower's west door and pulled out into the tower).

### Fixed — online + bots (#293)
- **Bots no longer die on the edge of Maker spikes / lava when they come down toward the strip** (#293): a bot crossing a hazard that was falling with ground just below used to "land first" instead of holding its height, and set its feet a few pixels short of the edge — inside the kill zone's margin. It now keeps jetting across.
- **A lagging player is no longer killed by the server's cheat checks** (#293): on a struggling server or client, a medikit heal could reach the host after its 2-second window (5 "hp clamp" strikes = forced death), and hits the host saw could arrive before the client had applied them ("ignored damage"). A granted heal now counts when it shows up (within 10 s, once), and "ignored damage" must hold for 3 s / 10 state updates before it acts — a client that really ignores damage is still caught.

### Dev — release gate on a busy machine (#293)
- **No more false FAILs when several gates share the box.** Each gate run now has its own user-data folder and its own LAN discovery port (parallel runs deleted each other's replays, heard each other's servers — Quick Play joined one — and the second LAN listener couldn't bind), and picks free game / master ports instead of random ones.
- **Timeouts and waits scale with the machine's load** (measured at the start and per step, up to 4x); dedicated servers print `Dedicated match ready` once the match is loaded and the gate starts its clients on that line; smoke-client windows, `selfcheck.py`, `mp_soak.sh` and the tests' own deadlines stretch with `GATE_LOAD`. Measured limits never stretch.
- **F `perf` measures the main thread's CPU time per frame** (seeded, same fight every run) instead of wall-clock frame gaps, which mostly measured other processes: ~5 ms whether the box is quiet or loaded, where the wall average swung from 6 to 58 ms. `PERF_INJECT_MS=10` (10 ms of extra work per frame) still fails it.
- **F `rtnav`**: the stall check times the graph adoption itself (`main.nav_adopt_ms`) instead of raw frame gaps (400–2000 ms under load), the build deadline scales with load, and "graph present before the runtime build" is checked on the match's first frame (it waited 3 frames, and a fast worker could finish in between).
- **F `features`**: a bot kill right before the limbo step held the respawn for the kill-cam rewind, and the next step reset the limbo pick before it was checked ("limbo pick not stored") — the later steps now wait too. **F `radio`**: stages the flag grab after 60 s without one (a random match sometimes had no grab for 150 s). **C `fill` / `two`**: the second client starts once the host has the first.
- More flakes fixed at the root: F `grenade` (the player sometimes spawned on a cluster bonus box — cluster fuse 1.9 vs frag 2.2 read as "0.3 s short"; the expected fuse now follows the grenade thrown), F `vart` (shells / bombs in flight and a respawned bot counted as node growth; the test's own rockets and wreck blasts shoved the parked plane, which rolled on — parked vehicles now start every state at rest, and none may move in a non-firing state), F `featured` (CTF pad routes are spawn -> enemy flag; bot-planned pad rides count), C `relay` (the smoke client retries an unreachable relay and the FAIL line says why), F `unlock` (the switch to the test gun can be refused mid-reload; the trigger is held until an own bullet appears), C `two` (the botfire client was often dead at the second client's final look; bodies seen during the whole window count), C `news` (the menu's single news fetch hit a master not yet listening; the gate waits for masters over HTTP), F `rtnav` `maker_basin` (Domination holders stand still: a third of the bots must travel).
- `SERVER_DIR` points the master-server cases at the server checkout (default `../server/master-server`, found automatically from a git worktree).

### Added — featured levels (#295)
- **LEVELS now opens on FEATURED: 8 hand-built levels that come with the game**, so there is always something to play — even offline, with no level server at all. Each one shows its outline, the modes it was built for, PLAY (a bot match), HOST ONLINE and **EDIT A COPY**, which opens the level in the Map Editor as a new, unsaved map with every piece editable — take one apart to see how it works, or make it your own.
  - **Twin Forts** (grassland, CTF / HTF / TDM / DM) — a mirrored CTF arena: hilltop forts, a sky route of floating islands, a jump pad up from the valley.
  - **Magma Crown** (desert, DOM / TDM / DM) — king of the hill between two lava pits, crossed on broken plank bridges.
  - **Skyline Tower** (urban, HTF / TDM / DM) — jump pads launch you up a zig-zag tower to the flag on the roof.
  - **Iron Valley** (jungle, TDM / CTF / DM) — wide-open vehicle warfare: every base has a buggy, a tank, a helicopter pad and a plane on its runway.
  - **The Bunker** (night, DM / RM / TDM / Gun Game) — three tight decks under a concrete roof, ladders and shotguns.
  - **Frostbite** (snow, CTF / INF / TDM / DM) — two peaks over a bottomless chasm, one ice bridge and a frozen pillar between them.
  - **Hollow Deep** (cave, DOM / CTF / TDM / DM) — stalactites, spike pits, ladders and three points to hold.
  - **Last Ridge** (grassland, Battle Royale / DM / Gun Game) — a big ridge with corner towers, bunkers and loot everywhere; the ring closes on the summit.
- **Maker: FILE > New map asks what to start from** — Empty, the Starter strip, or a copy of any featured level.
- Gate F test FEATURED-TEST: every featured level loads, validates, passes the map audit and the bot-navigation check for all its modes, the tab works offline, PLAY / HOST ONLINE / EDIT A COPY / Start from work, the new texts are translated, and bots play each level (travel, objectives, jump pads, vehicles, no hazard deaths to speak of).

### Fixed — bots on Maker maps (#296 #297)
- **Domination no longer freezes with every bot piled on one point** (#296). Bots of both teams walked to the exact centre of a contested point and stood inside each other; a shot starts at the muzzle, past a body that close, so nobody was ever hit, the point never changed hands and the match stood still (Magma Crown's hilltop, all 8 bots). On a point, a bot now keeps a point-blank enemy at gun range — each side backs off the other but stays on the point. A lava pool's rock basin merging with the ground under it was never the cause: the merged outline gives the same collision and the same bot graph, so Magma Crown's 3 px gap between them is gone.
- **Bots no longer jet into the underside of a platform hanging over them** (#297). A climb onto a floating island / slab 300–560 px over walkable ground was linked straight from the ground under it (the "step out past the lip, jet up beside it" detour was checked, but the link went straight through or along the platform's body), and bots under it jetted at its underside again and again. Those climbs now walk out past the lip first; a bot that finds a platform right over its head (after a fall, or chasing someone on top) walks out from under it instead of jumping or jetting into it. Bots also no longer give up on a tall climb while refuelling for it — the "I'm stuck" escape used to fire mid-refuel and jet off in a random direction, burning the fuel they were waiting for.
- Gate F `rtnav` gains `maker_basin` (Magma Crown with the basins merged, Domination: same graph as separate shapes, no blue and red bot standing inside each other on a point, kills) and `maker_overhang` (an island 420 px and a slab 340 px over flat ground: no climb link starts under them, no bot keeps hitting an underside, an attacker gets onto the island).

### Changed — planes and jump pads (#294)
- **Bots fly the planes on Fortress now.** Fortress's two planes moved from the far ends of the map to the raised strips right beside the keep (they take off outward and turn back over it), and bots will walk a little further to grab a free plane: when their trip is long and the plane takes off their way, or simply to fly an attack run when nobody on their team is in the air. In three 3-minute bot CTF matches bots took off in the Fortress planes 15 times (once in nine matches before) and never flew one into the ground; Industrial plays as before. Bot pilots also stop circling over a target they can't see (inside the keep): they bail out over their goal and drop in.
- **Bot pilots go for the flag instead of flying around for minutes** (#298). A bot flying to an objective (the enemy flag, its own flag to bring back, a flag carrier, a Domination point, home to defend) dogfights for the first 20 seconds, then bails out the next time it passes over the objective — enemies around or not — and after 35 seconds stops chasing targets and heads straight there. Pilots no longer climb to the top of the sky and circle there, and no longer turn back for a weapon lying on the ground below. On the Iron Valley test level the longest sortie went from 150 s (the time limit) to under a minute, and bots grab the enemy flag more often; bots out hunting still dogfight as long as they like.
- **Outpost no longer has a plane.** Its runway sat on top of the ridge, where no route leads on foot — not for bots and not really for players either. Runways are now only placed where every team can walk to them.
- **Abandoned planes go home.** A plane a bot pilot left (bailed out over its goal, or gave up on a take-off) and that came to rest somewhere is back on its spot about 8 seconds later instead of sitting there for a minute.
- **Bots no longer get flung around by jump pads they're only walking past** on Maker levels: they hop over a pad that isn't on their way up, and pick routes that don't cross pads when there's a reasonable alternative. Before, a bot crossing a pad got launched — often again and again, bouncing in place (a bot that lands on a pad it doesn't want now steps off it).

### Fixed — vehicles (#300)
- **Buggies and tanks can no longer be thrown out of the map (#300).** Driving over a grenade or a dropped gun could fling a vehicle up to 2,000 px into the sky (seen on Ascent, Industrial, Bigfalls, Boxed, Dusk, Erbium and Bridge): the wheels briefly rested on the item and the vehicle took over its (squeezed) speed when it rolled off. Vehicles now ignore the motion of anything they roll over.
- **Bot helicopter pilots no longer fly into cave ceilings (#300).** On cave maps the bot pilot climbed into the rock above it (or into a shaft narrower than its rotor) and wrecked the helicopter again and again — Abel's helicopter was destroyed about every 45 seconds. Pilots now keep the rotor clear of anything overhead, see walls early enough to stop (at skid, cabin and rotor height — including the walkway-only rock they used to fly straight into on Cobra) and brake instead of drifting into them, back out from under an overhang to climb over it, and land and get out when there is no way round. They also no longer hover for good under a ceiling: chasing an enemy standing on top of the rock above them, limping home under a low roof, or sitting on the ground somewhere too low to lift off. Abel's helicopter now flies most of the match without crashing.
- **Helicopters no longer sit unused after their first flight (#300).** Once a bot had landed one, every later bot pilot got straight back out of it again; a new pilot now always starts a fresh flight. Bots also board a helicopter parked on a slope or a ledge edge.
- **A vehicle a bot gave up on no longer sits in the same trap for a minute (#300).** When a bot driver leaves a buggy or tank because it is stuck or facing a drop it can't take, the vehicle now drives home after 12 seconds instead of 60, and bots leave it parked at home for a while instead of driving it straight back into the same spot (Viet's bridge, Warehouse's cliff crack, Laos, Lanubya).

### Fixed — training (#301)
- **Movement Course step 4 (Prone drop) is passable now (#301).** What went wrong for a real player: the steps before it teach jumping, and jumping off the ledge — especially holding jump for a full jump, as step 3 just taught — made every X press in the air silently undo itself (a held jump stood the soldier straight back up), so the step kept saying "TOO LONG — Press X in mid-air" however he pressed; even a prone that did register couldn't land in the ring after a jump. Pressing X just before the edge laid him down on the ledge so he crawled off and fell short, and only presses within ~0.37 s after leaving the ledge passed. Now holding jump in the air no longer cancels prone (only a fresh jump press does; on the ground jump still stands you up), a press up to 0.25 s before the edge counts as going prone the moment you leave it, the ring reaches a little further (prone up to ~0.45 s after the edge passes), the step says "don't jump", a big PRESS X / PRONE cue shows over the fall, and a miss says what happened: you jumped off, you went prone on the ledge, you went prone 0.52 s after the edge, X didn't register in the air, or a second X / jump press stood you up. Gate F `course` now sweeps the press timing (0.30 s before to 0.60 s after the edge), hop / jump approaches and double presses.

## [1.38.1] — 2026-10-20 — Hotfix

### Fixed
- **Buggies no longer get wedged at the Ascent tunnel mouth (#299).** Bots drove the blue buggy off the second hill's plateau into the narrow slot between its cliff and the tunnel mountain, where it hung nose-up against the rock every match (and bots kept climbing back into it, so it never went home); the red buggy ran into the tunnel's dead end right under it. Now any buggy or tank that is stuck in one spot for 4 seconds without a floor under it (or tipped over) is sent back to its spawn, crewed or empty — anyone inside steps out first, clear of the rock. Bot drivers brake before a drop that would land them on a face too steep to stand on and get out, and bots leave a vehicle they gave up on (stuck, or at a drop like that) alone until it has driven home. Helicopters and planes are not affected; vehicles that are moving or parked on the ground are never touched.

## [1.38.0] — 2026-10-19 — Planes

### Dev
- **Trailer tool (#263):** `tools/make_trailer.sh` renders a ~66 s 1080p60 gameplay trailer (+ 720p web copy), a 30 s vertical cut, key-art screenshots and the itch.io cover from staged bot matches with Godot's Movie Maker (`tools/trailer.gd` director: highlight-picked fights, jet chases, explosions, buggy / tank / helicopter / plane, a flag capture, Maker building a level + PLAY, the LEVELS browser; `tools/trailer_edit.py` picks each shot's best window from the event log and cuts / mixes it with ffmpeg). Gate F `trailer` (TRAILER-TEST) runs the director headless.

### Fixed — Android BACK button
- **The phone's BACK button (and Esc on PC) now always closes what's on top first** instead of throwing you out: in the map editor it closes the Publish dialog, the LEVELS browser, the load list, open drop-down lists, the context menu, the problems list and the Open sheet (then un-arms a piece / clears the selection) before leaving the editor; in a Maker test match it closes the pause menu, its Settings or quit prompt one step at a time, the chat line and the touch-layout editor, then goes back to EDIT; in the main menu the server browser goes back to Join, an open drop-down list closes before its screen, and the name prompt, update, WHAT'S NEW and connection-lost dialogs close (the first-launch name prompt stays) — BACK no longer quits the game from under any of them. In a match the pause menu's sub-screens step back one at a time too, and BACK now leaves the replay viewer (it did nothing before). New gate F test BACK-TEST.

### Fixed — dedicated servers
- **Dedicated servers no longer build the main menu before they start listening** (#278 #285 #289 #290): `menu.tscn` is only the project's main scene, so a `--dedicated` boot used to build the whole menu (backdrop shader, logo, fonts, every screen, news / LAN browser) for one frame before switching to the match. The server now prints `Dedicated server starting: Tracerfall <version>, port N` first, skips the menu, and when the port can't be opened says so on stdout (`DEDICATED-START-FAILED ... is another server already using UDP N?`) and exits 1 — an engine `ERROR:` line on stderr was all there was before, which log scrapers looking for `SCRIPT ERROR` read as "no error line". Gate C `dedboot`: boot from a never-imported checkout + busy-port case.

### Added — Discord status (#223)
- **Your Discord profile shows what you're playing** (Windows / Linux, Discord desktop app): "Playing Capture the Flag on Ascent" with the score ("Blue 3 – 2 Red", your score, or your Gun Game rung), elapsed time, a mode badge and the party size in online games — or "In the Maker editor", "Browsing levels", "In menus". Built in pure GDScript over Discord's local connection: nothing extra to install, no native plugins, never slows the game (it talks to Discord on a background thread, at most one update every 4 seconds). Turn it off in Settings → Game → **Discord status**. Phones and dedicated servers never run it. It goes live once the game's Discord application id is filled in (docs/discord/SETUP.md). New gate F test DISCORD-TEST.

### Added — itch.io (#224)
- **Page kit for itch.io** (docs/itch/): page text, tags, genre, theme colours matching the game, cover and screenshot list, a release-notes template and a step-by-step guide. **One-command uploads with butler:** `python tools/itch/push.py` pushes the Windows exe and Android apk to their itch channels with the game's version (optional server pack); `publish.bat` does it automatically after the GitHub release once butler and the project target are set up — and it can never make the GitHub release fail. Gate A checks the script with a fake butler.

### Added — self-check
- **`tools/selfcheck.py` / `tools\selfcheck.bat`** — the unattended self-check now lives in the repo (#278 #285 #289 #290): pull, import, dedicated server on a free port, a joining client and a bot-fire client, the whole process tree killed afterwards, a private user dir, `SELFCHECK PASS|FAIL <kind> <sha>`, logs in `build/selfcheck/`, and with `--report-github` ONE `[selfcheck] failing` issue that is commented on while it fails and closes itself on the next pass. Gate C `selfcheck`.

### Added — bots on Maker levels (#287, #286)
- **Bots use jump pads.** On a Maker level, bots now know where each jump pad (and big jump pad) can throw them and take the pad when it's the way to go — a flag or a fight up on a high floating island, for example. They walk onto the pad instead of jumping or jetting off it (which used to cancel the launch) and steer onto the landing in mid-air. Levels without pads play exactly as before. Bots also board and use the tanks and helicopters you place on a Maker level, like the buggies. (#287)

### Added — planes (#291)
- **Planes: a fast fighter you (and the bots) can fly.** Walk up and press F. It flies like a plane, not like the helicopter: **W / S** move the throttle lever (it stays where you leave it), **A / D** pitch the nose — or just point: the nose follows your mouse cursor (also the right stick and the touch aim stick). It can't hover or stop in mid-air: get too slow and it **stalls**, the nose drops and it falls until it has speed again. Loops are possible at speed. Take off with a run down the runway (the nose only lifts once you're fast enough); a plane placed up in open air waits there and launches already flying when someone gets in. Gentle touchdowns on the wheels are fine, hard impacts cost HP by how hard you hit, and a nose-dive into the ground or a wall at speed is the end of it. **Click** fires the nose gun (overheats after ~3 s), the **grenade key** drops a bomb (every 3.5 s). Bullets do 0.6x damage, explosives 1.4x (about as tough as the helicopter): rockets, M2s and Barretts bring it down. Shot down in the air, the pilot is thrown clear; F bails out any time — the jetpack does the rest. Bots take an empty plane when their goal is far, take off, fly over the terrain, strafe and bomb, and bail out over their goal. On Fortress, Outpost and Industrial (runways with room to climb out, found automatically), in the Maker **Vehicles** tab ("Plane") and the advanced editor; the Vehicles setting turns them off like the others. Online it works like the other vehicles (the pilot's game flies it, the host checks it). (#291)

## [1.37.0] — 2026-10-19 — Maker

This release also ships everything in 1.36 (Ultra HD soldiers, guns, terrain and dynamic lighting), listed under 1.36.0 below — the two went out together.

### Added — bots on custom maps (#287)
- **Bots now know their way around any map** — levels from the editor, Maker mode and shared levels used to have no bot navigation, so bots wandered. The game now builds the navigation graph itself when such a map loads (on a background thread, so the match start doesn't stutter; about a second): walking routes, jumps, jet climbs, drops, ledge detours and bridges to every objective. Rebuilt in-game, all classic maps pass the same route audit as their hand-baked graphs, and it works on dedicated servers too.
- **Bots handle Maker levels:** routes never run over spikes or lava; bots jet across a spike strip or lava pit holding height instead of a short hop that lands in it, steer off a hazard if they find themselves falling over one, don't bunny-hop into one, and respawn slides off a crowded base spawn never put anyone onto one. They also find, board and drive the buggies you place. The test (gate F `rtnav`) now plays a Maker level with spikes, lava and buggies.

### Added — level sharing (#288)
- **LEVELS: play, like and share levels other players built** (main menu → LEVELS, or the map editor's new Levels button). Tabs for Hot (likes and plays this week, newest count most), New, Most played, Top liked, Bookmarked and Search (title, author or share code). Every card draws the level's outline in its own colours with the flags and points marked, plus plays, likes and the modes it was built for. Pick one for PLAY (a bot match on it, in a mode it was made for), HOST ONLINE (the Host screen with the level picked, so friends can join), LIKE and BOOKMARK (bookmarks are kept with your settings and work offline; levels you've played before still play offline). Every level has a share code like `7KQ2-MX9P-4HDA`: type it into the course-code box (case, spaces and dashes don't matter). **Publish** in the map editor names your map, uploads it and shows its code; offensive titles are refused (and masked on the server). The old map library is still there under MAP FILES. Needs the updated master server. (#288)

### Added — Maker mode (#286)
- **Maker mode — build levels like Mario Maker (#286).** The map editor now opens on a palette of ready-made pieces with clear thumbnails, in tabs: **Terrain** (ground, wide ground, 30° / 45° ramps, round hill, floating island, a thin ledge you can shoot through, plank bridge, bullet wall, pillar, wall), **Hazards & helpers** (spikes, lava pit, jump pad, big jump pad, ladder, crates, sandbags, barrel), **Objectives** (player start, Blue / Red / free-for-all spawns, CTF flags, INF and HTF flags, DOM points, Rambo bow, Pointmatch diamonds), **Items** (all 16 weapons, bonus box, medikit, grenade kit), **Vehicles** (buggy, tank, heli pad, M2) and **Scenery** (trees, bushes, rocks, fences, lamps ...). Drag a piece onto the map — it snaps to the grid (10 / 20 / 40 / 80 px) with a live ghost and drops onto the ground under it — or tap a piece and tap the map to stamp copies. Click / drag to move, handles to resize, R / F to rotate / flip, box-select, duplicate, delete, undo / redo for everything, a minimap and zoom-to-fit.
- **Pieces that touch merge into one smooth piece of terrain** with slightly rounded corners and seam-free collision, coloured by a **theme** you pick (Grassland, Desert, Snow, Urban, Jungle, Cave, Night), so the HD terrain gives it the right material, grass / snow / sand lips and sky automatically. Map menu: world size S / M / L / XL, bottomless (falling = death) or a solid floor.
- **One button PLAY / EDIT:** PLAY checks the map (a spawn for each team, both CTF flags, nothing buried in the ground or outside the world, nothing standing in lava — click a problem to jump to it), then starts a test match in the mode you picked with you **spawned where the camera was**; EDIT (or F5, or Quit in the pause menu) brings you back to the same spot with the map exactly as you left it.
- **New map hazards for every map file:** spikes and lava kill on touch, jump pads launch you high (a big one for the top of the map). Bots steer clear of them. Missing objectives on a Maker map are placed on the terrain for you, so every game mode works on it.
- **Phones:** drag pieces up from the palette with a finger, one finger pans on empty space, pinch to zoom, hold for a context menu; bigger cards and buttons on touch screens.
- The classic tools are still there behind **ADVANCED** (free-form polygons, platforms, textures, generator) and work on the same map. Maker maps save the same map JSON as before (plus the piece list), so play-test, sharing, hosting and dedicated servers all keep working. New gate F test MAKER-TEST.

## [1.36.0] — 2026-10-19 — Ultra HD

### Added — new soldiers (#280, #281)
- **Every soldier is redrawn.** The chibi shapes are gone: a smaller head, slim limbs, a real torso with shoulders, tall combat boots and gloves, all on the same skeleton, animations and hit boxes. Modern gear: a ballistic helmet with a **glowing visor slit** in your team colour, plate carrier with mag pouches and a radio + antenna, war belt, shoulder / elbow / knee pads, headset with a mic boom, shooting glasses and a neck gaiter. Team colour stays on the uniform and pops in the accents (visor, shoulder stripes, chest patch, IR strobe), so friend / foe still reads at a glance.
- **A real jetpack** on every soldier's back (twin tanks, nozzle, status light). It rides the torso when you're prone, rolling or dead, and the flame comes out of its nozzle.
- Every cosmetic is redrawn to match: field cap, four hairstyles (crew cut, slicked back, mohawk, long), dreadlocks, the Vest as heavy plate armour (Vest paint applies), silver / gold chain, dog tag, cigar. Wounds show as blood on the new body.
- Painted at 9 px per game pixel with mipmaps, so they stay sharp on big screens and in the kill cam.
- **Settings → Video → Soldier look:** Operator (default) or Classic. Low graphics quality keeps the classic soldiers.

### Added — dynamic lighting (#282)
- On High (cinematic look), muzzle flashes, explosions, rocket motors, jetpack burns and vehicle lamps now **light the soldiers by direction** (normal-mapped): the side facing the flash lights up, the far side stays dark. Soldiers cast a soft contact shadow on the ground.

### Added — weapons in HD (#284)
- **All 16 weapons and the frag / cluster grenades are redrawn in ultra HD (6x the classic pixels)** to match the Operator soldiers: clean shapes in real materials (gunmetal, polymer, wood, brass, OD green), bevelled, lit and outlined, with rails, ejection ports with a brass case, magazines, sights and muzzle devices — and close-up surface detail: machined edge wear with bright chips, fine scratches, cerakote finish, stippled grips, knurling, pins and rivets, stamped model / calibre / serial markings, stencilled launchers and tanks, real wood grain and tarnished brass. Normal maps let the new dynamic lights play across them. They replace the blurry classic sprites in your hands, slung on your back, on the grenade belt and as dropped pickups (mipmapped, so they stay sharp when zoomed in or out).
- Grip, barrel length, muzzle flash and bullet spawn are exactly where they were — nothing about how the guns play changes. Weapon skins still tint them (the metal is mid-grey so desert / arctic / gold read properly). The Classic soldier look and Low quality keep the classic weapon sprites.
- `tools/gen_weapons_gfx.py` paints the set (deterministic); `tools/soldier_stage.gd --weapons [--classic-weapons] [--skins] [--cols=2 --zoom=14]` renders the lineups. Gate: new F test WEAPONS-ART-TEST.

### Added — HD terrain (#283)
- **Every map's ground is repainted in the cinematic look (Medium / High):** twelve new high-resolution materials (rock, dirt, soil, moss / grass, sandstone, snow, metal plate, concrete, wood, brick, masonry, ice) with normal maps, so cliffs show slabs, strata and cracks, dirt has pebbles, bunkers have formwork concrete, rivets and rust streaks, planks and nail heads. Each map keeps its own colours (a green jungle stays green, a snowy map white) and its light-and-shadow shading; materials blend where the classic colours change, and muzzle flashes / explosions light the relief on High.
- **Painted edges:** grass lips with tufts on grassy ledges, snow caps on snowy maps, sand and crumbly dirt lips, lit rock rims and worn bright metal edges, hanging roots and icicles under overhangs, and a soft shadow just inside every edge. Background walls you can't stand on are darker and calmer, so the playable ground reads first.
- **Themed backgrounds:** the far hills follow the map — city skylines with lit windows, desert mesas and cacti, snowy peaks and pines, jungle canopy and palms, ruined arches.
- Collision, map data, bots and netcode are untouched; Low quality and the Classic look draw exactly as before. Built once per map (a handful of draw calls instead of one per polygon). `tools/gen_terrain_gfx.py` generates the art (deterministic), `tools/terrain_capture.gd` renders before / after pairs and benchmarks. Gate: new F test TERRAIN-TEST.

### Fixed
- **The next-map vote no longer pops up every time a round ends** — a kill-limit win, a Survival wipe or a Battle Royale finish used to throw the vote at you (often right as you died) and switch maps every couple of minutes. The 5:00 clock is now the match clock: a round that ends early shows a short winner banner ("Next round - 3:12 left in the match"), restarts on the same map and the clock keeps running. Only a round that ends in the **last two minutes**, or the clock running out, ends the match with the winner screen and the map vote; the next match starts with a fresh clock. (#279)

## [1.35.0] — 2026-10-18 — Tracerfall

### Added — helicopter (#277)
- **New vehicle: the helicopter**, on the 15 biggest, most open classic maps (Messner, Fortress, Industrial, Airpirates, Outpost, B2B, Warehouse, Rescue, Veoto, Moonshine, Cobra, Abel, Crucifix, Belltower, Island2k5 — a pad per team base on team maps). Two seats: the **pilot** (W / Space / jet = climb, S = descend, A/D = fly; gamepad left stick; the touch stick) fires a **pair of rockets every 3 s** within a cone around the nose (aim at the other side and it turns round); the **door gunner** works the machine gun out of the side door with a wide arc. The rotor needs about a second to spin up before it lifts; it carries momentum, tilts into its speed, settles gently with no input, can't climb past the top of the world and lands on its skids.
- **Durability:** 420 HP; bullets do half damage, explosives (LAW, M79, grenades, tank shells, rockets) 1.5x. Hard landings, slamming into walls and rotor / tail strikes on terrain hurt it (a fast strike a lot). At 0 HP it **spins out** trailing fire and crashes into a burning wreck: a violent crash takes the crew with it, a gentle one (already down, slow) throws them clear. It respawns on its pad after 35 s; an abandoned one goes home after a minute (#259).
- **Bots:** they man the door gun of a landed helicopter and fly it — wait for the rotor (and a gunner), climb to a safe height, hold a stand-off from the nearest enemy while strafing and firing rockets, climb over terrain, head home and land when badly hurt or when there's nothing to do.
- **Online:** the pilot's machine flies it like a buggy driver drives (the host owns damage, wrecks, seats and respawns); impacts are reported to the host and checked, rockets go through the existing projectile paths, and the host now sanity-checks every client-driven vehicle's stream (speed over a quarter second, stays in the world). Honest pilots never trip the trust checks.
- **Look and sound:** fuselage with tinted cockpit glass and a reflection, the crew visible through the glass and the open door, tail boom, fin and spinning tail rotor, a main rotor that blurs into a disc as it spins up, rotor wash kicking dust off the ground below, a searchlight and blinking red / green nav lights (real lights on High), damage smoke and fire, a wreck. The rotor sound is the jet-boot hum pitched by rotor speed and chopped at the blade rate (no new audio files).
- Help screen / pickups list, a HELICOPTER readout on the HUD (rockets ready / reloading, rotor spin-up), entry toasts, translations (es / pt-BR / de / fr), replays show it. `tools/place_vehicles.py --heli` picks the pads (only `heli_spawns` is written; existing buggy / tank spots are untouched).
- Gate: new F test HELI-TEST (`tools/heli_test.gd`) and C net case `heli` (a client flies it on a dedicated server; the host sees it move; no trust lines).

### Added — vehicle art overhaul (#276)
- **Buggies and tanks redrawn** for the cinematic look: shaded gunmetal hulls with panel lines, rivets, grime and wear, a bright team stripe plus a team mark whose *shape* differs per side (roundel / chevron — readable with colour-blind settings), a cool rim light along the edges facing the moon. The buggy gets an exposed engine, spare tyre, roll cage, bull bar, sprung suspension (the body bobs on landings, squats and dives with the throttle) and spinning wheels with tread and motion blur; the tank a full track belt whose links roll around sprocket, idler and sprung road wheels, a side skirt, an antenna that whips about, and a barrel that slams back into the mantlet as the turret jolts.
- **Effects** (pooled, nothing created per effect): exhaust smoke, dust off wheels and tracks, muzzle flashes (with real light on High) and brass off the buggy gun, a glowing hot barrel, head-lamp cones and pooled head-lights, a white flash on hits. **Damage states** as HP drops: scorch marks and bullet holes, sparks, engine smoke that turns black, then fire. **Wrecks** blow apart into tumbling hull panels and burning bits under a smoke column, burn for a while and then smoulder as a charred husk until they respawn.
- Low quality keeps the shapes and drops the extras; Medium has most; High everything. The Classic look keeps the shading without the rim and neon. Purely cosmetic (no effect on physics, the network or the game's random numbers).
- Gate: new F test VART-TEST (`tools/vehicle_art_test.gd`): every vehicle in every state at every quality in both looks, no node growth, pooled effects only on Medium / High. `tools/vehicle_stage.gd` renders staged before / after shots.

### Added — graphics overhaul, phase C (#272)
- **One design language for every screen.** Dark blue-grey glass panels, off-white text, one warm ember accent (main actions, section headers) and one cool neon accent (hover edges, gamepad focus ring, highlights). New type: **Barlow / Barlow Condensed** (SIL OFL, credited in CREDITS.md and the in-game credits) with a fixed type scale. It reaches every menu, settings, the pause menu, the browser, toasts, the name prompt, the map editor, popups, tooltips, sliders, switches and scrollbars, plus the HUD.
- **Buttons respond:** they lift a little on hover / focus (1.03) and dip when pressed (0.97), glow at the edge, a light sweep runs across them, and you hear a soft tick on hover and a click on press. Primary actions (PLAY vs BOTS, QUICK PLAY, START HOSTING, CONNECT, RESUME) are solid ember.
- **Animated screen changes:** menus, sub-screens, modals and the pause menu slide and fade in (about 0.2 s). Nothing waits for the animation, so input works straight away and a quick back-press just cuts it short.
- **Living menu background:** the cinematic sky (moon, stars, drifting clouds) over the parallax ridges and ruins as a slow drifting shot, with embers floating up and the odd sweep of light. New **TRACERFALL wordmark** with a neon edge and a tracer round that streaks under it on load. Low quality keeps the old still picture.
- **Settings live preview:** opened from the main menu, Settings shows a small live scene beside the options: two soldiers trading fire with the current visual style, graphics quality, blood, damage numbers, screen shake, hit-stop and colour-blind team colours. It updates the moment you change something and only runs while Settings is open. (In a match the game itself already updates live.)
- **New settings (Video):** **UI scale** (85 / 100 / 115 / 130 %, applies straight away to the menus, the pause menu and the HUD; an accessibility option) and **Reduce motion** (no transitions, button motion or HUD pops, and a still menu background).
- **HUD, polished and minimal:** a vitals card with clean vector icons (health, jet, ammo, grenades), smooth bars with a white damage trail and a red pulse at low health, a magazine bar and the gun's icon. A **team-coloured score strip** puts BLUE and RED either side of the timer and flashes when a team scores. **Kill feed** rows sit on dark pills with weapon icons, a crosshair marker for headshots and an ember edge on your own kills and deaths. Chat, radio, toasts, the bonus and vehicle lines and the mode briefing are restyled too, along with the scoreboard (team bars, your row highlighted) and the winner banner. The **death screen** is now a band across the lower third (ELIMINATED, who killed you and with what, the respawn countdown and a progress bar), so the middle of the screen stays on the kill cam.
- Fixed: lazily opened menu screens (Leaderboard, Customize, Friends, Replays, Map Library, the name prompt) could keep the oversized rect from their first layout and run off the bottom of the screen; centred screens now stay centred at their real size.
- Gate: new F test UI-TEST (`tools/ui_test.gd`): transitions land on the right screen at the exact layout position, Reduce motion makes them instant, hover / press scale returns to 1.0, D-pad focus moves through the main menu, the preview exists only while Settings is open, opening / closing every menu screen three times leaves the node count flat, and the HUD vitals, strip, toast, death band and UI scale work. `tools/ui_capture.gd` renders the menu, settings, browser, HUD, scoreboard, pause and death screens (`--tour` adds every other menu screen). The gate's user-settings reset now follows `XDG_DATA_HOME`.

### Added — graphics overhaul, phase B (#271)
- **Gore, Soldat-style.** A kill now tears the soldier apart: limbs, torso and head fly as separate pieces (the soldier's own body-part sprites, bloodied), trailing blood, with a few frames of arterial spurt from the wounds. Blood comes out as droplets that arc, splash and **stain the walls and floor where they land** — dark, wet splats that dry and fade very slowly (capped per quality, oldest recycled). Bullet hits spray out the far side with a puff of mist. The Blood slider scales all of it, 0 turns it off (bots now honour it too).
- **Particles everywhere:** directional muzzle flashes with sparks and a wisp of smoke, brass casings that bounce, settle and fade, hot ricochet sparks + dust + chips off walls, explosions with debris, embers, sparks, rolling smoke, a scorch mark and (High) a **heat-haze shockwave** that ripples the screen; jetpacks shed embers and shimmer the air under the nozzle (High); dust on hard landings and dodge rolls.
- **Animation polish:** soldiers squash on landing and stretch on take-off, the body and gun kick back with every shot, and a hit soldier flashes white for a couple of frames.
- **Screen feel:** trauma-based screen shake (smooth, capped, nearby explosions shake too) that follows the Screen Shake slider; a short **hit-stop** on your kills and heavy hits and a **slow-mo look** (zoom punch, time smear, desaturation, sound dip) on multi-kills. New toggle: Settings → Game → "Hit-stop + slow-mo on your kills" (Screen Shake 0 also turns them off).
- **All cosmetic.** Hit-stop freezes only the picture (the game keeps running underneath — online matches never pause), slow-mo is a post effect, nothing touches physics, timers, the network or the game's random numbers (effects draw from their own), and effects run on every client from what the host already sends. Readability first: blood, debris and smoke sit behind soldiers, counts are capped. Low = the old Lo-fi (none of it), Medium = most of it with lower caps, High = everything.
- **Performance:** every effect is a slot in a fixed pool drawn by four batched canvas items — no node is created during combat (the old system made a node per glow / smoke puff / casing / impact and rigid bodies per death). Worst-case burst (8 gibbings + minigun + 4 explosions): node count flat, FX cost ≈0.8 ms per frame on High (headless).
- Cinematic soldiers are no longer drawn too dark (the rim-light shader squared their colours).
- Gate: new F tests FXPOOL-TEST (no node growth, pool / decal caps per quality, Blood 0, hit-stop / shake toggles, and the same scripted fight with effects on vs off ending bit-identical — position, velocity, health, ammo and the random stream) and FX-BENCH (`tools/fx_bench.gd`); `tools/fx_stage.gd` renders a staged fight for tuning.

### Added — graphics overhaul, phase A (#270)
- **New "Cinematic" look** (default; Settings → Video → Visual style, "Classic" keeps the original): an animated shader sky graded from each map's own colours, with a moon, twinkling stars and two layers of drifting clouds that parallax with the camera; five-layer parallax hills with fog, moonlit ridge rims and distant ruins (broken towers, a radio mast with a blinking light, gantries); a soft ambient darkening so lights read; a filmic grade (deep blacks, teal shadows / warm highlights, strong colours kept so team colours, fire and tracers stay readable) with fine film grain and a heavier vignette.
- **Real light** from muzzle flashes and explosions on High (a fixed pool of 16 lights, nothing created per shot) and a **rim light** on soldiers and vehicles that follows each body's silhouette.
- **Impact colour split** on nearby explosions (toggle in Settings → Video, with the hit flash).
- Everything is cosmetic: none of it touches physics, game state or the network. Low quality and headless servers use the classic path.
- Gate: new F test ATMOS-TEST (both looks, live switching, pooled lights, rim material on/off, post shader swap); `tools/capture.gd --ab` renders classic/cinematic pairs of the same moment.

### Changed — new name: **Tracerfall**
- The game is now called **Tracerfall** (#269): menu title, window title, credits, share/join text, the Windows exe description, the Android app label and the store copy. "Soldat" is the original game's name; the credits keep the Soldat attribution. Nothing moves on your machine: settings, stats, replays and updates carry over (the data folder and update files keep their old names).

### Changed — smoother, rounder classic maps
- **Rounded terrain** on all 99 classic maps (#273): sharp outline corners get small fillets (the outline moves at most ~4–5 px), in the collision shape soldiers run on as well as in the drawn terrain, so ledges, lips and slope changes are less jagged and soldiers roll over corners instead of catching on them. Topology is kept: no platform, bridge, gap, tunnel or hole appears or disappears (checked against every stance of the free-space graph and the bot nav graph per map), corners where solid, players-only and bullets-only terrain meet stay sharp, and every spawn, flag, DOM / point spot, pickup and vehicle spot audits exactly as before. Movement on the classic maps changes slightly; the Movement Course keeps its calibrated geometry.
- Smoother terrain shading: coincident triangle corners now share their vertex colour (area-weighted average) instead of showing faceted per-triangle seams; deliberate hard colour edges are kept (#273).
- The terrain edge shading (dark depth band, sunlit rim) joins smoothly around corners instead of leaving light wedges at inside corners and dark overlaps at outside corners (#273).
- `tools/smooth_maps.py`: the offline smoothing pass (originals kept in `tools/map_src/`, `--restore` puts them back); `tools/pms_to_map.py --regen` runs it on every re-ported map (#273). 2D MSAA was tried for anti-aliased edges but the GL Compatibility renderer doesn't support it in Godot 4.7 ("2D MSAA is not yet supported for GLES3"), so it stays off.

### Added — the movement course
- **Training phase 2: "Now the moves that make a Soldat"** (#262). After the shooting steps, Training loads a purpose-built Movement Course micro-map: a short gap under a spike ceiling (tap to hop — a held full jump hits the spikes), a wider gap (tap), a long gap (hold for the full jump), a prone-cancel drop from a high ledge into a target ring, and a timed bunny-hop lane that plain running and roll spam can't make. Falling into a pit or touching the spikes puts you straight back at the section start — no death screen. Each section ends with a toast, finishing shows your total time, and the best time is saved in your stats; press RELOAD to run it again. Gap widths, spike height, ring and lane time are calibrated from measured jump / drop / hop physics (numbers in `scripts/movement_course.gd`).
- **MOVEMENT COURSE button** next to TRAINING on the main menu, so returning players can run the course on its own.
- Course text goes through the UI translations (German, Spanish, French and Brazilian Portuguese included); with a controller plugged in, Training names the pad button next to the key.
- **Prone on a gamepad**: the left trigger now goes prone (saved controller layouts pick the new default up).

### Testing
- New release-gate test (F stage, COURSE-TEST): drives every course gate with the right technique (passes) and the wrong one (full jump into the spikes, tap on the long gap, non-prone drop, running / rolling the lane all fail), checks the best time, RELOAD replay, the Training settings restore, the committed map JSON against its generator and the translations.
- The all-map CTF sweep (E stage) no longer expects a sweep entry for the Training-only `movement_course.json` (it isn't in the map rotation), which made the full sweep report 102/103 maps and fail.

### Added
- **News line on the main menu** (#261). One short message from the master server (`GET /news`) under the version button, at most one fetch every 10 minutes. Click it to open its link; × hides that message for good (a new one shows again). It fails silently and never holds up the menu; on phones it has a touch-sized hit area.
- **Weekly featured mode/map on the official server** (#264). `featured.json` next to the server's game pack sets the week's mode, map and weapon bans; the hourly update restarts the server when the week changes, and an expired or missing file goes back to CTF. `deploy/featured-rotate.sh` cycles a preset plan by ISO week. With no other news, the menu news line advertises the featured week ("This week on the official server: Rambomatch on Voland").
- Dedicated servers take host weapon bans on the command line: `--bans=Minigun,Steyr AUG` (names as in the ban grid, case-insensitive; `--bans=` clears them) (#264).

### Fixed
- A dedicated server given an unknown `--map` / `--mode` name now says so in its log (it used to fall back silently), and a later bad flag no longer overrides an earlier good one, so a bad featured entry falls back to CTF (#264).

### Security — the host now checks what clients say about themselves
- Each player's own game decides the damage it takes, where it is, and who killed it — that's what keeps the game instant on every connection, but a modified client could ignore hits, teleport, or hand kills to a friend. The host now keeps its own account and steps in when a client's story can't be true (new `trust_guard.gd`):
  - **Ignored damage:** the host's own hit detection saw a player take two lives' worth of damage while their game reported almost none → host-side death.
  - **Impossible health:** HP above 100, or rising without a medikit / round reset / Rambo bow, is clamped; repeat offenders die.
  - **Impossible movement:** faster than anything in the game can push a soldier (teleports, speed hacks) or outside the world → host-side death on the second offence.
  - **Fake kill credit:** a death is only credited to someone who actually attacked in the last 10 s (and is an enemy unless friendly fire is on); otherwise nobody gets the kill.
  - Three forced deaths in five minutes is a kick, announced in chat. Bots and the host's own player are never checked; single player is untouched.
- New release-gate cases play a modified client (godmode, teleport, fake credit) against a dedicated server and require the host to catch each one; every existing online case now also fails if an honest client ever trips a check.

### Internal
- Structure batch 1 remainder of [#258](https://github.com/Predator04/Soldat-Reborn/issues/258): the server browser (browse screen, LAN / recent / master lists with live pings, Quick Join / Quick Play, skill matchmaking) moved out of `menu.gd` into `menu_browser.gd` (~430 lines; `menu.gd` 1,910 → 1,530). No behavior change.
- Structure batch 2 of [#258](https://github.com/Predator04/Soldat-Reborn/issues/258): `hud.gd` split — the vote prompt (`vote_panel.gd`), the end-of-round map vote (`next_map_panel.gd`), the kill feed and chat feed (`kill_feed.gd` / `chat_feed.gd`, sharing one expiring-line lane in `timed_feed.gd`) and the typed command / chat line with the vote + host commands (`hud_commands.gd`) are their own scripts; every HUD method other scripts call stays as a thin delegate (no behavior change).
- Structure batch 3 of [#258](https://github.com/Predator04/Soldat-Reborn/issues/258): `main.gd` (5,600 lines) split by system into `match_net.gd` (joining clients, player bodies, broadcasts), `match_modes.gd` (objectives, scoring, round end), `match_votes.gd` (votes + host commands), `match_bots.gd`, `match_vehicles.gd`, `match_bonuses.gd` and `match_world.gd` (terrain, geometry, anti-stuck); `main.gd` keeps the match state, boot / spawn flow and every RPC entry point (same node path and names — the network protocol is unchanged), now ~1,600 lines. No behavior change.
- Structure batch 4 of [#258](https://github.com/Predator04/Soldat-Reborn/issues/258): `SoldierArt.draw_soldier` takes a `SoldierDrawState` object (new `soldier_draw_state.gd`, one reused per soldier) instead of ~26 positional parameters, and `player._physics_process` (~520 lines) is a short dispatch into per-state handlers — replica, mounted (M2 / vehicle), input-locked (chat open) and live, the live path itself in ordered steps (stance, ladder, movement, aim, weapon keys, grenade, trigger, timers, effects, state stream). Physics constants stay in `player.gd`. No behavior change.

### Credits
- The three music tracks are now credited in-game and in CREDITS.md: they're renders of the tracker modules in the Soldat base content ("Gore" and "Necromancide" by Marshall Anderson, "Bloody Soil" author unrecorded), CC BY 4.0.

## [1.34.0] — 2026-10-15

### Added — movement tech from the original's tutorial
- **Tap-to-hop, hold-to-jump.** Holding jump sustains the rise for a short window (exactly the previous full-height jump); releasing early cuts it into a short hop (~40% height). Bunny-hop chains with held jump are unchanged.
- **Prone-cancel.** Going prone mid-air drops you noticeably faster — the classic momentum killer and gap-shortener.

### Added — fairer team games
- **Auto team balance between rounds.** When a team mode's sides differ by more than one at round reset, the lowest-killing bot switches sides (respawned at its new base, announced in chat). Humans are never moved; an all-human stack is left alone out of respect for choice.

### Ops
- Uptime watchdog: a 15-minute GitHub Actions health check opens an issue (one at a time) when the master stops answering and auto-closes it on recovery.
- Daily on-server backups of the leaderboard + shared maps + TLS/firewall config (14-day rotation).

## [1.33.3] — 2026-10-14

### Security
- **The master server connection is now HTTPS** (#252). The default server list / relay / leaderboard endpoint is `https://161-153-9-69.sslip.io` with a Let's Encrypt certificate (Caddy in front of the master, auto-renewing); the relay upgrades to `wss://`, so the server list, matchmaking, and relayed match packets are encrypted and tamper-proof in transit. The old plain endpoint stays up for one release so older builds keep working; a custom master URL still goes wherever you point it.

## [1.33.2] — 2026-10-14

### Internal
- Structure batch 1 of [#258](https://github.com/Predator04/Soldat-Reborn/issues/258): the name prompt and the update / WHAT'S-NEW UI moved out of `menu.gd` into `name_prompt.gd` and `menu_update.gd` (~300 lines, no behavior change — the server-browser extraction follows in the next batch). Also a nit pass: late joiners' pickup snapshot now shares its entry builder with the broadcast stream, the map editor's texture dropdowns create undo checkpoints, and the bots' ladder sensing is one shared implementation with the player's (#251 follow-up).
- Master server: relay broadcasts no longer hold the room lock while writing — a stalled peer can't delay joins/kicks for the whole room.

## [1.33.1] — 2026-10-13

### Fixed — vehicles
- **Buggies and tanks no longer stay stuck or abandoned forever** (#259). A vehicle nobody has touched (occupied, damaged, or entered) for 60 s returns to its spawn point through the same respawn a wreck uses — fresh hull included. A driver who's throttling into an obstacle without moving gets lifted out of the terrain after ~3 s (the unstick sweep). Occupied vehicles are never teleported. Applies to both buggies and tanks.

### Testing
- New release-gate stage: idle respawn home, touch resets the clock, occupied never teleports (VRESET-TEST).

## [1.33.0] — 2026-10-13

### Added — the community's classic asks
- **Weapon bans** (#256). The most-requested server customization in Soldat history (OpenSoldat #118: *"server can't customize which weapons... the only way requires recompiling"*). The host (or single player) toggles any weapon off in Host Settings / the Mods card — a banned weapon disappears from the weapon menu (shown struck out), can't be switched to, never spawns (loadouts fall back to the next allowed weapon), is never given to bots, and its map pickups don't appear. Clients receive the ban list with the rest of the host config. Instant "pistol only", "no sniper", "knives out" nights. Gun Game rungs and the Rambo bow are match objectives and stay.
- **Host chat commands** (#257) — the classic Soldat server set, typed straight into chat (host / single player): `/addbot [skill 1-5] [name]`, `/kick <name>`, `/bots <n>`, `/gamemode <0-9|name>`, `/map <name|index>`, `/restart`, `/say <msg>`, `/ff`. Names match by unique prefix; unknown names say so; clients are told commands are host-only.

### Testing
- New release-gate stage: weapon bans + host commands end to end (COMMUNITY-TEST).

## [1.32.1] — 2026-10-13

### Fixed — crashes & stability
- **M2 turrets crashed the host in multiplayer.** A client mounting or dismounting an M2 re-entered the host's RPC handler endlessly (stack overflow). Same class of bug the vehicle relay fixed years ago; the M2 handlers now use that pattern, and the host applies the dismount after relaying (#235, #254).
- **Crafted / corrupt maps could freeze or OOM the game.** A map's `world` header was trusted verbatim to size the collision index — a 30-byte edit meant a multi-second freeze (or an out-of-memory kill on phones). Dimensions are now clamped at every entry point: saved files, master-server downloads, and host-sent custom maps (#236).
- **Leaderboard / friends panels could crash** on a malformed master-server reply — including nested junk like a list where a number belongs (#239, #254).

### Fixed — updater security
- **Updates are now signature-verified.** The updater applied whatever the GitHub API pointed at, with only a byte count as a check. Releases now ship `SoldatReborn.exe.sig` (RSA over sha256) and the game refuses to install an update whose signature, host, or size doesn't check out (#237). The release tooling refuses to publish an exe without its signature (#254).

### Fixed — master server (hardening, live now)
- Per-IP rate and count caps on server registration; player counts are validated; control characters can't reach the server list (#master-server/1).
- Relay connections are capped per IP and globally, the join hello must arrive within 10 s, and trickled HTTP bodies are cut off — one address can no longer exhaust the whole service (#master-server/1).
- Only the relay host can register a listing for their room code; a third party could rename a live room before (#master-server/2).
- Joining a room whose host just left now gives a clean "no game with that code" instead of hanging connected forever (#master-server/3).
- Ranked reports are velocity-capped and death-free kill streaks beyond 40 matches stop counting kills (godmode farming) (#master-server/4). Invalid map uploads and profile-rank edge cases tightened (#master-server/7).

### Fixed — gameplay & online
- Map-placed weapon pickups no longer vanish 20 s into the match — they persist for the whole match (on clients too) and regenerate in place after being grabbed, without blocking bullets while regenerating (#241, #254).
- A host whose relay connection drops mid-match is now told, instead of advertising a dead join code forever (#238, #254).
- Weapon-drop spam from modded clients is bounded host-side — and the bounds no longer eat legitimate toss-and-catch throws or weapon-swap first shots (#240, #243, #254).
- Blood slider at 0 no longer latches low-FX mode on for the whole session (#242).
- Ranked results are retried on flaky networks instead of being dropped silently (#250).

### Performance
- Pickup sync only sends when the world actually changed instead of a full reliable snapshot at 10 Hz; vehicle HP broadcasts threshold to 5 % instead of per bullet (#246, #247).
- Settings sliders no longer rewrite the config file (and, for hosts, RPC every client) on every drag tick (#245, #254).
- Replay playback rebuilds the kill feed only when it changes instead of every frame (#244); map editor stops hashing the whole map on zoom clicks (#248); cluster-grenade cascades, big-bot gostek sweeps and a few other hot paths tightened (#249).

### Code
- Map / mode name lists live in one shared file instead of four copies (#251); training pins its map by name instead of a hardcoded index (#250).
- New release-gate stage: map weapon pickups persist + regenerate end to end.

## [1.32.0] — 2026-10-07

### Added
- **Skill matchmaking.** After 3 online matches you get a skill rating (average XP per match, so it measures how well you play, not how long). QUICK PLAY now prefers games with players near your level, as long as the ping is close. Servers at your level say "your level" in the server list, and the Leaderboard shows your skill. New players match anywhere.
- Master server: `/list` shows each server's average player skill, `/profile` shows yours.

### Testing
- New release-gate check: skill matchmaking against a real master server (ratings, server averages, Quick Play picks the server at your level).

## [1.31.0] — 2026-10-07

### Added
- **KILL CAM REPLAY.** When you die, the last 3 seconds rewind and play back: real speed, then slow motion over the killing shot, framed on you and your killer (arrow + ring on them). Then the live kill cam follows them until you respawn. Space / click / tap / A skips it and you respawn on the normal timer. Works online too (the server waits for you to finish watching). Can be turned off in Settings.
- **Graphics upgrade**, with a new **Graphics quality** setting (Low / Medium / High; phones start on Medium):
  - Terrain has depth now: a soft shadow along every edge, a lit rim on top surfaces, darker undersides, and grass growing on green ground (High).
  - Light: muzzle flashes, explosions and rockets glow, and on High explosions light up the walls around them.
  - Smoke and debris: rockets leave a smoke trail, explosions leave smoke clouds and a scorch mark on the ground, guns kick back and eject shell casings, hard landings kick up dust.
  - Soldiers and vehicles cast a soft shadow on the ground under them.
  - Post-processing: color grading and vignette, a red flash with color split when you're hit, bloom on High. Floating dust (fireflies at night) on High.
  - Low is the old Lo-fi mode. If a match runs under 35 fps, the game drops one quality step once and tells you.

### Fixed
- The release gate's server query check could time out its own server (it needed about 31 s of a 30 s window).
- The nav check flagged two maps whose objectives are reachable from a spawn on a different level than the first one.
- The unlock test could miss its gold tracer when the bullet hit a wall before it looked.

### Testing
- New release-gate checks: kill cam rewind (slow motion, respawn waits for it, skip respawns on time, live follow after), the same online with a dedicated server holding the respawn, and every graphics preset switched live mid-match (terrain depth, grass, post FX, bloom, lights, shadows, effect caps).

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
