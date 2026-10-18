extends Node
## Main's vehicles and M2 turrets (#258 split of main.gd).
## Buggies / tanks spawn at the map's vehicle_spawns / tank_spawns. The host owns
## them (damage, wrecks, respawns, who sits where); the driver's peer simulates
## movement and streams it. Every message goes through vehicle_send:
## single-player applies it directly, the host broadcasts it (and runs it), a
## client asks the host, which checks the sender and relays it.
##
## The @rpc entry points stay on Main (same node path + name); their bodies live
## here; shared match state (_vehicles, _players_by_id, ...) stays on Main.

const Main = preload("res://scripts/main.gd")
const Tank = preload("res://scripts/tank.gd")
const Buggy = preload("res://scripts/buggy.gd")

var main: Main


func _spawn_m2_mounts() -> void:
	var mounts: Array = main._map.get("m2_mounts", [])
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
		main.add_child(m2)


func find_m2(id: int) -> Node2D:
	# Called by m2.gd RPC receivers to look up their peer counterpart.
	for m in main.get_tree().get_nodes_in_group("m2_gun"):
		if is_instance_valid(m) and int(m.get("m2_id")) == id:
			return m
	return null


func net_m2_mount(m2_id: int, peer_id: int) -> void:
	# In MP the operator's peer id is what all peers use to identify who's driving
	# the turret. Client-initiated mounts route through host as the authority so
	# a race between two clients grabbing the same mount is arbitrated centrally.
	# #106: reject spoofed mounts — a client can only mount themselves, not
	# another peer. #235: relay WITHOUT local=true — re-entering this handler
	# synchronously kept the client as the RPC sender, so the host guard fired
	# again and recursed endlessly (same class of bug _vehicle_relay fixed).
	if _m2_relay("net_m2_mount", [m2_id, peer_id], peer_id):
		return
	var m2 := find_m2(m2_id)
	if m2 == null:
		return
	# Find operator by peer_id.
	var op: Node2D = null
	if main._players_by_id.has(peer_id):
		op = main._players_by_id[peer_id]
	if not is_instance_valid(op):
		return
	if m2.has_method("net_mount"):
		m2.net_mount(op)


func net_m2_dismount(m2_id: int) -> void:
	# #106: only the current operator may dismount themselves — reject any
	# client trying to knock another player off the turret. #235/#254: relay
	# without local=true so the handler doesn't re-enter with the client as
	# sender, and DON'T return — the host must fall through and apply the
	# dismount too, or its replica keeps the operator pinned at the turret.
	if Net.is_networked() and Net.is_host():
		var d_sender := main.multiplayer.get_remote_sender_id() if main.multiplayer.has_multiplayer_peer() else 0
		# (call_local reports the host's own id, not 0 — treat that as local.)
		if d_sender != 0 and d_sender != main.multiplayer.get_unique_id():
			var m2_local := find_m2(m2_id)
			if m2_local != null:
				var op = m2_local.get("operator")
				if is_instance_valid(op) and int(op.get_multiplayer_authority()) != d_sender:
					return
			main.bcast("net_m2_dismount", [m2_id], false)
	var m2 := find_m2(m2_id)
	if m2 != null and m2.has_method("net_dismount"):
		m2.net_dismount()


# Host side of an M2 RPC a client sent us: reject it (return true) unless it
# comes from the peer it concerns; otherwise pass it on to the other peers and
# return false so the host applies it too by falling through. Mirrors
# _vehicle_relay — never relay these with local=true (#235).
func _m2_relay(method: StringName, args: Array, allowed_peer: int) -> bool:
	if not Net.is_networked() or not Net.is_host():
		return false
	var sender := main.multiplayer.get_remote_sender_id()
	if sender == 0 or sender == main.multiplayer.get_unique_id():
		return false
	if sender != allowed_peer:
		return true
	main.bcast(method, args, false)
	return false


func net_m2_state(m2_id: int, aim_dir: Vector2) -> void:
	var m2 := find_m2(m2_id)
	if m2 == null or not m2.has_method("net_apply_state"):
		return
	# Only the current operator may steer the barrel — reject spoofed aim from
	# non-operators (aim-spoof / attribution exploit).
	if main.multiplayer.multiplayer_peer != null:
		var sender := main.multiplayer.get_remote_sender_id()
		var op = m2.get("operator")
		if not is_instance_valid(op):
			return
		var op_peer := int(op.get_multiplayer_authority())
		if sender == 0:
			if op_peer != main.multiplayer.get_unique_id():
				return
		elif sender != op_peer:
			return
	m2.net_apply_state(aim_dir)


