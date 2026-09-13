extends Node2D
## Main — sky, terrain, players, bots, HUD. Handles singleplayer + networked flows.

var player_scene := preload("res://scenes/player.tscn")
var bot_scene := preload("res://scenes/bot.tscn")
var sky_script := preload("res://scripts/sky.gd")
var parallax_script := preload("res://scripts/parallax.gd")
var hud_script := preload("res://scripts/hud.gd")
const PoaLoader = preload("res://scripts/poa_loader.gd")

signal kill(killer_name: String, victim_name: String, weapon_name: String, killer_team: int, victim_team: int)

var player: Node2D = null            # LOCAL player (whichever peer owns us)
var hud: CanvasLayer = null
var _map: Dictionary = {}
var _players_by_id: Dictionary = {}  # peer_id -> player node (host only, but also mirrored on clients)
var _ready_peers: Dictionary = {}    # peer_id -> true (host only, gate for outbound state RPCs)

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
		"bot_spawns": [Vector2(1100, 1350), Vector2(2500, 720), Vector2(3700, 350), Vector2(4200, 870)],
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
		"bot_spawns": [Vector2(600, 770), Vector2(4200, 770), Vector2(2400, 1120), Vector2(2400, 890)],
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
		"bot_spawns": [Vector2(1200, 1570), Vector2(2400, 1370), Vector2(3600, 1570), Vector2(2400, 1120)],
	},
]


func _ready() -> void:
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


# ── Singleplayer spawn path ───────────────────────────

func _spawn_player() -> void:
	var p := player_scene.instantiate()
	p.position = _map["player_spawn"]
	p.team = 0
	p.died.connect(_on_player_died)
	add_child(p)
	player = p
	_bind_local_camera(p)
	if hud:
		hud.player = p


func _on_player_died() -> void:
	if hud:
		hud.show_death(str(player.last_killer), str(player.last_weapon))
	get_tree().create_timer(2.0).timeout.connect(_spawn_player)


func _spawn_bots() -> void:
	var spots: Array = _map["bot_spawns"]
	for i in spots.size():
		# Last bot gets the LAW so at least one rocket-bot is always in the mix.
		var loadout := "LAW" if i == spots.size() - 1 else "AK-74"
		# Bot team 99: a dedicated non-peer id so bots stay hostile to any human peer (incl. host peer 1).
		_spawn_bot(spots[i], 99, "Bot %d" % (i + 1), loadout)


func _spawn_bot(pos: Vector2, team: int, bname: String, loadout: String = "AK-74") -> void:
	if not is_inside_tree():
		return
	var b := bot_scene.instantiate()
	b.position = pos
	b.team = team
	b.display_name = bname
	b.loadout = loadout
	# Bots respawn on the same slot so the match can accumulate score.
	b.died.connect(func() -> void:
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			# Guard against the outer Main being torn down (scene change / quit)
			# during the 2s respawn window — the SceneTreeTimer keeps firing.
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


# ── Match / score / round ─────────────────────────────

func _process(delta: float) -> void:
	# Client: state is driven entirely by host's net_match_state RPCs.
	if Net.is_networked() and not Net.is_host():
		return
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


func _on_kill_scored(killer_name: String, victim_name: String, _weapon_name: String, killer_team: int, victim_team: int) -> void:
	if Net.is_networked() and not Net.is_host():
		return
	if not round_active or killer_team < 0:
		return
	# Suicide or team-kill: no score for the victim's own team.
	if killer_name == victim_name or killer_team == victim_team:
		return
	scores[killer_team] = int(scores.get(killer_team, 0)) + 1
	if scores[killer_team] >= SCORE_TO_WIN:
		_end_round(killer_team)
	elif Net.is_networked() and Net.is_host():
		_broadcast_match_state()


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
	time_left = ROUND_TIME
	winner_team = -1
	winner_end_t = 0.0
	round_active = true
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
