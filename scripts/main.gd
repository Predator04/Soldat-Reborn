extends Node2D
## Main — sky, terrain, players, bots, HUD. Handles singleplayer + networked flows.

var player_scene := preload("res://scenes/player.tscn")
var hud_script := preload("res://scripts/hud.gd")
var pause_menu_script := preload("res://scripts/pause_menu.gd")
const PoaLoader = preload("res://scripts/poa_loader.gd")
const WeaponPickup = preload("res://scripts/weapon_pickup.gd")
const MapIO = preload("res://scripts/map_io.gd")
const Spectator = preload("res://scripts/spectator.gd")
const KillcamRewind = preload("res://scripts/killcam_rewind.gd")
const BonusPickup = preload("res://scripts/bonus_pickup.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const NavGraph = preload("res://scripts/nav_graph.gd")
const NavBuilder = preload("res://scripts/nav_builder.gd")   # #287 runtime graphs
const Bot = preload("res://scripts/bot.gd")                  # physics numbers for the pad rides (#286)

signal kill(killer_name: String, victim_name: String, weapon_name: String, killer_team: int, victim_team: int)
signal objective(kind: String, team: int, who: String)   # grab/drop/return/capture/dom/point

# System helpers (#258): plain child Nodes holding the code for one system each.
# Match state stays on Main (tests, HUD and peers read it here); every @rpc and
# every method other scripts call by name keeps a delegate below, so RPC paths
# and the public API are unchanged.
const MatchVehicles = preload("res://scripts/match_vehicles.gd")
const MatchBonuses = preload("res://scripts/match_bonuses.gd")
const MatchVotes = preload("res://scripts/match_votes.gd")
const MatchModes = preload("res://scripts/match_modes.gd")
const MatchNet = preload("res://scripts/match_net.gd")
const MatchBots = preload("res://scripts/match_bots.gd")
const MatchWorld = preload("res://scripts/match_world.gd")
const MatchHazards = preload("res://scripts/match_hazards.gd")
var _vehicles_sys: MatchVehicles = null   # match_vehicles.gd
var _bonuses: MatchBonuses = null   # match_bonuses.gd
var _votes: MatchVotes = null   # match_votes.gd
var _modes: MatchModes = null   # match_modes.gd
var _net: MatchNet = null   # match_net.gd
var _bots: MatchBots = null   # match_bots.gd
var _world: MatchWorld = null   # match_world.gd
var _hazards: MatchHazards = null   # match_hazards.gd (#286 spikes / lava / jump pads)

var player: Node2D = null            # LOCAL player (whichever peer owns us)
var hud: CanvasLayer = null
var killcam: Node2D = null           # killcam_rewind.gd — replays the last seconds before your death
var spectator: Node2D = null         # (#75) follow/free-cam while dead — owns its own Camera2D
var _map: Dictionary = {}
var _players_by_id: Dictionary = {}  # peer_id -> player node (host only, but also mirrored on clients)
var _peer_names: Dictionary = {}    # peer_id -> chosen display name (host only; client sends it in net_client_ready)
var _peer_team_by_id: Dictionary = {}  # peer_id -> last team (every peer; survives death, for chat identity)
# Per-soldier match stats for the scoreboard: name -> {"k", "d", "c"} (kills,
# deaths, captures/points). Every peer counts them from the same replicated
# kill-feed / objective events; joiners get a snapshot in net_client_ready.
var player_stats: Dictionary = {}
var _stats_round_active := true
var _ready_peers: Dictionary = {}    # peer_id -> true (host only, gate for outbound state RPCs)
var _pickup_peer_sig: Dictionary = {} # peer_id -> last pickup-state signature sent (#247)
# Peers whose main.tscn is loaded — populated on net_client_ready (before the
# spawn ack). Gates reliable spawn broadcasts so bots/bonuses spawned between
# the client's "ready" and its ack don't get permanently missed (#84).
var _connected_peers: Dictionary = {}
# Bot registry (host authority) — bot_id → bot node. Mirrored on clients via the
# net_spawn_bot/net_despawn_bot RPCs so per-bot state can address each replica.
var _bots_by_id: Dictionary = {}
var _bot_sync_cd: float = 0.0
const BOT_SYNC_HZ := 20.0            # host → clients broadcast rate for bot pos/vel/facing/etc.

# Team modes: fixed team ids (player joins BLUE, enemy bots on RED).
const TEAM_BLUE := 1
const TEAM_RED := 2
# FFA bots each get their own team id starting here (see _spawn_bot_at).
const FFA_BOT_TEAM_BASE := 1000


static func bot_color_for_team(t: int) -> Color:
	if t == TEAM_BLUE:
		return preload("res://scripts/team_colors.gd").blue()
	if t == TEAM_RED:
		return preload("res://scripts/team_colors.gd").red()
	if t >= FFA_BOT_TEAM_BASE:
		# Distinct, readable hues per FFA bot (golden-angle spacing).
		var h := fposmod(float(t - FFA_BOT_TEAM_BASE) * 0.618034 + 0.05, 1.0)
		return Color.from_hsv(h, 0.6, 0.9)
	return Color(0.85, 0.3, 0.25)

# CTF / INF / HTF flag nodes and score-to-win.
var flags: Array = []
const CTF_SCORE_TO_WIN := 3
const INF_SCORE_TO_WIN := 3
const HTF_SCORE_TO_WIN := 60      # 1 pt/sec while carrying → 60s hold = a win
const PM_SCORE_TO_WIN := 20
# Rambo bow — the current carrier's id (or 0 for none). Only they can score.
var _rambo_carrier_id: int = 0

# Domination — control point nodes + per-team hold accumulator.
var _dom_points: Array = []
const DOM_SCORE_TO_WIN := 90     # (owned_points × 1 pt/sec) → ~90s of full control wins

# Battle Royale — shrinking safe zone.
var _br_zone_radius: float = 2200.0
var _br_zone_center: Vector2 = Vector2(2400.0, 1200.0)
const BR_ZONE_DPS := 22.0      # damage/sec applied outside the ring

# Gun Game (MODE_GG) — per-soldier rung on the 16-weapon ladder, keyed by
# display_name so the level survives death/respawn (a fresh body reads its
# rung from here in _spawn_*). Host-authoritative in MP; the RPC below fans
# each update out to every peer so client-owned players re-apply the weapon.
var _gg_levels: Dictionary = {}
# Per-soldier kill tally for Gun Game (#91). Keyed by display_name so it
# survives death/respawn. Host-authoritative; mirrored to clients via the
# match-state broadcast. Cleared with _gg_levels on round reset.
var _gg_kills: Dictionary = {}

# ── Match state (host-authoritative in MP) ─────────────
const SCORE_TO_WIN := 20
const ROUND_TIME := 300.0
const MATCH_SYNC_HZ := 5.0           # host → clients broadcast rate for scoreboard

var scores: Dictionary = {}          # team_id -> int
var time_left := ROUND_TIME
# Release-gate tests (#266, --smoke-round-secs=N on a host): short rounds so a
# run sees the round end, the next-map vote and the map change.
var round_time := ROUND_TIME
var round_active := true
var winner_team := -1
# Human-readable subtitle explaining the end (draws especially — "no scores",
# "3-3 tie", etc.). Broadcast alongside the rest of match state.
var winner_note := ""
var winner_end_t := 0.0
# #279: the round that just ended also ended the match (inside the last two
# minutes, or by time) — only then is there a map vote and a fresh clock.
var match_over := false
# End-of-round map vote: three candidate maps on the winner screen. Players
# press 1/2/3 (D-pad, or tap); most votes wins. No votes = same map again,
# except a dedicated server rotates to the first choice.
var next_map_choices: Array = []     # map indices
var next_map_tally: Array = [0, 0, 0]
var my_next_map_vote := -1
var cur_map_index := -1              # built-in map playing now (-1 = custom)
var _match_sync_cd := 0.0
var _flag_sync_cd := 0.0
const FLAG_SYNC_HZ := 8.0

# ── Vote system (#77) ─────────────────────────────────
# Host-authoritative: any player calls /votemap or /votekick, F1/F2 to cast,
# majority passes. Broadcast alongside match state at MATCH_SYNC_HZ.
var vote_active := false
var vote_kind := ""              # "votemap" | "votekick"
var vote_target_str := ""        # human label ("Nuubia" / "Red Bot 3")
var vote_target_arg := 0         # map index (votemap) or peer id (votekick)
var vote_yes := 0
var vote_no := 0
var vote_time_left := 0.0
var vote_starter := ""           # display_name of who called it

# ── Bonus pickups (#78) ───────────────────────────────
# Host-authoritative: host places boxes, detects collection, applies effect
# to the toucher and schedules the box slot's respawn. Clients mirror boxes
# via net_bonus_spawn / net_bonus_despawn.
var _bonus_boxes: Dictionary = {}    # bonus_id → node (host + client)
# Weapon-pickup sync — host broadcasts (id, pos, vel, ang) so client-frozen
# pickup bodies mirror the host's physics timeline (#34).
var _pickup_sync_cd := 0.0
const PICKUP_SYNC_HZ := 10.0
# #107: throttle DOM/PM/BR mode-state broadcasts so we don't spam a
# per-peer RPC every host frame for objectives that change at UI speed.
var _mode_sync_cd := 0.0
const MODE_SYNC_HZ := 10.0

# World rect. Built-in maps use the classic 4800×2000 arena with the baseline
# floor's TOP edge at GROUND_Y. Ported .pms maps carry their own "world" dict
# (w / h / ground_y / kill_y) sized to the map, so every classic plays at the
# same soldier-to-terrain scale instead of being squeezed into 4800×2000.
const DEFAULT_MAP_W := 4800.0
const DEFAULT_MAP_H := 2000.0
const DEFAULT_GROUND_Y := 1900.0
var MAP_W := DEFAULT_MAP_W
var MAP_H := DEFAULT_MAP_H
var GROUND_Y := DEFAULT_GROUND_Y
# Soldiers whose feet drop below this line fell off the map (Soldat rule) and
# die. INF = no kill line (built-in maps have a solid floor everywhere).
var KILL_Y := INF
var _stuck_time: Dictionary = {}   # instance_id -> seconds continuously embedded
var safety_stats := {"unstuck": 0, "fell": 0}  # read by tools/stuck_test.gd
# Baked bot navigation graph for this map (empty for editor maps). Bots path
# over it with A* — see scripts/nav_graph.gd / tools/build_nav.py.
var nav: RefCounted = null
# #287: maps without a baked graph (editor / Maker / shared / custom) build one
# on a WorkerThreadPool thread at match start; bots chase directly until
# _tick_runtime_nav() adopts it.
var _nav_task := -1
var _nav_builder: RefCounted = null
var _nav_data: Dictionary = {}
var nav_runtime_ms := -1     # build time once adopted (tests / diagnostics)
var nav_adopt_ms := -1.0     # #293: main-thread wall ms _tick_runtime_nav spent adopting it (gate F rtnav)

var MAPS := [
	{
		"name": "Ascent",
		# Rolling hills climbing left → right, with a tunnel bored through the
		# mid-map mountain and a peaked ridge on the right. Polygons build the
		# organic silhouette; a few flat platforms give jet-boot climbers footing.
		"terrain_color": Color(0.30, 0.36, 0.30),
		"terrain_texture": "res://assets/textures/xt_ap_grasrock_02.png",
		"floor_texture": "res://assets/textures/drymud.png",
		"polys": [
			# Left rolling hill.
			{"points": PackedVector2Array([
				Vector2(200, 1900), Vector2(320, 1820), Vector2(520, 1720),
				Vector2(720, 1670), Vector2(920, 1720), Vector2(1080, 1820),
				Vector2(1240, 1900),
			])},
			# Second hill with a small plateau top.
			{"points": PackedVector2Array([
				Vector2(1240, 1900), Vector2(1360, 1780), Vector2(1500, 1620),
				Vector2(1620, 1560), Vector2(1720, 1560), Vector2(1740, 1900),
			])},
			# Ascent tunnel — dark back wall (decorative, no collision) so the
			# walk-through tunnel reads as a cave cut into the rock.
			{"col": 3, "points": PackedVector2Array([
				Vector2(1767, 1780), Vector2(2693, 1780), Vector2(2693, 1900), Vector2(1767, 1900),
			]), "vc": PackedColorArray([Color(0.16, 0.14, 0.13), Color(0.16, 0.14, 0.13), Color(0.3, 0.27, 0.24), Color(0.3, 0.27, 0.24)])},
			# Middle mountain with a horizontal tunnel bored through the base.
			# The tunnel runs the full width (ceiling y=1780, floor = map ground
			# at 1900) so it's a real walk-through, not a sealed notch.
			{"points": PackedVector2Array([
				Vector2(1767, 1780), Vector2(1780, 1720), Vector2(1880, 1500),
				Vector2(2000, 1350), Vector2(2140, 1260), Vector2(2260, 1240),
				Vector2(2380, 1290), Vector2(2500, 1400), Vector2(2600, 1560),
				Vector2(2680, 1720), Vector2(2693, 1780),
			])},
			# Valley + rising slope.
			{"points": PackedVector2Array([
				Vector2(2720, 1900), Vector2(2820, 1820), Vector2(3020, 1760),
				Vector2(3200, 1720), Vector2(3380, 1660),
				Vector2(3560, 1580), Vector2(3720, 1480),
				Vector2(3880, 1360), Vector2(4040, 1240),
				Vector2(4200, 1140), Vector2(4340, 1060),
				Vector2(4480, 1020), Vector2(4620, 1080), Vector2(4620, 1900),
			])},
		],
		"platforms": [
			# Sky platforms + tunnel-roof top for extended air routes.
			{"p": Vector2(2720, 1550), "s": Vector2(240, 18)},  # mountain-side ledge (east face)
			{"p": Vector2(3220, 1420), "s": Vector2(260, 18)},  # mid-air perch
			{"p": Vector2(3850, 1180), "s": Vector2(240, 18)},  # near peak
			{"p": Vector2(4460, 800),  "s": Vector2(260, 18)},  # sky peak
			{"p": Vector2(700, 1450),  "s": Vector2(180, 18)},  # early lift
		],
		"player_spawn": Vector2(200, 1775),
		"bot_spawns": [Vector2(2200, 1220), Vector2(3220, 1390), Vector2(3850, 1150), Vector2(4460, 770)],
		# Explicit objectives (the 4800-arena defaults put the RED flag and two
		# DOM points inside the hills). BLUE holds the valley, RED the peak.
		"ctf_flags": [Vector2(110, 1900), Vector2(4480, 1020)],
		"vehicle_spawns": [Vector2(150, 1900), Vector2(4480, 1020)],
		"inf_flag": Vector2(2230, 1900), "htf_flag": Vector2(2230, 1900),
		"dom_points": [Vector2(720, 1640), Vector2(2260, 1210), Vector2(3850, 1141)],
		# (Flat texture-square "scenery" decals removed in 1.13 — they read as
		# floating placeholder boxes over the hills.)
	},
	{
		"name": "Towers",
		# Two mountain fortresses left and right, each with a low tunnel through
		# the base and staircase platforms up the side. Central low ground with
		# a raised mid-arena and M2 mounts on the peaks.
		"terrain_color": Color(0.32, 0.30, 0.28),
		"terrain_texture": "res://assets/textures/earthen.png",
		"floor_texture": "res://assets/textures/drysand.png",
		"polys": [
			# Left tunnel — dark back wall (decorative, no collision) so the
			# walk-through tunnel reads as a cave cut into the rock.
			{"col": 3, "points": PackedVector2Array([
				Vector2(227, 1780), Vector2(1233, 1780), Vector2(1233, 1900), Vector2(227, 1900),
			]), "vc": PackedColorArray([Color(0.16, 0.14, 0.13), Color(0.16, 0.14, 0.13), Color(0.3, 0.27, 0.24), Color(0.3, 0.27, 0.24)])},
			# Left mountain with a walk-through tunnel under it (ceiling y=1780,
			# floor = map ground) — the BLUE flag sits inside.
			{"points": PackedVector2Array([
				Vector2(227, 1780), Vector2(240, 1720), Vector2(320, 1500),
				Vector2(420, 1300), Vector2(560, 1140), Vector2(700, 1060),
				Vector2(840, 1120), Vector2(960, 1260), Vector2(1080, 1440),
				Vector2(1180, 1620), Vector2(1233, 1780),
			])},
			# Central low mesa (players climb via ramps of platforms).
			{"points": PackedVector2Array([
				Vector2(2000, 1900), Vector2(2100, 1780), Vector2(2280, 1720),
				Vector2(2520, 1700), Vector2(2720, 1720), Vector2(2900, 1780),
				Vector2(3000, 1900),
			])},
			# Right tunnel — dark back wall (decorative, no collision) so the
			# walk-through tunnel reads as a cave cut into the rock.
			{"col": 3, "points": PackedVector2Array([
				Vector2(3567, 1780), Vector2(4573, 1780), Vector2(4573, 1900), Vector2(3567, 1900),
			]), "vc": PackedColorArray([Color(0.16, 0.14, 0.13), Color(0.16, 0.14, 0.13), Color(0.3, 0.27, 0.24), Color(0.3, 0.27, 0.24)])},
			# Right mountain, same walk-through tunnel — the RED flag sits inside.
			{"points": PackedVector2Array([
				Vector2(3567, 1780), Vector2(3620, 1620),
				Vector2(3720, 1440), Vector2(3840, 1260), Vector2(3980, 1120),
				Vector2(4120, 1060), Vector2(4260, 1140), Vector2(4380, 1300),
				Vector2(4480, 1500), Vector2(4560, 1720), Vector2(4573, 1780),
			])},
		],
		"platforms": [
			# Left tower staircase up the arena-facing (east) slope. Each step
			# is anchored INTO the slope — a gap between step and rock is a slot
			# soldiers fall into and wedge.
			{"p": Vector2(1222, 1560), "s": Vector2(170, 18)},
			{"p": Vector2(1112, 1360), "s": Vector2(190, 18)},
			{"p": Vector2(976, 1180),  "s": Vector2(190, 18)},
			# Right tower staircase up the arena-facing (west) slope.
			{"p": Vector2(3578, 1560), "s": Vector2(170, 18)},
			{"p": Vector2(3688, 1360), "s": Vector2(190, 18)},
			{"p": Vector2(3835, 1180), "s": Vector2(190, 18)},
			# Mid-arena high platform (M2 mount lives on top).
			{"p": Vector2(2500, 1400), "s": Vector2(560, 20)},
			{"p": Vector2(2500, 1160), "s": Vector2(220, 18)},
		],
		"player_spawn": Vector2(200, 1775),
		"bot_spawns": [Vector2(3688, 1340), Vector2(3835, 1160), Vector2(2500, 1130), Vector2(3578, 1540)],
		"m2_mounts": [Vector2(2500, 1380), Vector2(700, 1040), Vector2(4120, 1040)],
		"ctf_flags": [Vector2(710, 1900), Vector2(4090, 1900)],
		"vehicle_spawns": [Vector2(710, 1900), Vector2(4090, 1900)], "tank_spawns": [Vector2(308, 1900), Vector2(3688, 1900)],
		"inf_flag": Vector2(2400, 1710), "htf_flag": Vector2(2400, 1710),
		"dom_points": [Vector2(700, 1870), Vector2(2500, 1360), Vector2(4100, 1870)],
		# (Flat texture-square "scenery" decals removed in 1.13 — they read as
		# floating placeholder boxes over the hills.)
	},
	{
		"name": "Pillars",
		# Rugged interior: rolling hills at ground level, a wide central tunnel
		# and jagged spire "pillars" atop platforms. Everything is jet-reachable.
		"terrain_color": Color(0.34, 0.34, 0.32),
		"terrain_texture": "res://assets/textures/riverbed.png",
		"floor_texture": "res://assets/textures/riverbed.png",
		"polys": [
			# Left rugged ground with small bumps.
			{"points": PackedVector2Array([
				Vector2(200, 1900), Vector2(340, 1820), Vector2(500, 1780),
				Vector2(660, 1800), Vector2(820, 1740), Vector2(960, 1780),
				Vector2(1120, 1720), Vector2(1280, 1780), Vector2(1440, 1760),
				Vector2(1600, 1820), Vector2(1740, 1900),
			])},
			# Mesa tunnel — dark back wall (decorative, no collision) so the
			# walk-through tunnel reads as a cave cut into the rock.
			{"col": 3, "points": PackedVector2Array([
				Vector2(1800, 1780), Vector2(3123, 1780), Vector2(3123, 1900), Vector2(1800, 1900),
			]), "vc": PackedColorArray([Color(0.16, 0.14, 0.13), Color(0.16, 0.14, 0.13), Color(0.3, 0.27, 0.24), Color(0.3, 0.27, 0.24)])},
			# Central raised mesa with a wide walk-through tunnel underneath
			# (ceiling y=1780, floor = map ground).
			{"points": PackedVector2Array([
				Vector2(1800, 1780), Vector2(1900, 1620),
				Vector2(2040, 1460), Vector2(2260, 1360), Vector2(2540, 1340),
				Vector2(2800, 1400), Vector2(2980, 1520), Vector2(3080, 1680),
				Vector2(3123, 1780),
			])},
			# Right rugged ground with two spike-like bumps.
			{"points": PackedVector2Array([
				Vector2(3160, 1900), Vector2(3320, 1780), Vector2(3480, 1820),
				Vector2(3640, 1740), Vector2(3800, 1780), Vector2(3960, 1720),
				Vector2(4120, 1780), Vector2(4280, 1800), Vector2(4440, 1820),
				Vector2(4620, 1900),
			])},
		],
		"platforms": [
			# Pillars — narrow high platforms distributed across the map.
			{"p": Vector2(500, 1560),  "s": Vector2(90, 18)},
			{"p": Vector2(950, 1420),  "s": Vector2(90, 18)},
			{"p": Vector2(1300, 1560), "s": Vector2(90, 18)},
			{"p": Vector2(1620, 1240), "s": Vector2(110, 18)},
			{"p": Vector2(3300, 1240), "s": Vector2(110, 18)},
			{"p": Vector2(3620, 1560), "s": Vector2(90, 18)},
			{"p": Vector2(4000, 1420), "s": Vector2(90, 18)},
			{"p": Vector2(4400, 1560), "s": Vector2(90, 18)},
			# Central roof over the tunnel — jet up to reach the M2.
			{"p": Vector2(2400, 1140), "s": Vector2(340, 20)},
		],
		"player_spawn": Vector2(200, 1775),
		"bot_spawns": [Vector2(2400, 1110), Vector2(3620, 1530), Vector2(4000, 1390), Vector2(3300, 1210)],
		"ctf_flags": [Vector2(110, 1900), Vector2(4700, 1900)],
		"vehicle_spawns": [Vector2(150, 1900), Vector2(4650, 1900)],
		"inf_flag": Vector2(2400, 1900), "htf_flag": Vector2(2400, 1900),
		"dom_points": [Vector2(500, 1750), Vector2(2400, 1100), Vector2(4280, 1770)],
		"m2_mounts": [Vector2(2400, 1120)],
		# (Flat texture-square "scenery" decals removed in 1.13 — they read as
		# floating placeholder boxes over the hills.)
	},
]


const RadioMenu = preload("res://scripts/radio_menu.gd")
# Radio calls seen (any team) — tools/radio_test.gd reads it.
var radio_count := 0
# Kits picked up this match — tools/kit_test.gd reads it.
var kits_taken := 0


const Buggy = preload("res://scripts/buggy.gd")
const Tank = preload("res://scripts/tank.gd")
var _vehicles: Dictionary = {}   # vehicle_id -> buggy node (every peer)


func _init() -> void:
	_vehicles_sys = _attach(MatchVehicles.new(), "MatchVehicles")
	_bonuses = _attach(MatchBonuses.new(), "MatchBonuses")
	_votes = _attach(MatchVotes.new(), "MatchVotes")
	_modes = _attach(MatchModes.new(), "MatchModes")
	_net = _attach(MatchNet.new(), "MatchNet")
	_bots = _attach(MatchBots.new(), "MatchBots")
	_world = _attach(MatchWorld.new(), "MatchWorld")
	_hazards = _attach(MatchHazards.new(), "MatchHazards")


## A system helper is an internal child: freed with Main, invisible to
## get_children(), and never the target of an RPC (those stay on Main).
func _attach(h: Node, n: String) -> Node:
	h.name = n
	h.set("main", self)
	add_child(h, false, Node.INTERNAL_MODE_FRONT)
	return h


func _ready() -> void:
	if Net._smoke_arg("--smoke-round-secs") != "":
		round_time = maxf(10.0, float(Net._smoke_arg("--smoke-round-secs")))
		time_left = round_time
	TrustGuard.reset_match()
	# Dev override: `--mode=N` on the command line sets game_mode for headless smoke tests.
	# `--map=N` forces a specific MAPS index (useful for verifying each classic).
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--mode="):
			Settings.game_mode = int(arg.substr(7))
		elif arg.begins_with("--map="):
			Settings.map_index = int(arg.substr(6))
			Settings.custom_map_path = ""
	# Crosshair cursor = the mouse; aiming follows it (Soldat-style).
	Input.set_custom_mouse_cursor(load("res://assets/interface-gfx/cursor.png"), Input.CURSOR_ARROW, Vector2(12, 12))
	PoaLoader.preload_all()
	# Append the classic Soldat maps (ported from .pms via tools/pms_to_map.py)
	# to the built-in rotation. The three procedural remakes (Ascent / Towers /
	# Pillars) stay in slots 0–2 so existing Settings.map_index values still
	# resolve to the same map for players who had one pinned. (#53)
	for classic in MapIO.load_bundled_classics():
		MAPS.append(classic)
	if Net.is_networked():
		# Host picks the map (via Net.chosen_map_index). Clients receive it before
		# reaching this scene, so both peers build the same terrain.
		# #99: custom maps travel with the map RPC as a JSON blob (Net.custom_map_json)
		# so hand-edited ladder/M2/DOM positions stay in sync. Built-in maps still
		# just resolve by index — no blob needed, they're identical assets.
		_map = {}
		if Net.is_host() and Settings.custom_map_path != "":
			_map = MapIO.load_from_file(Settings.custom_map_path)
			if not _map.is_empty():
				Net.custom_map_json = MapIO.map_to_json(_map)
		if _map.is_empty() and Net.custom_map_json != "":
			_map = MapIO.json_to_map(Net.custom_map_json)
		if _map.is_empty():
			_map = MAPS[Net.chosen_map_index % MAPS.size()]
			cur_map_index = Net.chosen_map_index % MAPS.size()
			Net.custom_map_json = ""
	else:
		# Custom map (from the editor / user://maps/) short-circuits the built-in
		# rotation when Settings.custom_map_path is set (issue #31).
		_map = {}
		if Settings.custom_map_path != "":
			_map = MapIO.load_from_file(Settings.custom_map_path)
		if _map.is_empty():
			_map = MAPS[Settings.map_index % MAPS.size()]
			cur_map_index = Settings.map_index % MAPS.size()
			Settings.map_index = (Settings.map_index + 1) % MAPS.size()
	_normalize_team_sides()
	_world._apply_world()
	# Sky + parallax + ambient + post grade (scripts/gfx/atmosphere.gd, #270).
	Atmosphere.install(self, _map)
	_world._build_terrain()
	_world._build_gfx_world()
	_hazards._build()
	# Warm lazily-loaded art during the load, not mid-fight (frame hitches).
	preload("res://scripts/gostek.gd").warm_cache()
	if Net.replay_path != "":
		# Watching a replay: the map only, then the replay player draws the
		# recorded soldiers / shots / flags on top. No match logic runs.
		replay_mode = true
		var rp = preload("res://scripts/replay_player.gd").new()
		rp.main = self
		add_child(rp)
		return
	nav = NavGraph.load_for(_map)
	if nav.is_empty():
		_start_runtime_nav()
	_world._build_weather()
	_build_hud()
	_build_pause_menu()
	if Settings.training and not Net.is_networked() and hud != null:
		var tr := PanelContainer.new()
		tr.name = "Training"
		tr.set_script(preload("res://scripts/training.gd"))
		tr.set("main", self)
		hud.add_child(tr)
	_maybe_build_touch_controls()
	_build_maker_bar()
	_modes._spawn_mode_entities()
	_bonuses._spawn_bonus_boxes_init()
	_vehicles_sys._spawn_vehicles()
	kill.connect(_on_kill_scored)
	if not Net.is_dedicated and not Settings.training:
		recorder = preload("res://scripts/replay_recorder.gd").new()
		recorder.main = self
		add_child(recorder)

	if Net.is_networked():
		multiplayer.peer_disconnected.connect(_net._on_net_peer_disconnected)
		if Net.is_host():
			# Dedicated (headless) host: pure authority, no local player, no camera.
			# Fill the match with bots so a lone joining client has opponents (#54).
			if Net.is_dedicated:
				if Net.stats_url != "":
					ranked = preload("res://scripts/ranked.gd").new()
					ranked.main = self
					add_child(ranked)
				_spawn_bots()
				# Drain any net_client_ready calls that arrived before main.tscn
				# finished loading (#118 — race between ENet accept and scene load).
				for _pending in Net.consume_pending_clients():
					_handle_client_ready(_pending.id, _pending.name, _pending.version, str(_pending.get("token", "")))
				# #293: the match is loaded (comes after "listening on port"):
				# the release gate starts its clients on this line instead of
				# guessing a load time.
				print("Dedicated match ready: map=%s mode=%d bots=%d" % [str(_map.get("name", "?")), int(Settings.game_mode), _bots_by_id.size()])
			else:
				_net._spawn_networked_player(1)  # host is peer 1
				# Listen host: same bot roster as single player (Bots setting;
				# 0 = none, and Host Settings can change it live).
				_spawn_bots()
		else:
			# Client asks the host to spawn us; host also mirrors any existing players.
			# Send to Net autoload (always present) — it forwards to Main or buffers
			# if the host's main.tscn is still loading (#118).
			Net.disconnected.connect(_on_lost_host)
			# (--smoke-net-version=X: the gate plays an older build's handshake.)
			var nv: String = preload("res://scripts/game_info.gd").net_version()
			if Net._smoke_arg("--smoke-net-version") != "":
				nv = Net._smoke_arg("--smoke-net-version")
			Net.rpc_id(1, "net_client_ready", Settings.display_name(), nv, Net.session_token)
			Net.rpc_id(1, "net_profile", Settings.profile_id)
	else:
		_spawn_player()
		_spawn_bots()


static func _arr_to_color(a: Variant) -> Color:
	if typeof(a) == TYPE_COLOR:
		return a
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 3:
		return Color(0, 0, 0, 0)
	var arr: Array = a
	return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]) if arr.size() > 3 else 1.0)


