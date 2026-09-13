extends Node
## Net — high-level multiplayer wrapper (ENet). Autoload singleton "Net".
## Tracks mode (SP/HOST/CLIENT), owns the ENetMultiplayerPeer lifecycle,
## and exposes a human-readable connection status for the UI.

signal status_changed
signal connected
signal disconnected
signal map_received

enum Mode { SINGLEPLAYER, HOST, CLIENT }

const DEFAULT_PORT := 7777
const MAX_PEERS := 8

# Kept in-sync with menu.gd — used by --map/--mode CLI resolution before the
# menu ever loads (dedicated mode boots straight into main.tscn).
const MAP_NAMES := [
	"Ascent", "Towers", "Pillars",
	"Nuubia", "Maya", "Aftermath", "Hormone", "Viet",
	"Scorpion", "Warehouse", "Baire", "Airpirates", "Bunker",
]
const MODE_NAMES := [
	"Deathmatch", "Teammatch", "Capture the Flag",
	"Infiltration", "Hold the Flag", "Rambomatch", "Pointmatch",
	"Domination", "Battle Royale",
]

var mode: int = Mode.SINGLEPLAYER
var status := ""
var chosen_map_index := 0     # host's picked map; clients receive it via net_set_map
var _map_synced := false      # client-side: true once host has told us the map
# Dedicated (headless) server mode — host WITHOUT a local player. main.gd reads
# this to skip the peer-1 spawn and instead fill the match with bots so a lone
# joining client has opponents. See #54.
var is_dedicated := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_maybe_run_smoke_test()
	_maybe_run_dedicated()


func _maybe_run_smoke_test() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--smoke-host" in args:
		call_deferred("_smoke_host")
	elif "--smoke-join" in args:
		call_deferred("_smoke_join")


func _maybe_run_dedicated() -> void:
	# Dedicated (headless) server auto-host — --dedicated / --server / --smoke-dedicated.
	# Overrides: --port <n>, --map <name|index>, --mode <name|index>. Skips the menu
	# entirely and boots straight into main.tscn with no local player. See #54.
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var wants_dedicated: bool = ("--dedicated" in args) or ("--server" in args)
	var wants_smoke: bool = "--smoke-dedicated" in args
	if not (wants_dedicated or wants_smoke):
		return
	var port: int = DEFAULT_PORT
	var map_index: int = Settings.map_index
	var mode_index: int = Settings.game_mode
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		if a == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
			i += 1
		elif a.begins_with("--port="):
			port = int(a.substr(len("--port=")))
		elif a == "--map" and i + 1 < args.size():
			map_index = _resolve_map_arg(args[i + 1])
			i += 1
		elif a.begins_with("--map="):
			map_index = _resolve_map_arg(a.substr(len("--map=")))
		elif a == "--mode" and i + 1 < args.size():
			mode_index = _resolve_mode_arg(args[i + 1])
			i += 1
		elif a.begins_with("--mode="):
			mode_index = _resolve_mode_arg(a.substr(len("--mode=")))
		i += 1
	is_dedicated = true
	if wants_smoke:
		call_deferred("_smoke_dedicated", port, map_index, mode_index)
	else:
		call_deferred("_start_dedicated", port, map_index, mode_index)


func _resolve_map_arg(v: String) -> int:
	# Accepts "ctf_Nuubia", "Nuubia", or an integer index. Falls back to Settings on miss.
	if v.is_valid_int():
		return clampi(int(v), 0, MAP_NAMES.size() - 1)
	var needle: String = v.strip_edges()
	if needle.begins_with("ctf_") or needle.begins_with("inf_") or needle.begins_with("dm_"):
		needle = needle.substr(needle.find("_") + 1)
	for i in MAP_NAMES.size():
		if String(MAP_NAMES[i]).to_lower() == needle.to_lower():
			return i
	return Settings.map_index


func _resolve_mode_arg(v: String) -> int:
	if v.is_valid_int():
		return clampi(int(v), 0, MODE_NAMES.size() - 1)
	var needle: String = v.strip_edges().to_lower()
	for i in MODE_NAMES.size():
		if String(MODE_NAMES[i]).to_lower() == needle:
			return i
	# Common shorthand aliases (dm/tdm/ctf/inf/htf/rm/pm/dom/br) → mode index.
	var aliases := {"dm": 0, "tdm": 1, "ctf": 2, "inf": 3, "htf": 4, "rm": 5, "pm": 6, "dom": 7, "br": 8}
	if aliases.has(needle):
		return int(aliases[needle])
	return Settings.game_mode


