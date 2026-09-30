extends MultiplayerPeerExtension
## Relay transport (v1.25): the host and every client keep one outgoing
## WebSocket to the relay on the master server (/relay), which forwards game
## packets, so nobody needs an open port. Protocol: see
## server/master-server/relay.go. Clients only talk to the host (peer 1);
## SceneMultiplayer's server relay carries client-to-client traffic.

signal hosted(code: String)
signal failed(msg: String)

var ws := WebSocketPeer.new()
var host_mode := false
var code := ""
var _url := ""
var _hello: Dictionary = {}
var _id := 0
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _in: Array = []               # [from_id, PackedByteArray]
var _target := 0
var _peers: Dictionary = {}       # host: id -> true
var _refuse := false
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _said_hello := false


static func ws_url(master_url: String) -> String:
	var u := master_url.strip_edges().rstrip("/")
	if u.begins_with("https://"):
		u = "wss://" + u.substr(8)
	elif u.begins_with("http://"):
		u = "ws://" + u.substr(7)
	elif not (u.begins_with("ws://") or u.begins_with("wss://")):
		u = "ws://" + u
	return u + "/relay"


func start_host(master_url: String, name: String) -> Error:
	host_mode = true
	_hello = {"op": "host", "version": str(ProjectSettings.get_setting("application/config/version", "")), "name": name}
	return _open(master_url)


func start_join(master_url: String, room: String) -> Error:
	host_mode = false
	_hello = {"op": "join", "code": room.strip_edges().to_upper()}
	return _open(master_url)


func _open(master_url: String) -> Error:
	_url = ws_url(master_url)
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	ws.max_queued_packets = 4096
	var e := ws.connect_to_url(_url)
	if e == OK:
		_status = MultiplayerPeer.CONNECTION_CONNECTING
	return e


func _poll() -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _said_hello:
		_said_hello = true
		ws.send_text(JSON.stringify(_hello))
	while ws.get_available_packet_count() > 0:
		var pkt := ws.get_packet()
		if ws.was_string_packet():
			_on_control(JSON.parse_string(pkt.get_string_from_utf8()))
		elif host_mode:
			if pkt.size() >= 4 and _peers.has(pkt.decode_s32(0)):
				_in.append([pkt.decode_s32(0), pkt.slice(4)])
		else:
			_in.append([1, pkt])
	if st == WebSocketPeer.STATE_CLOSED and _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
		var was := _status
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		if was == MultiplayerPeer.CONNECTION_CONNECTING:
			failed.emit("Couldn't reach the relay (%s)" % _url)
		for pid in _peers.keys():
			peer_disconnected.emit(int(pid))
		_peers.clear()
		if not host_mode and was == MultiplayerPeer.CONNECTION_CONNECTED:
			peer_disconnected.emit(1)


func _on_control(d) -> void:
	if not (d is Dictionary):
		return
	match str(d.get("op", "")):
		"hosted":
			code = str(d.get("code", ""))
			_id = 1
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			hosted.emit(code)
		"joined":
			_id = int(d.get("id", 0))
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			_peers[1] = true
			peer_connected.emit(1)
		"peer_connected":
			var pid := int(d.get("id", 0))
			if _refuse:
				ws.send_text(JSON.stringify({"op": "kick", "id": pid}))
				return
			_peers[pid] = true
			peer_connected.emit(pid)
		"peer_disconnected":
			var pid2 := int(d.get("id", 0))
			# Packets it sent just before leaving are still queued: drop them
			# (SceneMultiplayer rejects packets from a peer it no longer knows).
			_in = _in.filter(func(p): return int(p[0]) != pid2)
			if _peers.erase(pid2):
				peer_disconnected.emit(pid2)
		"error":
			failed.emit(str(d.get("msg", "relay error")))
			ws.close()


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	if host_mode:
		var out := PackedByteArray()
		out.resize(4)
		out.encode_s32(0, _target)
		out.append_array(buffer)
		return ws.put_packet(out)
	return ws.put_packet(buffer)


func _get_packet_script() -> PackedByteArray:
	if _in.is_empty():
		return PackedByteArray()
	return _in.pop_front()[1]


func _get_available_packet_count() -> int:
	return _in.size()


func _get_packet_peer() -> int:
	return int(_in[0][0]) if not _in.is_empty() else 0


func _get_max_packet_size() -> int:
	return 1 << 20


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _set_transfer_channel(ch: int) -> void:
	_channel = ch


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(m: MultiplayerPeer.TransferMode) -> void:
	_mode = m


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_target_peer(p: int) -> void:
	_target = p


func _is_server() -> bool:
	return host_mode


func _get_unique_id() -> int:
	return _id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _close() -> void:
	ws.close()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_peers.clear()
	_in.clear()


func _disconnect_peer(p: int, _force: bool) -> void:
	if host_mode and _peers.has(p):
		ws.send_text(JSON.stringify({"op": "kick", "id": p}))
		_peers.erase(p)
		peer_disconnected.emit(p)


func _set_refuse_new_connections(on: bool) -> void:
	_refuse = on


func _is_refusing_new_connections() -> bool:
	return _refuse


func _is_server_relay_supported() -> bool:
	return true
