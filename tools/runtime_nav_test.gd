extends SceneTree
## Runtime bot navigation (#287, gate stage F).
##   godot --headless --fixed-fps 60 -s tools/runtime_nav_test.gd
## A map with no baked graph (a classic map saved as a custom map under a new
## name, then a map from the editor's generator) must get a graph built in-game
## on a worker thread: non-empty, adopted within the time limit, every CTF leg
## (each team's spawn -> enemy flag -> home) routable, bots actually travel on
## it, and the build must not stall the main thread (frame gaps stay small).
## Zero script errors (the gate greps the log).

const LIMIT_MS := 20000
var _st := 0
var _n := 0
var _t0 := 0
var _bad: Array = []
var _log: Array = []
var _saved := []
var _start_pos := {}
var _last_pos := {}
var _dist := {}
var _max_gap := 0
var _last_ms := 0
var _case := 0
var _cases := ["classic", "generated"]


func _write_custom(kind: String) -> String:
	var m: Dictionary = {}
	var io = load("res://scripts/map_io.gd")
	if kind == "classic":
		var f := FileAccess.open("res://assets/maps/arena.json", FileAccess.READ)
		m = io.json_to_map(f.get_as_text())
		m["name"] = "RTNav Classic Copy"
	else:
		m = load("res://scripts/map_gen.gd").generate(4242)
		m["name"] = "RTNav Generated"
	return io.save_to_file(str(m["name"]), m)


func _ok(nav, a: Vector2, b: Vector2) -> bool:
	var p: PackedVector2Array = nav.path(a, b)
	return p.size() > 0 and p[p.size() - 1].distance_to(b) < 260.0


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	var now := Time.get_ticks_msec()
	if _last_ms > 0 and _st == 2:
		_max_gap = maxi(_max_gap, now - _last_ms)
	_last_ms = now
	match _st:
		0:
			if _saved.is_empty():
				_saved = [st.custom_map_path, st.game_mode, st.bot_count, st.map_index]
			var path := _write_custom(_cases[_case])
			if path == "":
				return _end("could not save the %s test map" % _cases[_case])
			st.custom_map_path = path
			st.game_mode = 2
			st.bot_count = 6
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 1
			_n = 0
		1:
			var m = current_scene
			if m == null or m.get("nav") == null or _n < 3:
				return false
			if not m.nav.is_empty():
				_bad.append("%s: graph present before the runtime build (stale bake?)" % _cases[_case])
			_t0 = now
			_max_gap = 0
			_st = 2
		2:
			var m = current_scene
			if m.nav.is_empty():
				if now - _t0 > LIMIT_MS:
					return _end("%s: no runtime graph after %d ms" % [_cases[_case], LIMIT_MS])
				return false
			_log.append("%s graph %d ms (frame gap max %d ms)" % [_cases[_case], int(m.nav_runtime_ms), _max_gap])
			if _max_gap > 400:
				_bad.append("%s: main thread stalled %d ms during the build" % [_cases[_case], _max_gap])
			# CTF legs
			var home := {}
			for f in m.flags:
				home[int(f.get_meta("team"))] = f.get_meta("home")
			if home.size() >= 2:
				for t in [1, 2]:
					var e: int = 2 if t == 1 else 1
					var sp: Array = m._team_spawn_list(t)
					var s: Vector2 = m._settle_on_ground(sp[0] if not sp.is_empty() else home[t])
					if not _ok(m.nav, s, home[e]):
						_bad.append("%s: T%d spawn -> enemy flag unroutable" % [_cases[_case], t])
					if not _ok(m.nav, home[e], home[t]):
						_bad.append("%s: T%d enemy flag -> home unroutable" % [_cases[_case], t])
			_start_pos.clear()
			_last_pos.clear()
			_dist.clear()
			for b in m.get_tree().get_nodes_in_group("soldier"):
				if is_instance_valid(b) and b != m.player:
					_start_pos[b.get_instance_id()] = b.global_position
			_t0 = now
			_n = 0
			_st = 3
		3:
			# accumulate how far each bot walks / flies (defenders patrol, so
			# distance travelled says more than displacement)
			for b in current_scene.get_tree().get_nodes_in_group("soldier"):
				var id: int = b.get_instance_id()
				if not is_instance_valid(b) or not _start_pos.has(id):
					continue
				var last: Vector2 = _last_pos.get(id, b.global_position)
				var step: float = b.global_position.distance_to(last)
				if step < 60.0:          # ignore respawn teleports
					_dist[id] = float(_dist.get(id, 0.0)) + step
				_last_pos[id] = b.global_position
			if _n < 60 * 25:
				return false
			var m = current_scene
			var moved := 0
			var total := 0
			for b in m.get_tree().get_nodes_in_group("soldier"):
				if not is_instance_valid(b) or not _start_pos.has(b.get_instance_id()):
					continue
				total += 1
				if float(_dist.get(b.get_instance_id(), 0.0)) > 900.0:
					moved += 1
			_log.append("%s bots travelled %d/%d" % [_cases[_case], moved, total])
			if total == 0 or moved * 2 < total:
				_bad.append("%s: bots didn't travel (%d/%d covered > 900 px)" % [_cases[_case], moved, total])
			_case += 1
			if _case >= _cases.size():
				return _end("")
			_st = 0
	return false


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	var st = root.get_node_or_null("Settings")
	if st != null and not _saved.is_empty():
		st.custom_map_path = _saved[0]
		st.game_mode = _saved[1]
		st.bot_count = _saved[2]
		st.map_index = _saved[3]
		st.save()
	var ok := _bad.is_empty()
	print("RTNAV-TEST %s %s%s" % ["ok" if ok else "FAIL", " | ".join(_log), "" if ok else " | " + "; ".join(_bad)])
	quit(0 if ok else 1)
	return true