func _start_dedicated(port: int, map_index: int, mode_index: int) -> void:
	Settings.map_index = map_index
	Settings.game_mode = mode_index
	if not host_game(port, map_index):
		push_error("Dedicated host failed on port %d" % port)
		get_tree().quit(1)
		return
	var map_name: String = MAP_NAMES[map_index] if map_index >= 0 and map_index < MAP_NAMES.size() else "map#%d" % map_index
	var mode_name: String = MODE_NAMES[mode_index] if mode_index >= 0 and mode_index < MODE_NAMES.size() else "mode#%d" % mode_index
	print("Dedicated server listening on port %d, map=%s mode=%s" % [port, map_name, mode_name])
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _smoke_dedicated(port: int, map_index: int, mode_index: int) -> void:
	_start_dedicated(port, map_index, mode_index)
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		var listening: bool = multiplayer.multiplayer_peer != null and mode == Mode.HOST
		var main := get_tree().current_scene
		var pbi = main.get("_players_by_id") if main != null else null
		var pcount: int = pbi.size() if pbi != null else 0
		var bot_count := 0
		for s in get_tree().get_nodes_in_group("soldier"):
			if is_instance_valid(s) and (s.get_script() == null or String(s.get_script().resource_path).ends_with("bot.gd")):
				bot_count += 1
		print("SMOKE-DEDICATED listening=%s peers=%d players=%d bots=%d dedicated=%s" % [str(listening), multiplayer.get_peers().size(), pcount, bot_count, str(is_dedicated)])
		leave()
		get_tree().quit())


func _smoke_host() -> void:
	host_game(DEFAULT_PORT)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		var main := get_tree().current_scene
		var pbi = main.get("_players_by_id") if main != null else null
		var pcount: int = pbi.size() if pbi != null else 0
		print("SMOKE-HOST peers=%d players=%d" % [multiplayer.get_peers().size(), pcount])
		leave()
		get_tree().quit())


func _smoke_join() -> void:
	map_received.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	join_game("127.0.0.1", DEFAULT_PORT)
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		var main := get_tree().current_scene
		var pbi = main.get("_players_by_id") if main != null else null
		var pcount: int = pbi.size() if pbi != null else 0
		print("SMOKE-JOIN id=%d mode=%d players=%d" % [local_id(), mode, pcount])
		leave()
		get_tree().quit())


func host_game(port: int = DEFAULT_PORT, map_index: int = 0) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var e := peer.create_server(port, MAX_PEERS)
	if e != OK:
		_set_status("Host failed: %s" % error_string(e))
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	chosen_map_index = map_index
	_map_synced = true
	_set_status("Hosting on port %d · you are peer 1" % port)
	return true


func join_game(ip: String, port: int = DEFAULT_PORT) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var e := peer.create_client(ip, port)
	if e != OK:
		_set_status("Join failed: %s" % error_string(e))
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	_map_synced = false
	_set_status("Connecting to %s:%d..." % [ip, port])
	return true


func set_singleplayer() -> void:
	leave()


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	mode = Mode.SINGLEPLAYER
	_map_synced = false
	_set_status("")


func is_map_synced() -> bool:
	return _map_synced


func is_networked() -> bool:
	return mode != Mode.SINGLEPLAYER


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


func local_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()


func _set_status(s: String) -> void:
	status = s
	status_changed.emit()


func _on_peer_connected(id: int) -> void:
	if is_host():
		_set_status("Peer %d joined · hosting" % id)
		# Push chosen map to the new peer immediately so they build the same terrain.
		rpc_id(id, "net_set_map", chosen_map_index)


func _on_peer_disconnected(id: int) -> void:
	if is_host():
		_set_status("Peer %d left · hosting" % id)


func _on_connected() -> void:
	_set_status("Connected as peer %d" % multiplayer.get_unique_id())
	connected.emit()


func _on_connection_failed() -> void:
	_set_status("Connection failed")
	multiplayer.multiplayer_peer = null
	mode = Mode.SINGLEPLAYER
	_map_synced = false
	disconnected.emit()


func _on_server_disconnected() -> void:
	_set_status("Server disconnected")
	multiplayer.multiplayer_peer = null
	mode = Mode.SINGLEPLAYER
	_map_synced = false
	disconnected.emit()


@rpc("authority", "reliable")
func net_set_map(idx: int) -> void:
	chosen_map_index = idx
	_map_synced = true
	map_received.emit()
