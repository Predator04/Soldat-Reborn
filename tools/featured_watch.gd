extends SceneTree
## Dev tool (#295, not in the gate): watch bots play a FEATURED level.
##   godot --headless --fixed-fps 60 -s tools/featured_watch.gd -- --level=twin_forts --mode=ctf [--bots=8] [--secs=120]
## Prints the runtime nav graph, routability of the mode's legs, then after
## `secs`: objective events (grab / capture / dom ...), deaths by cause (incl.
## spikes / lava / falls), jump-pad launches, vehicle boardings + distance,
## how far bots travelled, how often they stood still, final scores.

const MODE_IDX := {"dm": 0, "tdm": 1, "ctf": 2, "inf": 3, "htf": 4, "rm": 5, "pm": 6, "dom": 7, "br": 8, "gg": 9, "bomb": 10}

var _level := "twin_forts"
var _mode := "ctf"
var _bots := 8
var _secs := 120.0
var _n := 0
var _st := 0
var _t := 0.0
var _events := {}
var _deaths := {}
var _launch0 := 0
var _hz0 := 0
var _dist := {}
var _last := {}
var _still := 0
var _samples := 0
var _win_pos := {}
var _win_t := 0.0
var _veh := {}       # id -> {kind, board, dist, last, drv}
var _rounds := 0
var _alt := 0.0
var _trace := false
var _trace_t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): _level = a.substr(8)
		elif a.begins_with("--mode="): _mode = a.substr(7)
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a == "--trace": _trace = true


func _ok(nav, a: Vector2, b: Vector2) -> bool:
	var p: PackedVector2Array = nav.path(a, b)
	return p.size() > 0 and p[p.size() - 1].distance_to(b) < 260.0


