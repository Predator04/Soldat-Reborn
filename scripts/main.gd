extends Node2D
## Main — sky, terrain, players, bots, HUD. Handles singleplayer + networked flows.

var player_scene := preload("res://scenes/player.tscn")
var bot_scene := preload("res://scenes/bot.tscn")
var sky_script := preload("res://scripts/sky.gd")
var parallax_script := preload("res://scripts/parallax.gd")
var hud_script := preload("res://scripts/hud.gd")
var pause_menu_script := preload("res://scripts/pause_menu.gd")
const PoaLoader = preload("res://scripts/poa_loader.gd")
const WeaponPickup = preload("res://scripts/weapon_pickup.gd")
const MapIO = preload("res://scripts/map_io.gd")
const Spectator = preload("res://scripts/spectator.gd")
const BonusPickup = preload("res://scripts/bonus_pickup.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const NavGraph = preload("res://scripts/nav_graph.gd")

signal kill(killer_name: String, victim_name: String, weapon_name: String, killer_team: int, victim_team: int)
signal objective(kind: String, team: int, who: String)   # grab/drop/return/capture/dom/point

var player: Node2D = null            # LOCAL player (whichever peer owns us)
var hud: CanvasLayer = null
var spectator: Node2D = null         # (#75) follow/free-cam while dead — owns its own Camera2D
# (#76) Kill-streak + multi-kill announcer state. Keyed by killer's display_name.
# {"streak": int (kills-per-life), "multi": int (kills within 2s), "multi_t": float,
#  "team": int (last-known team for banner tint)}. Runs on every peer so banners
# render locally; the kill-feed replication path (kill.emit → net_kill_feed) drives it.
var _streaks: Dictionary = {}
const STREAK_TITLES := {2: "Double Kill", 3: "Multi Kill", 4: "Killing Spree", 5: "Rampage", 6: "Godlike"}
const STREAK_ULTRA := "Ultra Godlike"    # 7+ collapses into a single top rung
const MULTI_KILL_WINDOW := 2.0            # seconds since previous kill still counts as multi
const STREAK_ANNOUNCE_END_MIN := 3        # streak length that earns an "ended X's N-kill streak" line
var _map: Dictionary = {}
var _players_by_id: Dictionary = {}  # peer_id -> player node (host only, but also mirrored on clients)
var _peer_names: Dictionary = {}    # peer_id -> chosen display name (host only; client sends it in net_client_ready)
var _peer_team_by_id: Dictionary = {}  # peer_id -> last team (every peer; survives death, for chat identity)
var _bot_pending: Dictionary = {}    # bot name -> true while its respawn timer runs
var _ready_peers: Dictionary = {}    # peer_id -> true (host only, gate for outbound state RPCs)
# Peers whose main.tscn is loaded — populated on net_client_ready (before the
# spawn ack). Gates reliable spawn broadcasts so bots/bonuses spawned between
# the client's "ready" and its ack don't get permanently missed (#84).
var _connected_peers: Dictionary = {}
# Bot registry (host authority) — bot_id → bot node. Mirrored on clients via the
# net_spawn_bot/net_despawn_bot RPCs so per-bot state can address each replica.
var _bots_by_id: Dictionary = {}
var _next_bot_id: int = 1
var _bot_sync_cd: float = 0.0
const BOT_SYNC_HZ := 20.0            # host → clients broadcast rate for bot pos/vel/facing/etc.
const BOT_STATE_CHUNK_MAX := 8       # #102: max bot entries per net_bot_state packet — keeps under ENet MTU (1392 B).

# Team modes: fixed team ids (player joins BLUE, enemy bots on RED).
const TEAM_BLUE := 1
const TEAM_RED := 2
# FFA bots each get their own team id starting here (see _spawn_bot_at).
const FFA_BOT_TEAM_BASE := 1000


static func bot_color_for_team(t: int) -> Color:
	if t == TEAM_BLUE:
		return Color(0.35, 0.55, 1.0)
	if t == TEAM_RED:
		return Color(0.85, 0.3, 0.25)
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
# HTF: while a team's carrier is alive with the flag, ticks accumulate. This
# fractional accumulator flushes to `scores` in whole points.
var _htf_accum: Dictionary = {}
# Rambo bow — the current carrier's id (or 0 for none). Only they can score.
var _rambo_carrier_id: int = 0
# Rambo bow — cooldown between carrier-death and the bow re-spawning at map center.
var _rambo_respawn_cd: float = 0.0
const RAMBO_RESPAWN_DELAY := 4.0
# Pointmatch — bookkeeping for respawning pickups (spawn_pos -> _next_respawn_t).
var _pm_pickups: Dictionary = {}

# Domination — control point nodes + per-team hold accumulator.
var _dom_points: Array = []
const DOM_CAPTURE_TIME := 4.0    # seconds standing on a neutral/enemy point to flip it
const DOM_SCORE_TO_WIN := 90     # (owned_points × 1 pt/sec) → ~90s of full control wins
var _dom_accum: Dictionary = {}  # team_id -> fractional accumulator (float)

# Battle Royale — shrinking safe zone.
var _br_zone_radius: float = 2200.0
var _br_zone_center: Vector2 = Vector2(2400.0, 1200.0)
const BR_SHRINK_RATE := 42.0   # px/sec — full ring closes in ~52s
const BR_ZONE_MIN := 180.0
const BR_ZONE_DPS := 22.0      # damage/sec applied outside the ring

# Gun Game (MODE_GG) — per-soldier rung on the 16-weapon ladder, keyed by
# display_name so the level survives death/respawn (a fresh body reads its
# rung from here in _spawn_*). Host-authoritative in MP; the RPC below fans
# each update out to every peer so client-owned players re-apply the weapon.
const GG_KNIFE_LEVEL := 15
const GG_GOLD_KNIFE_LEVEL := 16
# Ladder weapon names in rung order — mirrors Player.GG_LADDER. Used to
# validate that a kill was made with the killer's current rung weapon (so
# grenade / dropped-weapon / bonus-forced kills don't accidentally advance).
const GG_LADDER_NAMES := [
	"USSOCOM", "Deagles", "MP5", "Steyr AUG", "AK-74", "Spas-12",
	"Ruger 77", "Minimi", "M79", "Minigun", "Flamethrower", "Rambo Bow",
	"LAW", "Barrett", "Chainsaw", "Knife",
]
var _gg_levels: Dictionary = {}
# Per-soldier kill tally for Gun Game (#91). Keyed by display_name so it
# survives death/respawn. Host-authoritative; mirrored to clients via the
# match-state broadcast. Cleared with _gg_levels on round reset.
var _gg_kills: Dictionary = {}

# ── Match state (host-authoritative in MP) ─────────────
const SCORE_TO_WIN := 20
const ROUND_TIME := 300.0
const WINNER_DISPLAY := 4.0
const MATCH_SYNC_HZ := 5.0           # host → clients broadcast rate for scoreboard

var scores: Dictionary = {}          # team_id -> int
var time_left := ROUND_TIME
var round_active := true
var winner_team := -1
# Human-readable subtitle explaining the end (draws especially — "no scores",
# "3-3 tie", etc.). Broadcast alongside the rest of match state.
var winner_note := ""
var winner_end_t := 0.0
var _match_sync_cd := 0.0
var _flag_sync_cd := 0.0
const FLAG_SYNC_HZ := 8.0

# ── Vote system (#77) ─────────────────────────────────
# Host-authoritative: any player calls /votemap or /votekick, F1/F2 to cast,
# majority passes. Broadcast alongside match state at MATCH_SYNC_HZ.
const VOTE_DURATION := 30.0
const VOTE_COOLDOWN := 30.0
var vote_active := false
var vote_kind := ""              # "votemap" | "votekick"
var vote_target_str := ""        # human label ("Nuubia" / "Red Bot 3")
var vote_target_arg := 0         # map index (votemap) or peer id (votekick)
var vote_yes := 0
var vote_no := 0
var vote_time_left := 0.0
var vote_starter := ""           # display_name of who called it
var _vote_voters: Dictionary = {}  # host-only: peer_id → true (already voted)
var _vote_cooldown := 0.0          # host-only: gate between votes

# ── Bonus pickups (#78) ───────────────────────────────
# Host-authoritative: host places boxes, detects collection, applies effect
# to the toucher and schedules the box slot's respawn. Clients mirror boxes
# via net_bonus_spawn / net_bonus_despawn.
const BONUS_RESPAWN := 20.0
const BONUS_EFFECT_DURATION := 30.0
const BONUS_MAX_SLOTS := 3
var _bonus_boxes: Dictionary = {}    # bonus_id → node (host + client)
var _bonus_slots: Array = []         # host: list of Vector2 spawn positions
var _bonus_slot_cd: Array = []       # host: seconds until each slot respawns
var _bonus_slot_active: Array = []   # host: bonus_id currently occupying each slot (0 = empty)
var _next_bonus_id: int = 1          # host: monotonic id minter
# Weapon-pickup sync — host broadcasts (id, pos, vel, ang) so client-frozen
# pickup bodies mirror the host's physics timeline (#34).
var _pickup_sync_cd := 0.0
const PICKUP_SYNC_HZ := 10.0
var _next_pickup_id: int = 1
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
# Anti-stuck watchdog (see _tick_soldier_safety).
const STUCK_CHECK_HZ := 8.0
const STUCK_GRACE := 0.35          # seconds embedded before we nudge a soldier out
var _safety_cd := 0.0
var _stuck_time: Dictionary = {}   # instance_id -> seconds continuously embedded
var safety_stats := {"unstuck": 0, "fell": 0}  # read by tools/stuck_test.gd
# Player-solid terrain as plain geometry ({"r": Rect2 AABB, "pts": polygon}) so
# spawn/flag placement can test the map without waiting for the physics space.
var _solid_geo: Array = []
# Baked bot navigation graph for this map (empty for editor maps). Bots path
# over it with A* — see scripts/nav_graph.gd / tools/build_nav.py.
var nav: RefCounted = null

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
		"inf_flag": Vector2(2400, 1900), "htf_flag": Vector2(2400, 1900),
		"dom_points": [Vector2(500, 1750), Vector2(2400, 1100), Vector2(4280, 1770)],
		"m2_mounts": [Vector2(2400, 1120)],
		# (Flat texture-square "scenery" decals removed in 1.13 — they read as
		# floating placeholder boxes over the hills.)
	},
]


func _ready() -> void:
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
			Net.custom_map_json = ""
	else:
		# Custom map (from the editor / user://maps/) short-circuits the built-in
		# rotation when Settings.custom_map_path is set (issue #31).
		_map = {}
		if Settings.custom_map_path != "":
			_map = MapIO.load_from_file(Settings.custom_map_path)
		if _map.is_empty():
			_map = MAPS[Settings.map_index % MAPS.size()]
			Settings.map_index = (Settings.map_index + 1) % MAPS.size()
	_apply_world()
	_build_sky()
	_build_parallax()
	_build_terrain()
	nav = NavGraph.load_for(_map)
	_build_weather()
	_build_hud()
	_build_pause_menu()
	_maybe_build_touch_controls()
	_spawn_mode_entities()
	_spawn_bonus_boxes_init()
	kill.connect(_on_kill_scored)

	if Net.is_networked():
		multiplayer.peer_disconnected.connect(_on_net_peer_disconnected)
		if Net.is_host():
			# Dedicated (headless) host: pure authority, no local player, no camera.
			# Fill the match with bots so a lone joining client has opponents (#54).
			if Net.is_dedicated:
				_spawn_bots()
				# Drain any net_client_ready calls that arrived before main.tscn
				# finished loading (#118 — race between ENet accept and scene load).
				for _pending in Net.consume_pending_clients():
					_handle_client_ready(_pending.id, _pending.name, _pending.version)
			else:
				_spawn_networked_player(1)  # host is peer 1
		else:
			# Client asks the host to spawn us; host also mirrors any existing players.
			# Send to Net autoload (always present) — it forwards to Main or buffers
			# if the host's main.tscn is still loading (#118).
			Net.disconnected.connect(_on_lost_host)
			Net.rpc_id(1, "net_client_ready", Settings.player_name, str(ProjectSettings.get_setting("application/config/version", "")))
	else:
		_spawn_player()
		_spawn_bots()


func _spawn_mode_entities() -> void:
	# Called on both host and client so flags/pickups appear on all peers.
	match Settings.game_mode:
		Settings.MODE_CTF: _spawn_flags()
		Settings.MODE_INF: _spawn_flag_inf()
		Settings.MODE_HTF: _spawn_flag_htf()
		Settings.MODE_RM:  _spawn_rambo_bow()
		Settings.MODE_PM:  _spawn_point_pickups()
		Settings.MODE_DOM: _spawn_dom_points()
		Settings.MODE_BR:  _reset_br_zone()


func _apply_world() -> void:
	# Pull the per-map world rect (ported maps) or fall back to the built-in arena.
	var w: Dictionary = _map.get("world", {}) if typeof(_map.get("world", {})) == TYPE_DICTIONARY else {}
	MAP_W = float(w.get("w", DEFAULT_MAP_W))
	MAP_H = float(w.get("h", DEFAULT_MAP_H))
	GROUND_Y = float(w.get("ground_y", DEFAULT_GROUND_Y))
	KILL_Y = float(w.get("kill_y", INF))


func _build_sky() -> void:
	var sky := Node2D.new()
	sky.name = "Sky"
	sky.set_script(sky_script)
	# Ported maps carry Soldat's own background gradient colours.
	var sky_cfg: Variant = _map.get("sky", {})
	if typeof(sky_cfg) == TYPE_DICTIONARY and not (sky_cfg as Dictionary).is_empty():
		sky.set("map_top", _arr_to_color((sky_cfg as Dictionary).get("top", [])))
		sky.set("map_bottom", _arr_to_color((sky_cfg as Dictionary).get("bottom", [])))
	var layer := CanvasLayer.new()
	layer.layer = -20
	layer.add_child(sky)
	add_child(layer)


func _build_parallax() -> void:
	var par := Node2D.new()
	par.name = "Parallax"
	par.set_script(parallax_script)
	var sky_cfg: Variant = _map.get("sky", {})
	if typeof(sky_cfg) == TYPE_DICTIONARY and not (sky_cfg as Dictionary).is_empty():
		var bot := _arr_to_color((sky_cfg as Dictionary).get("bottom", []))
		if bot.a > 0.0:
			par.set("tint", bot)
	var layer := CanvasLayer.new()
	layer.layer = -15
	layer.add_child(par)
	add_child(layer)


# Per-map weather (#68). Reads _map["weather"] ("rain"/"snow" or ""). Renders as
# a CPUParticles2D anchored to the camera so a single emitter covers the visible
# region no matter how far the player travels. Skipped under Settings.lofi to
# stay consistent with the rest of the particle stack.
func _build_weather() -> void:
	var kind: String = str(_map.get("weather", "")).strip_edges().to_lower()
	if kind == "" or Settings.lofi:
		return
	var host := Node2D.new()
	host.name = "Weather"
	# We update the host position each frame from the camera; script inline via
	# a lambda-driven Node2D would be awkward, so use a wrapper method below.
	add_child(host)
	var p := CPUParticles2D.new()
	p.name = "WeatherFX"
	# Wide emission line above the camera; particles fall/drift down into view.
	# Sized generously so a quick camera pan doesn't outrun the emitter edge.
	var view := get_viewport().get_visible_rect().size
	var band_w: float = maxf(view.x + 400.0, 1600.0)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(band_w * 0.5, 8.0)
	p.one_shot = false
	p.local_coords = false
	if kind == "snow":
		# Slow, drifty flakes with visible horizontal sway.
		p.amount = 220
		p.lifetime = 8.0
		p.direction = Vector2(0, 1)
		p.gravity = Vector2(0, 40)
		p.initial_velocity_min = 30.0
		p.initial_velocity_max = 60.0
		p.spread = 12.0
		p.angular_velocity_min = -25.0
		p.angular_velocity_max = 25.0
		p.scale_amount_min = 1.4
		p.scale_amount_max = 2.6
		p.color = Color(0.94, 0.96, 1.0, 0.85)
		# Sinusoidal x-sway via tangential accel gives snow its side-to-side drift.
		p.tangential_accel_min = -18.0
		p.tangential_accel_max = 18.0
	else:
		# Rain — thin fast streaks straight down.
		p.amount = 380
		p.lifetime = 1.2
		p.direction = Vector2(0.08, 1)
		p.gravity = Vector2(0, 900)
		p.initial_velocity_min = 900.0
		p.initial_velocity_max = 1100.0
		p.spread = 3.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		p.color = Color(0.75, 0.85, 1.0, 0.55)
	p.emitting = true
	# Draw over terrain but under HUD.
	p.z_index = 90
	# Rain is a single vertical pixel-tall streak; snow uses a small circle.
	# CPUParticles2D without a texture draws a small dot — good enough for both.
	host.add_child(p)
	# Follow the camera each frame — a stub node with a script is overkill, so
	# reuse a timer + method on Main. Godot doesn't provide a per-node "process"
	# hook without a script, so we add a lightweight one inline.
	var follower := Node.new()
	follower.name = "WeatherFollow"
	follower.set_script(preload("res://scripts/weather_follow.gd"))
	follower.set("host_path", host.get_path())
	follower.set("band_w", band_w)
	host.add_child(follower)


static func _arr_to_color(a: Variant) -> Color:
	if typeof(a) == TYPE_COLOR:
		return a
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 3:
		return Color(0, 0, 0, 0)
	var arr: Array = a
	return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]) if arr.size() > 3 else 1.0)