func net_m2_fire(m2_id: int, muzzle: Vector2, aim_dir: Vector2, shooter_team: int, shooter_name: String) -> void:
	var m2 := find_m2(m2_id)
	if m2 == null or not m2.has_method("net_apply_fire"):
		return
	# Only the current operator may spawn M2 bullets. Also lock shooter_team +
	# shooter_name to the operator's own so kill attribution can't be forged.
	var op_team := shooter_team
	var op_name := shooter_name
	if main.multiplayer.multiplayer_peer != null:
		var sender := main.multiplayer.get_remote_sender_id()
		var op = m2.get("operator")
		if not is_instance_valid(op):
			return
		var op_peer := int(op.get_multiplayer_authority())
		if sender == 0:
			if op_peer != main.multiplayer.get_unique_id():
				return
		elif sender != op_peer:
			return
		op_team = int(op.get("team"))
		op_name = str(op.get("display_name"))
	m2.net_apply_fire(muzzle, aim_dir, op_team, op_name)


func _spawn_vehicles() -> void:
	if Net.is_networked() and not Net.is_host():
		return
	if not Settings.vehicles or Settings.game_mode == Settings.MODE_GG:
		return
	var vid := 0
	for pair in [["vehicle_spawns", "buggy"], ["tank_spawns", "tank"]]:
		for v in main._map.get(pair[0], []):
			var p: Vector2 = v if v is Vector2 else Vector2(float(v[0]), float(v[1]))
			_make_vehicle(vid, p + Vector2(0, -4), p + Vector2(0, -4), -1.0, true, pair[1])
			vid += 1


func _make_vehicle(vid: int, spawn: Vector2, pos: Vector2, hp_v: float, alive_v: bool, kind := "buggy") -> Node:
	if main._vehicles.has(vid) and is_instance_valid(main._vehicles[vid]):
		main._vehicles[vid].queue_free()
	var b = Tank.new() if kind == "tank" else Buggy.new()
	b.name = "%s_%d" % ["Tank" if kind == "tank" else "Buggy", vid]
	b.vehicle_id = vid
	b.position = spawn
	main.add_child(b)
	b.spawn_pos = spawn
	b.global_position = pos
	if hp_v >= 0.0:
		b.hp = hp_v
	if alive_v and spawn.distance_to(pos) < 1.0:
		b.unstick()
		b.spawn_pos = b.global_position
	if not alive_v:
		b.apply_destroy(pos, "", -1, true)
	main._vehicles[vid] = b
	return b


func find_vehicle(vid: int) -> Node:
	var v = main._vehicles.get(vid, null)
	return v if is_instance_valid(v) else null


func vehicle_send(method: StringName, args: Array, _reliable: bool) -> void:
	if not Net.is_networked() or not main.multiplayer.has_multiplayer_peer():
		main.callv(method, args)
		return
	if Net.is_host():
		main.bcast(method, args, true)
	else:
		main.callv("rpc_id", [1, method] + args)


# Host side, for a message a client sent us: reject it (return true) unless it
# comes from the peer allowed to send it; otherwise pass it on to the other
# peers and return false so the host applies it too. (Relaying with local=true
# re-entered this handler with the client still as the RPC sender — endless.)
func _vehicle_relay(method: StringName, args: Array, allowed_peer: int) -> bool:
	if not Net.is_networked() or not Net.is_host():
		return false
	var sender := main.multiplayer.get_remote_sender_id()
	if sender == 0 or sender == main.multiplayer.get_unique_id():
		return false
	if sender != allowed_peer:
		return true
	main.bcast(method, args, false)
	return false


# Clients only accept vehicle authority messages from the host.
func _from_host() -> bool:
	if not Net.is_networked() or Net.is_host():
		return true
	return main.multiplayer.get_remote_sender_id() == 1


func vehicle_request_seat(v: Node, s: Node, enter: bool) -> void:
	if not Net.is_networked():
		_decide_seat(v, s, enter)
		return
	if Net.is_host():
		_decide_seat(v, s, enter)
	else:
		main.rpc_id(1, "net_vehicle_seat_req", int(v.get("vehicle_id")), enter)


func net_vehicle_seat_req(vid: int, enter: bool) -> void:
	if not Net.is_host():
		return
	var v := find_vehicle(vid)
	var sender := main.multiplayer.get_remote_sender_id()
	var s = main._players_by_id.get(sender, null)
	if v == null or not is_instance_valid(s):
		return
	_decide_seat(v, s, enter)


func _decide_seat(v: Node, s: Node, enter: bool) -> void:
	if enter:
		if not v.can_enter(s):
			return
		var seat: int = v.free_seat()
		if seat < 0:
			return
		vehicle_send("net_vehicle_seat", [int(v.get("vehicle_id")), seat, _peer_of(s), true], true)
	else:
		var seat2: int = v.seat_of(s)
		if seat2 < 0:
			return
		vehicle_send("net_vehicle_seat", [int(v.get("vehicle_id")), seat2, _peer_of(s), false], true)


