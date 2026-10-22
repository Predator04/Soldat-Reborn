extends SceneTree
## Dev tool (#314, not in the gate): watch bots play Zombie.
##   godot --headless --fixed-fps 60 -s tools/zombie_watch.gd -- (--level=slug | --map=N) [--bots=8] [--secs=600] [--trace] [--out=file.jsonl] [--seed=N]
## Bots only: the local player is parked out of the match (out of group
## "soldier", match_zombie.exclude_local). Prints the ZOMBIE lines from
## match_zombie.gd as they happen, then WATCH ROUND per round and a summary:
## rounds, human / zombie round wins, why, round lengths, turns (by claws /
## other), deaths by weapon, score. Stops at --secs or the match end (the
## vote's map change can't leak in). --out appends one JSON line per run
## (match_zombie.round_log + totals) — batch runs and total the lines with
## tools/zombie_report.py. --trace prints every bot's side / goal each 10 s.

var _level := ""
var _map := 19
var _bots := 8
var _secs := 600.0
var _trace := false
var _st := 0
var _t := 0.0
var _trace_t := 0.0
var _deaths := {}
var _out := ""
var _seed := -1
var _logged := 0
var _m: Node = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): _level = a.substr(8)
		elif a.begins_with("--map="): _map = int(a.substr(6))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a == "--trace": _trace = true
		elif a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--seed="): _seed = int(a.substr(7))
	if _seed >= 0:
		seed(_seed)


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	match _st:
		0:
			st.game_mode = 11
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
			if m == null or m.get("_zombie") == null or not m._zombie.active():
				return false
			m._zombie.exclude_local = true
			if m.player != null and is_instance_valid(m.player):
				m.player.remove_from_group("soldier")
				m.player.global_position = Vector2(-600, -600)
				m.player.set_physics_process(false)
			m.kill.connect(func(_k, _v, w, _kt, _vt) -> void:
				_deaths[str(w)] = int(_deaths.get(str(w), 0)) + 1)
			_m = m
			print("WATCH map=%s nav=%s bots=%d" % [str(m._map.get("name", "?")), str(not m.nav.is_empty()), _bots])
			_st = 2
			return false
		2:
			var m = current_scene
			if m != _m:
				_finish(_m if is_instance_valid(_m) else null)
				return true
			_t += d
			_trace_t += d
			var z = m._zombie
			while _logged < z.round_log.size():
				var r: Dictionary = z.round_log[_logged]
				_logged += 1
				print("WATCH ROUND %d %s (%s) len=%.1f start=%dh/%dz turns=%d" % [int(r["round"]), str(r["winner"]), str(r["why"]),
					float(r["secs"]), int(r["start_humans"]), int(r["start_zombies"]), int(r["turns"])])
			if _trace and _trace_t >= 10.0:
				_trace_t = 0.0
				var parts: Array = []
				for b in get_nodes_in_group("soldier"):
					if is_instance_valid(b):
						parts.append("%s %s %s %s%s" % [str(b.get("display_name")).replace("Bot ", "B"), "Z" if int(b.get("team")) == 2 else "H",
							str(Vector2i(b.global_position)), str(b.get("_goal_label")), " DEAD" if bool(b.get("dead")) else ""])
				print("TRACE %.0fs r%d %s hl=%d %s | %s" % [_t, z.round_no, z.phase, z.humans_left, str(m.scores), " | ".join(parts)])
			if _t < _secs and not bool(m.match_over):
				return false
			_finish(m)
			return true
	return false


func _finish(m) -> void:
	var z = m._zombie if m != null else null
	var rounds: Array = z.round_log if z != null else []
	var hw := 0
	for r in rounds:
		if str(r["winner"]) == "human":
			hw += 1
	var nm := str(m._map.get("name", "?")) if m != null else "?"
	print("WATCH SUMMARY map=%s secs=%d rounds=%d human=%d zombie=%d turns=%d claw_turns=%d score=%s deaths=%s" % [
		nm, int(_t), rounds.size(), hw, rounds.size() - hw, int(z.stats["turns"]) if z != null else 0,
		int(z.stats["claw_turns"]) if z != null else 0, str(m.scores) if m != null else "{}", str(_deaths)])
	if _out != "":
		var line := JSON.stringify({"map": nm, "level": _level, "secs": int(_t), "bots": _bots, "rounds": rounds,
			"turns": int(z.stats["turns"]) if z != null else 0, "deaths": _deaths})
		var f := FileAccess.open(_out, FileAccess.READ_WRITE) if FileAccess.file_exists(_out) else FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
			f.close()
	quit(0)
