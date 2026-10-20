extends SceneTree
## Dev capture for the FEATURED levels (#295; not shipped): LEVELS on the
## FEATURED tab (offline — no level server at all) -> docs/screenshots/
## levels-featured.jpg; then the Maker's New map sheet, and an overview of each
## level in a bot match (PNGs in --out).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       --resolution 1280x720 -s tools/featured_capture.gd -- [--out=DIR] [--jpg=PATH] [--no-levels] --no-perf-guard

var _out := "user://featured_shots"
var _jpg := "res://docs/screenshots/levels-featured.jpg"
var _levels := true
var _only := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--jpg="): _jpg = a.substr(6)
		elif a == "--no-levels": _levels = false
		elif a.begins_with("--only="): _only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> Image:
	var img := root.get_texture().get_image()
	var p := _out.path_join(name + ".png")
	img.save_png(p)
	print("FEATURED-CAPTURE saved ", p, " ", img.get_size())
	return img


func _run() -> void:
	await _frames(2)
	while root.get_node_or_null("Settings") == null:
		await process_frame
	var st := root.get_node("Settings")
	st.name_set = true
	st.player_name = "Ace"
	st.reduce_motion = true
	st.game_mode = 2
	st.master_url = "http://127.0.0.1:9"   # offline on purpose: FEATURED needs no server
	var FL = load("res://scripts/featured_levels.gd")
	if _only == "":
		change_scene_to_file("res://scenes/menu.tscn")
		await _frames(60)
		var menu: Node = current_scene
		menu._open_levels()
		var pn: Node = menu.get("_levels_panel")
		await _frames(5)
		pn.select(FL.ID_PREFIX + "twin_forts")
		await _frames(40)
		var img := _shot("levels_featured")
		var jp := ProjectSettings.globalize_path(_jpg) if _jpg.begins_with("res://") else _jpg
		img.save_jpg(jp, 0.9)
		print("FEATURED-CAPTURE saved ", jp)
		pn.select(FL.ID_PREFIX + "iron_valley")
		await _frames(20)
		_shot("levels_featured_iron_valley")
		# The Maker: New map -> Start from.
		change_scene_to_file("res://scenes/map_editor.tscn")
		await _frames(40)
		var mk: Node = current_scene.get("_maker")
		mk.open_new()
		await _frames(30)
		_shot("maker_new_map")
		mk.start_from("skyline_tower")
		await _frames(30)
		_shot("maker_copy_skyline_tower")
	if _levels:
		for s in FL.slugs():
			if _only != "" and s != _only:
				continue
			st.custom_map_path = FL.local_copy(s)
			st.game_mode = int(MODE.get(str(FL.meta(s)["modes"]).get_slice(" ", 0), 0))
			st.bot_count = 8
			st.vehicles = true
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			await _frames(30)
			var m: Node = current_scene
			var w: Dictionary = (m.get("_map") as Dictionary).get("world", {})
			var cam := Camera2D.new()
			m.add_child(cam)
			var W := float(w.get("w", 4800.0))
			var H := float(w.get("h", 2000.0))
			var z := minf(1280.0 / W, 720.0 / H)
			cam.zoom = Vector2(z, z)
			cam.position = Vector2(W * 0.5, H * 0.5)
			cam.make_current()
			await _frames(200)
			cam.make_current()
			await _frames(10)
			_shot("level_" + s)
	quit(0)


const MODE := {"dm": 0, "tdm": 1, "ctf": 2, "inf": 3, "htf": 4, "rm": 5, "pm": 6, "dom": 7, "br": 8, "gg": 9}