func _make_polygon_body(points: PackedVector2Array, col: Color, tex_path: String = "",
		uvs_norm: PackedVector2Array = PackedVector2Array(), draw_outline: bool = true,
		col_class: int = 0, vcols: PackedColorArray = PackedColorArray()) -> Node2D:
	return _world._make_polygon_body(points, col, tex_path, uvs_norm, draw_outline, col_class, vcols)


# ── Graphics layers (gfx.gd) ────────────────────────────
var terrain_fx: Node2D = null       # terrain_fx.gd — edge shading / rim light / grass
var soldier_shadows: Node2D = null  # soldier_shadows.gd
var ambient_fx: CPUParticles2D = null


func apply_gfx_quality() -> void:
	_world.apply_gfx_quality()


# ── Placement geometry (no physics queries needed) ─────────────────────────


func _geom_ground_y(x: float, from_y: float) -> float:
	return _world._geom_ground_y(x, from_y)


func _settle_on_ground(pos: Vector2) -> Vector2:
	return _world._settle_on_ground(pos)


## Maker-map kill zones (#286): bots' pit guard and goal picking.
func has_hazards() -> bool:
	return not _hazards.zones.is_empty()


func hazard_at(p: Vector2, grow: float = 0.0) -> bool:
	return _hazards.hazard_at(p, grow)