func _make_platform(pos: Vector2, size: Vector2, col: Color, tex_path: String = "") -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	var vis := Polygon2D.new()
	var poly := PackedVector2Array([
		Vector2(-size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, size.y / 2.0),
		Vector2(-size.x / 2.0, size.y / 2.0),
	])
	vis.polygon = poly
	vis.color = col
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path) as Texture2D
		if tex != null:
			vis.texture = tex
			vis.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			# #112: explicit UVs = polygon coords + half-size so the texture starts
			# at (0,0) in the top-left and tiles at 1 world-pixel per texture-pixel.
			# Polygon2D falls back to (0,0)-mapped UVs when uv is empty, which
			# stretches one tile across the whole platform — invisible on a
			# 5000-pixel-wide baseline floor. Modulate stays at pure white so the
			# tiled grass/rock reads at full contrast against the sky.
			var uvs := PackedVector2Array()
			for p in poly:
				uvs.append(p + size * 0.5)
			vis.uv = uvs
			vis.color = Color(1, 1, 1, 1)
	body.add_child(vis)
	# Bevel trim: bright lip on the walkable top edge, dark underside — reads
	# as a solid ledge instead of a flat coloured box. Skipped on the huge
	# baseline floor/walls (size > 1000) where it'd just be a hairline.
	if size.x <= 1000.0 and size.y <= 1000.0 and size.y >= 6.0:
		var hx := size.x * 0.5
		var hy := size.y * 0.5
		var lip := Line2D.new()
		lip.width = 3.0
		lip.default_color = Color(1, 1, 1, 0.28)
		lip.points = PackedVector2Array([Vector2(-hx, -hy + 1.5), Vector2(hx, -hy + 1.5)])
		body.add_child(lip)
		var under := Line2D.new()
		under.width = 3.0
		under.default_color = Color(0, 0, 0, 0.45)
		under.points = PackedVector2Array([Vector2(-hx, hy - 1.5), Vector2(hx, hy - 1.5)])
		body.add_child(under)
		var sides := Line2D.new()
		sides.width = 2.0
		sides.default_color = Color(0, 0, 0, 0.35)
		sides.closed = true
		sides.points = poly
		body.add_child(sides)
	add_child(body)
	return body


# Collision layers for terrain classes (ported Soldat polygon types):
#   layer 1 (bit 1) — normal terrain: soldiers, bullets, pickups all collide.
#   layer 2 (bit 2) — "only bullets" polys: bullets/rockets/grenades mask it,
#                     soldiers don't, so players walk through.
#   layer 3 (bit 4) — "only players" polys: soldiers mask it, bullets don't.
const TERRAIN_LAYER_BULLETS_ONLY := 2
const TERRAIN_LAYER_PLAYERS_ONLY := 4

func _make_polygon_body(points: PackedVector2Array, col: Color, tex_path: String = "",
		uvs_norm: PackedVector2Array = PackedVector2Array(), draw_outline: bool = true,
		col_class: int = 0, vcols: PackedColorArray = PackedColorArray()) -> Node2D:
	# World-space polygon terrain. Enables hills / mountains / tunnel walls
	# without stacking dozens of small rectangles. `uvs_norm` are tile-space
	# UVs (from the .pms) that get scaled by texture size for tiled sampling.
	# col_class: 0 solid, 1 bullets only, 2 players only, 3 decorative (no body).
	if points.size() < 3:
		return null
	var body: Node2D
	if col_class == 3:
		body = Node2D.new()
	else:
		var sb := StaticBody2D.new()
		if col_class == 1:
			sb.collision_layer = TERRAIN_LAYER_BULLETS_ONLY
		elif col_class == 2:
			sb.collision_layer = TERRAIN_LAYER_PLAYERS_ONLY
		sb.collision_mask = 0
		var col_poly := CollisionPolygon2D.new()
		col_poly.polygon = points
		sb.add_child(col_poly)
		body = sb
	body.position = Vector2.ZERO
	var vis := Polygon2D.new()
	vis.polygon = points
	vis.color = col
	var textured := false
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path) as Texture2D
		if tex != null:
			vis.texture = tex
			vis.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			if uvs_norm.size() == points.size():
				# Ported .pms map: tile-space UVs. Multiply by texture size so
				# Godot samples at the same density Soldat did.
				var ts := tex.get_size()
				var uv_px := PackedVector2Array()
				for uv in uvs_norm:
					uv_px.append(Vector2(uv.x * ts.x, uv.y * ts.y))
				vis.uv = uv_px
			else:
				# #112: procedural remake maps (Ascent/Towers/Pillars) don't carry
				# per-vertex UVs. Polygon2D with an empty uv array stretches ONE
				# texture across the whole polygon, so a 1000×200 hill shows a
				# single blurry pixel of grass instead of tiling. Generate UVs
				# from world-space vertex positions so the texture repeats at its
				# native size (1 world pixel = 1 texture pixel).
				var uv_px := PackedVector2Array()
				for pt in points:
					uv_px.append(pt)
				vis.uv = uv_px
			# Pure-white modulate so the tiled texture reads at full contrast
			# instead of getting washed toward the fallback terrain_color.
			vis.color = Color(1, 1, 1, 1)
			textured = true
	# Soldat's per-vertex colours carry all of a classic map's shading (dark
	# caves, sunlit ridges, tinted water). Without them every map looked flat.
	if vcols.size() == points.size():
		vis.vertex_colors = vcols
	body.add_child(vis)
	if draw_outline:
		# Subtle darkened top-edge outline so hills read against the sky at distance.
		var outline := Line2D.new()
		outline.width = 3.0
		outline.default_color = col.darkened(0.4) if not textured else Color(0, 0, 0, 0.35)
		outline.antialiased = true
		var ridge := PackedVector2Array()
		for p in points:
			ridge.append(p)
		outline.points = ridge
		body.add_child(outline)
	add_child(body)
	return body


func _build_terrain() -> void:
	# Baseline floor + side walls always present so maps can rely on them.
	# The floor slab's TOP edge sits exactly at GROUND_Y (it used to be centred
	# on it, which put the walkable surface 100 px higher than every map, the
	# editor and map_gen assumed — sealing the built-in tunnels shut and burying
	# the bottom rows of every ported map).
	var floor_tex: String = str(_map.get("floor_texture", ""))
	var world_cfg: Dictionary = _map.get("world", {}) if typeof(_map.get("world", {})) == TYPE_DICTIONARY else {}
	var floor_body := _make_platform(Vector2(MAP_W / 2.0, GROUND_Y + 100.0), Vector2(MAP_W + 200, 200), Color(0.22, 0.26, 0.32), floor_tex)
	_solid_geo.clear()
	_register_solid(PackedVector2Array([Vector2(-100, GROUND_Y), Vector2(MAP_W + 100, GROUND_Y),
		Vector2(MAP_W + 100, GROUND_Y + 200), Vector2(-100, GROUND_Y + 200)]))
	if not bool(world_cfg.get("floor_visible", true)):
		# Ported maps: the floor only exists as a safety net below the kill line.
		for c in floor_body.get_children():
			if c is CanvasItem:
				(c as CanvasItem).visible = false
	# Optional polygon terrain (hills / mountains / tunnel walls). Each entry is
	# { "points": PackedVector2Array } with optional "color" and "texture".
	var default_terrain_col: Color = _map.get("terrain_color", Color(0.24, 0.28, 0.34))
	var default_terrain_tex: String = str(_map.get("terrain_texture", ""))
	# Ported .pms maps ship per-vertex UVs so we can suppress the sky-ridge outline
	# (which was there to give flat-color hills contrast) and let the tiled
	# texture carry the visual weight.
	var has_uvs := false
	var has_coll: bool = _map.has("collision") and typeof(_map["collision"]) == TYPE_ARRAY \
			and not (_map["collision"] as Array).is_empty()
	for poly in _map.get("polys", []):
		var pts: PackedVector2Array = poly.get("points", PackedVector2Array())
		var pc: Color = poly.get("color", default_terrain_col)
		var pt: String = str(poly.get("texture", default_terrain_tex))
		var uvs: PackedVector2Array = poly.get("uvs", PackedVector2Array())
		var draw_outline := uvs.size() != pts.size()
		if not draw_outline:
			has_uvs = true
		var vcols: PackedColorArray = poly.get("vc", PackedColorArray())
		var cc := int(poly.get("col", 0))
		# With merged collision outlines the triangles are drawn only.
		_make_polygon_body(pts, pc, pt, uvs, draw_outline, 3 if has_coll else cc, vcols)
		if not has_coll and pts.size() >= 3 and (cc == 0 or cc == 2):
			_register_solid(pts)
	# Ported maps: physics from merged, seam-free outlines (tools/pms_to_map.py
	# build_collision) so soldiers don't snag on the joins between triangles.
	if has_coll:
		for c in _map["collision"]:
			var cpts: PackedVector2Array = c["points"]
			var ccl := int(c.get("col", 0))
			var sb := StaticBody2D.new()
			if ccl == 1:
				sb.collision_layer = TERRAIN_LAYER_BULLETS_ONLY
			elif ccl == 2:
				sb.collision_layer = TERRAIN_LAYER_PLAYERS_ONLY
			sb.collision_mask = 0
			var cp := CollisionPolygon2D.new()
			cp.polygon = cpts
			sb.add_child(cp)
			add_child(sb)
			if ccl == 0 or ccl == 2:
				_register_solid(cpts)
	# Legacy rectangular platforms: textured with the map's terrain (slightly
	# darkened so they read as man-made ledges) instead of a flat grey box.
	var plat_tex: String = str(_map.get("platform_texture", default_terrain_tex))
	for pl in _map["platforms"]:
		var pb := _make_platform(pl["p"], pl["s"], Color(0.28, 0.32, 0.4), plat_tex)
		var hs: Vector2 = (pl["s"] as Vector2) * 0.5
		var pc2: Vector2 = pl["p"]
		_register_solid(PackedVector2Array([pc2 + Vector2(-hs.x, -hs.y), pc2 + Vector2(hs.x, -hs.y),
			pc2 + Vector2(hs.x, hs.y), pc2 + Vector2(-hs.x, hs.y)]))
		for c in pb.get_children():
			if c is Polygon2D and (c as Polygon2D).texture != null:
				(c as Polygon2D).color = Color(0.82, 0.8, 0.78, 1.0)
	var wall_l := _make_platform(Vector2(0, MAP_H / 2.0), Vector2(40, MAP_H * 2.0), Color(0.2, 0.23, 0.28))
	var wall_r := _make_platform(Vector2(MAP_W, MAP_H / 2.0), Vector2(40, MAP_H * 2.0), Color(0.2, 0.23, 0.28))
	if not bool(world_cfg.get("floor_visible", true)):
		for wb in [wall_l, wall_r]:
			for c in wb.get_children():
				if c is CanvasItem:
					(c as CanvasItem).visible = false
	# Ladders — climbable Area2D regions (see player.gd's climbing state).
	for ld in _map.get("ladders", []):
		_make_ladder(float(ld.get("x", 0.0)), float(ld.get("y", 0.0)),
			float(ld.get("w", 20.0)), float(ld.get("h", 120.0)))
	_spawn_scenery()
	_spawn_scenery_hints()
	_spawn_m2_mounts()
	_spawn_map_weapon_pickups()


# ── Placement geometry (no physics queries needed) ─────────────────────────

func _register_solid(pts: PackedVector2Array) -> void:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	_solid_geo.append({"r": r, "pts": pts})
	_geo_cols.clear()  # rebuild the column index lazily


# Column index over _solid_geo: bots probe ground/pits several times per tick,
# and scanning ~200-3000 pieces each time cost milliseconds per frame.
const GEO_COL_W := 32.0
var _geo_cols: Array = []


func _geo_candidates(x: float) -> PackedInt32Array:
	if _geo_cols.is_empty():
		var n := int(ceil((MAP_W + 400.0) / GEO_COL_W)) + 1
		_geo_cols.resize(n)
		for i in n:
			_geo_cols[i] = PackedInt32Array()
		for gi in _solid_geo.size():
			var rr: Rect2 = _solid_geo[gi]["r"]
			var c0 := clampi(int((rr.position.x + 200.0) / GEO_COL_W), 0, n - 1)
			var c1 := clampi(int((rr.end.x + 200.0) / GEO_COL_W), 0, n - 1)
			for c in range(c0, c1 + 1):
				# Packed arrays are value types: append to a local and store it
				# back (appending through the cast silently edited a copy).
				var col: PackedInt32Array = _geo_cols[c]
				col.append(gi)
				_geo_cols[c] = col
	return _geo_cols[clampi(int((x + 200.0) / GEO_COL_W), 0, _geo_cols.size() - 1)]


func _point_in_solid(p: Vector2) -> bool:
	if p.x <= 20.0 or p.x >= MAP_W - 20.0:
		return true  # inside a side wall
	for gi in _geo_candidates(p.x):
		var g: Dictionary = _solid_geo[gi]
		var r: Rect2 = g["r"]
		if p.x < r.position.x or p.x > r.end.x or p.y < r.position.y or p.y > r.end.y:
			continue
		if Geometry2D.is_point_in_polygon(p, g["pts"]):
			return true
	return false


func _spot_is_clear(feet: Vector2) -> bool:
	# Sample a soldier's standing box (14×24, feet-anchored) — edges + middle.
	for off in [Vector2(-6, -2), Vector2(6, -2), Vector2(0, -12), Vector2(-6, -22), Vector2(6, -22), Vector2(0, -23)]:
		if _point_in_solid(feet + off):
			return false
	return true


func _geom_ground_y(x: float, from_y: float) -> float:
	# Highest solid surface at column x at or below from_y (INF if none).
	var best := INF
	for gi in _geo_candidates(x):
		var g: Dictionary = _solid_geo[gi]
		var r: Rect2 = g["r"]
		if x < r.position.x or x > r.end.x or r.end.y < from_y:
			continue
		var pts: PackedVector2Array = g["pts"]
		var n := pts.size()
		for i in n:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % n]
			if (a.x <= x and b.x >= x) or (b.x <= x and a.x >= x):
				var y: float
				if absf(b.x - a.x) < 0.001:
					y = minf(a.y, b.y)
				else:
					y = lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
				if y >= from_y and y < best:
					best = y
	return best


func _settle_on_ground(pos: Vector2) -> Vector2:
	# Drop a map object (flag base, capture point) straight down onto the first
	# surface. If it starts buried, first lift it out (up to 400 px).
	var p := pos
	var lift := 0.0
	while _point_in_solid(p + Vector2(0, -2)) and lift < 1200.0:
		p.y -= 4.0
		lift += 4.0
	var gy := _geom_ground_y(p.x, p.y - 2.0)
	if gy == INF or gy > KILL_Y:
		return pos
	return Vector2(p.x, gy)


func _drop_flag(f: Node2D, at: Vector2) -> void:
	# Carrier died: the flag falls to the ground under them. If there is no
	# ground (carrier fell off the map), the flag goes straight home instead
	# of hanging in the void where nobody can ever reach it.
	f.set_meta("carrier", null)
	var ft: int = int(f.get_meta("team")) if f.has_meta("team") else 0
	var gy := _geom_ground_y(at.x, at.y - 4.0)
	if gy == INF or gy > KILL_Y or at.y > KILL_Y:
		f.position = f.get_meta("home")
		_objective_event("return", ft, "")
		return
	var p := Vector2(at.x, gy)
	if not _spot_is_clear(p + Vector2(0, -1)):
		f.position = f.get_meta("home")
		_objective_event("return", ft, "")
		return
	f.position = p
	_objective_event("drop", ft, "")


func _find_free_spot_near(feet: Vector2, max_r: float = 240.0) -> Vector2:
	# Nearest spot (upward first, then outward rings) where a standing soldier fits.
	if _spot_is_clear(feet):
		return feet
	var step := 6.0
	var r := step
	while r <= max_r:
		for off in [Vector2(0, -r), Vector2(-r, -r * 0.5), Vector2(r, -r * 0.5), Vector2(-r, 0),
				Vector2(r, 0), Vector2(0, r), Vector2(-r, -r), Vector2(r, -r)]:
			var c: Vector2 = feet + off
			if c.x < 30.0 or c.x > MAP_W - 30.0:
				continue
			if _spot_is_clear(c):
				return c
		r += step
	return feet


func _tick_soldier_safety(delta: float) -> void:
	# Runs on every peer for the soldiers THIS peer is authoritative over
	# (own player on clients; everyone incl. bots on host / single-player).
	# 1) Fell off a ported map (below the kill line) → dies, like Soldat.
	# 2) Somehow embedded in terrain for > STUCK_GRACE s (explosion shove,
	#    stance change under a low ceiling, spawning into a moved prop…) →
	#    nudged to the nearest free spot so nobody is ever trapped.
	_safety_cd -= delta
	if _safety_cd > 0.0:
		return
	var dt := 1.0 / STUCK_CHECK_HZ
	_safety_cd = dt
	var space := get_world_2d().direct_space_state
	# Dropped weapons / the Rambo bow that fall off a ported map would sit on
	# the hidden safety floor forever. Host (or SP) cleans them up; the bow
	# goes back to its spawn so Rambomatch can continue.
	if KILL_Y != INF and (not Net.is_networked() or Net.is_host()):
		for wp in get_tree().get_nodes_in_group("weapon_pickup"):
			if not is_instance_valid(wp) or (wp as Node2D).global_position.y <= KILL_Y:
				continue
			if wp.has_meta("rambo_spawn"):
				var ground_y: float = float(_map.get("ctf_ground_y", GROUND_Y))
				(wp as Node2D).global_position = _map.get("rambo_pos", Vector2(MAP_W * 0.5, ground_y - 40.0))
				if wp is RigidBody2D:
					(wp as RigidBody2D).linear_velocity = Vector2.ZERO
			else:
				wp.queue_free()
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")) or not (s is CharacterBody2D):
			continue
		if multiplayer.multiplayer_peer != null and not s.is_multiplayer_authority():
			continue
		var body := s as CharacterBody2D
		if body.global_position.y > KILL_Y:
			if s.has_method("take_damage"):
				s.set("ceasefire_t", 0.0)
				s.take_damage(9999.0, str(s.get("display_name")), "Fell", int(s.get("team")))
				safety_stats["fell"] = int(safety_stats["fell"]) + 1
				if OS.get_cmdline_user_args().has("--log-falls"):
					print("[fell] %s from x=%d goal=%s" % [s.get("display_name"), int(body.global_position.x), str(s.get("_goal_label"))])
			continue
		if s.get("mounted_m2") != null or bool(s.get("climbing")):
			_stuck_time.erase(s.get_instance_id())
			continue
		var cs: CollisionShape2D = null
		for c in body.get_children():
			if c is CollisionShape2D:
				cs = c
				break
		if cs == null or cs.shape == null:
			continue
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = cs.shape
		q.transform = cs.global_transform
		q.collision_mask = body.collision_mask
		q.collide_with_bodies = true
		q.collide_with_areas = false
		q.exclude = [body.get_rid()]
		q.margin = -1.5  # ignore resting contact — only real overlap counts
		var embedded := false
		for hit in space.intersect_shape(q, 4):
			if hit.get("collider") is StaticBody2D:
				embedded = true
				break
		var id := s.get_instance_id()
		if not embedded:
			_stuck_time.erase(id)
			continue
		_stuck_time[id] = float(_stuck_time.get(id, 0.0)) + dt
		if float(_stuck_time[id]) >= STUCK_GRACE:
			_stuck_time.erase(id)
			var to := _find_free_spot_near(body.global_position)
			if to != body.global_position:
				if OS.is_debug_build():
					print("[anti-stuck] freed %s at %s -> %s" % [s.get("display_name"), body.global_position, to])
				body.global_position = to
				body.velocity = Vector2.ZERO
				safety_stats["unstuck"] = int(safety_stats["unstuck"]) + 1


