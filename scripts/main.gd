extends Node2D
## Main — sky, terrain, players, bots, HUD. Handles singleplayer + networked flows.

var player_scene := preload("res://scenes/player.tscn")
var bot_scene := preload("res://scenes/bot.tscn")
var sky_script := preload("res://scripts/sky.gd")
var parallax_script := preload("res://scripts/parallax.gd")
var hud_script := preload("res://scripts/hud.gd")

signal kill(killer_name: String, victim_name: String, weapon_name: String, killer_team: int)

var player: Node2D = null            # LOCAL player (whichever peer owns us)
var hud: CanvasLayer = null
var _map: Dictionary = {}
var _players_by_id: Dictionary = {}  # peer_id -> player node (host only, but also mirrored on clients)
var _ready_peers: Dictionary = {}    # peer_id -> true (host only, gate for outbound state RPCs)

const MAP_W := 3200.0
const MAP_H := 1200.0
const GROUND_Y := 1150.0

const MAPS := [
	{
		"name": "Ascent",
		"platforms": [
			{"p": Vector2(450, 900), "s": Vector2(260, 22)},
			{"p": Vector2(900, 760), "s": Vector2(240, 22)},
			{"p": Vector2(1350, 640), "s": Vector2(240, 22)},
			{"p": Vector2(1800, 540), "s": Vector2(240, 22)},
			{"p": Vector2(2250, 660), "s": Vector2(240, 22)},
			{"p": Vector2(2700, 800), "s": Vector2(240, 22)},
		],
		"player_spawn": Vector2(200, 1050),
		"bot_spawns": [Vector2(1000, 1050), Vector2(1600, 500), Vector2(2400, 1050), Vector2(2900, 760)],
	},
	{
		"name": "Towers",
		"platforms": [
			{"p": Vector2(500, 900), "s": Vector2(220, 22)},
			{"p": Vector2(500, 700), "s": Vector2(220, 22)},
			{"p": Vector2(2700, 900), "s": Vector2(220, 22)},
			{"p": Vector2(2700, 700), "s": Vector2(220, 22)},
			{"p": Vector2(1600, 620), "s": Vector2(620, 22)},
			{"p": Vector2(1000, 980), "s": Vector2(180, 22)},
			{"p": Vector2(2200, 980), "s": Vector2(180, 22)},
		],
		"player_spawn": Vector2(200, 1050),
		"bot_spawns": [Vector2(500, 640), Vector2(2700, 640), Vector2(1600, 560), Vector2(1600, 1050)],
	},
	{
		"name": "Pillars",
		"platforms": [
			{"p": Vector2(800, 920), "s": Vector2(70, 22)},
			{"p": Vector2(1200, 800), "s": Vector2(70, 22)},
			{"p": Vector2(1600, 700), "s": Vector2(70, 22)},
			{"p": Vector2(2000, 800), "s": Vector2(70, 22)},
			{"p": Vector2(2400, 920), "s": Vector2(70, 22)},
			{"p": Vector2(600, 880), "s": Vector2(130, 22)},
			{"p": Vector2(2600, 880), "s": Vector2(130, 22)},
		],
		"player_spawn": Vector2(200, 1050),
		"bot_spawns": [Vector2(800, 860), Vector2(1600, 640), Vector2(2400, 860), Vector2(1600, 1050)],
	},
]


func _ready() -> void:
	if Net.is_networked():
		# Multiplayer: use a fixed map (Ascent) so host + client match without extra sync.
		_map = MAPS[0]
	else:
		_map = MAPS[Settings.map_index % MAPS.size()]
		Settings.map_index = (Settings.map_index + 1) % MAPS.size()
	_build_sky()
	_build_parallax()
	_build_terrain()
	_build_hud()

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
	get_tree().create_timer(2.0).timeout.connect(_spawn_player)


func _spawn_bots() -> void:
	var spots: Array = _map["bot_spawns"]
	for i in spots.size():
		var b := bot_scene.instantiate()
		b.position = spots[i]
		b.team = 1
		b.display_name = "Bot %d" % (i + 1)
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
	p.cam.limit_top = -500
	p.cam.limit_bottom = int(GROUND_Y + 200)


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
	# only NOW do we start sending state to this peer — their Main scene is loaded
	# and their Player nodes exist, so net_state RPCs will resolve their target path.
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
	_players_by_id[peer_id] = p
	if peer_id == Net.local_id():
		player = p
		_bind_local_camera(p)
		if hud:
			hud.player = p


@rpc("authority", "call_local", "reliable")
func net_despawn_player(peer_id: int) -> void:
	if _players_by_id.has(peer_id):
		var p = _players_by_id[peer_id]
		if is_instance_valid(p):
			p.queue_free()
		_players_by_id.erase(peer_id)
	if peer_id == Net.local_id():
		player = null


@rpc("any_peer", "call_local", "reliable")
func net_kill_feed(killer_name: String, victim_name: String, weapon_name: String, killer_team: int) -> void:
	kill.emit(killer_name, victim_name, weapon_name, killer_team)