func hazard_safe_goal(p: Vector2) -> Vector2:
	return _hazards.safe_goal(p)


# ── Maker mode PLAY / EDIT (#286) ───────────────────────
# The editor's PLAY button saves the map, stores its own state in
# Net.maker_return and starts this scene; the first spawn is where the editor
# camera was, and EDIT (button / F5 / pause menu Quit) goes back to the editor,
# which restores the map, camera and undo history from Net.maker_return.

func _maker_spawn_override(p: Node2D) -> void:
	if Net.is_networked() or not Net.maker_return.has("spawn"):
		return
	var at: Vector2 = Net.maker_return["spawn"]
	Net.maker_return.erase("spawn")
	var g := _settle_on_ground(at)
	var gy := _geom_ground_y(g.x, g.y - 2.0)
	if gy == INF or gy > minf(KILL_Y, GROUND_Y + 1.0):
		return   # nothing to stand on below the camera: keep the map's own spawn
	p.position = _world._find_free_spot_near(Vector2(g.x, gy))


func _build_maker_bar() -> void:
	if Net.maker_return.is_empty() or Net.is_networked():
		return
	var layer := CanvasLayer.new()
	layer.name = "MakerBar"
	layer.layer = 40
	add_child(layer)
	var b := Button.new()
	b.name = "Edit"
	b.text = tr("EDIT") + "  (F5)"
	b.tooltip_text = tr("Back to the Maker, same spot, map unchanged.")
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 48 if UITheme.is_touch() else 40)
	UITheme.style_button(b, 18, true)
	# Top centre, under the score strip: clear of the touch controls.
	b.set_anchors_preset(Control.PRESET_CENTER_TOP)
	b.offset_left = -75
	b.offset_right = 75
	b.offset_top = 142
	b.offset_bottom = 142 + b.custom_minimum_size.y
	b.pressed.connect(maker_edit)
	layer.add_child(b)