func _make_ladder(x: float, y: float, w: float, h: float) -> Area2D:
	# Ladder = non-collidable Area2D on the "ladder" group. player.gd polls
	# get_overlapping_areas() each physics frame to detect climb availability.
	# `center_x` is stashed on the area for the player's x-snap while climbing.
	var area := Area2D.new()
	area.add_to_group("ladder")
	area.position = Vector2(x + w * 0.5, y + h * 0.5)
	area.set_meta("center_x", area.position.x)
	area.set_meta("top_y", y)
	area.set_meta("bottom_y", y + h)
	area.set_meta("half_w", w * 0.5)
	area.set_meta("half_h", h * 0.5)
	# Only detect Area2D overlaps against the player's own ladder-probe Area2D
	# so soldiers don't drag physics bodies into the area's contact list.
	area.monitorable = true
	area.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, h)
	shape.shape = rect
	area.add_child(shape)
	# Cheap _draw-style visual: two vertical rails + rungs every ~20px.
	var vis := _LadderVisual.new()
	vis.width = w
	vis.height = h
	area.add_child(vis)
	add_child(area)
	return area


class _LadderVisual extends Node2D:
	var width: float = 20.0
	var height: float = 120.0

	func _draw() -> void:
		var col := Color(0.72, 0.55, 0.28, 0.95)
		var inset: float = clampf(width * 0.15, 2.0, 6.0)
		var lx := -width * 0.5 + inset
		var rx :=  width * 0.5 - inset
		var ty := -height * 0.5
		var by :=  height * 0.5
		# Faint fill so the ladder reads even against dark terrain.
		draw_rect(Rect2(Vector2(-width * 0.5, ty), Vector2(width, height)),
			Color(0.35, 0.24, 0.12, 0.28))
		draw_line(Vector2(lx, ty), Vector2(lx, by), col, 2.0)
		draw_line(Vector2(rx, ty), Vector2(rx, by), col, 2.0)
		var step := 20.0
		var y := ty + step * 0.5
		while y < by:
			draw_line(Vector2(lx, y), Vector2(rx, y), col, 1.5)
			y += step


func _spawn_scenery() -> void:
	# Non-collidable decorative sprites (trees / rocks / etc.). Each entry is
	# { "tex": res_path, "pos": Vector2, optional "scale": float, "mod": Color }.
	var items: Array = _map.get("scenery", [])
	if items.is_empty():
		return
	for it in items:
		var path: String = str(it.get("tex", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.position = it.get("pos", Vector2.ZERO)
		s.scale = Vector2.ONE * float(it.get("scale", 1.0))
		s.modulate = it.get("mod", Color(1, 1, 1, 1))
		s.z_index = int(it.get("z", -2))
		add_child(s)


# Level → z_index for ported .pms scenery. 0=back (behind terrain),
# 1=middle (in front of terrain but tree-ordered behind soldiers spawned
# later at z=0), 2=front (drawn above soldiers).
const _SCENERY_LEVEL_Z := {0: -3, 1: 0, 2: 5}


func _spawn_scenery_hints() -> void:
	# Ported .pms maps carry a `_scenery_hints` array holding the original
	# prop list: sprite name + world pos/scale/rot/alpha/level. Resolves each
	# name to res://assets/scenery/<stem>.png.
	var items: Array = _map.get("_scenery_hints", [])
	if items.is_empty():
		return
	# Sprites need to grow with the map's port-time scale so they stay in
	# proportion to terrain (both scaled together during .pms → JSON).
	var map_scale := float((_map.get("_source", {}) as Dictionary).get("scale", 1.0))
	for it in items:
		var raw_name: String = str(it.get("name", ""))
		if raw_name == "":
			continue
		var stem := raw_name.get_basename().to_lower()
		var path := "res://assets/scenery/%s.png" % stem
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			continue
		var pos_arr = it.get("pos", [0, 0])
		var pos := Vector2(float(pos_arr[0]), float(pos_arr[1]))
		var sc := float(it.get("scale", 1.0))
		var sc_y := float(it.get("scale_y", sc))
		var rot := float(it.get("rot", 0.0))
		var alpha := int(it.get("alpha", 255))
		var level := int(it.get("level", 1))
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false  # Soldat anchors props by top-left corner.
		s.position = pos
		# Soldat sizes a prop as its stored Width×Height (original sprite
		# size) × ScaleX/Y — not by the texture's pixel size. Our PNGs are
		# frequently HD, so normalise by the texture size when w/h are known.
		var tsz := tex.get_size()
		var fit := Vector2.ONE
		if it.has("w") and it.has("h") and tsz.x > 0.0 and tsz.y > 0.0:
			fit = Vector2(maxf(1.0, float(it["w"])) / tsz.x, maxf(1.0, float(it["h"])) / tsz.y)
		s.scale = Vector2(sc, sc_y) * map_scale * fit
		# Soldat renders props with -Rotation (MapGraphics.pas) in the same
		# y-down space Godot uses, so the sign flips here.
		s.rotation = -rot
		var tint := Color.WHITE
		if it.has("color"):
			tint = Color.html(str(it["color"]))
		s.modulate = Color(tint.r, tint.g, tint.b, clamp(alpha / 255.0, 0.0, 1.0))
		s.z_index = int(_SCENERY_LEVEL_Z.get(level, 0))
		add_child(s)


func _spawn_m2_mounts() -> void:
	var mounts: Array = _map.get("m2_mounts", [])
	if mounts.is_empty():
		return
	var M2 = preload("res://scripts/m2.gd")
	var idx: int = 0
	for pos in mounts:
		var m2 := Node2D.new()
		m2.set_script(M2)
		m2.position = pos
		m2.name = "M2_%d" % idx
		m2.set("m2_id", idx)
		idx += 1
		add_child(m2)


func _spawn_map_weapon_pickups() -> void:
	# #113: map editor can place resting weapon pickups. Only the host spawns
	# them — clients receive them via the normal pickup state stream.
	var wps: Array = _map.get("weapon_pickups", [])
	if wps.is_empty():
		return
	if Net.is_networked() and not Net.is_host():
		return
	for wp_def in wps:
		if typeof(wp_def) != TYPE_DICTIONARY:
			continue
		var wp := WeaponPickup.new()
		wp.weapon_name = str(wp_def.get("weapon", "AK-74"))
		wp.team = -1
		wp.thrower_name = ""
		wp.damage_on_hit = 0.0
		wp.global_position = wp_def.get("pos", Vector2.ZERO)
		wp.set_meta("map_spawn", true)
		if Net.is_networked() and Net.is_host():
			wp.pickup_id = next_pickup_id()
		add_child(wp)


func find_m2(id: int) -> Node2D:
	# Called by m2.gd RPC receivers to look up their peer counterpart.
	for m in get_tree().get_nodes_in_group("m2_gun"):
		if is_instance_valid(m) and int(m.get("m2_id")) == id:
			return m
	return null


@rpc("any_peer", "call_local", "reliable")
func net_m2_mount(m2_id: int, peer_id: int) -> void:
	# In MP the operator's peer id is what all peers use to identify who's driving
	# the turret. Client-initiated mounts route through host as the authority so
	# a race between two clients grabbing the same mount is arbitrated centrally.
	var m_sender := multiplayer.get_remote_sender_id() if multiplayer.has_multiplayer_peer() else 0
	# (call_local reports the host's own id, not 0 — treat that as local.)
	if Net.is_networked() and Net.is_host() and m_sender != 0 and m_sender != multiplayer.get_unique_id():
		# #106: reject spoofed mounts — a client can only mount themselves, not
		# another peer. Without this guard, any client could force other peers'
		# screens to show a different player driving the M2.
		if peer_id != multiplayer.get_remote_sender_id():
			return
		# Rebroadcast to everyone (call_local ensures host also applies it).
		rpc("net_m2_mount", m2_id, peer_id)
		return
	var m2 := find_m2(m2_id)
	if m2 == null:
		return
	# Find operator by peer_id.
	var op: Node2D = null
	if _players_by_id.has(peer_id):
		op = _players_by_id[peer_id]
	if not is_instance_valid(op):
		return
	if m2.has_method("net_mount"):
		m2.net_mount(op)


@rpc("any_peer", "call_local", "reliable")
func net_m2_dismount(m2_id: int) -> void:
	var d_sender := multiplayer.get_remote_sender_id() if multiplayer.has_multiplayer_peer() else 0
	if Net.is_networked() and Net.is_host() and d_sender != 0 and d_sender != multiplayer.get_unique_id():
		# #106: only the current operator may dismount themselves — reject any
		# client trying to knock another player off the turret.
		var m2_local := find_m2(m2_id)
		if m2_local != null:
			var op = m2_local.get("operator")
			if is_instance_valid(op) and int(op.get_multiplayer_authority()) != multiplayer.get_remote_sender_id():
				return
		rpc("net_m2_dismount", m2_id)
		return
	var m2 := find_m2(m2_id)
	if m2 != null and m2.has_method("net_dismount"):
		m2.net_dismount()


@rpc("any_peer", "unreliable_ordered")
func net_m2_state(m2_id: int, aim_dir: Vector2) -> void:
	var m2 := find_m2(m2_id)
	if m2 == null or not m2.has_method("net_apply_state"):
		return
	# Only the current operator may steer the barrel — reject spoofed aim from
	# non-operators (aim-spoof / attribution exploit).
	if multiplayer.multiplayer_peer != null:
		var sender := multiplayer.get_remote_sender_id()
		var op = m2.get("operator")
		if not is_instance_valid(op):
			return
		var op_peer := int(op.get_multiplayer_authority())
		if sender == 0:
			if op_peer != multiplayer.get_unique_id():
				return
		elif sender != op_peer:
			return
	m2.net_apply_state(aim_dir)


@rpc("any_peer", "call_local", "reliable")
func net_m2_fire(m2_id: int, muzzle: Vector2, aim_dir: Vector2, shooter_team: int, shooter_name: String) -> void:
	var m2 := find_m2(m2_id)
	if m2 == null or not m2.has_method("net_apply_fire"):
		return
	# Only the current operator may spawn M2 bullets. Also lock shooter_team +
	# shooter_name to the operator's own so kill attribution can't be forged.
	var op_team := shooter_team
	var op_name := shooter_name
	if multiplayer.multiplayer_peer != null:
		var sender := multiplayer.get_remote_sender_id()
		var op = m2.get("operator")
		if not is_instance_valid(op):
			return
		var op_peer := int(op.get_multiplayer_authority())
		if sender == 0:
			if op_peer != multiplayer.get_unique_id():
				return
		elif sender != op_peer:
			return
		op_team = int(op.get("team"))
		op_name = str(op.get("display_name"))
	m2.net_apply_fire(muzzle, aim_dir, op_team, op_name)


# ── Singleplayer spawn path ───────────────────────────

func _spawn_player() -> void:
	var p := player_scene.instantiate()
	p.position = _find_free_spot_near(_map["player_spawn"])
	# In team modes player joins BLUE (team 1); in DM/RM she's team 0 (FFA).
	if Settings.is_team_mode():
		p.team = TEAM_BLUE
		p.color = Color(0.35, 0.55, 1.0)
	else:
		p.team = 0
	p.display_name = Settings.player_name
	# Advance mode: start with the humble knife.
	if Settings.advance:
		p.set("using_secondary", true)
		p.set("secondary_index", 1)  # Knife
	# Gun Game: restore the persisted rung so death keeps you on the same weapon.
	if Settings.game_mode == Settings.MODE_GG:
		p.gg_level = _gg_get(str(p.display_name))
	p.died.connect(_on_player_died)
	add_child(p)
	player = p
	_bind_local_camera(p)
	if hud:
		hud.player = p
	# SP respawn — end the spectator cam so the new body's camera takes over (#75).
	_end_spectator()


func _on_player_died() -> void:
	# Kick off spectator (#75) — camera detaches from the dying body and follows
	# the nearest living soldier. Uses the just-died body's last known position as
	# the anchor for the first target pick so the transition doesn't hop the view.
	_begin_spectator()
	# In MP the host owns respawn scheduling (see player.gd::_die), so main only
	# shows the death UI — no local timer needed. SP still schedules here.
	if Net.is_networked():
		var mp_delay: float = _respawn_delay_for_team(int(player.team))
		if hud:
			if Settings.survival and round_active:
				hud.show_death(str(player.last_killer), str(player.last_weapon), -1.0)
			else:
				hud.show_death(str(player.last_killer), str(player.last_weapon), mp_delay)
		return
	# Survival: no respawn until round ends. _reset_round will (re)spawn everyone
	# (also when we die on the winner screen — a timer here would add a 2nd body).
	if Settings.survival:
		if hud:
			# Negative delay = HUD shows "waiting for next round" instead of a countdown.
			hud.show_death(str(player.last_killer), str(player.last_weapon), -1.0)
		return
	var delay: float = _respawn_delay_for_team(int(player.team))
	if hud:
		hud.show_death(str(player.last_killer), str(player.last_weapon), delay)
	get_tree().create_timer(delay).timeout.connect(_spawn_player)


func _begin_spectator() -> void:
	if spectator == null or not is_instance_valid(spectator):
		return
	var anchor: Vector2 = Vector2.ZERO
	if is_instance_valid(player):
		anchor = player.global_position
	spectator.activate(anchor)


func _end_spectator() -> void:
	if spectator != null and is_instance_valid(spectator):
		spectator.deactivate()


# ── Kill streaks + multi-kills (#76) ──────────────────
# Reads killer/victim from the shared kill signal. Runs on every peer so the
# banner lookup is identical everywhere without an extra RPC. Synthetic entries
# (FLAG capture, POINT capture, etc.) carry a killer_team but the "victim" is
# a scoreboard label, not a soldier — those still increment the killer's streak
# so a flag-capture-during-spree escalates the announcement naturally.
func _track_kill_streaks(killer_name: String, victim_name: String, killer_team: int) -> void:
	if killer_name == "":
		return
	# Suicide or team-kill: reset the killer's own streak. No banner.
	var is_self: bool = killer_name == victim_name
	if is_self:
		_reset_streak(killer_name)
		return
	# Before incrementing, capture the victim's pre-death streak for the
	# "ended <name>'s N-kill streak" announcement.
	var ended: int = 0
	if _streaks.has(victim_name):
		ended = int((_streaks[victim_name] as Dictionary).get("streak", 0))
	# Increment killer's own counters.
	var now := Time.get_ticks_msec() / 1000.0
	var s: Dictionary = _streaks.get(killer_name, {"streak": 0, "multi": 0, "multi_t": 0.0, "team": killer_team})
	s["team"] = killer_team
	s["streak"] = int(s.get("streak", 0)) + 1
	if float(s.get("multi_t", 0.0)) > now:
		s["multi"] = int(s.get("multi", 0)) + 1
	else:
		s["multi"] = 1
	s["multi_t"] = now + MULTI_KILL_WINDOW
	_streaks[killer_name] = s
	# Announce banner: whichever count is louder (streak or multi).
	var count: int = maxi(int(s["streak"]), int(s["multi"]))
	# Banner only for the local player's streaks (or big ones) — bot-vs-bot
	# FFA would otherwise spam it constantly.
	var is_me: bool = is_instance_valid(player) and str(player.display_name) == killer_name
	if count >= (2 if is_me else 5) and hud != null and hud.has_method("show_streak_banner"):
		hud.show_streak_banner(killer_name, _streak_title(count), int(s["team"]), count)
	# Streak-ended feed line — reuse the existing kill-feed styling for consistency.
	if ended >= STREAK_ANNOUNCE_END_MIN and hud != null and hud.has_method("post_streak_ended"):
		hud.post_streak_ended(killer_name, victim_name, ended, killer_team)
	# Victim loses their life-scoped streak. Multi window also clears — they're dead.
	_reset_streak(victim_name)


func _reset_streak(name: String) -> void:
	if name == "":
		return
	if not _streaks.has(name):
		return
	var s: Dictionary = _streaks[name]
	s["streak"] = 0
	s["multi"] = 0
	s["multi_t"] = 0.0
	_streaks[name] = s


func _streak_title(count: int) -> String:
	if STREAK_TITLES.has(count):
		return String(STREAK_TITLES[count])
	if count >= 7:
		return STREAK_ULTRA
	return "Multi Kill"


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
	pos = _find_free_spot_near(pos)
	var candidate := pos
	for step in MAX_STEPS:
		var clear := true
		# A sideways-shifted slot must still be open air with ground under it
		# before the kill line — otherwise we'd spawn someone inside a wall or
		# over a pit on the narrower ported maps.
		if step > 0 and (not _spot_is_clear(candidate) or _geom_ground_y(candidate.x, candidate.y - 2.0) > minf(KILL_Y, GROUND_Y + 1.0)):
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


func _spawn_bots() -> void:
	var spots: Array = _map["bot_spawns"]
	# #67: bot_count -1 = "every spawn slot" (legacy). Otherwise cap to the setting.
	# We recycle spawn positions round-robin if the user asks for more bots than slots.
	var desired: int = spots.size() if MatchConfig.bot_count() < 0 else MatchConfig.bot_count()
	if desired <= 0 or spots.is_empty():
		return
	for i in desired:
		_spawn_bot_at(i, desired)


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


func _spawn_bot_at(i: int, desired: int) -> void:
	var spots: Array = _map["bot_spawns"]
	var slot: Vector2 = spots[i % spots.size()]
	var loadout := "LAW" if i == desired - 1 else "AK-74"
	var mode: int = Settings.game_mode
	if Settings.is_team_mode():
		if mode == Settings.MODE_INF:
			# INF: bots are attackers (RED). Player defends solo on BLUE.
			var rl := _team_spawn_list(TEAM_RED)
			_spawn_bot(rl[i % rl.size()], TEAM_RED, "Red Bot %d" % (i + 1), loadout)
		else:
			# TDM/CTF/HTF/PM: split bots BLUE/RED evenly, each at its own base.
			var on_blue: bool = i < desired / 2
			var t: int = TEAM_BLUE if on_blue else TEAM_RED
			var nm := "Blue Bot %d" % (i + 1) if on_blue else "Red Bot %d" % (i + 1)
			var tl := _team_spawn_list(t)
			_spawn_bot(tl[i % tl.size()], t, nm, loadout)
	else:
		# DM/RM/GG/BR: every bot is its own team (FFA_BOT_TEAM_BASE + i), so bots
		# fight each other as well as humans. Ids sit far above peer ids (humans
		# use team = peer_id in MP FFA, 0 in single-player).
		_spawn_bot(slot, FFA_BOT_TEAM_BASE + i, "Bot %d" % (i + 1), loadout)


# Reconcile the live bot count to MatchConfig.bot_count() — called when the host
# tweaks the bot-count slider mid-match so new bots appear / extras vanish without
# a full restart. Host/SP only; clients get spawn/despawn pushed via RPC.
func _reconcile_bots() -> void:
	if Net.is_networked() and not Net.is_host():
		return
	var spots: Array = _map["bot_spawns"]
	if spots.is_empty():
		return
	var desired: int = spots.size() if MatchConfig.bot_count() < 0 else MatchConfig.bot_count()
	var live: Array = _live_bots()
	# Dead bots waiting on their respawn timer count too — otherwise lowering
	# then raising the slider mid-fight spawned extras AND the pending respawns.
	var have: int = live.size() + _bot_pending.size()
	var diff: int = desired - have
	if diff > 0:
		for i in range(have, desired):
			_spawn_bot_at(i, desired)
	elif diff < 0:
		var excess: int = -diff
		for k in _bot_pending.keys():
			if excess <= 0:
				break
			_bot_pending.erase(k)
			excess -= 1
		for i in range(maxi(0, live.size() - excess), live.size()):
			_despawn_bot(live[i])


func _live_bots() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(n) and n.get("loadout") != null and not bool(n.get("dead")):
			out.append(n)
	return out


func _despawn_bot(b: Node) -> void:
	var bid: int = int(b.get("bot_id"))
	if Net.is_networked() and Net.is_host() and bid > 0:
		rpc("net_bot_despawn", bid)
		_bots_by_id.erase(bid)
	if is_instance_valid(b):
		b.queue_free()


func _spawn_bot(pos: Vector2, team: int, bname: String, loadout: String = "AK-74") -> void:
	if not is_inside_tree():
		return
	# Clients never spawn bots directly — the host owns bot lifecycle and pushes
	# spawn/despawn via net_spawn_bot / net_despawn_bot RPCs (issue #55).
	if Net.is_networked() and not Net.is_host():
		return
	var b := bot_scene.instantiate()
	b.position = _safe_spawn_near(pos, team)
	b.team = team
	b.display_name = bname
	b.loadout = loadout
	# Colorize per team so friend/foe reads at a glance (FFA bots get a hue each).
	b.color = bot_color_for_team(team)
	# Assign a stable id + set host as authority so the bot's own is_multiplayer_authority()
	# check gates AI to peer 1. Clients skip _physics_process AI (see bot.gd).
	var assigned_id: int = 0
	if Net.is_networked() and Net.is_host():
		assigned_id = _next_bot_id
		_next_bot_id += 1
		b.bot_id = assigned_id
		b.name = "Bot_%d" % assigned_id
		b.set_multiplayer_authority(1)
	# Gun Game: bots share the players' ladder — restore the persisted rung so
	# a bot that climbed pre-death re-spawns holding the same rung's weapon.
	if Settings.game_mode == Settings.MODE_GG:
		b.gg_level = _gg_get(bname)
	# Bots respawn on the same slot so the match can accumulate score.
	# Survival gates this — the next spawn only happens on _reset_round.
	b.died.connect(func() -> void:
		if assigned_id > 0:
			_bots_by_id.erase(assigned_id)
		# Survival: _reset_round respawns everyone — a death on the winner
		# screen used to schedule an extra body that appeared after the reset.
		if Settings.survival:
			return
		var delay: float = _respawn_delay_for_team(team)
		_bot_pending[bname] = true
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			# Guard against the outer Main being torn down (scene change / quit)
			# during the respawn window — the SceneTreeTimer keeps firing.
			if not is_inside_tree():
				return
			# Cancelled by _reconcile_bots (slider lowered while dead).
			if not _bot_pending.has(bname):
				return
			_bot_pending.erase(bname)
			_spawn_bot(pos, team, bname, loadout)))
	add_child(b)
	# Reassert authority after add_child so children added in _ready inherit it.
	if Net.is_networked() and Net.is_host():
		b.set_multiplayer_authority(1, true)
		_bots_by_id[assigned_id] = b
		# Notify every peer whose main.tscn is loaded so they spawn a replica.
		# We gate on _connected_peers (populated in net_client_ready) instead of
		# _ready_peers (populated on net_spawn_ack) so bots spawned in the gap
		# between the client's "ready" and its ack still reach the joining peer
		# — otherwise those bots would be permanently invisible to it (#84).
		# _connected_peers may be empty on the first bot batch (dedicated boot) —
		# that's fine, joiners get all live bots mirrored in net_client_ready below.
		for pid in _connected_peers.keys():
			rpc_id(int(pid), "net_spawn_bot", assigned_id, b.position, team, bname, loadout, b.cosmetics)


# ── Shared ────────────────────────────────────────────

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.set_script(hud_script)
	add_child(hud)
	hud.player = player
	hud.map_name = str(_map["name"])
	kill.connect(hud._on_kill)
	# Spectator (#75) — created alongside the HUD so it exists before any player
	# dies. Camera stays disabled until activate() is called on local death.
	spectator = Spectator.new()
	spectator.name = "Spectator"
	spectator.main = self
	add_child(spectator)


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
		or DisplayServer.is_touchscreen_available()
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


func _spawn_flags() -> void:
	# CTF bases: BLUE on the far left, RED on the far right of the map's ground row.
	# Custom maps (editor) can override the pair via `ctf_flags: [blue, red]`.
	var ground_y: float = float(_map.get("ctf_ground_y", GROUND_Y))
	var blue_base := Vector2(300, ground_y)
	var red_base := Vector2(MAP_W - 300, ground_y)
	var custom: Array = _map.get("ctf_flags", [])
	if custom.size() >= 2:
		blue_base = custom[0]
		red_base = custom[1]
	# Flags stand on their pole — settle each base onto the ground beneath it
	# so none float in mid-air or sit buried in a floor.
	blue_base = _settle_on_ground(blue_base)
	red_base = _settle_on_ground(red_base)
	flags = [
		_make_flag(TEAM_BLUE, blue_base),
		_make_flag(TEAM_RED, red_base),
	]


func _spawn_flag_inf() -> void:
	# INF: single neutral flag near the center. Attackers (RED) deliver to the
	# defenders' base (BLUE) to score. Defenders return the flag by touching it.
	# Custom maps override the flag + defender base via `inf_flag` / `ctf_flags[0]`.
	var ground_y: float = float(_map.get("ctf_ground_y", GROUND_Y))
	var center: Vector2 = _settle_on_ground(_map.get("inf_flag", Vector2(MAP_W * 0.5, ground_y)))
	var defender_base := Vector2(300, ground_y)
	var custom_flags: Array = _map.get("ctf_flags", [])
	if custom_flags.size() >= 1:
		defender_base = custom_flags[0]
	defender_base = _settle_on_ground(defender_base)
	var f := _make_flag(0, center)
	f.set_meta("capture_point", defender_base)
	flags = [f]


func _spawn_flag_htf() -> void:
	# HTF: single neutral flag mid-map. The carrying team ticks score per second.
	var ground_y: float = float(_map.get("ctf_ground_y", GROUND_Y))
	var center: Vector2 = _settle_on_ground(_map.get("htf_flag", Vector2(MAP_W * 0.5, ground_y)))
	flags = [_make_flag(0, center)]


func _spawn_rambo_bow() -> void:
	# RM: single Rambo Bow pickup at map center — carrier gets HP regen +
	# is the only one who scores kills.
	# In MP only the host spawns it — the pickup state stream (#34) mirrors
	# it to clients so both peers agree on where the bow is.
	if Net.is_networked() and not Net.is_host():
		return
	var ground_y: float = float(_map.get("ctf_ground_y", GROUND_Y))
	var wp := WeaponPickup.new()
	wp.weapon_name = "Rambo Bow"
	wp.team = -1
	wp.thrower_name = ""
	wp.damage_on_hit = 0.0
	wp.global_position = _map.get("rambo_pos", Vector2(MAP_W * 0.5, ground_y - 40.0))
	wp.set_meta("rambo_spawn", true)
	if Net.is_networked() and Net.is_host():
		wp.pickup_id = next_pickup_id()
	add_child(wp)


func _spawn_point_pickups() -> void:
	# PM: scatter respawning point pickups. Each grants +1 to the toucher's team.
	# #113: honor an explicit "point_spawns" list from the map editor; fall back
	# to the built-in scan-line pattern so procedural maps still play PM.
	var explicit: Array = _map.get("point_spawns", [])
	if not explicit.is_empty():
		for pos in explicit:
			if pos is Vector2:
				_spawn_point_pickup(pos)
		return
	# Default pattern scales with the map width and sits 30 px above the
	# actual ground (the old fixed 4800-arena row floated or sank into hills).
	var ground_y: float = float(_map.get("ctf_ground_y", GROUND_Y))
	var fracs: PackedFloat32Array = [0.15, 0.29, 0.44, 0.5, 0.56, 0.71, 0.85]
	for f in fracs:
		_spawn_point_pickup(_settle_on_ground(Vector2(MAP_W * f, ground_y - 2.0)) + Vector2(0, -30.0))


func _make_flag(team: int, base: Vector2) -> Area2D:
	var a := Area2D.new()
	a.add_to_group("ctf_flag")
	a.set_meta("team", team)
	a.set_meta("home", base)
	a.set_meta("carrier", null)
	a.position = base
	var col := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 18.0
	col.shape = cs
	a.add_child(col)
	# Animated flag (scripts/flag_visual.gd): waving shaded cloth on a pole with
	# a stone base + team glow at home, strapped to the carrier's back while
	# carried, and planted with a blinking beacon when dropped.
	var vis := Node2D.new()
	vis.name = "FlagVisual"
	vis.set_script(preload("res://scripts/flag_visual.gd"))
	a.add_child(vis)
	add_child(a)
	return a


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

func _spawn_networked_player(peer_id: int) -> void:
	# FFA MP (DM/RM): spawn joining players at a random bot_spawn — classic Soldat
	# spawn-point behavior. Puts them in the action zone instead of the map corner
	# where player_spawn typically sits (Ascent/Towers/Pillars have player_spawn at
	# (200,1775) but every bot_spawn is >2000px away, so a fresh joiner would never
	# actually meet a bot within the first ~10s). Team modes keep player_spawn so
	# team sides stay coherent. (#57)
	var t: int = _assign_team_for_peer(peer_id)
	var base: Vector2 = _map["player_spawn"]
	if Settings.is_team_mode() and t == TEAM_RED:
		var rl := _team_spawn_list(TEAM_RED)
		base = rl[randi() % rl.size()]
	if Net.is_networked() and not Settings.is_team_mode():
		var bs: Array = _map.get("bot_spawns", [])
		if not bs.is_empty():
			base = bs[randi() % bs.size()]
	var spawn_pos := _jitter_spawn(base)
	var display_name: String = Settings.player_name if peer_id == 1 else str(_peer_names.get(peer_id, "Player %d" % peer_id))
	rpc("net_spawn_player", peer_id, spawn_pos, display_name, t)


func _assign_team_for_peer(peer_id: int) -> int:
	# Deathmatch / Rambomatch stay FFA — team = peer_id so every soldier is a
	# distinct hostile entity.
	if not Settings.is_team_mode():
		return peer_id
	# Team modes: alternate BLUE/RED to keep sides balanced. INF is asymmetric —
	# first peer defends (BLUE), everyone else attacks.
	var blue_count := 0
	var red_count := 0
	for pid in _players_by_id.keys():
		if int(pid) == peer_id:
			continue
		var p = _players_by_id[pid]
		if not is_instance_valid(p):
			continue
		if int(p.team) == TEAM_BLUE:
			blue_count += 1
		elif int(p.team) == TEAM_RED:
			red_count += 1
	if Settings.game_mode == Settings.MODE_INF:
		return TEAM_BLUE if blue_count == 0 else TEAM_RED
	return TEAM_BLUE if blue_count <= red_count else TEAM_RED


func _schedule_peer_respawn(peer_id: int, t: int) -> void:
	if not Net.is_host():
		return
	# Survival: _reset_round rebuilds everyone's body; no timer.
	if Settings.survival:
		return
	var delay: float = _respawn_delay_for_team(t)
	var mode_at_schedule: int = Net.mode
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if Net.mode != mode_at_schedule or not is_inside_tree():
			return
		# A round reset in between may already have given this peer a body.
		var cur: Variant = _players_by_id.get(peer_id)
		if cur != null and is_instance_valid(cur) and not bool((cur as Node).get("dead")):
			return
		_respawn_peer(peer_id))


