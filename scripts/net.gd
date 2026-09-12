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

var mode: int = Mode.SINGLEPLAYER
var status := ""
var chosen_map_index := 0     # host's picked map; clients receive it via net_set_map
var _map_synced := false      # client-side: true once host has told us the map


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_maybe_run_smoke_test()


func _maybe_run_smoke_test() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--smoke-host" in args:
		call_deferred("_smoke_host")
	elif "--smoke-join" in args:
		call_deferred("_smoke_join")


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
	disconnected.emit()


func _on_server_disconnected() -> void:
	_set_status("Server disconnected")
	multiplayer.multiplayer_peer = null
	mode = Mode.SINGLEPLAYER
	disconnected.emit()


@rpc("authority", "reliable")
func net_set_map(idx: int) -> void:
	chosen_map_index = idx
	_map_synced = true
	map_received.emit()
