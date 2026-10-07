extends SceneTree
## Runtime nav reachability audit (CTF): for every map, using the flags'
## real in-game homes and team spawns, can each side path to the enemy flag
## and carry it back home?  Prints one line per broken map + a summary.
##   godot --headless -s tools/nav_check.gd -- [--from=0] [--to=999]

var _from := 0
var _to := 999
var _idx := 0
var _frames := 0
var _loaded := false
var _count := -1
var _bad := 0
var _checked := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from="): _from = int(a.substr(7))
		elif a.begins_with("--to="): _to = int(a.substr(5))
	_idx = _from


func _ok(nav, a: Vector2, b: Vector2) -> bool:
	var p: PackedVector2Array = nav.path(a, b)
	return p.size() > 0 and p[p.size() - 1].distance_to(b) < 260.0


func _process(_d: float) -> bool:
	var st := root.get_node_or_null("Settings")
	if st == null:
		return false
	if not _loaded:
		st.set("custom_map_path", "")
		st.set("map_index", _idx)
		st.set("game_mode", 2)
		change_scene_to_file("res://scenes/main.tscn")
		_loaded = true
		_frames = 0
		return false
	_frames += 1
	var m := current_scene
	if m == null or m.get("MAPS") == null or _frames < 4:
		return false
	if _count < 0:
		_count = (m.get("MAPS") as Array).size()
	var nav = m.get("nav")
	var flags: Array = m.get("flags")
	var name := str((m.get("_map") as Dictionary).get("name", "?"))
	_checked += 1
	if nav == null or nav.is_empty() or flags.size() < 2:
		print("map %3d %-14s NO-NAV" % [_idx, name])
		_bad += 1
	else:
		var home := {}
		for f in flags:
			home[int(f.get_meta("team"))] = f.get_meta("home")
		var probs: PackedStringArray = PackedStringArray()
		for t in [1, 2]:
			var e: int = 2 if t == 1 else 1
			var sp: Array = m._team_spawn_list(t)
			var s: Vector2 = sp[0] if not sp.is_empty() else home[t]
			s = m._settle_on_ground(s)
			if not _ok(nav, s, home[e]):
				var pp: PackedVector2Array = nav.path(s, home[e])
				var na: int = nav.nearest(s)
				var nb: int = nav.nearest(home[e], 900.0)
				probs.append("T%d spawn%s->enemy flag%s (node %s comp %d -> node %s comp %d)" % [t, Vector2i(s), Vector2i(home[e]), (Vector2i(nav.point(na)) if na >= 0 else Vector2i(-1, -1)), (nav._comp[na] if na >= 0 else -1), (Vector2i(nav.point(nb)) if nb >= 0 else Vector2i(-1, -1)), (nav._comp[nb] if nb >= 0 else -1)])
			if not _ok(nav, home[e], home[t]):
				probs.append("T%d enemy flag->home" % t)
		# Other modes' objectives (INF/HTF flag, Rambo bow, DOM points) must be
		# reachable from a spawn, and the spawn reachable back from them.
		var md: Dictionary = m.get("_map")
		var objs: Array = []
		for k in ["inf_flag", "htf_flag", "rambo_pos"]:
			if md.has(k):
				objs.append([k, md[k]])
		var di := 0
		for dp in md.get("dom_points", []):
			objs.append(["dom%d" % di, dp])
			di += 1
		var sp1: Array = m._team_spawn_list(1)
		var base: Vector2 = m._settle_on_ground(sp1[0] if not sp1.is_empty() else home[1])
		for o in objs:
			var op: Vector2 = m._settle_on_ground(o[1])
			# Reachable from a team spawn and back to one (any of them: some
			# maps split spawns between levels, or put one on a jet-only ledge).
			var out := false
			var back := false
			for sp_pt in (sp1 if not sp1.is_empty() else [base]):
				var g: Vector2 = m._settle_on_ground(sp_pt)
				out = out or _ok(nav, g, op)
				back = back or _ok(nav, op, g)
				if out and back:
					break
			if not out or not back:
				probs.append("OBJ %s%s" % [o[0], Vector2i(op)])
		if not probs.is_empty():
			_bad += 1
			print("map %3d %-14s %s" % [_idx, name, ", ".join(probs)])
	_idx += 1
	if _idx > _to or _idx >= _count:
		print("NAVCHECK checked=%d broken=%d" % [_checked, _bad])
		quit()
		return true
	_loaded = false
	return false
