extends Node2D
## Main — sky, terrain, players, bots, HUD. Handles singleplayer + networked flows.

var player_scene := preload("res://scenes/player.tscn")
var bot_scene := preload("res://scenes/bot.tscn")
var sky_script := preload("res://scripts/sky.gd")
var parallax_script := preload("res://scripts/parallax.gd")
var hud_script := preload("res://scripts/hud.gd")
const PoaLoader = preload("res://scripts/poa_loader.gd")
const WeaponPickup = preload("res://scripts/weapon_pickup.gd")

signal kill(killer_name: String, victim_name: String, weapon_name: String, killer_team: int, victim_team: int)

var player: Node2D = null            # LOCAL player (whichever peer owns us)
var hud: CanvasLayer = null
var _map: Dictionary = {}
var _players_by_id: Dictionary = {}  # peer_id -> player node (host only, but also mirrored on clients)
var _ready_peers: Dictionary = {}    # peer_id -> true (host only, gate for outbound state RPCs)

# Team modes: fixed team ids (player joins BLUE, enemy bots on RED).
const TEAM_BLUE := 1
const TEAM_RED := 2

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
# Pointmatch — bookkeeping for respawning pickups (spawn_pos -> _next_respawn_t).
var _pm_pickups: Dictionary = {}

# ── Match state (host-authoritative in MP) ─────────────
const SCORE_TO_WIN := 20
const ROUND_TIME := 300.0
const WINNER_DISPLAY := 4.0
const MATCH_SYNC_HZ := 5.0           # host → clients broadcast rate for scoreboard

var scores: Dictionary = {}          # team_id -> int
var time_left := ROUND_TIME
var round_active := true
var winner_team := -1
var winner_end_t := 0.0
var _match_sync_cd := 0.0

const MAP_W := 4800.0
const MAP_H := 2000.0
const GROUND_Y := 1900.0

const MAPS := [
	{
		"name": "Ascent",
		"platforms": [
			{"p": Vector2(400, 1720), "s": Vector2(260, 22)},
			{"p": Vector2(750, 1550), "s": Vector2(240, 22)},
			{"p": Vector2(1100, 1380), "s": Vector2(240, 22)},
			{"p": Vector2(1450, 1210), "s": Vector2(240, 22)},
			{"p": Vector2(1800, 1050), "s": Vector2(240, 22)},
			{"p": Vector2(2150, 900), "s": Vector2(220, 22)},
			{"p": Vector2(2500, 750), "s": Vector2(220, 22)},
			{"p": Vector2(2850, 600), "s": Vector2(220, 22)},
			{"p": Vector2(3200, 460), "s": Vector2(220, 22)},
			{"p": Vector2(3700, 380), "s": Vector2(400, 22)},
			{"p": Vector2(4200, 900), "s": Vector2(140, 22)},
			{"p": Vector2(2000, 1700), "s": Vector2(300, 22)},
		],
		"player_spawn": Vector2(200, 1775),
		"bot_spawns": [Vector2(2500, 720), Vector2(3200, 430), Vector2(3700, 350), Vector2(4200, 870)],
	},
	{
		"name": "Towers",
		"platforms": [
			{"p": Vector2(600, 1720), "s": Vector2(220, 22)},
			{"p": Vector2(600, 1490), "s": Vector2(220, 22)},
			{"p": Vector2(600, 1260), "s": Vector2(220, 22)},
			{"p": Vector2(600, 1030), "s": Vector2(220, 22)},
			{"p": Vector2(600, 800), "s": Vector2(220, 22)},
			{"p": Vector2(4200, 1720), "s": Vector2(220, 22)},
			{"p": Vector2(4200, 1490), "s": Vector2(220, 22)},
			{"p": Vector2(4200, 1260), "s": Vector2(220, 22)},
			{"p": Vector2(4200, 1030), "s": Vector2(220, 22)},
			{"p": Vector2(4200, 800), "s": Vector2(220, 22)},
			{"p": Vector2(1400, 1350), "s": Vector2(240, 22)},
			{"p": Vector2(3400, 1350), "s": Vector2(240, 22)},
			{"p": Vector2(2400, 1150), "s": Vector2(700, 22)},
			{"p": Vector2(2400, 920), "s": Vector2(240, 22)},
		],
		"player_spawn": Vector2(200, 1775),
		"bot_spawns": [Vector2(3400, 1320), Vector2(4200, 770), Vector2(2400, 890), Vector2(4200, 1460)],
		"m2_mounts": [Vector2(2400, 1130), Vector2(600, 780), Vector2(4200, 780)],
	},
	{
		"name": "Pillars",
		"platforms": [
			{"p": Vector2(400, 1650), "s": Vector2(80, 22)},
			{"p": Vector2(800, 1500), "s": Vector2(80, 22)},
			{"p": Vector2(1200, 1600), "s": Vector2(80, 22)},
			{"p": Vector2(1600, 1400), "s": Vector2(100, 22)},
			{"p": Vector2(2000, 1600), "s": Vector2(80, 22)},
			{"p": Vector2(2400, 1400), "s": Vector2(350, 22)},
			{"p": Vector2(2800, 1600), "s": Vector2(80, 22)},
			{"p": Vector2(3200, 1450), "s": Vector2(100, 22)},
			{"p": Vector2(3600, 1600), "s": Vector2(80, 22)},
			{"p": Vector2(4000, 1500), "s": Vector2(80, 22)},
			{"p": Vector2(4400, 1650), "s": Vector2(80, 22)},
			{"p": Vector2(1600, 1200), "s": Vector2(100, 22)},
			{"p": Vector2(3200, 1250), "s": Vector2(100, 22)},
			{"p": Vector2(2400, 1150), "s": Vector2(300, 22)},
		],
		"player_spawn": Vector2(200, 1775),
		"bot_spawns": [Vector2(2400, 1370), Vector2(3600, 1570), Vector2(4000, 1470), Vector2(3200, 1220)],
		"m2_mounts": [Vector2(2400, 1120)],
	},
]


