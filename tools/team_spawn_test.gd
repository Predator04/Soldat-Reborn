extends SceneTree
## Team sides check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/team_spawn_test.gd
## Reported: "shouldn't players start on each side of the map?" In team modes
## every map must spawn BLUE by the BLUE flag and RED by the RED flag (ported
## maps had the alpha/bravo groups backwards on ~30 maps), and the human (BLUE)
## must start on BLUE's side, not at a player_spawn inside RED's base.

var _phase := 0
var _t := 0.0


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		st.set("custom_map_path", "")
		st.set("game_mode", 2)  # CTF
		st.set("map_index", 0)  # Airpirates: player_spawn sits by the RED flag
		st.set("bot_count", 4); st.set("survival", false); st.set("advance", false)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += d
	if _t < 1.5:
		return false
	var bad: Array = []
	# The live match: the human and the bots are on their own halves.
	var fl: Array = m.get("flags")
	var bh: Vector2 = fl[0].get_meta("home"); var rh: Vector2 = fl[1].get_meta("home")
	var p = m.get("player")
	if p == null or p.global_position.distance_to(bh) > p.global_position.distance_to(rh):
		bad.append("player spawned on RED's side at %s (blue %s red %s)" % [p.global_position if p else "-", bh, rh])
	for s in get_nodes_in_group("soldier"):
		if s.get("bot_id") == null:
			continue
		var home: Vector2 = bh if int(s.get("team")) == 1 else rh
		var away: Vector2 = rh if int(s.get("team")) == 1 else bh
		if s.global_position.distance_to(home) > s.global_position.distance_to(away) and _t < 3.0:
			bad.append("%s on the wrong side" % s.get("display_name"))
	# Every map: each team's spawn list sits by its own flag.
	var maps: Array = m.get("MAPS")
	var checked := 0
	var saved = m.get("_map")
	for i in maps.size():
		var mp: Dictionary = maps[i]
		var f: Array = mp.get("ctf_flags", [])
		if f.size() < 2:
			continue
		m.set("_map", mp)
		m.call("_normalize_team_sides")
		var b: Array = m.call("_team_spawn_list", 1)
		var r: Array = m.call("_team_spawn_list", 2)
		var cb: Vector2 = m.call("_centroid", b)
		var cr: Vector2 = m.call("_centroid", r)
		checked += 1
		if cb.distance_to(f[0]) > cb.distance_to(f[1]) or cr.distance_to(f[1]) > cr.distance_to(f[0]):
			bad.append("%s: sides swapped" % mp.get("name"))
	m.set("_map", saved)
	print("TEAMSPAWN-TEST %s %s | maps_checked=%d" % ["ok" if bad.is_empty() else "FAIL", bad.slice(0, 6), checked])
	quit()
	return true