func _respawn_peer(peer_id: int) -> void:
	if not Net.is_host():
		return
	# still connected?
	if peer_id != 1 and not multiplayer.get_peers().has(peer_id):
		return
	_spawn_networked_player(peer_id)


func _on_net_peer_disconnected(id: int) -> void:
	if Net.is_host():
		_ready_peers.erase(id)
		_connected_peers.erase(id)
		rpc("net_despawn_player", id)
		# If the disconnecting peer was the votekick target, resolve the vote
		# immediately — no one benefits from a countdown against a phantom.
		if vote_active and vote_kind == "votekick" and vote_target_arg == id:
			_resolve_vote(false, "Target left the server")


func ready_peer_ids() -> Array:
	return _ready_peers.keys()


func _handle_client_ready(sender_id: int, joiner_name: String = "", client_version: String = "") -> void:
	if not Net.is_host():
		return
	var sender := sender_id
	# One ready per connection — a repeat call used to be a free respawn/rename.
	if _connected_peers.has(sender):
		return
	# Version handshake: mismatched builds desync maps/nav/RPCs in odd ways, so
	# refuse them with a readable reason instead.
	var host_version := str(ProjectSettings.get_setting("application/config/version", ""))
	if client_version != host_version:
		rpc_id(sender, "net_reject", "Version mismatch: host %s, you %s" % [host_version, client_version if client_version != "" else "(old build)"])
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(sender))
		return
	# Remember the joiner's chosen display name (sanitized, unique) so
	# _spawn_networked_player uses it instead of "Player N". Duplicate names
	# broke kill credit, spawn protection and Gun Game rungs (all name-keyed).
	var clean_name: String = str(joiner_name).strip_edges().left(24)
	if clean_name == "":
		clean_name = "Player %d" % sender
	_peer_names[sender] = _unique_display_name(clean_name, sender)
	# Mark the peer as able to receive reliable spawn RPCs BEFORE we mirror — any
	# host-initiated spawn between now and net_spawn_ack still needs to reach
	# this peer, otherwise it'd be permanently invisible (#84).
	_connected_peers[sender] = true
	# #97: send the Gun Game rung snapshot FIRST so the spawn RPCs below read
	# from a populated _gg_levels. Previously the joiner spawned replicas at
	# rung 0 and only self-healed on the next kill.
	if Settings.game_mode == Settings.MODE_GG:
		rpc_id(sender, "net_gg_state_sync", _gg_levels)
	# tell the new peer about all currently living players
	for existing_id in _players_by_id.keys():
		var p: Node = _players_by_id[existing_id]
		if not is_instance_valid(p):
			continue
		rpc_id(sender, "net_spawn_player", existing_id, p.position, p.display_name, int(p.team))
	# Mirror every live bot to the joining peer so they see the current roster
	# (dedicated server pre-populates before any client connects — issue #55).
	for bid in _bots_by_id.keys():
		var b: Node = _bots_by_id[bid]
		if not is_instance_valid(b):
			continue
		rpc_id(sender, "net_spawn_bot", int(bid), b.position, int(b.team), str(b.display_name), str(b.loadout), b.cosmetics)
	# Mirror every live bonus box (#78) so the joiner sees the same crates.
	for bid in _bonus_boxes.keys():
		var box: Node = _bonus_boxes[bid]
		if not is_instance_valid(box):
			continue
		rpc_id(sender, "net_bonus_spawn", int(bid), box.position, str(box.get("bonus_kind")))
	# then spawn a body for the new peer on everyone
	_spawn_networked_player(sender)
	# NOTE: _ready_peers[sender] is set only when the client acks the spawn (net_spawn_ack).
	# Otherwise net_state (unreliable_ordered) can beat the reliable spawn RPC and error out.


func _unique_display_name(want: String, for_peer: int) -> String:
	var taken := {}
	if not Net.is_dedicated:
		taken[Settings.player_name] = true
	for pid in _peer_names.keys():
		if int(pid) != for_peer:
			taken[str(_peer_names[pid])] = true
	for s in get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(s):
			taken[str(s.get("display_name"))] = true
	var nm := want
	var n := 2
	while taken.has(nm):
		nm = "%s (%d)" % [want, n]
		n += 1
	return nm


@rpc("authority", "call_remote", "reliable")
func net_reject(reason: String) -> void:
	_leave_to_menu(reason)


func _on_lost_host() -> void:
	_leave_to_menu("Disconnected from host")


func _leave_to_menu(reason: String) -> void:
	# Client lost its host (quit / kicked / rejected): back to the menu with a
	# message instead of silently running single-player logic in a dead match.
	if Net.disconnected.is_connected(_on_lost_host):
		Net.disconnected.disconnect(_on_lost_host)
	Net.leave()
	Net.status = reason
	Net.last_disconnect_reason = reason
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", "res://scenes/menu.tscn")


