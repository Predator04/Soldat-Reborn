extends SceneTree
## Leaderboard + Map Library panels against a local master server (gate C,
## run after tools/ranked_test.gd on the same master): the board lists the
## ranked players; a map shared from user://maps can be found and downloaded.
##   godot --headless -s tools/online_panels_test.gd -- --master=http://127.0.0.1:PORT

var _st := 0
var _n := 0
var _t := 0
var _saved_url := ""
var _saved_pid := ""
var _m: Node
var _log: Array = []
const TEST_MAP := "user://maps/zz_library_test.json"


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	match _st:
		0:
			_saved_url = st.master_url
			_saved_pid = st.profile_id
			st.profile_id = "0123456789abcdef0123456789abcdef"   # "Ace" in ranked_test.gd
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--master="):
					st.master_url = a.substr(9)
			var mi = load("res://scripts/map_io.gd")
			mi.save_to_file("zz library test", {"name": "zz library test", "platforms": [{"p": Vector2(0, 500), "s": Vector2(800, 40)}],
				"player_spawn": Vector2(100, 400), "bot_spawns": [Vector2(300, 400), Vector2(600, 400)]})
			change_scene_to_file("res://scenes/menu.tscn")
			_st = 1
		1:
			_m = current_scene
			if _m == null or _m.get("_menu_root") == null or _n < 10:
				return false
			_m._open_leaderboard()
			_t = _n
			_st = 2
		2:
			var lb = _m._lb_panel
			if lb.loaded_rows >= 0 and lb._me.text != "":
				_log.append("board rows=%d" % lb.loaded_rows)
				if lb.loaded_rows < 2:
					return _end(false, "leaderboard rows %d: %s" % [lb.loaded_rows, lb._list.text.left(120)])
				if not lb._me.text.contains("#1"):
					return _end(false, "own rank missing: %s" % lb._me.text.left(120))
				lb.visible = false
				lb.closed.emit()
				_m._open_map_library()
				_st = 3
			elif _n - _t > 600:
				return _end(false, "leaderboard never loaded")
		3:
			var lib = _m._lib_panel
			if lib.loaded_rows < 0:
				return false
			lib.share_file(TEST_MAP)
			_t = _n
			_st = 4
		4:
			var lib = _m._lib_panel
			if not lib.last_upload.is_empty() and lib.loaded_rows >= 0 and _n - _t > 5:
				if not bool(lib.last_upload.get("ok", false)):
					return _end(false, "upload: %s" % str(lib.last_upload))
				_log.append("shared id=%s listed=%d" % [str(lib.last_upload.get("id")), lib.loaded_rows])
				if lib.loaded_rows < 1:
					return _end(false, "shared map not listed")
				lib.download(str(lib.last_upload.get("id")), "zz library test")
				_t = _n
				_st = 5
			elif _n - _t > 600:
				return _end(false, "upload never finished")
		5:
			var lib = _m._lib_panel
			if lib.last_saved != "":
				var mi = load("res://scripts/map_io.gd")
				var mp: Dictionary = mi.load_from_file(lib.last_saved)
				var ok: bool = (mp.get("platforms", []) as Array).size() == 1
				_log.append("downloaded %s platforms=%d" % [lib.last_saved.get_file(), (mp.get("platforms", []) as Array).size()])
				DirAccess.remove_absolute(lib.last_saved)
				return _end(ok, " | ".join(_log))
			elif _n - _t > 600:
				return _end(false, "download never finished: %s" % lib._status.text)
	return false


func _end(ok: bool, msg: String) -> bool:
	root.get_node("Settings").master_url = _saved_url
	root.get_node("Settings").profile_id = _saved_pid
	DirAccess.remove_absolute(TEST_MAP)
	print("PANELS-TEST %s %s" % ["ok" if ok else "FAIL", msg])
	quit(0 if ok else 1)
	return true
