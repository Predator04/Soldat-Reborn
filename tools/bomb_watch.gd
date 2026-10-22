extends SceneTree
## Dev tool (#304, not in the gate): watch bots play Bomb Defusal.
##   godot --headless --fixed-fps 60 -s tools/bomb_watch.gd -- (--level=slug | --map=N) [--bots=8] [--secs=300] [--trace]
## The local player is parked out of the match (out of group "soldier"), so
## it's bots only. Prints each BOMB line from match_bomb.gd as it happens and a
## summary: rounds, plants, defuses, detonations, timeouts, drops / pickups,
## deaths by cause, score; --trace adds every bot's goal + position each 10 s.

var _level := ""
var _map := 19
var _bots := 8
var _secs := 300.0
var _trace := false
var _n := 0
var _st := 0
var _t := 0.0
var _trace_t := 0.0
var _deaths := {}
var _first := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): _level = a.substr(8)
		elif a.begins_with("--map="): _map = int(a.substr(6))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a == "--trace": _trace = true


func _process(d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	match _st:
		0:
			st.game_mode = 10
			st.bot_count = _bots
			st.custom_map_path = ""
			st.map_index = _map
			if _level != "":
				st.custom_map_path = load("res://scripts/featured_levels.gd").local_copy(_level)
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 1
			return false
		1:
			var m = current_scene
			if m == null or m.get("_bomb") == null or not m._bomb.active():
				return false
			if m.player != null and is_instance_valid(m.player):
				m.player.remove_from_group("soldier")
				m.player.global_position = Vector2(-600, -600)
				m.player.set_physics_process(false)
			m.kill.connect(func(_k, _v, w, _kt, _vt) -> void:
				_deaths[str(w)] = int(_deaths.get(str(w), 0)) + 1)
			m.objective.connect(func(kind: String, _tm: int, _who: String) -> void:
				if not _first.has(kind):
					_first[kind] = snappedf(_t, 0.1))
			var s: Array = []
			for site in m._bomb.sites:
				s.append("%s %s" % [site["name"], str(site["rect"])])
			print("WATCH map=%s sites=%s nav=%s" % [str(m._map.get("name", "?")), ", ".join(s), str(not m.nav.is_empty())])
			_st = 2
			return false
		2:
			var m = current_scene
			_t += d
			_trace_t += d
			if _trace and _trace_t >= 10.0:
				_trace_t = 0.0
				var parts: Array = []
				for b in get_nodes_in_group("soldier"):
					if is_instance_valid(b):
						parts.append("%s t%d %s %s%s" % [str(b.get("display_name")).replace(" Bot ", ""), int(b.get("team")),
							str(Vector2i(b.global_position)), str(b.get("_goal_label")), " DEAD" if bool(b.get("dead")) else ""])
				var b = m._bomb
				print("TRACE %.0fs r%d %s %s bomb=%s %s | %s" % [_t, b.round_no, b.phase, str(m.scores), b.bomb_state,
					str(Vector2i(b.bomb_pos)), " | ".join(parts)])
			if _t < _secs:
				return false
			var b = m._bomb
			print("WATCH SUMMARY map=%s secs=%d rounds=%d plants=%d defuses=%d booms=%d timeouts=%d drops=%d pickups=%d score=%s round_no=%d first=%s deaths=%s" % [
				str(m._map.get("name", "?")), int(_t), int(b.stats["rounds"]), int(b.stats["plants"]), int(b.stats["defuses"]),
				int(b.stats["booms"]), int(b.stats["timeouts"]), int(b.stats["drops"]), int(b.stats["pickups"]), str(m.scores),
				b.round_no, str(_first), str(_deaths)])
			quit(0)
			return true
	return false