@rpc("any_peer", "reliable")
func net_spawn_ack() -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	_ready_peers[sender] = true
	# Push the current MatchConfig snapshot (#74) so the joining peer applies
	# the host's mods / friendly-fire / bot roster immediately instead of
	# running under its own local Settings until the next admin-menu change.
	rpc_id(sender, "net_match_config_apply", MatchConfig.to_dict())
	# Send an immediate pickup snapshot + M2 mount ownership so a late-joiner
	# sees currently-thrown weapons on the ground and knows which turrets are
	# already occupied, instead of waiting for the next 10Hz broadcast tick.
	var arr: Array = []
	for wp in get_tree().get_nodes_in_group("weapon_pickup"):
		if not is_instance_valid(wp):
			continue
		if int(wp.get("pickup_id")) <= 0:
			continue
		arr.append({
			"id": int(wp.get("pickup_id")),
			"name": str(wp.get("weapon_name")),
			"team": int(wp.get("team")),
			"thrower": str(wp.get("thrower_name")),
			"pos": wp.global_position,
			"vel": wp.linear_velocity,
			"ang": float(wp.angular_velocity),
			"rot": float(wp.rotation),
			# #94: carry damage explicitly so future damage-on-hit weapons
			# (axe/bayonet/etc.) don't silently lose their damage on clients
			# because we re-derived by name.
			"dmg": float(wp.get("damage_on_hit")),
		})
	if not arr.is_empty():
		rpc_id(sender, "net_pickup_state", arr)
	for m2 in get_tree().get_nodes_in_group("m2_gun"):
		if not is_instance_valid(m2):
			continue
		var op = m2.get("operator")
		if is_instance_valid(op):
			rpc_id(sender, "net_m2_mount", int(m2.get("m2_id")), int(op.get_multiplayer_authority()))
	# #108: hydrate scoreboard / flag / mode state immediately so a joiner
	# landing during e.g. the winner-display window or with a flag being
	# carried doesn't render 0-0-0 / flag-at-home for up to a broadcast tick.
	rpc_id(sender, "net_match_state", scores, time_left, round_active, winner_team, winner_end_t, winner_note, _gg_levels, _gg_kills)
	if flags.size() > 0:
		var flag_arr: Array = []
		for f in flags:
			if not is_instance_valid(f):
				flag_arr.append({"pos": Vector2.ZERO, "carrier": 0})
				continue
			var cid := 0
			var carrier: Variant = f.get_meta("carrier") if f.has_meta("carrier") else null
			if is_instance_valid(carrier):
				var nm := String(carrier.name)
				if nm.begins_with("Player_"):
					cid = int(nm.substr(7))
			flag_arr.append({"pos": f.position, "carrier": cid})
		rpc_id(sender, "net_flag_state", flag_arr)
	var mode: int = Settings.game_mode
	if mode == Settings.MODE_DOM or mode == Settings.MODE_PM or mode == Settings.MODE_BR:
		var mp: Dictionary = {}
		if mode == Settings.MODE_DOM:
			var dom: Array = []
			for a in _dom_points:
				if not is_instance_valid(a):
					dom.append([0, 0.0, 0])
					continue
				dom.append([int(a.get_meta("owner_team", 0)), float(a.get_meta("progress", 0.0)), int(a.get_meta("cap_team", 0))])
			mp["dom"] = dom
		elif mode == Settings.MODE_PM:
			var pm: Array = []
			for p in get_tree().get_nodes_in_group("point_pickup"):
				if is_instance_valid(p):
					pm.append(p.get_meta("spawn_pos", p.global_position))
			mp["pm"] = pm
		elif mode == Settings.MODE_BR:
			mp["br"] = {"c": _br_zone_center, "r": _br_zone_radius}
		if not mp.is_empty():
			rpc_id(sender, "net_mode_state", mp)


@rpc("authority", "reliable")
func net_match_config_apply(cfg: Dictionary) -> void:
	# Thin trampoline to MatchConfig.apply_dict — kept on Main so the RPC target
	# lives on a scene-node the multiplayer stack always resolves (autoloads
	# resolve too, but co-locating the match state RPCs here matches the pattern
	# used by net_match_state / net_flag_state / net_pickup_state).
	MatchConfig.apply_dict(cfg)


@rpc("authority", "call_local", "reliable")
func net_match_restart(map_idx: int, mode_idx: int) -> void:
	# Host-driven full-match restart (#74). Everyone lands on the same map+mode
	# by updating the shared knobs BEFORE reloading main.tscn — main._ready()
	# then reads them and rebuilds terrain / spawns cleanly.
	Net.chosen_map_index = clampi(map_idx, 0, MAPS.size() - 1)
	Settings.map_index = Net.chosen_map_index
	Settings.custom_map_path = ""  # networked matches always use built-in maps
	Net.custom_map_json = ""       # ...and must not rebuild the previous custom map
	Settings.game_mode = clampi(mode_idx, 0, Net.MODE_NAMES.size() - 1)
	Settings.save()
	call_deferred("_do_reload_main")


func _do_reload_main() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


@rpc("authority", "call_local", "reliable")
func net_spawn_player(peer_id: int, spawn_pos: Vector2, display_name: String, assigned_team: int = -1) -> void:
	if assigned_team >= 0:
		_peer_team_by_id[peer_id] = assigned_team
	# Free stale record if this peer had a prior body (e.g., on respawn).
	if _players_by_id.has(peer_id):
		var old = _players_by_id[peer_id]
		if is_instance_valid(old):
			old.queue_free()
		_players_by_id.erase(peer_id)
	var p := player_scene.instantiate()
	p.name = "Player_%d" % peer_id
	p.position = spawn_pos
	p.display_name = display_name
	# Backward-compat: pre-#22 callers may send no team. In FFA the peer_id acts
	# as a distinct hostile team; in team modes we resolve via the balancer so a
	# raw peer id (millions-range) never leaks into team/colour checks (#85).
	var t: int
	if assigned_team >= 0:
		t = assigned_team
	elif Settings.is_team_mode():
		t = _assign_team_for_peer(peer_id)
	else:
		t = peer_id
	p.team = t
	if t == TEAM_BLUE:
		p.color = Color(0.35, 0.55, 1.0)
	elif t == TEAM_RED:
		p.color = Color(0.85, 0.3, 0.25)
	p.set_multiplayer_authority(peer_id)
	# Gun Game: restore persisted rung on respawn so death doesn't reset progress.
	if Settings.game_mode == Settings.MODE_GG:
		p.gg_level = _gg_get(display_name)
	add_child(p)
	# Re-apply after add_child so children created in _ready (cam, jet_particles) inherit authority.
	p.set_multiplayer_authority(peer_id, true)
	_players_by_id[peer_id] = p
	if peer_id == Net.local_id():
		player = p
		_bind_local_camera(p)
		if hud:
			hud.player = p
		# Wire death signal so MP local respawn goes through _on_player_died — that's
		# where the spectator kicks in (#75) and the death UI is shown consistently.
		if not p.died.is_connected(_on_player_died):
			p.died.connect(_on_player_died)
		# Respawn happened — cut the spectator cam and hide the "you died" overlay
		# so the freshly-spawned body's own camera takes over cleanly.
		_end_spectator()
		if hud and hud.has_method("_hide_death"):
			hud._hide_death()
		# Tell the host our body is spawned locally so it can start sending state.
		if Net.is_client():
			rpc_id(1, "net_spawn_ack")


@rpc("authority", "call_local", "reliable")
func net_despawn_player(peer_id: int) -> void:
	if _players_by_id.has(peer_id):
		var p = _players_by_id[peer_id]
		if is_instance_valid(p):
			p.queue_free()
		_players_by_id.erase(peer_id)
	if peer_id == Net.local_id():
		player = null


# ── Objective events (grab / drop / return / capture / dom / point) ───────
# Host-side game logic calls _objective_event; every peer gets the banner,
# feed line and sound via net_objective_event (they used to be host-only
# kill-feed hacks that also double-scored).
func _objective_event(kind: String, team: int, who: String) -> void:
	if Net.is_networked():
		if Net.is_host() and multiplayer.has_multiplayer_peer():
			rpc("net_objective_event", kind, team, who)
	else:
		net_objective_event(kind, team, who)


@rpc("authority", "call_local", "reliable")
func net_objective_event(kind: String, team: int, who: String) -> void:
	objective.emit(kind, team, who)
	if hud != null and hud.has_method("announce_objective"):
		hud.announce_objective(kind, team, who)
	Sfx.objective(kind)


@rpc("authority", "call_local", "reliable")
func net_kill_feed(killer_name: String, victim_name: String, weapon_name: String, killer_team: int, victim_team: int) -> void:
	kill.emit(killer_name, victim_name, weapon_name, killer_team, victim_team)


@rpc("any_peer", "call_local", "reliable")
func net_chat(author: String, msg: String, scope: String, sender_team: int) -> void:
	# #105: never trust client-supplied author / sender_team. In a networked
	# match, resolve both from the sender's peer_id so a client can't
	# impersonate other players or leak team chat across teams. Host-local
	# announcer messages (see hud.post_chat calls elsewhere) bypass this RPC.
	msg = msg.left(200)
	if Net.is_networked():
		var sender: int = multiplayer.get_remote_sender_id()
		if sender > 0 and sender != multiplayer.get_unique_id():
			# Resolve from the sender's registered identity even while dead —
			# otherwise a dead client could post as anyone / read-leak team chat.
			if _players_by_id.has(sender) and is_instance_valid(_players_by_id[sender]):
				author = str(_players_by_id[sender].display_name)
				sender_team = int(_players_by_id[sender].team)
			elif _peer_team_by_id.has(sender):
				author = str(_peer_names.get(sender, "Player %d" % sender))
				sender_team = int(_peer_team_by_id[sender])
			else:
				return
	# Team chat is filtered locally so opponents don't see it. Global chat is
	# visible to everyone. Route through the HUD's chat feed.
	if scope == "team" and is_instance_valid(player) and int(player.team) != sender_team:
		return
	if hud != null and hud.has_method("post_chat"):
		hud.post_chat(author, msg, scope == "team")


# ── Match / score / round ─────────────────────────────

func _process(delta: float) -> void:
	# Vote timer + cooldown ticks — before the client early-return so the vote
	# countdown reads smoothly on every peer between host state broadcasts (#77).
	_tick_vote(delta)
	# Kill line + anti-stuck watchdog — per peer, for locally-owned soldiers.
	_tick_soldier_safety(delta)
	# Client: state is driven entirely by host's net_match_state RPCs.
	if Net.is_networked() and not Net.is_host():
		# BR ring damage is applied by each soldier's authority; the host can't
		# damage a client-owned body, so the client burns its own (zone state
		# arrives via the host snapshot).
		if Settings.game_mode == Settings.MODE_BR and round_active and player != null \
				and is_instance_valid(player) and not bool(player.get("dead")) \
				and player.global_position.distance_to(_br_zone_center) > _br_zone_radius:
			player.take_damage(BR_ZONE_DPS * delta, "", "Zone", -1)
		if Settings.game_mode == Settings.MODE_RM and player != null and is_instance_valid(player) \
				and not bool(player.get("dead")) and player.has_method("current_weapon_name") \
				and str(player.current_weapon_name()) == "Rambo Bow":
			player.health = minf(100.0, float(player.health) + 40.0 * delta)
		return
	# Bonus box respawn timer (#78) — host / SP owns spawn cadence.
	_tick_bonus_boxes(delta)
	# Objectives freeze on the winner screen — re-scoring there used to re-call
	# _end_round every tick and reset the countdown forever (DOM/BR/HTF).
	if not round_active:
		pass
	elif Settings.game_mode == Settings.MODE_CTF and flags.size() == 2:
		_tick_ctf()
	elif Settings.game_mode == Settings.MODE_INF and flags.size() == 1:
		_tick_inf()
	elif Settings.game_mode == Settings.MODE_HTF and flags.size() == 1:
		_tick_htf(delta)
	elif Settings.game_mode == Settings.MODE_RM:
		_tick_rambo()
	elif Settings.game_mode == Settings.MODE_PM:
		_tick_pointmatch(delta)
	elif Settings.game_mode == Settings.MODE_DOM:
		_tick_domination(delta)
	elif Settings.game_mode == Settings.MODE_BR:
		_tick_battle_royale(delta)
	if round_active:
		time_left = maxf(0.0, time_left - delta)
		if time_left <= 0.0:
			_end_round_by_time()
	else:
		winner_end_t = maxf(0.0, winner_end_t - delta)
		if winner_end_t <= 0.0:
			_reset_round()
	if Net.is_networked() and Net.is_host():
		_match_sync_cd -= delta
		if _match_sync_cd <= 0.0:
			_match_sync_cd = 1.0 / MATCH_SYNC_HZ
			_broadcast_match_state()
			if vote_active:
				_broadcast_vote_state()
		# Flag positions + carriers stream faster so grabs/drops feel snappy.
		if flags.size() > 0:
			_flag_sync_cd -= delta
			if _flag_sync_cd <= 0.0:
				_flag_sync_cd = 1.0 / FLAG_SYNC_HZ
				_broadcast_flag_state()
		# Pickup physics stream at 10 Hz so thrown weapons + rambo bow stay in sync.
		_pickup_sync_cd -= delta
		if _pickup_sync_cd <= 0.0:
			_pickup_sync_cd = 1.0 / PICKUP_SYNC_HZ
			_broadcast_pickup_state()
		# DOM cap progress, PM pickup availability, BR zone size — client _process
		# early-returns before the mode ticks, so without this broadcast clients
		# see stale objectives (neutral points, ghost diamonds, static BR ring).
		# #107: throttled to MODE_SYNC_HZ; was called every frame.
		_mode_sync_cd -= delta
		if _mode_sync_cd <= 0.0:
			_mode_sync_cd = 1.0 / MODE_SYNC_HZ
			_broadcast_mode_state()
		# Bot state (pos/vel/facing/health/loadout/dead) streams at 20 Hz — matches
		# the player net_state cadence so bot bodies read smoothly on clients (#55).
		if not _bots_by_id.is_empty():
			_bot_sync_cd -= delta
			if _bot_sync_cd <= 0.0:
				_bot_sync_cd = 1.0 / BOT_SYNC_HZ
				_broadcast_bot_state()


func _tick_ctf() -> void:
	# Two-flag CTF: touch enemy flag to carry, deliver to own home to score.
	# Carried flags snap to the carrier; dropped flags stay in place until touched.
	var soldiers := get_tree().get_nodes_in_group("soldier")
	for f in flags:
		if not is_instance_valid(f):
			continue
		var flag_team: int = int(f.get_meta("team"))
		var home: Vector2 = f.get_meta("home")
		var carrier: Variant = f.get_meta("carrier") if f.has_meta("carrier") else null
		if typeof(carrier) == TYPE_OBJECT and not is_instance_valid(carrier):
			# Carrier body was freed (killed bot / disconnect) before we saw it
			# die — drop the flag where it was instead of leaving it hovering.
			_drop_flag(f, f.position + Vector2(0, 30))
			continue
		if is_instance_valid(carrier):
			if bool(carrier.get("dead")):
				# Carrier died — drop flag where they fell (settled onto the ground).
				_drop_flag(f, carrier.global_position)
				continue
			f.position = carrier.global_position + Vector2(0, -30)
			# Did the carrier reach their own base (their home flag)? Score + reset both.
			for other in flags:
				if other == f:
					continue
				var other_team: int = int(other.get_meta("team"))
				var other_home: Vector2 = other.get_meta("home")
				var other_carrier: Variant = other.get_meta("carrier") if other.has_meta("carrier") else null
				if int(carrier.get("team")) == other_team and other_carrier == null:
					if f.global_position.distance_to(other_home) < 40.0:
						_ctf_score(int(carrier.get("team")), str(carrier.get("display_name")))
						# Return both flags to base.
						for ff in flags:
							ff.position = ff.get_meta("home")
							ff.set_meta("carrier", null)
			continue
		# Not carried — check for a grab (enemy touches) or return-to-base (own team touches).
		for s in soldiers:
			if not is_instance_valid(s) or bool(s.get("dead")):
				continue
			if s.global_position.distance_to(f.global_position) < 22.0:
				var s_team: int = int(s.get("team"))
				if s_team == flag_team:
					# Own team touches: if the flag is away from home, return it.
					if f.position.distance_to(home) > 12.0:
						f.position = home
						_objective_event("return", flag_team, str(s.get("display_name")))
						break
					# A defender standing on its home flag must not block an
					# enemy grab — keep scanning.
					continue
				else:
					# Enemy pickup.
					f.set_meta("carrier", s)
					_objective_event("grab", flag_team, str(s.get("display_name")))
				break


func _tick_inf() -> void:
	# Single-flag INF: RED = attackers, BLUE = defenders. RED delivers to
	# the defenders' base to score; BLUE returns the flag by touching it.
	var f: Area2D = flags[0] as Area2D
	if not is_instance_valid(f):
		return
	var home: Vector2 = f.get_meta("home")
	var capture: Vector2 = f.get_meta("capture_point")
	var carrier: Variant = f.get_meta("carrier") if f.has_meta("carrier") else null
	if typeof(carrier) == TYPE_OBJECT and not is_instance_valid(carrier):
		_drop_flag(f, f.position + Vector2(0, 30))
		return
	if is_instance_valid(carrier):
		if bool(carrier.get("dead")):
			_drop_flag(f, carrier.global_position)
			return
		f.position = carrier.global_position + Vector2(0, -30)
		if int(carrier.get("team")) == TEAM_RED \
				and f.global_position.distance_to(capture) < 40.0:
			_inf_score(TEAM_RED, str(carrier.get("display_name")))
			f.position = home
			f.set_meta("carrier", null)
		return
	# Not carried — pickup / return.
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		if s.global_position.distance_to(f.global_position) < 22.0:
			var s_team: int = int(s.get("team"))
			if s_team == TEAM_RED:
				f.set_meta("carrier", s)
				_objective_event("grab", 0, str(s.get("display_name")))
				break
			elif s_team == TEAM_BLUE:
				if f.position.distance_to(home) > 12.0:
					f.position = home
					_objective_event("return", 0, str(s.get("display_name")))
					break


func _inf_score(team: int, capturer: String) -> void:
	scores[team] = int(scores.get(team, 0)) + 1
	_objective_event("capture", team, capturer)
	if int(scores[team]) >= INF_SCORE_TO_WIN:
		_end_round(team)


func _tick_htf(delta: float) -> void:
	# Single-flag HTF: whichever team's soldier is carrying accumulates points
	# per second. Enemy soldier picks it up → carrier switches. If dropped and
	# no one grabs, it just waits.
	var f: Area2D = flags[0] as Area2D
	if not is_instance_valid(f):
		return
	var home: Vector2 = f.get_meta("home")
	var carrier: Variant = f.get_meta("carrier") if f.has_meta("carrier") else null
	if typeof(carrier) == TYPE_OBJECT and not is_instance_valid(carrier):
		_drop_flag(f, f.position + Vector2(0, 30))
		return
	if is_instance_valid(carrier):
		if bool(carrier.get("dead")):
			_drop_flag(f, carrier.global_position)
			return
		f.position = carrier.global_position + Vector2(0, -30)
		var ct: int = int(carrier.get("team"))
		_htf_accum[ct] = float(_htf_accum.get(ct, 0.0)) + delta
		# Flush whole seconds into scores so the scoreboard ticks visibly.
		while float(_htf_accum.get(ct, 0.0)) >= 1.0:
			_htf_accum[ct] = float(_htf_accum[ct]) - 1.0
			scores[ct] = int(scores.get(ct, 0)) + 1
			if int(scores[ct]) >= HTF_SCORE_TO_WIN:
				_end_round(ct)
				return
		return
	# Not carried — first soldier to touch grabs it.
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		if s.global_position.distance_to(f.global_position) < 22.0:
			f.set_meta("carrier", s)
			_objective_event("grab", 0, str(s.get("display_name")))
			break
	# If dropped far from home and untouched for a while, reset (mercy behavior).
	if f.position.distance_to(home) > 1400.0:
		f.position = home


