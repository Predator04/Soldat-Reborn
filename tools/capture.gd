extends SceneTree
## Dev capture for store pages (not shipped): boots a bot match and saves a
## run of frames.  godot -s tools/capture.gd -- --map=N --mode=M --out=DIR --frames=60 --every=3 --skip=240 --follow-bot
var _out := ""
var _frames := 60
var _every := 3
var _skip := 240
var _n := 0
var _saved := 0
var _map := 19
var _mode := 2
var _bots := 8
var _zoom := 1.0
var _cam: Camera2D = null
var _nohud := false
var _focus: Node2D = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--frames="): _frames = int(a.substr(9))
		elif a.begins_with("--every="): _every = int(a.substr(8))
		elif a.begins_with("--skip="): _skip = int(a.substr(7))
		elif a.begins_with("--map="): _map = int(a.substr(6))
		elif a.begins_with("--mode="): _mode = int(a.substr(7))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--zoom="): _zoom = float(a.substr(7))
		elif a == "--nohud": _nohud = true


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _n == 2:
		st.bot_count = _bots
		st.game_mode = _mode
		st.map_index = _map
		st.custom_map_path = ""
		st.name_set = true
		st.player_name = "You"
		st.cos_wskin = "gold"; st.cos_jet = "blue"; st.cos_finish = "night"
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		return false
	if _n < _skip:
		return false
	var m = current_scene
	if _n == _skip and m != null and m.get("player") != null and is_instance_valid(m.player):
		# Let the player sit out so a bot leads the action; camera follows it.
		m.player.ceasefire_t = 9999.0
		if m.player.cam != null:
			m.player.cam.zoom = Vector2(_zoom, _zoom)
	# Follow the bot in the thick of it (has a live target), switching only
	# when that bot dies, so the clip shows a fight instead of the idle player.
	if _cam == null and m != null:
		_cam = Camera2D.new()
		_cam.position_smoothing_enabled = true
		_cam.position_smoothing_speed = 5.0
		_cam.zoom = Vector2(_zoom, _zoom)
		m.add_child(_cam)
		_cam.make_current()
	if _focus == null or not is_instance_valid(_focus) or bool(_focus.get("dead")):
		_focus = null
		for b in get_nodes_in_group("soldier"):
			if b.get("loadout") != null and not bool(b.get("dead")) and is_instance_valid(b.get("target")):
				_focus = b
				break
	if _nohud and m.get("hud") != null and is_instance_valid(m.hud):
		m.hud.visible = false
	if _focus != null and _cam != null:
		_cam.global_position = _focus.global_position + Vector2(0, -40)
	if (_n - _skip) % _every == 0:
		root.get_texture().get_image().save_png("%s/f%03d.png" % [_out, _saved])
		_saved += 1
		if _saved >= _frames:
			quit()
			return true
	return false
