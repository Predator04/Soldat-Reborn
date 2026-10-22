extends SceneTree
## Dev tool (#304, not in the gate): watch bots play Bomb Defusal.
##   godot --headless --fixed-fps 60 -s tools/bomb_watch.gd -- (--level=slug | --map=N) [--bots=8] [--secs=300] [--trace] [--out=file.jsonl] [--seed=N]
## The local player is parked out of the match (out of group "soldier"), so
## it's bots only. Prints each BOMB line from match_bomb.gd as it happens and a
## summary: rounds, plants, defuses, detonations, timeouts, drops / pickups,
## deaths by cause, score; --trace adds every bot's goal + position each 10 s.
## #307: also round wins by SIDE (attack / defense, halftime-aware), why each
## round ended and the time from round start to the plant; --out appends one
## JSON line per run (batch several runs and total the lines).

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
var _out := ""
var _seed := -1
var _round_t0 := 0.0
var _plant_t := -1.0
var _rounds: Array = []
var _m: Node = null   # [{"side": "att"|"def", "why", "plant": secs or -1, "len": secs}]


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
			_m = m
			m.objective.connect(_on_objective)
			var s: Array = []
			for site in m._bomb.sites:
				s.append("%s %s" % [site["name"], str(site["rect"])])
			print("WATCH map=%s sites=%s nav=%s auto=%s" % [str(m._map.get("name", "?")), ", ".join(s), str(not m.nav.is_empty()), str(m._bomb.auto_info)])
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
			var att := 0
			var plants: Array = []
			for r in _rounds:
				if str(r["side"]) == "att":
					att += 1
				if float(r["plant"]) >= 0.0:
					plants.append(float(r["plant"]))
			print("WATCH SIDES map=%s rounds=%d attack=%d defense=%d plant_times=%s" % [str(m._map.get("name", "?")),
				_rounds.size(), att, _rounds.size() - att, str(plants)])
			if _out != "":
				var line := JSON.stringify({"map": str(m._map.get("name", "?")), "level": _level, "secs": int(_t),
					"rounds": _rounds, "plants": int(b.stats["plants"]), "defuses": int(b.stats["defuses"]),
					"booms": int(b.stats["booms"]), "timeouts": int(b.stats["timeouts"]), "drops": int(b.stats["drops"]),
					"sites": _site_txt(m)})
				var f := FileAccess.open(_out, FileAccess.READ_WRITE) if FileAccess.file_exists(_out) else FileAccess.open(_out, FileAccess.WRITE)
				if f != null:
					f.seek_end()
					f.store_line(line)
					f.close()
			quit(0)
			return true
	return false


func _site_txt(m) -> String:
	var s: Array = []
	for site in m._bomb.sites:
		var r: Rect2 = site["rect"]
		s.append("%s(%d,%d)" % [site["name"], int(r.get_center().x), int(r.end.y)])
	return " ".join(s)


func _on_objective(kind: String, tm: int, who: String) -> void:
	if not _first.has(kind):
		_first[kind] = snappedf(_t, 0.1)
	match kind:
		"bomb_start":
			_round_t0 = _t
			_plant_t = -1.0
		"bomb_plant":
			_plant_t = snappedf(_t - _round_t0, 0.1)
		"bomb_round":
			var side := "att" if tm == int(_m._bomb.attack_team()) else "def"
			_rounds.append({"side": side, "why": who, "plant": _plant_t, "len": snappedf(_t - _round_t0, 0.1),
				"site": str(_m._bomb.planted_site) if _plant_t >= 0.0 else "", "bot_site": str(_m._bomb.bot_site)})
			print("WATCH ROUND %d %s (%s) plant=%.1f len=%.1f" % [_rounds.size(), side, who, _plant_t, _t - _round_t0])