# Host / single-player: a bot takes a free seat (the gunner's, in practice).
func vehicle_bot_board(v: Node, bot: Node, want_seat := 1) -> void:
	if Net.is_networked() and not Net.is_host():
		return
	if not v.can_enter(bot):
		return
	var seat: int = want_seat
	var cur: Array = v.get("seats")
	if seat < 0 or seat >= cur.size() or is_instance_valid(cur[seat]):
		return
	if Net.is_networked():
		main.bcast("net_vehicle_seat_bot", [int(v.get("vehicle_id")), seat, int(bot.get("bot_id")), true], true)
	else:
		v.set_seat(seat, bot)   # bot_id is only unique online


func net_vehicle_seat_bot(vid: int, seat: int, bot_id: int, enter: bool) -> void:
	if not _from_host():
		return
	var v := find_vehicle(vid)
	var b = null
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(s) and s.get("bot_id") != null and int(s.get("bot_id")) == bot_id:
			b = s
	if v == null or b == null:
		return
	if enter:
		v.set_seat(seat, b)
	else:
		v.clear_seat_of(b)


func _peer_of(s: Node) -> int:
	return int(s.get_multiplayer_authority()) if Net.is_networked() else 1


func _soldier_for_peer(peer: int) -> Node:
	if not Net.is_networked():
		return main.player
	var s = main._players_by_id.get(peer, null)
	return s if is_instance_valid(s) else null


func net_vehicle_seat(vid: int, seat: int, peer: int, enter: bool) -> void:
	if not _from_host():
		return
	var v := find_vehicle(vid)
	var s := _soldier_for_peer(peer)
	if v == null or s == null:
		return
	if enter:
		v.set_seat(seat, s)
	else:
		v.clear_seat_of(s)


func net_vehicle_spawn(vid: int, spawn: Vector2, pos: Vector2, hp_v: float, alive_v: bool, kind: String = "buggy") -> void:
	if not _from_host():
		return
	_make_vehicle(vid, spawn, pos, hp_v, alive_v, kind)


func net_vehicle_state(vid: int, pos: Vector2, vel: Vector2, tilt: float, f: float, aim: Vector2) -> void:
	var v := find_vehicle(vid)
	if v == null:
		return
	if _vehicle_relay("net_vehicle_state", [vid, pos, vel, tilt, f, aim], int(v.sim_peer())):
		return
	if Net.is_networked() and not Net.is_host() and main.multiplayer.get_remote_sender_id() != 1:
		return
	v.apply_state(pos, vel, tilt, f, aim)


func net_vehicle_fire(vid: int, muzzle: Vector2, dir: Vector2) -> void:
	var v := find_vehicle(vid)
	if v == null:
		return
	var shooter: Node = v.gunner() if v.gunner() != null else v.driver()
	if shooter == null:
		return
	if _vehicle_relay("net_vehicle_fire", [vid, muzzle, dir], _peer_of(shooter)):
		return
	if Net.is_networked() and not Net.is_host() and main.multiplayer.get_remote_sender_id() != 1:
		return
	# The muzzle must be on the buggy (no firing from across the map).
	if muzzle.distance_to((v as Node2D).global_position) > 90.0:
		return
	v.apply_fire(muzzle, dir.normalized())


func net_vehicle_hp(vid: int, hp_v: float) -> void:
	if not _from_host():
		return
	var v := find_vehicle(vid)
	if v != null:
		v.apply_hp(hp_v)


func net_vehicle_destroy(vid: int, at: Vector2, killer: String, killer_team: int, violent := true) -> void:
	if not _from_host():
		return
	var v := find_vehicle(vid)
	if v != null:
		v.apply_destroy(at, killer, killer_team, false, violent)


func net_vehicle_respawn(vid: int) -> void:
	if not _from_host():
		return
	var v := find_vehicle(vid)
	if v != null:
		v.apply_respawn()


# Run-over damage, decided by the host; the victim's owner applies it.
func vehicle_hit_soldier(s: Node, dmg: float, killer: String, killer_team: int, vel: Vector2, weapon := "Buggy") -> void:
	if not Net.is_networked() or s.is_multiplayer_authority():
		s.set("ceasefire_t", 0.0)
		s.take_damage(dmg, killer, weapon, killer_team)
		if s.get("dead") != true:
			s.set("velocity", Vector2(vel.x * 0.9, -260.0))
		return
	if s.has_method("net_vehicle_hurt"):
		TrustGuard.note_activity(killer, killer_team)
		if s.has_method("observe_damage"):
			s.observe_damage(dmg, killer, weapon, killer_team)
		s.rpc_id(int(s.get_multiplayer_authority()), "net_vehicle_hurt", dmg, killer, killer_team, vel, weapon)