func _ready() -> void:
	# Dev override: `--mode=N` on the command line sets game_mode for headless smoke tests.
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--mode="):
			Settings.game_mode = int(arg.substr(7))
	# Crosshair cursor = the mouse; aiming follows it (Soldat-style).
	Input.set_custom_mouse_cursor(load("res://assets/interface-gfx/cursor.png"), Input.CURSOR_ARROW, Vector2(12, 12))
	PoaLoader.preload_all()
	if Net.is_networked():
		# Host picks the map (via Net.chosen_map_index). Clients receive it before
		# reaching this scene, so both peers build the same terrain.
		_map = MAPS[Net.chosen_map_index % MAPS.size()]
	else:
		_map = MAPS[Settings.map_index % MAPS.size()]
		Settings.map_index = (Settings.map_index + 1) % MAPS.size()
	_build_sky()
	_build_parallax()
	_build_terrain()
	_build_hud()
	kill.connect(_on_kill_scored)

	if Net.is_networked():
		multiplayer.peer_disconnected.connect(_on_net_peer_disconnected)
		if Net.is_host():
			_spawn_networked_player(1)  # host is peer 1
		else:
			# Client asks the host to spawn us; host also mirrors any existing players.
			rpc_id(1, "net_client_ready")
	else:
		_spawn_player()
		_spawn_bots()
		# Flag / pickup entities are per-mode.
		if Settings.game_mode == Settings.MODE_CTF:
			_spawn_flags()
		elif Settings.game_mode == Settings.MODE_INF:
			_spawn_flag_inf()
		elif Settings.game_mode == Settings.MODE_HTF:
			_spawn_flag_htf()
		elif Settings.game_mode == Settings.MODE_RM:
			_spawn_rambo_bow()
		elif Settings.game_mode == Settings.MODE_PM:
			_spawn_point_pickups()


func _build_sky() -> void:
	var sky := Node2D.new()
	sky.name = "Sky"
	sky.set_script(sky_script)
	var layer := CanvasLayer.new()
	layer.layer = -20
	layer.add_child(sky)
	add_child(layer)


func _build_parallax() -> void:
	var par := Node2D.new()
	par.name = "Parallax"
	par.set_script(parallax_script)
	var layer := CanvasLayer.new()
	layer.layer = -15
	layer.add_child(par)
	add_child(layer)


func _make_platform(pos: Vector2, size: Vector2, col: Color) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([
		Vector2(-size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, size.y / 2.0),
		Vector2(-size.x / 2.0, size.y / 2.0),
	])
	vis.color = col
	body.add_child(vis)
	add_child(body)
	return body