func _process(d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	match _st:
		0:
			var FL = load("res://scripts/featured_levels.gd")
			var path: String = FL.local_copy(_level)
			if path == "":
				print("WATCH no such level ", _level)
				quit(1)
				return true
			st.custom_map_path = path
			st.game_mode = int(MODE_IDX[_mode])
			st.bot_count = _bots
			st.vehicles = true
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 1
			return false
		1:
			var m = current_scene
			if m == null or m.get("nav") == null or m.nav.is_empty():
				return false
			_report_nav(m)
			m.objective.connect(func(kind: String, team: int, _who: String) -> void:
				var k := "%s/%d" % [kind, team]
				_events[k] = int(_events.get(k, 0)) + 1)
			m.kill.connect(func(_k, _v, w, _kt, _vt) -> void:
				_deaths[str(w)] = int(_deaths.get(str(w), 0)) + 1)
			var hz = m.get("_hazards")
			_launch0 = int(hz.bot_launches) if hz != null else 0
			_hz0 = int(hz.kills) if hz != null else 0
			_st = 2
			_t = 0.0
			return false
		2:
			var m = current_scene
			_t += d
			_trace_t += d
			if _trace and _trace_t >= 10.0:
				_trace_t = 0.0
				var parts: Array = []
				for b in get_nodes_in_group("soldier"):
					if is_instance_valid(b) and b != m.player:
						var pth: PackedVector2Array = b.get("_path")
						var pi: int = int(b.get("_path_i"))
						var nx: Array = []
						for k in range(pi, mini(pi + 3, pth.size())):
							nx.append(str(Vector2i(pth[k])))
						parts.append("%s t%d %s %s hp%d%s wp[%s]" % [str(b.get("display_name")), int(b.get("team")), str(Vector2i(b.global_position)),
							str(b.get("_goal_label")), int(b.get("health")), " DEAD" if bool(b.get("dead")) else "", ",".join(nx)])
				print("TRACE %.0fs round=%s scores=%s | %s" % [_t, str(m.get("round_active")), str(m.scores), " | ".join(parts)])
			for b in get_nodes_in_group("soldier"):
				if not is_instance_valid(b) or b == m.player:
					continue
				var id: int = b.get_instance_id()
				var gp: Vector2 = b.global_position
				var step: float = gp.distance_to(_last.get(id, gp))
				if step < 60.0:
					_dist[id] = float(_dist.get(id, 0.0)) + step
				_last[id] = gp
			_win_t += d
			if _win_t >= 8.0:
				_win_t = 0.0
				for b in get_nodes_in_group("soldier"):
					if not is_instance_valid(b) or b == m.player or bool(b.get("dead")):
						continue
					var id: int = b.get_instance_id()
					if _win_pos.has(id):
						_samples += 1
						if (b.global_position as Vector2).distance_to(_win_pos[id]) < 50.0:
							_still += 1
					_win_pos[id] = b.global_position
			for v in get_nodes_in_group("vehicle"):
				if not is_instance_valid(v) or not v.has_method("driver"):
					continue
				var vid: int = v.get_instance_id()
				if not _veh.has(vid):
					_veh[vid] = {"kind": str(v.get("kind")) if v.get("kind") != null else str(v.name), "board": 0, "dist": 0.0,
						"last": (v as Node2D).global_position, "drv": null, "name": str(v.name)}
				var s: Dictionary = _veh[vid]
				var drv = v.driver()
				var vp: Vector2 = (v as Node2D).global_position
				if drv != null and drv != m.player:
					if s["drv"] != drv:
						s["board"] = int(s["board"]) + 1
					var stp: float = vp.distance_to(s["last"])
					if stp < 80.0:
						s["dist"] = float(s["dist"]) + stp
				s["drv"] = drv
				s["last"] = vp
			if _t >= _secs:
				_report(m)
				quit()
				return true
	return false


func _report_nav(m) -> void:
	var nav = m.nav
	var probs: Array = []
	var md: Dictionary = m.get("_map")
	var home := {}
	for f in m.flags:
		if f.has_meta("team"):
			home[int(f.get_meta("team"))] = f.get_meta("home")
	var legs := 0
	if _mode == "ctf" and home.size() >= 2:
		for t in [1, 2]:
			var e: int = 2 if t == 1 else 1
			for sp in m._team_spawn_list(t):
				var s: Vector2 = m._settle_on_ground(sp)
				legs += 2
				if not _ok(nav, s, home[e]):
					probs.append("T%d spawn%s->flag" % [t, Vector2i(s)])
				if not _ok(nav, home[e], s):
					probs.append("T%d flag->spawn%s" % [t, Vector2i(s)])
			legs += 1
			if not _ok(nav, home[e], home[t]):
				probs.append("T%d enemy flag->home" % t)
	var objs: Array = []
	if _mode == "dom":
		for dp in md.get("dom_points", []):
			objs.append(dp)
	for k in ["inf_flag", "htf_flag", "rambo_pos"]:
		if _mode == {"inf_flag": "inf", "htf_flag": "htf", "rambo_pos": "rm"}[k] and md.has(k):
			objs.append(md[k])
	for o in objs:
		var op: Vector2 = m._settle_on_ground(o)
		for t in [1, 2]:
			for sp in m._team_spawn_list(t):
				var s: Vector2 = m._settle_on_ground(sp)
				legs += 2
				if not _ok(nav, s, op):
					probs.append("T%d spawn%s->obj%s" % [t, Vector2i(s), Vector2i(op)])
				if not _ok(nav, op, s):
					probs.append("T%d obj%s->spawn%s" % [t, Vector2i(op), Vector2i(s)])
	print("WATCH %s %s nav nodes=%d legs=%d broken=%d %s ms=%d" % [_level, _mode, nav._pts.size(), legs, probs.size(), ", ".join(probs), int(m.nav_runtime_ms)])


func _report(m) -> void:
	var hz = m.get("_hazards")
	var moved := 0
	var total := 0
	var tot_d := 0.0
	for id in _dist:
		total += 1
		tot_d += float(_dist[id])
		if float(_dist[id]) > 1500.0:
			moved += 1
	var vs: Array = []
	for vid in _veh:
		var s: Dictionary = _veh[vid]
		vs.append("%s:%dx/%dpx" % [s["name"], int(s["board"]), int(s["dist"])])
	print("WATCH %s %s %ds events=%s" % [_level, _mode, int(_secs), str(_events)])
	print("WATCH deaths=%s hazard_kills=%d %s" % [str(_deaths), (int(hz.kills) - _hz0) if hz != null else 0, str(hz.kill_log) if hz != null else ""])
	print("WATCH pad_launches=%d travelled=%d/%d avg=%dpx still=%d/%d scores=%s" % [(int(hz.bot_launches) - _launch0) if hz != null else 0,
		moved, total, int(tot_d / maxf(1.0, total)), _still, _samples, str(m.scores)])
	if not vs.is_empty():
		print("WATCH vehicles ", " ".join(vs))