func maker_edit() -> void:
	if Net.maker_return.is_empty():
		return
	get_tree().paused = false
	Settings.custom_map_path = ""
	Settings.save()
	get_tree().change_scene_to_file("res://scenes/map_editor.tscn")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F5 \
			and not Net.maker_return.is_empty():
		get_viewport().set_input_as_handled()
		maker_edit()


@rpc("any_peer", "call_local", "reliable")
func net_m2_mount(m2_id: int, peer_id: int) -> void:
	_vehicles_sys.net_m2_mount(m2_id, peer_id)


@rpc("any_peer", "call_local", "reliable")
func net_m2_dismount(m2_id: int) -> void:
	_vehicles_sys.net_m2_dismount(m2_id)


@rpc("any_peer", "unreliable_ordered")
func net_m2_state(m2_id: int, aim_dir: Vector2) -> void:
	_vehicles_sys.net_m2_state(m2_id, aim_dir)


@rpc("any_peer", "call_local", "reliable")
func net_m2_fire(m2_id: int, muzzle: Vector2, aim_dir: Vector2, shooter_team: int, shooter_name: String, stamp: int = 0) -> void:
	_vehicles_sys.net_m2_fire(m2_id, muzzle, aim_dir, shooter_team, shooter_name, stamp)


# ── Singleplayer spawn path ───────────────────────────

## Respawn with the gun picked in the limbo menu (or last switched to).
## Advance and Gun Game pick the weapon themselves.
func _apply_spawn_loadout(p: Node) -> void:
	if Settings.advance or Settings.game_mode == Settings.MODE_GG:
		return
	# #256: a banned pick falls back to the first allowed weapon in that slot.
	var prim: Array = p.get("weapons")
	var wi: int = clampi(Settings.spawn_primary, 0, prim.size() - 1)
	if MatchConfig.weapon_banned(str(prim[wi]["name"])):
		wi = 0
		for i in prim.size():
			if not MatchConfig.weapon_banned(str(prim[i]["name"])):
				wi = i
				break
	var sec: Array = p.get("secondary")
	var si: int = clampi(Settings.spawn_secondary, 0, sec.size() - 1)
	if MatchConfig.weapon_banned(str(sec[si]["name"])):
		si = 0
		for j in sec.size():
			if not MatchConfig.weapon_banned(str(sec[j]["name"])):
				si = j
				break
	p.set("weapon_index", wi)
	p.set("secondary_index", si)

func _spawn_player() -> void:
	var p := player_scene.instantiate()
	# Team modes: start on BLUE's own side of the map (by its flag), not at the
	# map's single player_spawn, which on many ported maps sits in RED's base.
	# FFA: any spawn point, preferring ones away from the bots.
	var ffa: Array = (_map.get("bot_spawns", []) as Array).duplicate()
	ffa.append(_map["player_spawn"])
	var my_team: int = TEAM_BLUE if Settings.is_team_mode() else 0
	var pick: Vector2 = _team_spawn_pick(TEAM_BLUE) if Settings.is_team_mode() else _pick_spawn_away(ffa, 0)
	p.position = _safe_spawn_near(pick, my_team)
	_maker_spawn_override(p)
	# In team modes player joins BLUE (team 1); in DM/RM she's team 0 (FFA).
	if Settings.is_team_mode():
		p.team = TEAM_BLUE
		p.color = Color(0.35, 0.55, 1.0)
	else:
		p.team = 0
	p.display_name = Settings.display_name()
	# Advance mode: start with the humble knife.
	if Settings.advance:
		p.set("using_secondary", true)
		p.set("secondary_index", 1)  # Knife
	# Gun Game: restore the persisted rung so death keeps you on the same weapon.
	if Settings.game_mode == Settings.MODE_GG:
		p.gg_level = _modes._gg_get(str(p.display_name))
	_apply_spawn_loadout(p)
	p.died.connect(_on_player_died)
	add_child(p)
	player = p
	_bind_local_camera(p)
	if hud:
		hud.player = p
	# SP respawn — end the spectator cam so the new body's camera takes over (#75).
	_end_spectator()
	# Clear the death screen too: the timed respawn hides it by counting down,
	# but a Survival round reset (no countdown) left "Waiting for next round"
	# and the grey overlay up over the new life.
	if hud and hud.has_method("_hide_death"):
		hud._hide_death()
	Sfx.spawn(p.global_position)