func _build_terrain() -> void:
	_make_platform(Vector2(MAP_W / 2.0, GROUND_Y), Vector2(MAP_W + 200, 200), Color(0.22, 0.26, 0.32))
	for pl in _map["platforms"]:
		_make_platform(pl["p"], pl["s"], Color(0.28, 0.32, 0.4))
	_make_platform(Vector2(0, MAP_H / 2.0), Vector2(40, MAP_H * 2.0), Color(0.2, 0.23, 0.28))
	_make_platform(Vector2(MAP_W, MAP_H / 2.0), Vector2(40, MAP_H * 2.0), Color(0.2, 0.23, 0.28))
	_spawn_m2_mounts()


func _spawn_m2_mounts() -> void:
	var mounts: Array = _map.get("m2_mounts", [])
	if mounts.is_empty():
		return
	var M2 = preload("res://scripts/m2.gd")
	for pos in mounts:
		var m2 := Node2D.new()
		m2.set_script(M2)
		m2.position = pos
		add_child(m2)


# ── Singleplayer spawn path ───────────────────────────

func _spawn_player() -> void:
	var p := player_scene.instantiate()
	p.position = _map["player_spawn"]
	# In team modes player joins BLUE (team 1); in DM/RM she's team 0 (FFA).
	if Settings.is_team_mode():
		p.team = TEAM_BLUE
		p.color = Color(0.35, 0.55, 1.0)
		p.display_name = "Blue"
	else:
		p.team = 0
	# Advance mode: start with the humble knife.
	if Settings.advance:
		p.set("using_secondary", true)
		p.set("secondary_index", 1)  # Knife
	p.died.connect(_on_player_died)
	add_child(p)
	player = p
	_bind_local_camera(p)
	if hud:
		hud.player = p


func _on_player_died() -> void:
	if hud:
		hud.show_death(str(player.last_killer), str(player.last_weapon))
	# Survival: no respawn until round ends. _reset_round will (re)spawn everyone.
	if Settings.survival and round_active:
		return
	var delay: float = _respawn_delay_for_team(int(player.team))
	get_tree().create_timer(delay).timeout.connect(_spawn_player)


func _respawn_delay_for_team(t: int) -> float:
	# INF attackers pay a longer respawn (defender advantage).
	if Settings.game_mode == Settings.MODE_INF and t == TEAM_RED:
		return 5.0
	return 2.0


func _spawn_bots() -> void:
	var spots: Array = _map["bot_spawns"]
	var mode: int = Settings.game_mode
	for i in spots.size():
		var loadout := "LAW" if i == spots.size() - 1 else "AK-74"
		if Settings.is_team_mode():
			if mode == Settings.MODE_INF:
				# INF: bots are attackers (RED). Player defends solo on BLUE.
				_spawn_bot(spots[i], TEAM_RED, "Red Bot %d" % (i + 1), loadout)
			else:
				# TDM/CTF/HTF/PM: split bots BLUE/RED evenly.
				var on_blue: bool = i < spots.size() / 2
				var t: int = TEAM_BLUE if on_blue else TEAM_RED
				var nm := "Blue Bot %d" % (i + 1) if on_blue else "Red Bot %d" % (i + 1)
				_spawn_bot(spots[i], t, nm, loadout)
		else:
			# DM/RM: bot team 99 is a dedicated non-peer id → hostile to any human peer.
			_spawn_bot(spots[i], 99, "Bot %d" % (i + 1), loadout)


func _spawn_bot(pos: Vector2, team: int, bname: String, loadout: String = "AK-74") -> void:
	if not is_inside_tree():
		return
	var b := bot_scene.instantiate()
	b.position = pos
	b.team = team
	b.display_name = bname
	b.loadout = loadout
	# Colorize per team so friend/foe reads at a glance in TDM/CTF.
	if team == TEAM_BLUE:
		b.color = Color(0.35, 0.55, 1.0)
	elif team == TEAM_RED:
		b.color = Color(0.85, 0.3, 0.25)
	# Bots respawn on the same slot so the match can accumulate score.
	# Survival gates this — the next spawn only happens on _reset_round.
	b.died.connect(func() -> void:
		if Settings.survival and round_active:
			return
		var delay: float = _respawn_delay_for_team(team)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			# Guard against the outer Main being torn down (scene change / quit)
			# during the respawn window — the SceneTreeTimer keeps firing.
			if not is_inside_tree():
				return
			_spawn_bot(pos, team, bname, loadout)))
	add_child(b)


