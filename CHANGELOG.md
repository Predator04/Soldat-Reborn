# Changelog

All notable changes to Soldat Reborn.

## [1.18.0] — 2026-09-28

Content and sound pass.

### Added
- **Medikits and grenade kits** on all 99 classic maps, at the spots the original map makers placed them (read from the Soldat `.pms` files). A medikit heals you to full, a grenade kit refills you to 3 grenades; each comes back 25 s after it's taken. You can't waste one: at full health you walk past a medikit. Bots use them too and head for one when they're hurt or out of grenades. Bonus crates now use Soldat's own kit sprites.
- **Team radio** (V, rebindable): pick what — enemy flag carrier, friendly flag carrier, enemy spotted — then where — up / mid / down — with 1–3. Your team hears Soldat's radio voice line and sees an amber "(RADIO)" chat line. Bots call out the enemy flag carrier when someone steals their flag.
- **Positional sound**: other soldiers' gunfire, reloads, jumps, explosions and deaths come from where they happen — quieter with distance and panned left/right. Far-off fights use Soldat's muffled distant-gunfire / distant-explosion samples.
- New sounds from the Soldat set that were sitting unused: footsteps (running and crouched), landing thuds (heavier after big drops), bullet ricochets off walls, bullet whizz-bys when an enemy round passes your head, death cries (plus a crunch on headshot kills), grenade pin pull when you start cooking, grenade bounces, weapon switch, weapon pickup and throw, roll, going prone / standing up, respawn, kit and bonus pickups.
- Rain and snow maps play a looping rain / wind bed. Six more classic maps get the weather their `.pms` file asks for (April, Bigfalls, Biologic, Mossy: rain; B2B, Messner: snow).

### Fixed
- **The Barrett never fired.** It spun up, clicked and nothing came out: it's semi-auto with a 0.32 s wind-up, and the "release the trigger before the next shot" check was already tripped by the time the wind-up finished. A click now queues the shot, which goes off after the wind-up (even if you let go), one round per click.

### QA
- `tools/fire_test.gd` (gate stage F): every primary must fire from a click; the Barrett exactly one round per click. Fails on 1.17.1.
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