func _on_player_died() -> void:
	# Kick off spectator (#75) — camera detaches from the dying body and follows
	# the nearest living soldier. Uses the just-died body's last known position as
	# the anchor for the first target pick so the transition doesn't hop the view.
	_begin_spectator()
	var rewinding: bool = killcam != null and killcam.is_active()
	# In MP the host owns respawn scheduling (see player.gd::_die), so main only
	# shows the death UI — no local timer needed. SP still schedules here.
	if Net.is_networked():
		var mp_delay: float = _respawn_delay_for_team(int(player.team))
		if rewinding:
			mp_delay += _killcam_pad(mp_delay)
		else:
			request_respawn_ready.call_deferred()   # nothing to watch: respawn on the normal timer
		if hud:
			if Settings.survival and round_active:
				hud.show_death(str(player.last_killer), str(player.last_weapon), -1.0)
			else:
				hud.show_death(str(player.last_killer), str(player.last_weapon), mp_delay)
		# The body lingers ~1.5 s as an inert husk (see player._become_husk);
		# drop our references now so nothing treats it as the live player.
		player = null
		if hud:
			hud.player = null
		return
	# Survival: no respawn until round ends. _reset_round will (re)spawn everyone
	# (also when we die on the winner screen — a timer here would add a 2nd body).
	if Settings.survival:
		if hud:
			# Negative delay = HUD shows "waiting for next round" instead of a countdown.
			hud.show_death(str(player.last_killer), str(player.last_weapon), -1.0)
		return
	var delay: float = _respawn_delay_for_team(int(player.team))
	var pad: float = _killcam_pad(delay) if rewinding else 0.0
	if hud:
		hud.show_death(str(player.last_killer), str(player.last_weapon), delay + pad)
	_respawn_gate(0, delay, pad, func() -> void:
		# A round reset in between may already have spawned us.
		if player == null or not is_instance_valid(player) or bool(player.get("dead")):
			_spawn_player())


func _begin_spectator() -> void:
	if spectator == null or not is_instance_valid(spectator):
		return
	var anchor: Vector2 = Vector2.ZERO
	var killer := ""
	var weapon := ""
	if is_instance_valid(player):
		anchor = player.global_position
		killer = str(player.last_killer)
		weapon = str(player.last_weapon).replace(" (headshot)", "")
		if killer == str(player.display_name):
			killer = ""
	spectator.activate(anchor, killer, weapon)
	# Kill cam rewind: replay the last seconds (from this client's recorder).
	if killer != "" and Settings.killcam_replay and killcam != null and recorder != null and is_instance_valid(player):
		killcam.start(recorder, killer, str(player.display_name), weapon)


func _end_spectator() -> void:
	if killcam != null and is_instance_valid(killcam):
		killcam.stop(false, false)
	if spectator != null and is_instance_valid(spectator):
		spectator.deactivate()


# ── Respawn gate (kill cam rewind) ──────────────────────
# A death waits `base` seconds as always, plus `pad` while the kill cam
# rewind plays. The player can skip it (request_respawn_ready); the respawn
# then happens as soon as the normal `base` delay is over. Keyed per peer on
# the host (0 = singleplayer local player).
var _rs_state: Dictionary = {}
var _rs_tok := 0
var _rs_early: Dictionary = {}   # key -> msec a "ready" arrived before its gate existed


## Extra wait so a full rewind fits before the respawn (none if the normal
## delay is already long enough, e.g. INF attackers).
func _killcam_pad(base: float) -> float:
	return maxf(0.0, KillcamRewind.LENGTH + 0.3 - base)


func _respawn_gate(key: int, base: float, pad: float, fire: Callable) -> void:
	_rs_tok += 1
	var tok := _rs_tok
	var early: bool = Time.get_ticks_msec() - int(_rs_early.get(key, -100000)) < 1500
	_rs_early.erase(key)
	_rs_state[key] = {"ready": pad <= 0.0 or early, "base": false, "tok": tok, "fire": fire}
	get_tree().create_timer(base).timeout.connect(func() -> void:
		# #249: SceneTreeTimers always fire, even after a scene change freed
		# this Main — same guard every other timer lambda here carries.
		if not is_inside_tree():
			return
		var st: Variant = _rs_state.get(key)
		if st == null or int(st.tok) != tok:
			return
		st.base = true
		if bool(st.ready):
			_rs_fire(key))
	if pad > 0.0:
		get_tree().create_timer(base + pad).timeout.connect(func() -> void:
			if not is_inside_tree():
				return
			var st: Variant = _rs_state.get(key)
			if st != null and int(st.tok) == tok:
				_rs_fire(key))


func _rs_fire(key: int) -> void:
	var st: Variant = _rs_state.get(key)
	if st == null:
		return
	_rs_state.erase(key)
	(st.fire as Callable).call()


func _rs_ready(key: int) -> void:
	var st: Variant = _rs_state.get(key)
	if st == null:
		_rs_early[key] = Time.get_ticks_msec()
		return
	st.ready = true
	if bool(st.base):
		_rs_fire(key)


## Local player is done watching (rewind ended / skipped / nothing to show).
func request_respawn_ready() -> void:
	if not Net.is_networked():
		_rs_ready(0)
	elif Net.is_host():
		_rs_ready(1)
	else:
		rpc_id(1, "net_respawn_ready")


@rpc("any_peer", "reliable")
func net_respawn_ready() -> void:
	if Net.is_host():
		_rs_ready(multiplayer.get_remote_sender_id())


func _respawn_delay_for_team(t: int) -> float:
	# INF attackers pay a longer respawn (defender advantage).
	if Settings.game_mode == Settings.MODE_INF and t == TEAM_RED:
		return 5.0
	return 2.0


func _safe_spawn_near(pos: Vector2, team: int) -> Vector2:
	# Slide the spawn horizontally when an enemy soldier is standing on the intended
	# slot — otherwise the respawning bot pops right into the player's crosshair.
	const MIN_ENEMY_DIST := 280.0
	const MAX_STEPS := 6
	const STEP := 220.0
	# Never hand out a spawn inside terrain (bad map data / editor maps).
	pos = _world._find_free_spot_near(pos)
	var candidate := pos
	for step in MAX_STEPS:
		var clear := true
		# A sideways-shifted slot must still be open air with ground under it
		# before the kill line — otherwise we'd spawn someone inside a wall or
		# over a pit on the narrower ported maps.
		if step > 0 and (not _world._spot_is_clear(candidate) or _geom_ground_y(candidate.x, candidate.y - 2.0) > minf(KILL_Y, GROUND_Y + 1.0)):
			clear = false
		# ...and in the same room, on ground you can stand on. HH's spawns
		# slid 440 px left straight through the building wall onto the steep
		# outside face, and bots slid off the map on every respawn.
		if clear and step > 0 and not _spawn_slide_ok(pos, candidate):
			clear = false
		# ...and never onto Maker spikes / lava (#286): the 3rd slide off a
		# CTF base spawn landed bots in a spike strip.
		if clear and step > 0 and has_hazards():
			var hg: float = _geom_ground_y(candidate.x, candidate.y - 2.0)
			if hazard_at(Vector2(candidate.x, (hg if hg != INF else candidate.y) - 6.0), 40.0):
				clear = false
		for s in get_tree().get_nodes_in_group("soldier"):
			if not clear:
				break
			if not is_instance_valid(s) or bool(s.get("dead")):
				continue
			if int(s.get("team")) == team:
				continue
			if candidate.distance_to(s.global_position) < MIN_ENEMY_DIST:
				clear = false
				break
		if clear:
			return candidate
		# Alternate left/right around the original slot; clamp to the map interior.
		var offset := STEP * float(step + 1) * (1.0 if step % 2 == 0 else -1.0)
		candidate = Vector2(clampf(pos.x + offset, 80.0, MAP_W - 80.0), pos.y)
	# Every shifted slot was blocked — the original (verified-free) slot wins.
	return pos


func _spawn_slide_ok(from: Vector2, to: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from + Vector2(0, -14), to + Vector2(0, -14), 1 | 4)
	if not space.intersect_ray(q).is_empty():
		return false
	var g0: float = _geom_ground_y(to.x - 10.0, to.y - 2.0)
	var g1: float = _geom_ground_y(to.x + 10.0, to.y - 2.0)
	var gm: float = _geom_ground_y(to.x, to.y - 2.0)
	if gm == INF or g0 == INF or g1 == INF:
		return false
	# Standing ground within a short drop, not a cliff face (> ~50° over 20 px).
	return gm - to.y < 120.0 and absf(g1 - g0) < 24.0


func _spawn_bots() -> void:
	_bots._spawn_bots()


var ranked: Node = null   # ranked.gd on a dedicated host with a stats URL
var replay_mode := false  # this scene is showing a recorded match
var recorder: Node = null # replay_recorder.gd (every match except dedicated servers)


func _team_base(t: int) -> Vector2:
	# Where a team "lives": its CTF flag home, else BLUE = player_spawn and
	# RED = the spawn farthest from it.
	for f in flags:
		if is_instance_valid(f) and int(f.get_meta("team")) == t and f.has_meta("home"):
			return f.get_meta("home")
	var ps: Vector2 = _map["player_spawn"]
	if t == TEAM_BLUE:
		return ps
	var far := ps
	for v in _map.get("bot_spawns", []):
		if (v as Vector2).distance_to(ps) > far.distance_to(ps):
			far = v
	return far


# Team modes put each side by its own flag. Ported Soldat maps label their
# spawn groups alpha/bravo, but on about a third of them that is the opposite
# of our BLUE/RED flag order, and on some the two groups are mixed around the
# middle, so BLUE could start at RED's flag. Re-split the map's spawn points
# by which flag they're nearer to (keeping at least two per side).
func _normalize_team_sides() -> void:
	var fl: Array = _map.get("ctf_flags", [])
	if fl.size() < 2:
		return
	var pool: Array = []
	var ts: Variant = _map.get("team_spawns", {})
	if typeof(ts) == TYPE_DICTIONARY:
		for k in (ts as Dictionary):
			for v in (ts as Dictionary)[k]:
				if not pool.has(v):
					pool.append(v)
	var fb: Vector2 = fl[0]
	var fr: Vector2 = fl[1]
	var blue: Array = []
	var red: Array = []
	for pass_i in 2:
		if pass_i == 1:
			# One side came up short (all of a map's team spawns on one half):
			# widen the pool with the general spawn points too.
			if blue.size() >= 2 and red.size() >= 2:
				break
			for v in _map.get("bot_spawns", []):
				if not pool.has(v):
					pool.append(v)
			if not pool.has(_map["player_spawn"]):
				pool.append(_map["player_spawn"])
		blue.clear()
		red.clear()
		for v in pool:
			if (v as Vector2).distance_to(fb) <= (v as Vector2).distance_to(fr):
				blue.append(v)
			else:
				red.append(v)
	# A side with no spawn points of its own (some maps put every spawn on one
	# half) spawns at its flag base; the free-spot finder settles it on ground.
	for side in [[blue, fb], [red, fr]]:
		var lst: Array = side[0]
		if lst.is_empty():
			var f: Vector2 = side[1]
			lst.append(f + Vector2(0, -40))
	_map["team_spawns"] = {TEAM_BLUE: blue, TEAM_RED: red}