# ── Shared ────────────────────────────────────────────

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.set_script(hud_script)
	add_child(hud)
	hud.player = player
	hud.map_name = str(_map["name"])
	kill.connect(hud._on_kill)


func _spawn_flags() -> void:
	# CTF bases: BLUE on the far left, RED on the far right of the map's ground row.
	var ground_y: float = float(_map.get("ctf_ground_y", 1830.0))
	var blue_base := Vector2(300, ground_y)
	var red_base := Vector2(MAP_W - 300, ground_y)
	flags = [
		_make_flag(TEAM_BLUE, blue_base),
		_make_flag(TEAM_RED, red_base),
	]


func _spawn_flag_inf() -> void:
	# INF: single neutral flag near the center. Attackers (RED) deliver to the
	# defenders' base (BLUE) to score. Defenders return the flag by touching it.
	var ground_y: float = float(_map.get("ctf_ground_y", 1830.0))
	var center := Vector2(MAP_W * 0.5, ground_y)
	var defender_base := Vector2(300, ground_y)
	var f := _make_flag(0, center)
	f.set_meta("capture_point", defender_base)
	flags = [f]


func _spawn_flag_htf() -> void:
	# HTF: single neutral flag mid-map. The carrying team ticks score per second.
	var ground_y: float = float(_map.get("ctf_ground_y", 1830.0))
	var center := Vector2(MAP_W * 0.5, ground_y)
	flags = [_make_flag(0, center)]


func _spawn_rambo_bow() -> void:
	# RM: single Rambo Bow pickup at map center — carrier gets HP regen +
	# is the only one who scores kills.
	var ground_y: float = float(_map.get("ctf_ground_y", 1830.0))
	var wp := WeaponPickup.new()
	wp.weapon_name = "Rambo Bow"
	wp.team = -1
	wp.thrower_name = ""
	wp.damage_on_hit = 0.0
	wp.global_position = Vector2(MAP_W * 0.5, ground_y - 40.0)
	wp.set_meta("rambo_spawn", true)
	add_child(wp)


func _spawn_point_pickups() -> void:
	# PM: scatter respawning point pickups. Each grants +1 to the toucher's team.
	var ground_y: float = float(_map.get("ctf_ground_y", 1830.0))
	var xs: PackedFloat32Array = [ 700.0, 1400.0, 2100.0, 2400.0, 2700.0, 3400.0, 4100.0 ]
	for x in xs:
		_spawn_point_pickup(Vector2(x, ground_y - 60.0))


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
	# Load the flag sprite (same for both teams — tinted per team).
	var flag_tex: Texture2D = load("res://assets/interface-gfx/flag.png") as Texture2D
	if flag_tex != null:
		var s := Sprite2D.new()
		s.texture = flag_tex
		s.scale = Vector2(0.5, 0.5)
		s.offset = Vector2(0, -18)
		s.modulate = Color(0.35, 0.55, 1.0) if team == TEAM_BLUE else Color(0.95, 0.35, 0.3)
		a.add_child(s)
	else:
		# Fallback vector: pole + banner rectangle so flags still read without the PNG.
		var pole := Polygon2D.new()
		pole.polygon = PackedVector2Array([Vector2(-1, -32), Vector2(1, -32), Vector2(1, 0), Vector2(-1, 0)])
		pole.color = Color(0.4, 0.35, 0.3)
		a.add_child(pole)
		var banner := Polygon2D.new()
		banner.polygon = PackedVector2Array([Vector2(1, -32), Vector2(18, -26), Vector2(1, -20)])
		banner.color = Color(0.35, 0.55, 1.0) if team == TEAM_BLUE else Color(0.95, 0.35, 0.3)
		a.add_child(banner)
	add_child(a)
	return a


func _bind_local_camera(p: Node) -> void:
	if p == null or p.get("cam") == null:
		return
	p.cam.limit_left = 0
	p.cam.limit_right = int(MAP_W)
	# Clamp to the actual map rect so the camera can't drift into void above or past the ground body.
	p.cam.limit_top = 0
	p.cam.limit_bottom = int(MAP_H)