func _tick_rambo() -> void:
	# Rambo Match: single bow pickup. Whoever holds it regenerates HP fast and
	# is the only player whose kills score. Kill feed handled by _on_kill_scored.
	# Determine current carrier by scanning weapon_pickups + soldiers holding "Rambo Bow".
	var carrier_id := 0
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		# player.weapons + secondary lookup: if their active weapon is "Rambo Bow".
		var wname := ""
		if s.get("weapons") != null:
			var idx: int = int(s.get("weapon_index"))
			var arr: Array = s.get("weapons")
			if idx >= 0 and idx < arr.size():
				wname = str(arr[idx]["name"])
		elif s.get("loadout") != null:
			wname = str(s.get("loadout"))
		if wname == "Rambo Bow":
			carrier_id = s.get_instance_id()
			# Regenerate carrier's HP fast.
			# Health belongs to the body's authority — a client-owned carrier
			# regenerates itself (see the client branch of _process).
			if multiplayer.multiplayer_peer == null or s.is_multiplayer_authority():
				var hp: float = float(s.get("health"))
				s.set("health", minf(100.0, hp + 40.0 * get_process_delta_time()))
			break
	# Cooldown gate (#38): if the previous frame had a carrier and we now have none,
	# they died — hold off the bow's map-center respawn for a few seconds so an
	# instant re-pickup doesn't happen the same tick.
	if _rambo_carrier_id != 0 and carrier_id == 0:
		_rambo_respawn_cd = RAMBO_RESPAWN_DELAY
	_rambo_carrier_id = carrier_id
	_rambo_respawn_cd = maxf(0.0, _rambo_respawn_cd - get_process_delta_time())
	# Respawn the bow at map center if it doesn't exist and nobody is holding it.
	if carrier_id == 0 and _rambo_respawn_cd <= 0.0:
		var exists := false
		for wp in get_tree().get_nodes_in_group("weapon_pickup"):
			if is_instance_valid(wp) and str(wp.get("weapon_name")) == "Rambo Bow":
				exists = true
				break
		if not exists:
			_spawn_rambo_bow()


# ── Domination ─────────────────────────────────────────

func _spawn_dom_points() -> void:
	# Three capture points along the map — left, center, right — on the ground row.
	# Custom maps override the trio via `dom_points: [Vector2, Vector2, Vector2]`.
	var ground_y: float = float(_map.get("ctf_ground_y", GROUND_Y))
	var default_slots := [
		{"pos": _settle_on_ground(Vector2(MAP_W * 0.20, ground_y - 30.0)) + Vector2(0, -30.0), "name": "A"},
		{"pos": _settle_on_ground(Vector2(MAP_W * 0.50, ground_y - 30.0)) + Vector2(0, -30.0), "name": "B"},
		{"pos": _settle_on_ground(Vector2(MAP_W * 0.80, ground_y - 30.0)) + Vector2(0, -30.0), "name": "C"},
	]
	var slots: Array = default_slots
	var custom: Array = _map.get("dom_points", [])
	if custom.size() >= 1:
		slots = []
		var labels := ["A", "B", "C", "D", "E"]
		for i in custom.size():
			slots.append({"pos": custom[i], "name": labels[mini(i, labels.size() - 1)]})
	var visual := preload("res://scripts/dom_point_visual.gd")
	for slot in slots:
		var a := Area2D.new()
		a.add_to_group("dom_point")
		a.set_meta("owner_team", 0)   # 0 = neutral, 1 = BLUE, 2 = RED
		a.set_meta("progress", 0.0)   # 0..1 while being captured; polarity is signed by team
		a.set_meta("cap_team", 0)     # which team is actively capturing (0 = none)
		a.set_meta("label", str(slot["name"]))
		a.position = slot["pos"]
		var col := CollisionShape2D.new()
		var cs := CircleShape2D.new()
		cs.radius = 40.0
		col.shape = cs
		a.add_child(col)
		var vis := Node2D.new()
		vis.set_script(visual)
		a.add_child(vis)
		add_child(a)
		_dom_points.append(a)


func _tick_domination(delta: float) -> void:
	var soldiers := get_tree().get_nodes_in_group("soldier")
	for a in _dom_points:
		if not is_instance_valid(a):
			continue
		# Which teams have soldiers standing on this point?
		var blue_on := 0
		var red_on := 0
		var radius: float = 44.0
		for s in soldiers:
			if not is_instance_valid(s) or bool(s.get("dead")):
				continue
			var t: int = int(s.get("team"))
			if s.global_position.distance_to(a.global_position) > radius:
				continue
			if t == TEAM_BLUE:
				blue_on += 1
			elif t == TEAM_RED:
				red_on += 1
		var contested: bool = blue_on > 0 and red_on > 0
		var owner_team: int = int(a.get_meta("owner_team"))
		var progress: float = float(a.get_meta("progress"))
		var cap_team: int = int(a.get_meta("cap_team"))
		if not contested and (blue_on > 0 or red_on > 0):
			var t_cap: int = TEAM_BLUE if blue_on > 0 else TEAM_RED
			if owner_team == t_cap:
				progress = 0.0
				cap_team = 0
			else:
				# Same capturing team as last tick → keep ramping. Fresh team resets progress.
				if cap_team != t_cap:
					cap_team = t_cap
					progress = 0.0
				progress = clampf(progress + delta / DOM_CAPTURE_TIME, 0.0, 1.0)
				if progress >= 1.0:
					owner_team = t_cap
					progress = 0.0
					cap_team = 0
					_objective_event("dom", t_cap, str(a.get_meta("label")))
		elif not contested and blue_on == 0 and red_on == 0:
			# Empty point drains progress over time so long-held drops reset naturally.
			progress = maxf(0.0, progress - delta / (DOM_CAPTURE_TIME * 2.0))
			if progress <= 0.0:
				cap_team = 0
		a.set_meta("owner_team", owner_team)
		a.set_meta("progress", progress)
		a.set_meta("cap_team", cap_team)
	# Tick score: each owned point = 1 pt/sec into that team's accumulator.
	for a in _dom_points:
		if not is_instance_valid(a):
			continue
		var owner_team: int = int(a.get_meta("owner_team"))
		if owner_team == 0:
			continue
		_dom_accum[owner_team] = float(_dom_accum.get(owner_team, 0.0)) + delta
		while float(_dom_accum.get(owner_team, 0.0)) >= 1.0:
			_dom_accum[owner_team] = float(_dom_accum[owner_team]) - 1.0
			scores[owner_team] = int(scores.get(owner_team, 0)) + 1
			if int(scores[owner_team]) >= DOM_SCORE_TO_WIN:
				_end_round(owner_team)
				return


func dom_points() -> Array:
	return _dom_points


# ── Battle Royale ──────────────────────────────────────

func _reset_br_zone() -> void:
	_br_zone_radius = 2200.0
	_br_zone_center = Vector2(MAP_W * 0.5, MAP_H * 0.6)
	# Big ported maps: start the ring wide enough to cover the whole world.
	_br_zone_radius = maxf(2200.0, Vector2(MAP_W, MAP_H).length() * 0.5)
	# Attach the zone visual once — it reads center/radius from us on each redraw.
	if not has_node("BrZoneVisual"):
		var vis := Node2D.new()
		vis.name = "BrZoneVisual"
		vis.set_script(preload("res://scripts/br_zone_visual.gd"))
		add_child(vis)


func _tick_battle_royale(delta: float) -> void:
	_br_zone_radius = maxf(BR_ZONE_MIN, _br_zone_radius - BR_SHRINK_RATE * delta)
	# Damage anyone outside the safe zone; last soldier alive wins.
	var alive: Array = []
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		alive.append(s)
		var d: float = s.global_position.distance_to(_br_zone_center)
		if d > _br_zone_radius and s.has_method("take_damage"):
			# Non-authority replicas will refuse — matches CFG for other damage paths.
			if multiplayer.multiplayer_peer == null or s.is_multiplayer_authority():
				s.take_damage(BR_ZONE_DPS * delta, "", "Zone", -1)
	# Winner: only one soldier alive.
	if alive.size() == 1:
		var lone: Node = alive[0]
		scores[int(lone.get("team"))] = int(scores.get(int(lone.get("team")), 0)) + 1
		_end_round(int(lone.get("team")))
	elif alive.is_empty():
		_end_round(-1)


func br_zone() -> Dictionary:
	return {"center": _br_zone_center, "radius": _br_zone_radius}


func _spawn_point_pickup(pos: Vector2) -> void:
	var a := Area2D.new()
	a.add_to_group("point_pickup")
	a.position = pos
	a.set_meta("spawn_pos", pos)
	var col := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 12.0
	col.shape = cs
	a.add_child(col)
	# Draw as a small golden diamond so it reads on the terrain.
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0, -10), Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0)])
	poly.color = Color(1.0, 0.85, 0.25)
	a.add_child(poly)
	add_child(a)


func _tick_pointmatch(delta: float) -> void:
	# PM: pickups grant +1 to the toucher's team, then respawn after 6s.
	var soldiers := get_tree().get_nodes_in_group("soldier")
	var live_pickups := get_tree().get_nodes_in_group("point_pickup")
	for p in live_pickups:
		if not is_instance_valid(p):
			continue
		for s in soldiers:
			if not is_instance_valid(s) or bool(s.get("dead")):
				continue
			if p.global_position.distance_to(s.global_position) < 22.0:
				var s_team: int = int(s.get("team"))
				scores[s_team] = int(scores.get(s_team, 0)) + 1
				_objective_event("point", s_team, str(s.get("display_name")))
				var spawn_pos: Vector2 = p.get_meta("spawn_pos")
				_pm_pickups[spawn_pos] = 6.0
				p.queue_free()
				if int(scores[s_team]) >= PM_SCORE_TO_WIN:
					_end_round(s_team)
					return
				break
	# Respawn pickups after their cooldown.
	for pos in _pm_pickups.keys():
		var t: float = float(_pm_pickups[pos])
		t -= delta
		if t <= 0.0:
			_pm_pickups.erase(pos)
			_spawn_point_pickup(pos)
		else:
			_pm_pickups[pos] = t


func _ctf_score(team: int, capturer: String) -> void:
	scores[team] = int(scores.get(team, 0)) + 1
	_objective_event("capture", team, capturer)
	if scores[team] >= CTF_SCORE_TO_WIN:
		_end_round(team)


func _on_kill_scored(killer_name: String, victim_name: String, _weapon_name: String, killer_team: int, victim_team: int) -> void:
	# Objective feed lines (victim_team < 0: FLAG/POINT) were double-scoring
	# (+1 here on top of the mode's own point) and counting as kills in Stats.
	if victim_team < 0:
		return
	# Local stats — track the local player's kills / deaths / suicides.
	# Skips scoreboard synthetic entries (FLAG/POINT etc.) which have killer_team but no soldier.
	if is_instance_valid(player):
		var me: String = str(player.display_name)
		if killer_name == me and victim_name != me:
			Stats.record_kill(_weapon_name)
		if victim_name == me and killer_name == me:
			Stats.record_suicide()
		elif victim_name == me:
			Stats.record_death()
	# (#76) Streak + multi-kill announcer — runs on every peer (banner is local
	# per-viewer) so it must live above the host-only early-return below.
	_track_kill_streaks(killer_name, victim_name, killer_team)
	if Net.is_networked() and not Net.is_host():
		return
	if not round_active or killer_team < 0:
		return
	# Gun Game runs its own ladder BEFORE the generic team/suicide gate.
	# Suicides are still filtered here so a self-kill can't earn a rung-up.
	if Settings.game_mode == Settings.MODE_GG:
		if killer_name == victim_name:
			if Settings.survival:
				_check_survival_end()
			return
		# #91: track per-killer kill count so the GG scoreboard reads live.
		# Advances on every non-suicide kill (rung/grenade/off-rung alike) so
		# players see kill throughput even when the ladder hasn't moved yet.
		_gg_kills[killer_name] = int(_gg_kills.get(killer_name, 0)) + 1
		var k_lvl: int = _gg_get(killer_name)
		var weapon_key: String = str(_weapon_name).replace(" (headshot)", "")
		# Ladder advances only on kills with the killer's CURRENT rung weapon.
		# Grenade / off-rung / dropped-weapon kills stay on-kill-feed but grant
		# no progress — otherwise every rung could be skipped with a nade.
		var rung_weapon: String = ""
		if k_lvl >= 0:
			# Golden-knife rung (16) is still a knife kill.
			rung_weapon = str(GG_LADDER_NAMES[mini(k_lvl, GG_LADDER_NAMES.size() - 1)])
		var on_rung: bool = weapon_key == rung_weapon
		# Demote only when the killer is actually on the knife rung.
		var is_knife_kill: bool = weapon_key == "Knife" and k_lvl >= GG_KNIFE_LEVEL
		if on_rung and k_lvl >= GG_GOLD_KNIFE_LEVEL:
			winner_note = "%s reached the golden knife" % killer_name
			_end_round(killer_team)
			if Net.is_networked() and Net.is_host():
				_broadcast_match_state()
			return
		# Broadcast the new killer level; every peer applies it to the body
		# they own (host owns bots + host player; each client owns their player).
		if on_rung:
			if Net.is_networked():
				rpc("net_gg_set_level", killer_name, k_lvl + 1)
			else:
				_gg_set(killer_name, k_lvl + 1)
		if is_knife_kill:
			if Net.is_networked():
				rpc("net_gg_set_level", victim_name, _gg_get(victim_name) - 1)
			else:
				_gg_set(victim_name, _gg_get(victim_name) - 1)
		if Settings.survival:
			_check_survival_end()
		if Net.is_networked() and Net.is_host():
			_broadcast_match_state()
		return
	# Suicide or team-kill: no score change, but still check survival end so
	# the round can end on the last soldier down even from friendly fire.
	if killer_name == victim_name or killer_team == victim_team:
		if Settings.survival:
			_check_survival_end()
		return
	# Rambo mode: only the current bow carrier's kills count.
	if Settings.game_mode == Settings.MODE_RM:
		var carrier_is_killer := false
		for s in get_tree().get_nodes_in_group("soldier"):
			if is_instance_valid(s) and str(s.get("display_name")) == killer_name:
				if s.get_instance_id() == _rambo_carrier_id:
					carrier_is_killer = true
				break
		if not carrier_is_killer:
			return
	scores[killer_team] = int(scores.get(killer_team, 0)) + 1
	# Advance: bump the local player's kill counter and auto-equip any new tier.
	if Settings.advance and is_instance_valid(player) and str(player.display_name) == killer_name:
		var unlocked: PackedStringArray = player.advance_receive_kill()
		for name in unlocked:
			if hud != null and hud.has_method("post_chat"):
				hud.post_chat("ADVANCE", "Unlocked: %s" % name, false)
	if scores[killer_team] >= SCORE_TO_WIN:
		_end_round(killer_team)
	elif Settings.survival:
		# Survival: last team standing ends the round early.
		_check_survival_end()
	if Net.is_networked() and Net.is_host():
		_broadcast_match_state()


func _check_survival_end() -> void:
	# Round ends when only one team has any live soldier remaining.
	var alive_teams: Dictionary = {}
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		alive_teams[int(s.get("team"))] = true
	if alive_teams.size() <= 1:
		var winner_t := -1
		for k in alive_teams.keys():
			winner_t = int(k)
			break
		_end_round(winner_t)


func _gg_get(display_name: String) -> int:
	return int(_gg_levels.get(display_name, 0))


func _gg_set(display_name: String, level: int) -> void:
	# Store the clamped level, then push it into whichever live body carries the
	# name. Only the peer that owns the body mutates it — non-authority replicas
	# will pick up the swap through the usual net_state / net_bot_state stream.
	var clamped: int = clampi(level, 0, GG_GOLD_KNIFE_LEVEL)
	_gg_levels[display_name] = clamped
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s):
			continue
		if str(s.get("display_name")) != display_name:
			continue
		if not s.has_method("_apply_gg_weapon"):
			continue
		if multiplayer.multiplayer_peer != null and not s.is_multiplayer_authority():
			continue
		s.gg_level = clamped
		s._apply_gg_weapon()
		break


@rpc("authority", "call_local", "reliable")
func net_gg_set_level(display_name: String, level: int) -> void:
	_gg_set(display_name, level)


@rpc("authority", "reliable")
func net_gg_state_sync(levels: Dictionary) -> void:
	# Replace the entire cache — used both for a joining peer's initial snapshot
	# (so mid-match spawns read the correct rung locally) and for a round reset
	# so stale entries don't leak into the next round's first spawn wave.
	_gg_levels = levels.duplicate(true)


func _end_round(team: int) -> void:
	if not round_active:
		return  # already over — don't restart the winner countdown / re-save stats
	winner_team = team
	round_active = false
	winner_end_t = WINNER_DISPLAY
	# Record local W/L for the human player. In FFA modes the winner is the local
	# player's own team id; in team modes it's TEAM_BLUE / TEAM_RED.
	if is_instance_valid(player):
		var won: bool = team >= 0 and int(player.team) == team
		Stats.record_match_end(won)
	if Net.is_networked() and Net.is_host():
		_broadcast_match_state()


func _end_round_by_time() -> void:
	# Fixes #37: on time-out with an empty or tied scoreboard, describe *why*
	# the round ended as a draw instead of just showing "DRAW".
	# Gun Game (#91): use the ladder itself — highest rung wins, kills break ties.
	if Settings.game_mode == Settings.MODE_GG:
		var top_name: String = ""
		var top_lvl: int = -1
		var top_kills: int = -1
		var top_team: int = -1
		for s in get_tree().get_nodes_in_group("soldier"):
			if not is_instance_valid(s):
				continue
			var nm: String = str(s.get("display_name"))
			var lvl: int = _gg_get(nm)
			var kills: int = int(_gg_kills.get(nm, 0))
			if lvl > top_lvl or (lvl == top_lvl and kills > top_kills):
				top_lvl = lvl
				top_kills = kills
				top_name = nm
				top_team = int(s.get("team"))
		if top_name == "":
			winner_note = "Time up — no rung climbed"
			_end_round(-1)
		else:
			winner_note = "Time up — top rung: %s on rung %d/%d" % [top_name, top_lvl + 1, GG_GOLD_KNIFE_LEVEL]
			_end_round(top_team)
		return
	if scores.is_empty():
		winner_note = "Time up — no team scored"
		_end_round(-1)
		return
	var top_team := -1
	var top_score := -1
	var tied := false
	for t in scores.keys():
		var s := int(scores[t])
		if s > top_score:
			top_score = s
			top_team = int(t)
			tied = false
		elif s == top_score:
			tied = true
	if tied:
		var pieces: PackedStringArray = PackedStringArray()
		for t in scores.keys():
			pieces.append("%d" % int(scores[t]))
		winner_note = "Tied at %s — time up" % " – ".join(pieces)
		_end_round(-1)
	else:
		winner_note = "Time up — top score %d" % top_score
		_end_round(top_team)


