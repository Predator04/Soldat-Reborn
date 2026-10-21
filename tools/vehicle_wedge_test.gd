extends SceneTree
## #299: wedged ground vehicles recover (gate stage F `wedge`).
##   godot --headless --fixed-fps 60 -s tools/vehicle_wedge_test.gd [-- --match-secs=180]
## Part 1 (Ascent, no bots): a buggy dropped into the slot between the second
## hill's cliff and the tunnel mountain (where the owner's buggies wedged) is
## sent home within the time limit — with the player at the wheel stepped out
## clear of the rock — and so is an empty one, a tank, and a buggy whose tilt
## reads past 70 deg; a crewed buggy parked on flat ground, one on a slope and
## the helicopter / plane (hover / fly in place) are never reset.
## Part 2: an Ascent CTF bot match with buggies — no ground vehicle stays
## wedged (still, no floor under it) longer than the reset allows.

const SLOT := Vector2(1758, 1640)       # drop point above the Ascent slot
const LIMIT := 7.0                      # WEDGE_TIME (4 s) + fall + slack

var _match_secs := 180.0
var _phase := 0
var _t := 0.0
var _case := 0
var _bad: Array = []
var _log: Array = []
var _main: Node = null
var _player: Node2D = null
var _car0: Node = null
var _car1: Node = null
var _tank: Node = null
var _r0 := 0
var _w0 := 0
var _wedged_seen := false
var _track: Dictionary = {}
var _worst := 0.0
var _resets := 0
var _brakes := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--match-secs="):
			_match_secs = float(a.substr(13))


func _start(bots: int) -> void:
	var st := root.get_node("Settings")
	st.set("custom_map_path", "")
	st.set("map_index", 0)
	st.set("game_mode", 2)
	st.set("bot_count", bots)
	st.set("vehicles", true)
	st.set("bot_skill", 3)
	for k in ["survival", "realistic", "advance"]:
		st.set(k, false)
	root.get_node("Net").set_singleplayer()
	change_scene_to_file("res://scenes/main.tscn")


static func _supported(v: Node) -> bool:
	return bool(v.call("floor_supported"))


func _in_rock(s: Node2D) -> bool:
	return (s as CharacterBody2D).test_move(s.global_transform, Vector2.ZERO, null, 0.08, true)


func _place(v: Node, at: Vector2) -> void:
	(v as Node2D).global_position = at
	v.set("velocity", Vector2.ZERO)
	_r0 = int(v.get("respawns"))
	_w0 = int(v.get("wedge_resets"))
	_wedged_seen = false
	_t = 0.0


func _home(v: Node) -> bool:
	return int(v.get("respawns")) > _r0 and (v as Node2D).global_position.distance_to(v.get("spawn_pos")) < 40.0


# A wedge case: by 1.5 s it must be stuck there without a floor (proves the
# spot really wedges), then back home within LIMIT, counted as a wedge reset.
func _wedge_case(v: Node, label: String) -> int:
	if _t >= 1.5 and _t < 2.0 and not _wedged_seen:
		_wedged_seen = true
		var p := (v as Node2D).global_position
		_log.append("%s stuck@%s sup=%s" % [label, Vector2i(p), str(_supported(v))])
		if _supported(v) or p.distance_to(SLOT) > 140.0:
			_bad.append("%s: did not wedge in the slot (at %s, supported=%s)" % [label, Vector2i(p), str(_supported(v))])
			return 1
	if _home(v):
		if int(v.get("wedge_resets")) != _w0 + 1:
			_bad.append("%s: went home but not via the wedge reset" % label)
		_log.append("%s home in %.1fs" % [label, _t])
		return 1
	if _t > LIMIT:
		_bad.append("%s: still wedged after %.0fs at %s" % [label, LIMIT, Vector2i((v as Node2D).global_position)])
		return 1
	return 0