# ── Networked spawn path ──────────────────────────────

func _spawn_networked_player(peer_id: int) -> void:
	var base: Vector2 = _map["player_spawn"]
	var spawn_pos := base + Vector2(randf_range(-140.0, 140.0), 0.0)
	var display_name := "Host" if peer_id == 1 else "Player %d" % peer_id
	rpc("net_spawn_player", peer_id, spawn_pos, display_name)


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
		rpc("net_despawn_player", id)


func ready_peer_ids() -> Array:
	return _ready_peers.keys()


@rpc("any_peer", "reliable")
func net_client_ready() -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	# tell the new peer about all currently living players
	for existing_id in _players_by_id.keys():
		var p: Node = _players_by_id[existing_id]
		if not is_instance_valid(p):
			continue
		rpc_id(sender, "net_spawn_player", existing_id, p.position, p.display_name)
	# then spawn a body for the new peer on everyone
	_spawn_networked_player(sender)
	# NOTE: _ready_peers[sender] is set only when the client acks the spawn (net_spawn_ack).
	# Otherwise net_state (unreliable_ordered) can beat the reliable spawn RPC and error out.


@rpc("any_peer", "reliable")
func net_spawn_ack() -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	_ready_peers[sender] = true


@rpc("authority", "call_local", "reliable")
func net_spawn_player(peer_id: int, spawn_pos: Vector2, display_name: String) -> void:
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
	p.team = peer_id  # FFA: each peer owns their own team so bullets damage everyone else
	p.set_multiplayer_authority(peer_id)
	add_child(p)
	# Re-apply after add_child so children created in _ready (cam, jet_particles) inherit authority.
	p.set_multiplayer_authority(peer_id, true)
	_players_by_id[peer_id] = p
	if peer_id == Net.local_id():
		player = p
		_bind_local_camera(p)
		if hud:
			hud.player = p
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


@rpc("authority", "call_local", "reliable")
func net_kill_feed(killer_name: String, victim_name: String, weapon_name: String, killer_team: int, victim_team: int) -> void:
	kill.emit(killer_name, victim_name, weapon_name, killer_team, victim_team)


@rpc("any_peer", "call_local", "reliable")
func net_chat(author: String, msg: String, scope: String, sender_team: int) -> void:
	# Team chat is filtered locally so opponents don't see it. Global chat is
	# visible to everyone. Route through the HUD's chat feed.
	if scope == "team" and is_instance_valid(player) and int(player.team) != sender_team:
		return
	if hud != null and hud.has_method("post_chat"):
		hud.post_chat(author, msg, scope == "team")


# ── Match / score / round ─────────────────────────────

func _process(delta: float) -> void:
	# Client: state is driven entirely by host's net_match_state RPCs.
	if Net.is_networked() and not Net.is_host():
		return
	if Settings.game_mode == Settings.MODE_CTF and flags.size() == 2:
		_tick_ctf()
	elif Settings.game_mode == Settings.MODE_INF and flags.size() == 1:
		_tick_inf()
	elif Settings.game_mode == Settings.MODE_HTF and flags.size() == 1:
		_tick_htf(delta)
	elif Settings.game_mode == Settings.MODE_RM:
		_tick_rambo()
	elif Settings.game_mode == Settings.MODE_PM:
		_tick_pointmatch(delta)
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


func _tick_ctf() -> void:
	# Two-flag CTF: touch enemy flag to carry, deliver to own home to score.
	# Carried flags snap to the carrier; dropped flags stay in place until touched.
	var soldiers := get_tree().get_nodes_in_group("soldier")
	for f in flags:
		if not is_instance_valid(f):
			continue
		var flag_team: int = int(f.get_meta("team"))
		var home: Vector2 = f.get_meta("home")
		var carrier = f.get_meta("carrier")
		if is_instance_valid(carrier):
			if bool(carrier.get("dead")):
				# Carrier died — drop flag at their last position.
				f.position = carrier.global_position
				f.set_meta("carrier", null)
				continue
			f.position = carrier.global_position + Vector2(0, -30)
			# Did the carrier reach their own base (their home flag)? Score + reset both.
			for other in flags:
				if other == f:
					continue
				var other_team: int = int(other.get_meta("team"))
				var other_home: Vector2 = other.get_meta("home")
				if int(carrier.get("team")) == other_team and other.get_meta("carrier") == null:
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
				else:
					# Enemy pickup.
					f.set_meta("carrier", s)
				break