func _reset_round() -> void:
	scores.clear()
	_stuck_time.clear()
	# Flags home, nobody carrying — a carrier teleported to spawn used to start
	# the next round holding the enemy flag next to their own base.
	for f in flags:
		if is_instance_valid(f):
			f.position = f.get_meta("home")
			f.set_meta("carrier", null)
	_htf_accum.clear()
	_dom_accum.clear()
	_gg_levels.clear()
	_gg_kills.clear()
	# Reset control points to neutral so the next round has fresh objectives.
	for a in _dom_points:
		if not is_instance_valid(a):
			continue
		a.set_meta("owner_team", 0)
		a.set_meta("progress", 0.0)
		a.set_meta("cap_team", 0)
	_reset_br_zone()
	# Wipe stale weapon pickups so a knife lying on the ground from last round
	# doesn't linger into the fresh round. `restore_for_round` already clears
	# per-player `_thrown` sets on host; the physics bodies need parity.
	if not Net.is_networked() or Net.is_host():
		for wp in get_tree().get_nodes_in_group("weapon_pickup"):
			if is_instance_valid(wp):
				wp.queue_free()
	time_left = ROUND_TIME
	winner_team = -1
	winner_note = ""
	winner_end_t = 0.0
	round_active = true
	# Survival: nobody respawns during the round, so at reset we wipe surviving
	# bodies and start everyone fresh.
	if Settings.survival:
		if Net.is_networked():
			# Only the host owns spawn authority; clients receive net_spawn_player.
			# Wipe living peer bodies + re-spawn every connected peer.
			if Net.is_host():
				for pid in _players_by_id.keys():
					var p = _players_by_id[pid]
					if is_instance_valid(p):
						p.queue_free()
				_players_by_id.clear()
				# Peer 1 (host, unless dedicated) + every fully-connected peer.
				if not Net.is_dedicated:
					_spawn_networked_player(1)
				for pid in _connected_peers.keys():
					_spawn_networked_player(int(pid))
				# #92: surviving bots kept last round's HP/ammo/pos while players
				# started fresh — wipe them too and re-spawn via net_spawn_bot so
				# clients mirror the reset.
				for bid in _bots_by_id.keys():
					var b = _bots_by_id[bid]
					if is_instance_valid(b):
						rpc("net_bot_despawn", bid)
						b.queue_free()
				_bots_by_id.clear()
				call_deferred("_spawn_bots")
		else:
			for s in get_tree().get_nodes_in_group("soldier"):
				if is_instance_valid(s):
					s.queue_free()
			_bots_by_id.clear()
			call_deferred("_spawn_player")
			call_deferred("_spawn_bots")
	else:
		# Non-survival (#58): the round ended but soldiers keep running around
		# with mid-fight HP/ammo/pos. Give every LIVING soldier a clean slate —
		# full HP, refilled ammo, teleport to a spawn slot. Dead-and-respawning
		# soldiers keep their own scheduled timer (no double-spawn) and come back
		# fresh the normal way.
		if Net.is_networked():
			if Net.is_host():
				rpc("net_round_reset")
				_restore_living_soldiers_local()
		else:
			_restore_living_soldiers_local()
	if Net.is_networked() and Net.is_host():
		_broadcast_match_state()


func _restore_living_soldiers_local() -> void:
	# Each peer restores only bodies it has authority over (host owns its own
	# player + bots; clients own their own player). Non-authority replicas will
	# receive the fresh state via the usual net_state / net_bot_state broadcasts.
	for s in get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")):
			continue
		if multiplayer.multiplayer_peer != null and not s.is_multiplayer_authority():
			continue
		if not s.has_method("restore_for_round"):
			continue
		s.position = _safe_spawn_near(_round_spawn_pos_for_team(int(s.get("team"))), int(s.get("team")))
		s.restore_for_round()


func _round_spawn_pos_for_team(t: int) -> Vector2:
	# Mirrors _spawn_networked_player's slot picker: team modes use the shared
	# player_spawn; FFA picks a random bot_spawns entry so respawning peers land
	# in the action instead of a corner. Small jitter avoids stacking on top.
	var base: Vector2 = _map["player_spawn"]
	if Settings.is_team_mode() and t == TEAM_RED:
		var rl := _team_spawn_list(TEAM_RED)
		base = rl[randi() % rl.size()]
	if not Settings.is_team_mode():
		var bs: Array = _map.get("bot_spawns", [])
		if not bs.is_empty():
			base = bs[randi() % bs.size()]
	return _jitter_spawn(base)


func _jitter_spawn(base: Vector2) -> Vector2:
	# Small random sideways offset so respawns don't stack — but only onto open
	# air with real ground below (a blind ±140 px shift used to drop players
	# inside walls or over pits on the tighter ported maps).
	var safe_base := _find_free_spot_near(base)
	for _i in 6:
		var c := safe_base + Vector2(randf_range(-140.0, 140.0), 0.0)
		if c.x < 60.0 or c.x > MAP_W - 60.0 or not _spot_is_clear(c):
			continue
		var gy := _geom_ground_y(c.x, c.y - 2.0)
		if gy == INF or gy > minf(KILL_Y, GROUND_Y + 1.0) or gy - c.y > 600.0:
			continue
		return c
	return safe_base


@rpc("authority", "call_remote", "reliable")
func net_round_reset() -> void:
	# Host-triggered non-survival round reset (#58). Runs on every client so
	# each peer restores the state of the soldier it owns.
	# Gun Game: also drop the client's cached rungs so a stale entry from the
	# previous round can't seed a fresh net_spawn_player / net_spawn_bot with
	# the wrong weapon before the next net_gg_set_level fires.
	_gg_levels.clear()
	_restore_living_soldiers_local()


func _broadcast_match_state() -> void:
	if not Net.is_host():
		return
	for pid in _ready_peers.keys():
		rpc_id(int(pid), "net_match_state", scores, time_left, round_active, winner_team, winner_end_t, winner_note, _gg_levels, _gg_kills)


@rpc("authority", "reliable")
func net_match_state(new_scores: Dictionary, tl: float, active: bool, winner: int, we: float, note: String = "", gg_ranks: Dictionary = {}, gg_kills: Dictionary = {}) -> void:
	scores = new_scores.duplicate(true)
	time_left = tl
	round_active = active
	winner_team = winner
	winner_end_t = we
	winner_note = note
	# #91 / #97: mirror GG ladder + kills so the scoreboard reads live on the
	# client and joining peers see the correct rung without waiting for the
	# next kill event. Empty dicts (non-GG modes) are a no-op.
	if not gg_ranks.is_empty():
		_gg_levels = gg_ranks.duplicate(true)
	_gg_kills = gg_kills.duplicate(true)


func _broadcast_mode_state() -> void:
	if not Net.is_host():
		return
	if _ready_peers.is_empty():
		return
	var mode: int = Settings.game_mode
	# Only bundle state that's relevant to the current mode — reduces payload
	# for DM/TDM/CTF etc. where none of this applies.
	var payload: Dictionary = {}
	if mode == Settings.MODE_DOM:
		var dom: Array = []
		for a in _dom_points:
			if not is_instance_valid(a):
				dom.append([0, 0.0, 0])
				continue
			dom.append([int(a.get_meta("owner_team", 0)), float(a.get_meta("progress", 0.0)), int(a.get_meta("cap_team", 0))])
		payload["dom"] = dom
	elif mode == Settings.MODE_PM:
		var pm: Array = []
		for p in get_tree().get_nodes_in_group("point_pickup"):
			if is_instance_valid(p):
				pm.append(p.get_meta("spawn_pos", p.global_position))
		payload["pm"] = pm
	elif mode == Settings.MODE_BR:
		payload["br"] = {"c": _br_zone_center, "r": _br_zone_radius}
	if payload.is_empty():
		return
	for pid in _ready_peers.keys():
		rpc_id(int(pid), "net_mode_state", payload)


@rpc("authority", "unreliable_ordered")
func net_mode_state(payload: Dictionary) -> void:
	# Client-side apply of host-authoritative mode state. Runs on client only —
	# host mutates these directly in its own ticks and short-circuits its net_
	# broadcast for itself.
	if not Net.is_networked() or Net.is_host():
		return
	if payload.has("dom"):
		var dom: Array = payload["dom"]
		for i in mini(dom.size(), _dom_points.size()):
			var a = _dom_points[i]
			if not is_instance_valid(a):
				continue
			var entry: Array = dom[i]
			a.set_meta("owner_team", int(entry[0]))
			a.set_meta("progress", float(entry[1]))
			a.set_meta("cap_team", int(entry[2]))
	if payload.has("pm"):
		var alive: Array = payload["pm"]
		var alive_set: Dictionary = {}
		for pos in alive:
			alive_set[str(pos)] = true
		var have_set: Dictionary = {}
		for p in get_tree().get_nodes_in_group("point_pickup"):
			if not is_instance_valid(p):
				continue
			var key: String = str(p.get_meta("spawn_pos", p.global_position))
			if not alive_set.has(key):
				p.queue_free()
			else:
				have_set[key] = true
		# Spawn any pickup we don't have locally (host respawned it after cooldown).
		for pos in alive:
			if not have_set.has(str(pos)):
				_spawn_point_pickup(pos)
	if payload.has("br"):
		var br: Dictionary = payload["br"]
		_br_zone_center = br.get("c", _br_zone_center)
		_br_zone_radius = float(br.get("r", _br_zone_radius))


# ── Vote system (#77) ─────────────────────────────────
# Host-authoritative. Public entry points are request_vote/cast_vote/cancel_vote.
# Chat commands (/votemap /votekick /votecancel) route in via HUD.

func _tick_vote(delta: float) -> void:
	if vote_active:
		vote_time_left = maxf(0.0, vote_time_left - delta)
	# Only host owns cooldown + resolution.
	if Net.is_networked() and not Net.is_host():
		return
	if vote_active and vote_time_left <= 0.0:
		_resolve_vote(vote_yes * 2 > _eligible_voters())
	if not vote_active:
		_vote_cooldown = maxf(0.0, _vote_cooldown - delta)


func request_vote(kind: String, arg: String) -> void:
	# Called from HUD when a player submits /votemap or /votekick.
	if Net.is_networked() and not Net.is_host():
		rpc_id(1, "net_vote_start", kind, arg)
	else:
		_host_start_vote(kind, arg, Net.local_id())


func cast_vote(is_yes: bool) -> void:
	if not vote_active:
		return
	if Net.is_networked() and not Net.is_host():
		rpc_id(1, "net_vote_cast", is_yes)
	else:
		_host_apply_vote(Net.local_id(), is_yes)


func cancel_vote() -> void:
	# Host-only power (SP owner too). Silently no-op for clients.
	if Net.is_networked() and not Net.is_host():
		return
	if not vote_active:
		return
	_resolve_vote(false, "Cancelled by host")


func _peer_display_name(peer_id: int) -> String:
	if _players_by_id.has(peer_id):
		var p: Node = _players_by_id[peer_id]
		if is_instance_valid(p):
			return str(p.display_name)
	if peer_id == 1:
		return "Host"
	return "Peer %d" % peer_id


func _vote_chat(msg: String) -> void:
	if hud != null and hud.has_method("post_chat"):
		hud.post_chat("VOTE", msg, false)


func _resolve_map_name(idx: int) -> String:
	# Prefer the actual runtime rotation (procedural + bundled classics), fall
	# back to the host-admin MAP_NAMES list which mirrors menu.gd.
	if idx >= 0 and idx < MAPS.size():
		return str(MAPS[idx].get("name", "Map %d" % idx))
	return "Map %d" % idx


func _resolve_vote_map_arg(arg: String) -> int:
	# Accepts an integer index OR a case-insensitive map name.
	var s := arg.strip_edges()
	if s == "":
		return -1
	if s.is_valid_int():
		var n := int(s)
		if n >= 0 and n < MAPS.size():
			return n
		return -1
	var needle := s.to_lower()
	for i in MAPS.size():
		if str(MAPS[i].get("name", "")).to_lower() == needle:
			return i
	return -1


func _resolve_vote_kick_arg(arg: String) -> int:
	# Accepts integer peer id or a case-insensitive display_name match (partial ok).
	var s := arg.strip_edges()
	if s == "":
		return 0
	if s.is_valid_int():
		var n := int(s)
		if _players_by_id.has(n):
			return n
		return 0
	var needle := s.to_lower()
	for pid in _players_by_id.keys():
		var p: Node = _players_by_id[pid]
		if not is_instance_valid(p):
			continue
		if str(p.display_name).to_lower() == needle:
			return int(pid)
	# Partial contains-match as a fallback (typing /votekick red matches "Red 3").
	for pid in _players_by_id.keys():
		var p: Node = _players_by_id[pid]
		if not is_instance_valid(p):
			continue
		if str(p.display_name).to_lower().find(needle) >= 0:
			return int(pid)
	return 0


func _host_start_vote(kind: String, arg: String, starter_id: int) -> void:
	if vote_active:
		_vote_chat("A vote is already in progress.")
		return
	if _vote_cooldown > 0.0:
		_vote_chat("Vote cooldown: %ds left." % int(ceil(_vote_cooldown)))
		return
	var starter := _peer_display_name(starter_id)
	match kind:
		"votemap":
			var idx := _resolve_vote_map_arg(arg)
			if idx < 0:
				_vote_chat("%s: unknown map '%s'." % [starter, arg])
				return
			vote_kind = "votemap"
			vote_target_arg = idx
			vote_target_str = _resolve_map_name(idx)
		"votekick":
			if not Net.is_networked():
				_vote_chat("votekick only works in multiplayer.")
				return
			var pid := _resolve_vote_kick_arg(arg)
			if pid <= 0:
				_vote_chat("%s: unknown player '%s'." % [starter, arg])
				return
			if pid == starter_id:
				_vote_chat("You can't votekick yourself.")
				return
			vote_kind = "votekick"
			vote_target_arg = pid
			vote_target_str = _peer_display_name(pid)
		_:
			return
	vote_active = true
	vote_yes = 1  # starter's implicit yes vote
	vote_no = 0
	_vote_voters = {starter_id: true}
	vote_time_left = VOTE_DURATION
	vote_starter = starter
	_vote_chat("%s called a %s: %s   ([F1]/[F2] to vote)" % [starter, vote_kind, vote_target_str])
	if Net.is_networked() and Net.is_host():
		_broadcast_vote_state()


func _host_apply_vote(peer_id: int, is_yes: bool) -> void:
	if not vote_active:
		return
	if _vote_voters.has(peer_id):
		return  # already voted, no changing minds
	_vote_voters[peer_id] = true
	if is_yes:
		vote_yes += 1
	else:
		vote_no += 1
	# Resolve early once the outcome is certain.
	var eligible := _eligible_voters()
	if vote_yes * 2 > eligible:
		_resolve_vote(true)
		return
	if vote_no * 2 >= eligible:
		_resolve_vote(false)
		return
	if Net.is_networked() and Net.is_host():
		_broadcast_vote_state()


func _eligible_voters() -> int:
	# Majority of the humans in the match (a lone starter's own yes no longer
	# passes a kick/map vote by default). The kick target doesn't vote.
	if not Net.is_networked():
		return 1
	var n := _ready_peers.size() + (0 if Net.is_dedicated else 1)
	if vote_kind == "votekick" and n > 1:
		n -= 1
	return maxi(1, n)


func _resolve_vote(passed: bool, reason: String = "") -> void:
	if not vote_active:
		return
	# Snapshot pre-clear so the summary + apply steps see the right values even
	# after the state reset below.
	var kind := vote_kind
	var target := vote_target_arg
	var target_label := vote_target_str
	var yes_ct := vote_yes
	var no_ct := vote_no
	var summary: String
	if reason != "":
		summary = reason
	else:
		summary = "PASSED (%d-%d)" % [yes_ct, no_ct] if passed else "FAILED (%d-%d)" % [yes_ct, no_ct]
	_vote_chat("%s %s — %s" % [kind, target_label, summary])
	# Broadcast end state so clients clear their prompt in sync.
	if Net.is_networked() and Net.is_host():
		rpc("net_vote_end", kind, target_label, passed, yes_ct, no_ct, reason)
	# Clear locally BEFORE triggering restart/kick — scene reload otherwise fires
	# with stale vote_active still true on the next frame.
	vote_active = false
	vote_kind = ""
	vote_target_str = ""
	vote_target_arg = 0
	vote_yes = 0
	vote_no = 0
	vote_time_left = 0.0
	_vote_voters.clear()
	_vote_cooldown = VOTE_COOLDOWN
	if not passed:
		return
	match kind:
		"votemap":
			if Net.is_networked() and Net.is_host():
				rpc("net_match_restart", target, Settings.game_mode)
			elif not Net.is_networked():
				Settings.map_index = target
				Settings.custom_map_path = ""
				Settings.save()
				call_deferred("_do_reload_main")
		"votekick":
			if Net.is_networked() and Net.is_host() and multiplayer.multiplayer_peer != null and target > 1:
				multiplayer.multiplayer_peer.disconnect_peer(target)


func _broadcast_vote_state() -> void:
	if not Net.is_host():
		return
	for pid in _ready_peers.keys():
		rpc_id(int(pid), "net_vote_state", vote_active, vote_kind, vote_target_str, vote_yes, vote_no, vote_time_left, vote_starter)