func _centroid(pts: Array) -> Vector2:
	var c := Vector2.ZERO
	for v in pts:
		c += v as Vector2
	return c / maxf(1.0, float(pts.size()))


# A spawn point on team t's own side (team modes), away from enemies.
func _team_spawn_pick(t: int) -> Vector2:
	return _pick_spawn_away(_team_spawn_list(t), t)


# Classic Soldat respawns at a random spawn point, which can drop you next to
# someone who's already aiming at the spot. Prefer the points farthest from
# living enemies, with a little randomness among the best few so spawns don't
# become predictable.
func _pick_spawn_away(cands: Array, team: int) -> Vector2:
	if cands.is_empty():
		return _map["player_spawn"]
	var enemies: Array = []
	for s in get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(s) and not bool(s.get("dead")) and int(s.get("team")) != team:
			enemies.append((s as Node2D).global_position)
	if enemies.is_empty():
		return cands[randi() % cands.size()]
	var scored: Array = []
	for c in cands:
		var near := INF
		for e in enemies:
			near = minf(near, (c as Vector2).distance_to(e))
		scored.append([near, c])
	scored.sort_custom(func(a, b) -> bool: return a[0] > b[0])
	var top: int = clampi(int(ceil(scored.size() / 3.0)), 1, 3)
	return scored[randi() % top][1]


func _team_spawn_list(t: int) -> Array:
	# Team modes spawn each side at its own base (Soldat alpha/bravo spawns for
	# ported maps; otherwise the half of all spawn points nearest the base).
	# Previously every bot used the shared list, so BLUE bots often spawned
	# inside RED's base and vice versa.
	var ts: Variant = _map.get("team_spawns", {})
	if typeof(ts) == TYPE_DICTIONARY and (ts as Dictionary).has(t) and not ((ts as Dictionary)[t] as Array).is_empty():
		return (ts as Dictionary)[t]
	var all: Array = (_map.get("bot_spawns", []) as Array).duplicate()
	all.append(_map["player_spawn"])
	var base := _team_base(t)
	all.sort_custom(func(a, b) -> bool: return (a as Vector2).distance_to(base) < (b as Vector2).distance_to(base))
	return all.slice(0, maxi(1, int(ceil(all.size() / 2.0))))


func _reconcile_bots() -> void:
	_bots._reconcile_bots()


func _live_bots() -> Array:
	return _bots._live_bots()


func _spawn_bot(pos: Vector2, team: int, bname: String, loadout: String = "AK-74") -> void:
	_bots._spawn_bot(pos, team, bname, loadout)


# ── Shared ────────────────────────────────────────────

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.set_script(hud_script)
	hud.name = "HUD"
	add_child(hud)
	hud.player = player
	hud.map_name = str(_map["name"])
	if OS.get_cmdline_user_args().has("--hosthits-log"):
		print("HOSTHITS-MAP %s" % str(_map["name"]))   # (tools/hosthits_test.gd: map changes)
	kill.connect(hud._on_kill)
	# Spectator (#75) — created alongside the HUD so it exists before any player
	# dies. Camera stays disabled until activate() is called on local death.
	spectator = Spectator.new()
	spectator.name = "Spectator"
	spectator.main = self
	add_child(spectator)
	killcam = KillcamRewind.new()
	killcam.name = "KillcamRewind"
	killcam.main = self
	add_child(killcam)
	killcam.finished.connect(func(_skipped: bool) -> void: request_respawn_ready())


func _build_pause_menu() -> void:
	# Pause overlay lives above the HUD so ESC can freeze the round without
	# stealing input while the death screen / arrow / crosshair remain visible.
	var pm := CanvasLayer.new()
	pm.name = "PauseMenu"
	pm.set_script(pause_menu_script)
	add_child(pm)


func _maybe_build_touch_controls() -> void:
	# Touch overlay (#116) only spawns on touch devices (Android build) so
	# desktop KB/M + gamepad (#115) never sees the on-screen joystick + buttons.
	# The dedicated headless path skips it too — no viewport, no player.
	if Net.is_dedicated:
		return
	var touch: bool = OS.has_feature("android") \
		or OS.has_feature("mobile") \
		or DisplayServer.is_touchscreen_available() \
		or "--force-touch" in OS.get_cmdline_user_args()   # dev: preview the overlay on desktop
	if not touch:
		return
	var layer := CanvasLayer.new()
	layer.name = "TouchControls"
	# Above the HUD (layer 0) so the joystick + buttons stay visible over the
	# scoreboard / kill feed. Below the pause menu (which uses its own default
	# layer) so pausing hides them naturally when the pause overlay covers them.
	layer.layer = 50
	add_child(layer)
	var tc := TouchControls.new()
	tc.name = "Overlay"
	layer.add_child(tc)


func _bind_local_camera(p: Node) -> void:
	if p == null or p.get("cam") == null:
		return
	p.cam.limit_left = 0
	p.cam.limit_right = int(MAP_W)
	if spectator != null and is_instance_valid(spectator) and spectator.get("cam") != null:
		spectator.cam.limit_right = int(MAP_W)
		spectator.cam.limit_bottom = int(MAP_H)
	# Clamp to the actual map rect so the camera can't drift into void above or past the ground body.
	p.cam.limit_top = 0
	p.cam.limit_bottom = int(MAP_H)


# ── Networked spawn path ──────────────────────────────


func _schedule_peer_respawn(peer_id: int, t: int) -> void:
	_net._schedule_peer_respawn(peer_id, t)


@rpc("authority", "call_local", "reliable")
func net_bot_chat(author: String, msg: String) -> void:
	_bots.net_bot_chat(author, msg)


@rpc("authority", "call_remote", "reliable")
func net_stats_sync(stats: Dictionary) -> void:
	_net.net_stats_sync(stats)


@rpc("any_peer", "call_remote", "reliable")
func net_proj(node_name: String, method: String, args: Array) -> void:
	_net.net_proj(node_name, method, args)


func ready_peer_ids() -> Array:
	return _net.ready_peer_ids()


@rpc("authority", "reliable")
func net_ready_list(ids: Array) -> void:
	_net.net_ready_list(ids)


func client_send_peer_ids() -> Array:
	return _net.client_send_peer_ids()


func bcast(method: StringName, args: Array = [], local: bool = false) -> void:
	_net.bcast(method, args, local)


func _handle_client_ready(sender_id: int, joiner_name: String = "", client_version: String = "", token: String = "") -> void:
	_net._handle_client_ready(sender_id, joiner_name, client_version, token)


@rpc("authority", "call_remote", "reliable")
func net_reject(reason: String) -> void:
	_net.net_reject(reason)


func _on_lost_host() -> void:
	_net._on_lost_host()


@rpc("any_peer", "reliable")
func net_spawn_ack() -> void:
	_net.net_spawn_ack()


@rpc("authority", "reliable")
func net_match_config_apply(cfg: Dictionary) -> void:
	_net.net_match_config_apply(cfg)


@rpc("authority", "call_local", "reliable")
func net_match_restart(map_idx: int, mode_idx: int) -> void:
	_net.net_match_restart(map_idx, mode_idx)


func _exit_tree() -> void:
	if _nav_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_nav_task)   # never leave the builder running on a freed scene
		_nav_task = -1
	# Leaving mid-round (quit to menu, disconnect, map change): keep what was played.
	if recorder != null and is_instance_valid(recorder):
		recorder.save()


func _do_reload_main() -> void:
	_net._do_reload_main()


@rpc("authority", "call_local", "reliable")
func net_spawn_player(peer_id: int, spawn_pos: Vector2, display_name: String, assigned_team: int = -1) -> void:
	_net.net_spawn_player(peer_id, spawn_pos, display_name, assigned_team)


@rpc("authority", "call_local", "reliable")
func net_despawn_player(peer_id: int) -> void:
	_net.net_despawn_player(peer_id)


@rpc("authority", "call_local", "reliable")
func net_objective_event(kind: String, team: int, who: String) -> void:
	_net.net_objective_event(kind, team, who)


@rpc("authority", "call_local", "reliable")
func net_kill_feed(killer_name: String, victim_name: String, weapon_name: String, killer_team: int, victim_team: int) -> void:
	_net.net_kill_feed(killer_name, victim_name, weapon_name, killer_team, victim_team)


@rpc("any_peer", "call_local", "reliable")
func net_radio(author: String, code: String, sender_team: int) -> void:
	_net.net_radio(author, code, sender_team)


# Up / mid / down relative to the two flag bases (Soldat's convention).
func radio_dir(pos: Vector2) -> String:
	var ys: Array = []
	for f in flags:
		if is_instance_valid(f) and f.has_meta("home"):
			ys.append(float((f.get_meta("home") as Vector2).y))
	var mid_y: float = MAP_H * 0.5
	if not ys.is_empty():
		mid_y = 0.0
		for y in ys:
			mid_y += float(y)
		mid_y /= ys.size()
	var band: float = maxf(220.0, MAP_H * 0.12)
	if pos.y < mid_y - band:
		return "up"
	if pos.y > mid_y + band:
		return "down"
	return "mid"