func _tick_inf() -> void:
	# Single-flag INF: RED = attackers, BLUE = defenders. RED delivers to
	# the defenders' base to score; BLUE returns the flag by touching it.
	var f: Area2D = flags[0] as Area2D
	if not is_instance_valid(f):
		return
	var home: Vector2 = f.get_meta("home")
	var capture: Vector2 = f.get_meta("capture_point")
	var carrier = f.get_meta("carrier")
	if is_instance_valid(carrier):
		if bool(carrier.get("dead")):
			f.position = carrier.global_position
			f.set_meta("carrier", null)
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
			elif s_team == TEAM_BLUE:
				if f.position.distance_to(home) > 12.0:
					f.position = home
			break


func _inf_score(team: int, capturer: String) -> void:
	scores[team] = int(scores.get(team, 0)) + 1
	Sfx._play_event("explode", -2.0, 1.0)
	kill.emit(capturer, "FLAG", "infiltrated", team, -1)
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
	var carrier = f.get_meta("carrier")
	if is_instance_valid(carrier):
		if bool(carrier.get("dead")):
			f.position = carrier.global_position
			f.set_meta("carrier", null)
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
			var hp: float = float(s.get("health"))
			s.set("health", minf(100.0, hp + 40.0 * get_process_delta_time()))
			break
	_rambo_carrier_id = carrier_id
	# Respawn the bow at map center if it doesn't exist and nobody is holding it.
	if carrier_id == 0:
		var exists := false
		for wp in get_tree().get_nodes_in_group("weapon_pickup"):
			if is_instance_valid(wp) and str(wp.get("weapon_name")) == "Rambo Bow":
				exists = true
				break
		if not exists:
			_spawn_rambo_bow()


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
				kill.emit(str(s.get("display_name")), "POINT", "captured", s_team, -1)
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
	Sfx._play_event("explode", -2.0, 1.0)
	# Emit a fake kill-feed entry so players see who capped the flag.
	kill.emit(capturer, "FLAG", "captured", team, -1)
	if scores[team] >= CTF_SCORE_TO_WIN:
		_end_round(team)


func _on_kill_scored(killer_name: String, victim_name: String, _weapon_name: String, killer_team: int, victim_team: int) -> void:
	if Net.is_networked() and not Net.is_host():
		return
	if not round_active or killer_team < 0:
		return
	# Suicide or team-kill: no score for the victim's own team.
	if killer_name == victim_name or killer_team == victim_team:
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
	if scores[killer_team] >= SCORE_TO_WIN:
		_end_round(killer_team)
	# Survival: last team standing ends the round early.
	elif Settings.survival:
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


func _end_round(team: int) -> void:
	winner_team = team
	round_active = false
	winner_end_t = WINNER_DISPLAY
	if Net.is_networked() and Net.is_host():
		_broadcast_match_state()


func _end_round_by_time() -> void:
	var top_team := -1
	var top_score := -1
	for t in scores.keys():
		var s := int(scores[t])
		if s > top_score:
			top_score = s
			top_team = int(t)
	_end_round(top_team)


func _reset_round() -> void:
	scores.clear()
	_htf_accum.clear()
	time_left = ROUND_TIME
	winner_team = -1
	winner_end_t = 0.0
	round_active = true
	# Survival: nobody respawns during the round, so at reset we wipe surviving
	# bodies and start everyone fresh.
	if Settings.survival and not Net.is_networked():
		for s in get_tree().get_nodes_in_group("soldier"):
			if is_instance_valid(s):
				s.queue_free()
		call_deferred("_spawn_player")
		call_deferred("_spawn_bots")
	if Net.is_networked() and Net.is_host():
		_broadcast_match_state()


func _broadcast_match_state() -> void:
	if not Net.is_host():
		return
	for pid in _ready_peers.keys():
		rpc_id(int(pid), "net_match_state", scores, time_left, round_active, winner_team, winner_end_t)


@rpc("authority", "reliable")
func net_match_state(new_scores: Dictionary, tl: float, active: bool, winner: int, we: float) -> void:
	scores = new_scores.duplicate(true)
	time_left = tl
	round_active = active
	winner_team = winner
	winner_end_t = we