@rpc("any_peer", "reliable")
func net_vote_start(kind: String, arg: String) -> void:
	if not Net.is_host():
		return
	_host_start_vote(kind, arg, multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func net_vote_cast(is_yes: bool) -> void:
	if not Net.is_host():
		return
	_host_apply_vote(multiplayer.get_remote_sender_id(), is_yes)


@rpc("authority", "reliable")
func net_vote_state(active: bool, kind: String, target: String, yes_ct: int, no_ct: int, tl: float, starter: String) -> void:
	vote_active = active
	vote_kind = kind
	vote_target_str = target
	vote_yes = yes_ct
	vote_no = no_ct
	vote_time_left = tl
	vote_starter = starter


@rpc("authority", "reliable")
func net_vote_end(kind: String, target_label: String, passed: bool, yes_ct: int, no_ct: int, reason: String) -> void:
	var summary: String
	if reason != "":
		summary = reason
	else:
		summary = "PASSED (%d-%d)" % [yes_ct, no_ct] if passed else "FAILED (%d-%d)" % [yes_ct, no_ct]
	_vote_chat("%s %s — %s" % [kind, target_label, summary])
	vote_active = false
	vote_kind = ""
	vote_target_str = ""
	vote_yes = 0
	vote_no = 0
	vote_time_left = 0.0


# ── Bonus pickups (#78) ───────────────────────────────
# Host owns spawn slots + collection detection. Boxes are Area2D nodes; the
# BonusPickup script emits `touched` on host only. Application of the effect
# is routed via each player's net_bonus_apply RPC (call_local) so every peer
# applies the same effect to the target replica.

func _spawn_bonus_boxes_init() -> void:
	# Client: waits for host to broadcast net_bonus_spawn. No local slots needed.
	if Net.is_networked() and not Net.is_host():
		return
	# #113: map editor can supply an explicit "bonus_spawns" list; fall back to
	# bot spawns when not specified so procedural + legacy maps still spawn bonus
	# boxes at bot positions.
	var explicit: Array = _map.get("bonus_spawns", [])
	var spots: Array = explicit.duplicate() if not explicit.is_empty() \
		else (_map.get("bot_spawns", []) as Array).duplicate()
	if spots.is_empty():
		return
	spots.shuffle()
	var count: int = mini(BONUS_MAX_SLOTS, spots.size())
	for i in count:
		# Lift each slot a bit above the ground so the crate reads floating and
		# isn't clipped by the terrain body.
		_bonus_slots.append((spots[i] as Vector2) + Vector2(0, -22.0))
		_bonus_slot_cd.append(0.0)
		_bonus_slot_active.append(0)
	for i in count:
		_spawn_bonus_at_slot(i)


func _spawn_bonus_at_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _bonus_slots.size():
		return
	if int(_bonus_slot_active[slot_idx]) != 0:
		return  # slot already occupied
	var pos: Vector2 = _bonus_slots[slot_idx]
	var kind: String = BonusPickup.KINDS[randi() % BonusPickup.KINDS.size()]
	var bid: int = _next_bonus_id
	_next_bonus_id += 1
	_bonus_slot_active[slot_idx] = bid
	_make_bonus_box_local(bid, pos, kind, slot_idx)
	# Mirror to every client whose main.tscn is loaded (see #84 for why we key
	# off _connected_peers rather than the acked-only _ready_peers).
	if Net.is_networked() and Net.is_host():
		for pid in _connected_peers.keys():
			rpc_id(int(pid), "net_bonus_spawn", bid, pos, kind)


func _make_bonus_box_local(bid: int, pos: Vector2, kind: String, slot_idx: int) -> void:
	# Idempotent: if a box with this id already exists (e.g., late client spawn
	# arrived after we joined), free it before mounting the replacement.
	if _bonus_boxes.has(bid):
		var old: Node = _bonus_boxes[bid]
		if is_instance_valid(old):
			old.queue_free()
	var box: Area2D = BonusPickup.new()
	box.bonus_id = bid
	box.bonus_kind = kind
	box.position = pos
	box.name = "Bonus_%d" % bid
	# Host: bind the collision-triggered signal to our collect handler. Client
	# replicas don't need this — the box is inert until the host says so.
	if not Net.is_networked() or Net.is_host():
		box.touched.connect(_on_bonus_touched.bind(bid, slot_idx))
	_bonus_boxes[bid] = box
	add_child(box)


func _on_bonus_touched(body: Node, bid: int, slot_idx: int) -> void:
	# Host-only collection. In SP the local player is the sole eligible toucher;
	# in MP we resolve peer_id via _players_by_id. Bots are ignored — the bonus
	# system is a player perk.
	if Net.is_networked() and not Net.is_host():
		return
	var box: Node = _bonus_boxes.get(bid, null)
	if not is_instance_valid(box):
		return
	var kind: String = str(box.get("bonus_kind"))
	var peer_id: int = 0
	if not Net.is_networked():
		if body != player:
			return  # bots + non-player bodies don't collect
		peer_id = 1
	else:
		for pid in _players_by_id.keys():
			if _players_by_id[pid] == body:
				peer_id = int(pid)
				break
		if peer_id == 0:
			return  # not a player peer (bot) — ignore
	# Apply the effect via the target player's call_local RPC so every peer's
	# replica of that soldier ticks the same effect state.
	if _players_by_id.has(peer_id):
		var p: Node = _players_by_id[peer_id]
		if is_instance_valid(p) and p.has_method("apply_bonus"):
			p.apply_bonus(kind, BONUS_EFFECT_DURATION)
	elif not Net.is_networked() and is_instance_valid(player):
		player.apply_bonus(kind, BONUS_EFFECT_DURATION)
	# Despawn on every peer.
	if Net.is_networked() and Net.is_host():
		rpc("net_bonus_despawn", bid)
	_despawn_bonus_local(bid)
	# Free the slot and start the respawn countdown so a new random-kind box
	# will land there in BONUS_RESPAWN seconds.
	if slot_idx >= 0 and slot_idx < _bonus_slot_cd.size():
		_bonus_slot_active[slot_idx] = 0
		_bonus_slot_cd[slot_idx] = BONUS_RESPAWN
	# Sfx cue for the local player — reuse the existing UI blip so we don't
	# need a new sample.
	Sfx.ui()


func _despawn_bonus_local(bid: int) -> void:
	var box: Node = _bonus_boxes.get(bid, null)
	if is_instance_valid(box):
		box.queue_free()
	_bonus_boxes.erase(bid)


func _tick_bonus_boxes(delta: float) -> void:
	if _bonus_slots.is_empty():
		return
	for i in _bonus_slot_cd.size():
		if int(_bonus_slot_active[i]) != 0:
			continue
		var cd: float = float(_bonus_slot_cd[i]) - delta
		_bonus_slot_cd[i] = cd
		if cd <= 0.0:
			_spawn_bonus_at_slot(i)


@rpc("authority", "reliable")
func net_bonus_spawn(bid: int, pos: Vector2, kind: String) -> void:
	# Host already has this locally; this RPC targets clients only.
	if Net.is_host():
		return
	_make_bonus_box_local(bid, pos, kind, -1)


@rpc("authority", "reliable")
func net_bonus_despawn(bid: int) -> void:
	if Net.is_host():
		return
	_despawn_bonus_local(bid)


func _broadcast_flag_state() -> void:
	# Each flag: {pos, carrier peer_id (0 = none)}. Only sent to acked peers.
	var arr: Array = []
	for f in flags:
		if not is_instance_valid(f):
			arr.append({"pos": Vector2.ZERO, "carrier": 0})
			continue
		var cid := 0
		var carrier: Variant = f.get_meta("carrier") if f.has_meta("carrier") else null
		if is_instance_valid(carrier):
			var nm := String(carrier.name)
			if nm.begins_with("Player_"):
				cid = int(nm.substr(7))
			elif int(carrier.get("bot_id")) > 0:
				# Bots ride as negative ids so clients can attach the flag to the
				# bot replica (smooth carried visual) instead of an 8 Hz dot.
				cid = -int(carrier.get("bot_id"))
		arr.append({"pos": f.position, "carrier": cid})
	for pid in _ready_peers.keys():
		rpc_id(int(pid), "net_flag_state", arr)


func next_pickup_id() -> int:
	var id: int = _next_pickup_id
	_next_pickup_id += 1
	return id


func _broadcast_pickup_state() -> void:
	# Collect every host-authoritative pickup body + its live physics state.
	var arr: Array = []
	for wp in get_tree().get_nodes_in_group("weapon_pickup"):
		if not is_instance_valid(wp):
			continue
		if int(wp.get("pickup_id")) <= 0:
			continue
		arr.append({
			"id": int(wp.get("pickup_id")),
			"name": str(wp.get("weapon_name")),
			"team": int(wp.get("team")),
			"thrower": str(wp.get("thrower_name")),
			"pos": wp.global_position,
			"vel": wp.linear_velocity,
			"ang": float(wp.angular_velocity),
			"rot": float(wp.rotation),
			# #94: carry damage explicitly so future damage-on-hit weapons
			# (axe/bayonet/etc.) don't silently lose their damage on clients
			# because we re-derived by name.
			"dmg": float(wp.get("damage_on_hit")),
		})
	for pid in _ready_peers.keys():
		rpc_id(int(pid), "net_pickup_state", arr)


@rpc("authority", "reliable")
func net_pickup_state(arr: Array) -> void:
	# Map existing frozen pickups by id, spawn any we haven't seen, and reconcile
	# positions. Host-only pickups that vanish trigger client-side despawn.
	var seen: Dictionary = {}
	var by_id: Dictionary = {}
	for wp in get_tree().get_nodes_in_group("weapon_pickup"):
		if not is_instance_valid(wp):
			continue
		var pid: int = int(wp.get("pickup_id"))
		if pid > 0:
			by_id[pid] = wp
	for entry in arr:
		var id: int = int(entry.get("id", 0))
		if id <= 0:
			continue
		seen[id] = true
		var wp: Node = by_id.get(id) as Node
		if wp == null:
			# First time we're hearing about this pickup — spawn a client-frozen copy.
			# #69: give it a stable name matching the id so future per-instance RPCs
			# (should we ever add pickup-level state sync) resolve on both peers.
			var new_wp := WeaponPickup.new()
			new_wp.pickup_id = id
			new_wp.name = "Pickup_%d" % id
			new_wp.weapon_name = str(entry.get("name", "AK-74"))
			new_wp.team = int(entry.get("team", 0))
			new_wp.thrower_name = str(entry.get("thrower", ""))
			# #94: pull damage from the host's payload instead of reconstructing
			# by weapon name. Fallback to the legacy Knife=55 rule when the host
			# is running a pre-#94 build with no "dmg" field.
			if entry.has("dmg"):
				new_wp.damage_on_hit = float(entry.get("dmg", 0.0))
			else:
				new_wp.damage_on_hit = 55.0 if str(entry.get("name", "")) == "Knife" else 0.0
			new_wp.global_position = entry.get("pos", Vector2.ZERO)
			add_child(new_wp)
			wp = new_wp
		wp.global_position = entry.get("pos", wp.global_position)
		wp.linear_velocity = entry.get("vel", Vector2.ZERO)
		wp.angular_velocity = float(entry.get("ang", 0.0))
		wp.rotation = float(entry.get("rot", 0.0))
	# Despawn any client-side pickup whose id no longer appears in the host's list.
	for pid in by_id.keys():
		if not seen.has(pid):
			var wp: Node = by_id[pid]
			if is_instance_valid(wp):
				wp.queue_free()


@rpc("authority", "reliable")
func net_flag_state(arr: Array) -> void:
	for i in arr.size():
		if i >= flags.size():
			break
		var f = flags[i]
		if not is_instance_valid(f):
			continue
		var entry: Dictionary = arr[i]
		f.position = entry.get("pos", f.position)
		var cid := int(entry.get("carrier", 0))
		if cid > 0 and _players_by_id.has(cid):
			var p = _players_by_id[cid]
			if is_instance_valid(p):
				f.set_meta("carrier", p)
			else:
				f.set_meta("carrier", null)
		elif cid < 0 and _bots_by_id.has(-cid) and is_instance_valid(_bots_by_id[-cid]):
			f.set_meta("carrier", _bots_by_id[-cid])
		else:
			f.set_meta("carrier", null)


# ── Bot replication (issue #55) ───────────────────────
# Host-only AI, host broadcasts per-bot state at BOT_SYNC_HZ so clients can render
# a matching replica. Spawn/despawn are reliable RPCs; state is unreliable_ordered
# to mirror the player net_state cadence.

func _broadcast_bot_state() -> void:
	if _ready_peers.is_empty():
		return
	# #102: positional Array-of-Arrays instead of Dictionary-of-strings. Dropping
	# the 14 key strings per entry shrinks each bot from ~365 B → ~140 B, keeping
	# the unreliable_ordered packet under the ENet MTU (1392) for the common 4-8
	# bot case. Field order MUST match net_bot_state below.
	# Layout: [id, pos, vel, facing, jet, health, dead, loadout, ammo,
	#         reloading, muzzle_t, ceasefire, using_secondary, secondary_ammo]
	var arr: Array = []
	for bid in _bots_by_id.keys():
		var b: Node = _bots_by_id[bid]
		if not is_instance_valid(b):
			continue
		arr.append([
			int(bid),
			b.position,
			b.velocity,
			float(b.facing),
			bool(b.jet_on),
			float(b.health),
			bool(b.dead),
			str(b.loadout),
			int(b.ammo),
			bool(b.reloading),
			float(b.muzzle_t),
			float(b.ceasefire_t),
			bool(b.using_secondary),
			int(b.secondary_ammo),
		])
	if arr.is_empty():
		return
	# Split across ticks if bot_count -1 (use every map spawn) yields more than
	# BOT_STATE_CHUNK_MAX bots — safeguards against a giant map pushing us back
	# over the MTU. 8/chunk × ~140 B ≈ 1120 B < 1392 B.
	for pid in _ready_peers.keys():
		var i: int = 0
		while i < arr.size():
			var end: int = min(i + BOT_STATE_CHUNK_MAX, arr.size())
			rpc_id(int(pid), "net_bot_state", arr.slice(i, end))
			i = end


@rpc("authority", "reliable")
func net_spawn_bot(bot_id: int, spawn_pos: Vector2, team: int, display_name: String, loadout: String, cosmetics: Dictionary) -> void:
	# Free any stale replica with the same id (bot respawn re-uses ids? no — we mint
	# a fresh id per spawn — but a peer that missed the despawn should still recover).
	if _bots_by_id.has(bot_id):
		var old = _bots_by_id[bot_id]
		if is_instance_valid(old):
			old.queue_free()
		_bots_by_id.erase(bot_id)
	var b := bot_scene.instantiate()
	b.name = "Bot_%d" % bot_id
	b.position = spawn_pos
	b.team = team
	b.display_name = display_name
	b.loadout = loadout
	b.bot_id = bot_id
	# Copy cosmetics so the client bot reads the same outfit as the host's — bot.gd's
	# _ready only randomises when cosmetics is empty (see bot.gd:89).
	if cosmetics != null and not cosmetics.is_empty():
		b.cosmetics = cosmetics.duplicate(true)
	b.color = bot_color_for_team(team)
	# Host (peer 1) owns the bot's AI + damage authority. Non-authority replicas
	# skip _physics_process and are driven by net_bot_state (see bot.gd guards).
	b.set_multiplayer_authority(1)
	# Gun Game: mirror the client's cached rung so the newly-spawned replica
	# reads the right weapon in-hand even before the first net_bot_state tick.
	if Settings.game_mode == Settings.MODE_GG:
		b.gg_level = _gg_get(display_name)
	add_child(b)
	b.set_multiplayer_authority(1, true)
	_bots_by_id[bot_id] = b


@rpc("authority", "reliable")
func net_bot_despawn(bot_id: int) -> void:
	if not _bots_by_id.has(bot_id):
		return
	var b = _bots_by_id[bot_id]
	_bots_by_id.erase(bot_id)
	if is_instance_valid(b):
		b.queue_free()


@rpc("authority", "reliable")
func net_bot_die(bot_id: int) -> void:
	if not _bots_by_id.has(bot_id):
		return
	var b = _bots_by_id[bot_id]
	_bots_by_id.erase(bot_id)
	if is_instance_valid(b) and b.has_method("die_replica"):
		b.die_replica()
	elif is_instance_valid(b):
		b.queue_free()


@rpc("authority", "call_remote", "unreliable_ordered")
func net_bot_state(arr: Array) -> void:
	# #102: entries are now positional Arrays (see _broadcast_bot_state).
	# Defend against malformed payloads — a corrupt / crafted packet used to
	# crash the client on the raw assignments (#86.1). Skip entries that aren't
	# 14-element arrays; guard each field so an incorrect type keeps the previous
	# value instead of forcing an invalid assignment.
	for entry in arr:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 14:
			continue
		var id: int = int(entry[0])
		if not _bots_by_id.has(id):
			continue
		var b: Node = _bots_by_id[id]
		if not is_instance_valid(b):
			continue
		var pos_v: Variant = entry[1]
		if typeof(pos_v) == TYPE_VECTOR2:
			b.position = pos_v
		var vel_v: Variant = entry[2]
		if typeof(vel_v) == TYPE_VECTOR2:
			b.velocity = vel_v
		var facing_v: Variant = entry[3]
		if typeof(facing_v) == TYPE_FLOAT or typeof(facing_v) == TYPE_INT:
			b.facing = float(facing_v)
		b.jet_on = bool(entry[4])
		var health_v: Variant = entry[5]
		if typeof(health_v) == TYPE_FLOAT or typeof(health_v) == TYPE_INT:
			b.health = float(health_v)
		b.dead = bool(entry[6])
		var loadout_v: Variant = entry[7]
		if typeof(loadout_v) == TYPE_STRING or typeof(loadout_v) == TYPE_STRING_NAME:
			b.loadout = String(loadout_v)
		var ammo_v: Variant = entry[8]
		if typeof(ammo_v) == TYPE_INT or typeof(ammo_v) == TYPE_FLOAT:
			b.ammo = int(ammo_v)
		b.reloading = bool(entry[9])
		var mz_v: Variant = entry[10]
		if typeof(mz_v) == TYPE_FLOAT or typeof(mz_v) == TYPE_INT:
			b.muzzle_t = float(mz_v)
		var cf_v: Variant = entry[11]
		if typeof(cf_v) == TYPE_FLOAT or typeof(cf_v) == TYPE_INT:
			b.ceasefire_t = float(cf_v)
		# #79: apply secondary state so the client-side replica draws the same
		# in-hand weapon as the host (physics-side ammo tracking is irrelevant
		# on the replica because _physics_process is authority-gated).
		b.using_secondary = bool(entry[12])
		var sa_v: Variant = entry[13]
		if typeof(sa_v) == TYPE_INT or typeof(sa_v) == TYPE_FLOAT:
			b.secondary_ammo = int(sa_v)