@rpc("any_peer", "call_local", "reliable")
func net_chat(author: String, msg: String, scope: String, sender_team: int) -> void:
	_net.net_chat(author, msg, scope, sender_team)


# ── Match / score / round ─────────────────────────────

# Low-FPS guard: if a match settles under ~35 fps for 8 s (after a 6 s
# warm-up), switch Lo-fi on once and say so. Never on headless / dedicated,
# and only the first time (Settings.lofi_auto_done).
var _perf_t := 0.0
var _perf_frames := 0
var _perf_done := false


func _tick_perf_watch(delta: float) -> void:
	if _perf_done or Settings.lofi or Settings.lofi_auto_done or Net.is_dedicated \
			or DisplayServer.get_name() == "headless" or get_tree().paused \
			or "--no-perf-guard" in OS.get_cmdline_user_args():
		return
	_perf_t += delta
	if _perf_t < 6.0:
		_perf_frames = 0
		return
	_perf_frames += 1
	if _perf_t < 14.0:
		return
	_perf_done = true
	var fps: float = float(_perf_frames) / (_perf_t - 6.0)
	if fps >= 35.0:
		return
	# Step the graphics preset down one notch (High → Medium → Low).
	Settings.set_gfx_quality(maxi(0, int(Settings.gfx_quality) - 1))
	Settings.lofi_auto_done = true
	Settings.save()
	apply_gfx_quality()
	if hud:
		var qn: String = ["Low", "Medium", "High"][int(Settings.gfx_quality)]
		hud.post_chat("SYSTEM", "Low frame rate (%d fps): graphics set to %s. Settings → Video to change it." % [int(fps), qn], false)


# Online: the host measures each client's round trip (ENet) and shares the
# table every 2 s so everyone's scoreboard has a PING column.
var peer_pings: Dictionary = {}   # display name -> ms
var _ping_t := 0.0


static func remember_players(names: Array, now: int) -> void:
	var list: Array = Settings.recent_players
	for nm in names:
		var found = null
		for e in list:
			if e is Dictionary and str(e.get("name", "")) == nm:
				found = e
				break
		if found == null:
			found = {"name": nm, "fav": false}
			list.push_front(found)
		found["last"] = now
	list.sort_custom(func(a, b): return int(a.get("last", 0)) > int(b.get("last", 0)))
	var keep: Array = []
	var others := 0
	for e in list:
		if bool(e.get("fav", false)):
			keep.append(e)
		elif others < 40:
			keep.append(e)
			others += 1
	Settings.recent_players = keep


@rpc("authority", "call_remote", "unreliable")
func net_pings(table: Dictionary) -> void:
	_net.net_pings(table)


# #266: round-trip probes (host -> client -> host) for the host's rewind.
@rpc("authority", "call_remote", "unreliable")
func net_rtt_probe(stamp: int) -> void:
	_net.net_rtt_probe(stamp)


@rpc("any_peer", "call_remote", "unreliable")
func net_rtt_echo(stamp: int) -> void:
	_net.net_rtt_echo(stamp)


## #287: build the bot graph in the background (pure data, no scene access).
func _start_runtime_nav() -> void:
	if _nav_task >= 0:
		return
	var nb := NavBuilder.new()
	# Jump-pad rides (#286) are simulated with the bots' physics as this
	# match's modifiers scale it (bot.gd: gravity, run speed + acceleration).
	nb.pad_gravity = Bot.BASE_GRAVITY * MatchConfig.mod_gravity()
	nb.pad_run = Bot.RUN_SPEED * MatchConfig.mod_speed()
	nb.pad_accel = 1300.0 * MatchConfig.mod_speed()
	nb.pad_max_fall = Bot.MAX_FALL
	_nav_builder = nb
	var m: Dictionary = _map.duplicate(true)
	var b: RefCounted = _nav_builder
	_nav_task = WorkerThreadPool.add_task(func() -> void: _nav_data = b._build(m), false, "bot nav build")


func _tick_runtime_nav() -> void:
	if _nav_task < 0 or not WorkerThreadPool.is_task_completed(_nav_task):
		return
	var t0 := Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(_nav_task)
	_nav_task = -1
	if nav != null and nav.has_method("adopt"):
		nav.adopt(_nav_data)
	var st: Dictionary = _nav_data.get("stats", {})
	nav_runtime_ms = int(st.get("ms", 0))
	print("NAV runtime graph for %s: %d nodes, %d links, %d bridges in %d ms" % [str(_map.get("name", "?")),
		int(st.get("nodes", 0)), int(st.get("edges", 0)), int(st.get("bridges", 0)), nav_runtime_ms])
	_nav_data = {}
	_nav_builder = null
	nav_adopt_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _process(delta: float) -> void:
	_tick_runtime_nav()
	_world._tick_ambient_fx()
	if replay_mode:
		return
	_net._tick_pings(delta)
	_net._tick_rtt(delta)
	_net._tick_recent_players(delta)
	# Vote timer + cooldown ticks — before the client early-return so the vote
	# countdown reads smoothly on every peer between host state broadcasts (#77).
	_votes._tick_vote(delta)
	# Kill line + anti-stuck watchdog — per peer, for locally-owned soldiers.
	_world._tick_soldier_safety(delta)
	# Maker-map spikes / lava / jump pads (#286) — same per-authority rule.
	_hazards._tick(delta)
	_tick_perf_watch(delta)
	# New round (on every peer, from the synced round_active flag): fresh board.
	if round_active and not _stats_round_active:
		player_stats.clear()
	_stats_round_active = round_active
	# Client: state is driven entirely by host's net_match_state RPCs.
	if Net.is_networked() and not Net.is_host():
		# BR ring damage on a client's own body is decided by the host (#266,
		# host_hits.gd). The Rambo bow's regen shows here at once; the host's
		# ledger regenerates too and corrects any drift.
		if Settings.game_mode == Settings.MODE_RM and player != null and is_instance_valid(player) \
				and not bool(player.get("dead")) and player.has_method("current_weapon_name") \
				and str(player.current_weapon_name()) == "Rambo Bow":
			player.health = minf(100.0, float(player.health) + 40.0 * delta)
		return
	# Bonus box respawn timer (#78) — host / SP owns spawn cadence.
	_bonuses._tick_bonus_boxes(delta)
	_bonuses._smoke_bonus_tick(delta)   # gate C `drop` only (--smoke-bonus=KIND)
	# Objectives freeze on the winner screen — re-scoring there used to re-call
	# _end_round every tick and reset the countdown forever (DOM/BR/HTF).
	if not round_active:
		pass
	elif Settings.game_mode == Settings.MODE_CTF and flags.size() == 2:
		_modes._tick_ctf()
	elif Settings.game_mode == Settings.MODE_INF and flags.size() == 1:
		_modes._tick_inf()
	elif Settings.game_mode == Settings.MODE_HTF and flags.size() == 1:
		_modes._tick_htf(delta)
	elif Settings.game_mode == Settings.MODE_RM:
		_modes._tick_rambo()
	elif Settings.game_mode == Settings.MODE_PM:
		_modes._tick_pointmatch(delta)
	elif Settings.game_mode == Settings.MODE_DOM:
		_modes._tick_domination(delta)
	elif Settings.game_mode == Settings.MODE_BR:
		_modes._tick_battle_royale(delta)
	if round_active:
		time_left = maxf(0.0, time_left - delta)
		if time_left <= 0.0:
			_modes._end_round_by_time()
	else:
		winner_end_t = maxf(0.0, winner_end_t - delta)
		if winner_end_t <= 0.0:
			if not _votes._apply_next_map_vote():
				_reset_round()
	if Net.is_networked() and Net.is_host():
		_match_sync_cd -= delta
		if _match_sync_cd <= 0.0:
			_match_sync_cd = 1.0 / MATCH_SYNC_HZ
			_net._broadcast_match_state()
			if vote_active:
				_votes._broadcast_vote_state()
		# Flag positions + carriers stream faster so grabs/drops feel snappy.
		if flags.size() > 0:
			_flag_sync_cd -= delta
			if _flag_sync_cd <= 0.0:
				_flag_sync_cd = 1.0 / FLAG_SYNC_HZ
				_net._broadcast_flag_state()
		# Pickup physics stream at 10 Hz so thrown weapons + rambo bow stay in sync.
		_pickup_sync_cd -= delta
		if _pickup_sync_cd <= 0.0:
			_pickup_sync_cd = 1.0 / PICKUP_SYNC_HZ
			_bonuses._broadcast_pickup_state()
		# DOM cap progress, PM pickup availability, BR zone size — client _process
		# early-returns before the mode ticks, so without this broadcast clients
		# see stale objectives (neutral points, ghost diamonds, static BR ring).
		# #107: throttled to MODE_SYNC_HZ; was called every frame.
		_mode_sync_cd -= delta
		if _mode_sync_cd <= 0.0:
			_mode_sync_cd = 1.0 / MODE_SYNC_HZ
			_net._broadcast_mode_state()
		# Bot state (pos/vel/facing/health/loadout/dead) streams at 20 Hz — matches
		# the player net_state cadence so bot bodies read smoothly on clients (#55).
		if not _bots_by_id.is_empty():
			_bot_sync_cd -= delta
			if _bot_sync_cd <= 0.0:
				_bot_sync_cd = 1.0 / BOT_SYNC_HZ
				_broadcast_bot_state()


# ── Domination ─────────────────────────────────────────


func dom_points() -> Array:
	return _modes.dom_points()


# ── Battle Royale ──────────────────────────────────────


func br_zone() -> Dictionary:
	return _modes.br_zone()


