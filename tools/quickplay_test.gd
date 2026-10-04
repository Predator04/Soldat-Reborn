extends SceneTree
## Quick Play (gate stage F): with no reachable game online, the main-menu
## QUICK PLAY button drops you straight into a bot match.
##   godot --headless -s tools/quickplay_test.gd

var _n := 0
var _st := 0
var _saved := []
var _t0 := 0


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _st == 0:
		_saved = [st.master_url, st.player_name, st.name_set]
		st.master_url = "http://127.0.0.1:9"   # nothing listens there
		st.player_name = "Tester"
		st.name_set = true
		change_scene_to_file("res://scenes/menu.tscn")
		_st = 1
		return false
	var m = current_scene
	if _st == 1:
		if m == null or m.get("_menu_root") == null or _n < 10:
			return false
		var btn: Button = null
		for b in _buttons(m._menu_root):
			if b.text == "QUICK PLAY":
				btn = b
		if btn == null:
			return _end(false, "no QUICK PLAY button on the main menu")
		btn.pressed.emit()
		_t0 = Time.get_ticks_msec()
		_st = 2
		return false
	if _st == 2:
		if m != null and m.scene_file_path.ends_with("main.tscn"):
			var net = root.get_node("Net")
			var bots := 0
			for s in get_nodes_in_group("soldier"):
				if s.get("loadout") != null:
					bots += 1
			if _n % 30 == 0 and bots > 0:
				return _end(not net.is_networked(), "bot match after %d ms, bots=%d networked=%s" % [Time.get_ticks_msec() - _t0, bots, str(net.is_networked())])
		if Time.get_ticks_msec() - _t0 > 20000:
			return _end(false, "still on %s after 20 s" % (m.scene_file_path if m else "?"))
	return false


func _buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out


func _end(ok: bool, msg: String) -> bool:
	var st = root.get_node("Settings")
	st.master_url = _saved[0]
	st.player_name = _saved[1]
	st.name_set = _saved[2]
	print("QUICKPLAY-TEST %s %s" % ["ok" if ok else "FAIL", msg])
	quit(0 if ok else 1)
	return true
