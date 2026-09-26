extends SceneTree
## Map editor round trip: place one of everything, save, reload (counts must
## match), move + delete, generate, then Play-test the saved map for a few
## seconds with the autopilot-free player. Any error in the log fails it.
##   godot --headless -s tools/editor_test.gd

var _n := 0
var _phase := 0
var _t := 0.0
var _counts := {}


var _saw_player := false


func _count(m: Dictionary) -> Dictionary:
	var out := {}
	for k in ["platforms", "ladders", "bot_spawns", "ctf_flags", "dom_points", "m2_mounts", "polys",
			"scenery", "weapon_pickups", "bonus_spawns", "point_spawns"]:
		out[k] = (m.get(k, []) as Array).size()
	for k in ["inf_flag", "htf_flag", "rambo_pos", "player_spawn"]:
		out[k] = m.get(k) != null
	return out


func _process(delta: float) -> bool:
	_n += 1
	if _phase == 0:
		change_scene_to_file("res://scenes/map_editor.tscn")
		_phase = 1
		return false
	var e := current_scene
	if _phase == 1:
		if e == null or not e.has_method("_on_lmb_press") or _n < 5:
			return false
		var T = e.Tool
		e._new_map()
		# Platforms via drag + a default-size click.
		e._set_tool(T.PLATFORM)
		e._on_lmb_press(Vector2(400, 1700)); e._dragging = true; e._on_lmb_release(Vector2(1400, 1740))
		e._on_lmb_press(Vector2(2000, 1500)); e._on_lmb_release(Vector2(2000, 1500))
		e._set_tool(T.LADDER)
		e._on_lmb_press(Vector2(1500, 1400)); e._on_lmb_release(Vector2(1520, 1700))
		for spec in [[T.PLAYER_SPAWN, Vector2(600, 1600)], [T.BOT_SPAWN, Vector2(800, 1600)], [T.BOT_SPAWN, Vector2(1200, 1600)],
				[T.FLAG_BLUE, Vector2(500, 1680)], [T.FLAG_RED, Vector2(1300, 1680)], [T.FLAG_NEUTRAL, Vector2(900, 1680)],
				[T.DOM_POINT, Vector2(700, 1650)], [T.DOM_POINT, Vector2(900, 1650)], [T.DOM_POINT, Vector2(1100, 1650)],
				[T.M2_MOUNT, Vector2(1000, 1690)], [T.SCENERY, Vector2(650, 1690)], [T.WEAPON_PICKUP, Vector2(750, 1690)],
				[T.BONUS_BOX, Vector2(850, 1690)], [T.POINT_PICKUP, Vector2(950, 1690)], [T.RAMBO, Vector2(1050, 1690)],
				[T.INF_FLAG, Vector2(1150, 1690)], [T.HTF_FLAG, Vector2(1250, 1690)]]:
			e._set_tool(spec[0])
			e._on_lmb_press(spec[1])
		e._set_tool(T.TERRAIN_POLY)
		for v in [Vector2(2400, 1800), Vector2(3000, 1800), Vector2(2700, 1500)]:
			e._on_lmb_press(v)
		e._commit_terrain_poly()
		# Move the red flag, delete a bot spawn.
		e._set_tool(T.MOVE)
		e._on_lmb_press(Vector2(1300, 1680)); e._on_lmb_release(Vector2(1340, 1680))
		e._set_tool(T.DELETE)
		e._on_lmb_press(Vector2(1200, 1600))
		_counts = _count(e._map)
		e._name_edit.text = "qa_editor_roundtrip"
		e._save_map()
		e._new_map()
		var path := ""
		for f in e.MapIO.list_files():
			if str(f).ends_with("qa_editor_roundtrip.json"):
				path = str(f)
		e._load_map(path)
		var after := _count(e._map)
		print("EDITOR-TEST roundtrip ", "ok" if after == _counts else "MISMATCH %s vs %s" % [str(_counts), str(after)])
		e._generate()
		e._load_map(path)
		e._play_test()
		_phase = 2
		_t = 0.0
		return false
	if _phase == 2:
		_t += delta
		if e != null and e.get("MAPS") != null and int(_t * 2.0) != int((_t - delta) * 2.0):
			var pp = e.get("player")
			print("  t=%.1f player=%s soldiers=%d fell=%s" % [_t, str(pp != null and is_instance_valid(pp) and not bool(pp.get("dead"))), get_nodes_in_group("soldier").size(), str((e.get("safety_stats") as Dictionary).get("fell", -1))])
		if e != null and e.get("MAPS") != null:
			var pv = e.get("player")
			if pv != null and is_instance_valid(pv):
				_saw_player = true   # bots may have killed it by the 6 s mark
		if e != null and e.get("MAPS") != null and _t > 6.0:
			print("EDITOR-TEST playtest ok map=%s player=%s" % [str((e.get("_map") as Dictionary).get("name", "?")), str(_saw_player)])
			# Don't leave the play-test map selected in this machine's settings.
			var st := root.get_node_or_null("Settings")
			if st != null:
				st.set("custom_map_path", "")
				st.call("save")
			quit()
			return true
	return false