func _process(delta: float) -> bool:
	if root.get_node_or_null("Settings") == null:
		return false
	if _phase == 0:
		_start(0)
		_phase = 1
		return false
	var m := current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += delta
	if _phase == 1:
		_main = m
		_player = m.get("player")
		if _player == null or not is_instance_valid(_player) or _t < 1.0:
			return false
		for v in get_nodes_in_group("vehicle"):
			if int(v.get("vehicle_id")) == 0:
				_car0 = v
			elif int(v.get("vehicle_id")) == 1:
				_car1 = v
		if _car0 == null or _car1 == null:
			return _end("Ascent buggies missing")
		m.call("net_vehicle_spawn", 40, Vector2(900, 1700), Vector2(900, 1660), 300.0, true, "tank")
		m.call("net_vehicle_spawn", 41, Vector2(2200, 1890), Vector2(2200, 1890), 300.0, true, "heli")
		_tank = m.get("_vehicles").get(40)
		var heli = m.get("_vehicles").get(41)
		if _tank == null or heli == null:
			return _end("could not spawn the test tank / heli")
		if bool(heli.call("_wedge_watch")):
			_bad.append("heli is wedge-watched (hover would be reset)")
		var pl = load("res://scripts/plane.gd").new()
		if bool(pl.call("_wedge_watch")):
			_bad.append("plane is wedge-watched (flight would be reset)")
		pl.free()
		heli.queue_free()
		m.get("_vehicles").erase(41)
		_phase = 2
		_case = 0
		_place(_car0, SLOT)
		_player.global_position = SLOT + Vector2(0, -12)
		_car0.call("set_seat", 0, _player)
		return false
	if _phase == 2:
		match _case:
			0:   # crewed buggy in the slot: home, the player out, clear of the rock
				if _wedge_case(_car0, "crewed") == 0:
					return false
				if _car0.call("driver") != null or _player.get("mounted_m2") != null:
					_bad.append("crewed: driver still seated after the reset")
				if _in_rock(_player):
					_bad.append("crewed: player stepped out inside the rock at %s" % Vector2i(_player.global_position))
				if _player.get("dead") == true:
					_bad.append("crewed: player died")
				_log.append("player out@%s" % Vector2i(_player.global_position))
				_player.global_position = Vector2(200, 1770)
				_player.set("velocity", Vector2.ZERO)
				_case = 1
				_place(_car1, SLOT)
			1:   # empty red buggy in the slot
				if _wedge_case(_car1, "empty") == 0:
					return false
				_case = 2
				_place(_tank, SLOT + Vector2(0, -20))
			2:   # tank (subclass) in the slot
				if _wedge_case(_tank, "tank") == 0:
					return false
				_case = 3
				_place(_car0, Vector2(2200, 1890))
			3:   # tilt reads upside down (as a replica streams it) on flat ground
				_car0.set("_tilt", PI)
				if _home(_car0):
					_log.append("tilted home in %.1fs" % _t)
					_case = 4
					_place(_car0, Vector2(2200, 1890))
					_player.global_position = Vector2(2200, 1878)
					_car0.call("set_seat", 0, _player)
				elif _t > LIMIT:
					_bad.append("tilted: not reset")
					_case = 4
					_place(_car0, Vector2(2200, 1890))
					_player.global_position = Vector2(2200, 1878)
					_car0.call("set_seat", 0, _player)
			4:   # negatives: crewed + still on flat ground, empty on a slope
				if not _car1.has_meta("r0"):
					_car1.set_meta("r0", int(_car1.get("respawns")))
					(_car1 as Node2D).global_position = Vector2(420, 1740)
					_car1.set("velocity", Vector2.ZERO)
				if _t < 9.0:
					return false
				if int(_car0.get("wedge_resets")) != _w0 or int(_car0.get("respawns")) != _r0:
					_bad.append("parked crewed buggy was reset (wedge %d->%d, respawns %d->%d)" % [_w0, int(_car0.get("wedge_resets")), _r0, int(_car0.get("respawns"))])
				if _car0.call("driver") != _player:
					_bad.append("parked crewed buggy lost its driver")
				if int(_car1.get("respawns")) != int(_car1.get_meta("r0")):
					_bad.append("buggy parked on the slope was reset")
				if not _supported(_car1):
					_bad.append("buggy on the slope not resting on a floor")
				_log.append("parked ok (crewed@%s slope@%s)" % [Vector2i((_car0 as Node2D).global_position), Vector2i((_car1 as Node2D).global_position)])
				_car0.call("clear_seat_of", _player)
				_phase = 3
				_t = 0.0
				_start(8)
		return false
	if _phase == 3:
		_main = m
		if _t < 1.0:
			return false
		var p = m.get("player")
		if p != null and is_instance_valid(p):
			p.set_physics_process(false)
			p.global_position = Vector2(-500, -500)
		for v in get_nodes_in_group("vehicle"):
			if not is_instance_valid(v) or not (str(v.get("kind")) in ["buggy", "tank"]):
				continue
			var id: int = v.get_instance_id()
			var pos: Vector2 = (v as Node2D).global_position
			var tr: Dictionary = _track.get(id, {"a": pos, "t": 0.0, "w": int(v.get("wedge_resets"))})
			if not v.get("alive") or pos.distance_to(tr["a"]) > 20.0 or _supported(v):
				tr["a"] = pos
				tr["t"] = 0.0
			else:
				tr["t"] = float(tr["t"]) + delta
				_worst = maxf(_worst, float(tr["t"]))
			_track[id] = tr
			if int(v.get("drive_ban_t")) > 0 and not v.has_meta("ban_seen"):
				v.set_meta("ban_seen", true)
				_brakes += 1
			elif int(v.get("drive_ban_t")) == 0 and v.has_meta("ban_seen"):
				v.remove_meta("ban_seen")
		if _t >= _match_secs:
			for v in get_nodes_in_group("vehicle"):
				if is_instance_valid(v) and v.get("wedge_resets") != null:
					_resets += int(v.get("wedge_resets"))
			_log.append("match %ds: longest wedge %.1fs, wedge resets %d, bot give-ups %d" % [int(_match_secs), _worst, _resets, _brakes])
			if _worst > LIMIT:
				_bad.append("a buggy stayed wedged %.1fs in the bot match" % _worst)
			return _end("")
	return false


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	print("WEDGE-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
	quit()
	return true
