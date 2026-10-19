extends SceneTree
## HD terrain renders / benchmark (#283; dev tool, not shipped).
##   godot --rendering-driver opengl3 --resolution 1280x720 -s tools/terrain_capture.gd -- \
##       --map=jungle --out=DIR [--shots=3] [--every=90] [--skip=300] [--zoom=1.0]
##       [--at=X,Y] [--style=cinematic|classic] [--quality=2] [--hud] [--bench] --no-perf-guard
## Each shot is saved twice from the same frame state: <map>_<n>_before.png
## (classic terrain under the cinematic look — TerrainHD.suppress) and
## <map>_<n>_after.png (HD terrain). The camera follows a bot that is in a
## fight, or stays at --at. --bench pans a camera across the map for 240
## frames with the HD terrain off, then on, and prints the mean frame time.
var _out := "."
var _map := "jungle"
var _shots := 3
var _every := 90
var _skip := 300
var _zoom := 1.0
var _at := Vector2.INF
var _style := "cinematic"
var _quality := 2
var _nohud := true
var _bench := false
var _bots := 8

var _n := 0
var _saved := 0
var _cam: Camera2D = null
var _focus: Node2D = null
var _phase := 0        # 0 waiting, 1 before saved -> after pending
var _wait := 0
var _hd = null
var _bench_t0 := 0
var _bench_frames := 0
var _bench_res: Array = []
var _bench_dc := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--map="): _map = a.substr(6)
		elif a.begins_with("--shots="): _shots = int(a.substr(8))
		elif a.begins_with("--every="): _every = int(a.substr(8))
		elif a.begins_with("--skip="): _skip = int(a.substr(7))
		elif a.begins_with("--zoom="): _zoom = float(a.substr(7))
		elif a.begins_with("--style="): _style = a.substr(8)
		elif a.begins_with("--quality="): _quality = int(a.substr(10))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a == "--hud": _nohud = false
		elif a == "--bench": _bench = true
		elif a.begins_with("--at="):
			var p := a.substr(5).split(",")
			_at = Vector2(float(p[0]), float(p[1]))
	DirAccess.make_dir_recursive_absolute(_out)


func _map_index() -> int:
	if _map.is_valid_int():
		return int(_map)
	var MapIO = load("res://scripts/map_io.gd")
	var i: int = MapIO.BUNDLED_CLASSICS.find(_map)
	if i >= 0:
		return i + 3
	return ["ascent", "towers", "pillars"].find(_map.to_lower())


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _n == 2:
		st.bot_count = _bots
		st.game_mode = 0
		st.map_index = maxi(0, _map_index())
		st.custom_map_path = ""
		st.name_set = true
		st.player_name = "You"
		st.visual_style = _style
		st.set_gfx_quality(_quality)
		root.get_node("Net").set_singleplayer()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		change_scene_to_file("res://scenes/main.tscn")
		return false
	if _n < _skip:
		return false
	var m = current_scene
	if m == null:
		return false
	if _hd == null:
		_hd = load("res://scripts/gfx/terrain_hd.gd")
	if _n == _skip:
		if m.get("player") != null and is_instance_valid(m.player):
			m.player.ceasefire_t = 9999.0
		_cam = Camera2D.new()
		_cam.zoom = Vector2(_zoom, _zoom)
		m.add_child(_cam)
		_cam.make_current()
		if _nohud and m.get("hud") != null and is_instance_valid(m.hud):
			var ui = m.hud.get_node_or_null("UIRoot")
			if ui != null:
				ui.visible = false
		if _bench:
			_bench_start(m)
	if _bench:
		return _bench_tick(m)
	_track(m)
	if _phase == 1:
		_wait += 1
		if _wait >= 3:
			_save("after")
			_hd.suppress = false
			_phase = 0
			_saved += 1
			if _saved >= _shots:
				quit()
				return true
		return false
	if (_n - _skip) % _every == _every - 1:
		_hd.suppress = true
		_phase = 2
		_wait = 0
		return false
	if _phase == 2:
		_wait += 1
		if _wait >= 3:
			_save("before")
			_hd.suppress = false
			_phase = 1
			_wait = 0
	return false


func _save(tag: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s_%d_%s.png" % [_out, _map, _saved, tag])
	print("saved %s %d %s" % [_map, _saved, tag])


func _track(m) -> void:
	if _cam == null:
		return
	if _at != Vector2.INF:
		_cam.global_position = _at
		return
	if _phase != 0:
		return   # freeze framing while a pair is being taken
	if _focus == null or not is_instance_valid(_focus) or bool(_focus.get("dead")):
		_focus = null
		for b in get_nodes_in_group("soldier"):
			if b.get("loadout") != null and not bool(b.get("dead")) and is_instance_valid(b.get("target")):
				_focus = b
				break
	if _focus != null:
		_cam.global_position = _cam.global_position.lerp(_focus.global_position + Vector2(0, -50), 0.2)


func _bench_start(m) -> void:
	_bench_frames = 0
	_bench_res = []
	_hd.suppress = true


func _bench_tick(m) -> bool:
	# Deterministic pan: left to right across the map at the map's spawn height.
	var w: float = float(m.get("MAP_W"))
	var sp: Variant = m._map.get("player_spawn", Vector2(0, 600))
	var y: float = (float((sp as Vector2).y) if typeof(sp) == TYPE_VECTOR2 else 600.0) - 60.0
	var t := float(_bench_frames % 240) / 240.0
	_cam.global_position = Vector2(lerpf(300.0, w - 300.0, t), y)
	if _bench_frames == 20:
		_bench_t0 = Time.get_ticks_usec()
		_bench_dc = 0.0
	if _bench_frames > 20:
		_bench_dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_bench_frames += 1
	if _bench_frames == 260:
		var ms := float(Time.get_ticks_usec() - _bench_t0) / 240.0 / 1000.0
		_bench_res.append(ms)
		print("BENCH %s hd=%s mean_frame_ms=%.2f draw_calls=%.0f" % [_map, str(not _hd.suppress), ms, _bench_dc / 239.0])
		if _bench_res.size() == 1:
			_hd.suppress = false
			_bench_frames = 0
		else:
			print("BENCH %s classic=%.2f hd=%.2f delta=%+.1f%%" % [_map, _bench_res[0], _bench_res[1], (_bench_res[1] / _bench_res[0] - 1.0) * 100.0])
			quit()
			return true
	return false
