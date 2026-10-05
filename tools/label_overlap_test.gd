extends SceneTree
## Pickup name tags (gate stage F, #185): on maps with kits side by side the
## tags never overlap (identical neighbours show once, different ones stack).
##   godot --headless -s tools/label_overlap_test.gd

const MAPS := ["Voland", "Ash", "Krab", "Arena3", "Rubik"]
var _mi := 0
var _n := 0
var _bad: Array = []
var _log: Array = []


func _process(_d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	var net = root.get_node_or_null("Net")
	if st == null or net == null:
		return false
	if _n == 0:
		if _mi >= MAPS.size():
			print("LABELS-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
			quit(0 if _bad.is_empty() else 1)
			return true
		st.bot_count = 0
		st.game_mode = 2
		st.custom_map_path = ""
		st.map_index = net.MAP_NAMES.find(MAPS[_mi])
		net.set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
	_n += 1
	if _n < 40:
		return false
	var font := ThemeDB.fallback_font
	var rects: Array = []
	for l in get_nodes_in_group("item_label"):
		if bool(l.get("_dup")):
			continue
		var w: float = font.get_string_size(str(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var c: Vector2 = (l as Node2D).global_position - Vector2(0, float(l.lift) + float(l.get("_nudge")))
		rects.append([Rect2(c.x - w * 0.5, c.y - 11, w, 11), str(l.text)])
	var hits := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i][0] as Rect2).grow(-1).intersects((rects[j][0] as Rect2).grow(-1)):
				hits += 1
				_bad.append("%s: '%s' over '%s'" % [MAPS[_mi], rects[i][1], rects[j][1]])
	_log.append("%s:%d tags" % [MAPS[_mi], rects.size()])
	_mi += 1
	_n = 0
	return false