func _on_kill_scored(killer_name: String, victim_name: String, _weapon_name: String, killer_team: int, victim_team: int) -> void:
	_modes._on_kill_scored(killer_name, victim_name, _weapon_name, killer_team, victim_team)


@rpc("authority", "call_local", "reliable")
func net_gg_set_level(display_name: String, level: int) -> void:
	_modes.net_gg_set_level(display_name, level)


@rpc("authority", "reliable")
func net_gg_state_sync(levels: Dictionary) -> void:
	_modes.net_gg_state_sync(levels)


func _end_round(team: int) -> void:
	_modes._end_round(team)


@rpc("authority", "call_remote", "reliable")
func net_next_maps(choices: Array, tally: Array) -> void:
	_votes.net_next_maps(choices, tally)


func next_map_name(i: int) -> String:
	return _votes.next_map_name(i)


func vote_next_map(i: int) -> void:
	_votes.vote_next_map(i)


@rpc("any_peer", "reliable")
func net_next_map_vote(i: int) -> void:
	_votes.net_next_map_vote(i)


func _reset_round() -> void:
	_modes._reset_round()


@rpc("authority", "call_remote", "reliable")
func net_round_reset() -> void:
	_modes.net_round_reset()


@rpc("authority", "reliable")
func net_match_state(new_scores: Dictionary, tl: float, active: bool, winner: int, we: float, note: String = "", gg_ranks: Dictionary = {}, gg_kills: Dictionary = {}) -> void:
	_net.net_match_state(new_scores, tl, active, winner, we, note, gg_ranks, gg_kills)


@rpc("authority", "unreliable_ordered")
func net_mode_state(payload: Dictionary) -> void:
	_net.net_mode_state(payload)


# ── Vote system (#77) ─────────────────────────────────
# Host-authoritative. Public entry points are request_vote/cast_vote/cancel_vote.
# Chat commands (/votemap /votekick /votecancel) route in via HUD.


# ── Host chat commands (#257) — the classic Soldat server set, driven from
# the chat line. Host / single-player only; the HUD rejects clients.

func host_addbot(skill: int, bot_name: String) -> void:
	_votes.host_addbot(skill, bot_name)

func host_set_bots(n: int) -> void:
	_votes.host_set_bots(n)

func host_kick(name: String) -> bool:
	return _votes.host_kick(name)

func host_restart_to(map_idx: int, mode_idx: int) -> void:
	_votes.host_restart_to(map_idx, mode_idx)

func trust_kick(peer_id: int, who: String) -> void:
	_votes.trust_kick(peer_id, who)


func host_say(text: String) -> void:
	_votes.host_say(text)

func host_toggle_ff() -> void:
	_votes.host_toggle_ff()


func request_vote(kind: String, arg: String) -> void:
	_votes.request_vote(kind, arg)


func cast_vote(is_yes: bool) -> void:
	_votes.cast_vote(is_yes)


func cancel_vote() -> void:
	_votes.cancel_vote()


@rpc("any_peer", "reliable")
func net_vote_start(kind: String, arg: String) -> void:
	_votes.net_vote_start(kind, arg)


@rpc("any_peer", "reliable")
func net_vote_cast(is_yes: bool) -> void:
	_votes.net_vote_cast(is_yes)


@rpc("authority", "reliable")
func net_vote_state(active: bool, kind: String, target: String, yes_ct: int, no_ct: int, tl: float, starter: String) -> void:
	_votes.net_vote_state(active, kind, target, yes_ct, no_ct, tl, starter)


@rpc("authority", "reliable")
func net_vote_end(kind: String, target_label: String, passed: bool, yes_ct: int, no_ct: int, reason: String) -> void:
	_votes.net_vote_end(kind, target_label, passed, yes_ct, no_ct, reason)


# ── Bonus pickups (#78) ───────────────────────────────
# Host owns spawn slots + collection detection. Boxes are Area2D nodes; the
# BonusPickup script emits `touched` on host only. Application of the effect
# is routed via each player's net_bonus_apply RPC (call_local) so every peer
# applies the same effect to the target replica.


func _on_bonus_touched(body: Node, bid: int, slot_idx: int) -> void:
	_bonuses._on_bonus_touched(body, bid, slot_idx)


func _collect_kit(body: Node, bid: int, slot_idx: int, kind: String) -> void:
	_bonuses._collect_kit(body, bid, slot_idx, kind)


@rpc("authority", "reliable")
func net_bonus_spawn(bid: int, pos: Vector2, kind: String) -> void:
	_bonuses.net_bonus_spawn(bid, pos, kind)


@rpc("authority", "reliable")
func net_bonus_despawn(bid: int) -> void:
	_bonuses.net_bonus_despawn(bid)


## #303: the local player drops his power-up (SP / host: now; client: asks).
func drop_powerup_request() -> void:
	_bonuses.drop_powerup_request()


@rpc("any_peer", "call_remote", "reliable")
func net_drop_powerup(target_pid: int) -> void:
	_bonuses.net_drop_powerup(target_pid)


func next_pickup_id() -> int:
	return _bonuses.next_pickup_id()


@rpc("authority", "reliable")
func net_pickup_state(arr: Array) -> void:
	_bonuses.net_pickup_state(arr)


@rpc("authority", "reliable")
func net_flag_state(arr: Array) -> void:
	_net.net_flag_state(arr)


# ── Bot replication (issue #55) ───────────────────────
# Host-only AI, host broadcasts per-bot state at BOT_SYNC_HZ so clients can render
# a matching replica. Spawn/despawn are reliable RPCs; state is unreliable_ordered
# to mirror the player net_state cadence.

func _broadcast_bot_state() -> void:
	_bots._broadcast_bot_state()


@rpc("authority", "reliable")
func net_spawn_bot(bot_id: int, spawn_pos: Vector2, team: int, display_name: String, loadout: String, cosmetics: Dictionary) -> void:
	_bots.net_spawn_bot(bot_id, spawn_pos, team, display_name, loadout, cosmetics)


@rpc("authority", "reliable")
func net_bot_despawn(bot_id: int) -> void:
	_bots.net_bot_despawn(bot_id)


@rpc("authority", "reliable")
func net_bot_die(bot_id: int) -> void:
	_bots.net_bot_die(bot_id)


@rpc("authority", "call_remote", "unreliable_ordered")
func net_bot_state(arr: Array) -> void:
	_bots.net_bot_state(arr)


# ── Vehicles (v1.19) ──────────────────────────────────
# Buggies spawn at the map's "vehicle_spawns", tanks at "tank_spawns",
# helicopters at "heli_spawns", planes at "plane_spawns" (#291)
# (tools/place_vehicles.py). The
# host owns them (damage, wrecks, respawns, who sits where); the driver's peer
# simulates movement and streams it. Every message goes through vehicle_send:
# single-player applies it directly, the host broadcasts it (and runs it), a
# client asks the host, which checks the sender and relays it.


func vehicle_send(method: StringName, args: Array, _reliable: bool) -> void:
	_vehicles_sys.vehicle_send(method, args, _reliable)


func vehicle_request_seat(v: Node, s: Node, enter: bool) -> void:
	_vehicles_sys.vehicle_request_seat(v, s, enter)


@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_seat_req(vid: int, enter: bool) -> void:
	_vehicles_sys.net_vehicle_seat_req(vid, enter)


func vehicle_bot_board(v: Node, bot: Node, want_seat := 1) -> void:
	_vehicles_sys.vehicle_bot_board(v, bot, want_seat)


@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_seat_bot(vid: int, seat: int, bot_id: int, enter: bool) -> void:
	_vehicles_sys.net_vehicle_seat_bot(vid, seat, bot_id, enter)


@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_seat(vid: int, seat: int, peer: int, enter: bool) -> void:
	_vehicles_sys.net_vehicle_seat(vid, seat, peer, enter)


@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_spawn(vid: int, spawn: Vector2, pos: Vector2, hp_v: float, alive_v: bool, kind: String = "buggy") -> void:
	_vehicles_sys.net_vehicle_spawn(vid, spawn, pos, hp_v, alive_v, kind)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_vehicle_state(vid: int, pos: Vector2, vel: Vector2, tilt: float, f: float, aim: Vector2) -> void:
	_vehicles_sys.net_vehicle_state(vid, pos, vel, tilt, f, aim)


@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_fire(vid: int, muzzle: Vector2, dir: Vector2, stamp: int = 0) -> void:
	_vehicles_sys.net_vehicle_fire(vid, muzzle, dir, stamp)


@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_hp(vid: int, hp_v: float) -> void:
	_vehicles_sys.net_vehicle_hp(vid, hp_v)


@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_destroy(vid: int, at: Vector2, killer: String, killer_team: int, violent: bool) -> void:
	_vehicles_sys.net_vehicle_destroy(vid, at, killer, killer_team, violent)


# #277: a seat-specific weapon (the helicopter pilot's rockets — the gunner's
# MG stays on net_vehicle_fire).
@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_fire_seat(vid: int, seat: int, muzzle: Vector2, dir: Vector2, stamp: int = 0) -> void:
	_vehicles_sys.net_vehicle_fire_seat(vid, seat, muzzle, dir, stamp)


# #277: the simulating peer reports a hard landing / wall hit / rotor strike /
# the crash that ends a spin-out; the host checks the sender and applies it.
@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_crash(vid: int, dmg: float, speed: float, final: bool) -> void:
	_vehicles_sys.net_vehicle_crash(vid, dmg, speed, final)


@rpc("any_peer", "call_remote", "reliable")
func net_vehicle_respawn(vid: int) -> void:
	_vehicles_sys.net_vehicle_respawn(vid)


func vehicle_hit_soldier(s: Node, dmg: float, killer: String, killer_team: int, vel: Vector2, weapon := "Buggy") -> void:
	_vehicles_sys.vehicle_hit_soldier(s, dmg, killer, killer_team, vel, weapon)
