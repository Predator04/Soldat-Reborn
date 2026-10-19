extends SceneTree
## Dev capture for the LEVELS browser (#288; not shipped): seeds the
## in-process fake level server (tools/levels_fake_master.gd) with sample
## levels — random editor maps and a few classic layouts — opens LEVELS from
## the main menu, picks one and saves docs/screenshots/levels-browser.jpg
## (+ a PNG per tab in --out).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       --resolution 1280x720 -s tools/levels_capture.gd -- [--out=DIR] [--jpg=PATH]

var _out := "user://levels_shots"
var _jpg := "res://docs/screenshots/levels-browser.jpg"
var _fake: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--jpg="): _jpg = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> Image:
	var img := root.get_texture().get_image()
	var p := _out.path_join(name + ".png")
	img.save_png(p)
	print("LEVELS-CAPTURE saved ", p, " ", img.get_size())
	return img


func _upload(api: Node, title: String, author: String, m: Dictionary, theme: String) -> String:
	var res := []
	api.upload(title, author, m, theme, func(ok: bool, d: Dictionary, _e: String) -> void: res.append(d if ok else {}))
	while res.is_empty():
		await process_frame
	return str(res[0].get("id", ""))


func _run() -> void:
	await _frames(2)
	while root.get_node_or_null("Settings") == null:
		await process_frame
	var st := root.get_node("Settings")
	st.name_set = true
	st.player_name = "Ace"
	st.reduce_motion = true
	st.level_bookmarks = []
	st.game_mode = 2
	_fake = load("res://tools/levels_fake_master.gd").new()
	root.add_child(_fake)
	_fake.start()
	st.master_url = _fake.url()
	var api: Node = load("res://scripts/levels_api.gd").new()
	root.add_child(api)
	var mapio = load("res://scripts/map_io.gd")
	var gen = load("res://scripts/map_gen.gd")
	var classic := func(stem: String) -> Dictionary:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/%s.json" % stem))
		return d if d is Dictionary else {}
	var editor_map := func(seed: int) -> Dictionary:
		var d = JSON.parse_string(mapio.map_to_json(gen.generate(seed)))
		return d if d is Dictionary else {}
	# title, author, map, theme, plays, likes, age (hours)
	var samples := [
		["Frostbite Fortress", "Nyx", classic.call("icebeam"), "snow", 1840, 312, 30],
		["Rooftop Rumble", "Kestrel", editor_map.call(41), "urban", 960, 205, 50],
		["Sandstorm Siege", "Dune", classic.call("desert"), "desert", 2210, 188, 140],
		["Jungle Gym", "Moss", classic.call("jungle"), "jungle", 530, 141, 12],
		["Tower of Pain", "Ace", editor_map.call(7), "rock", 120, 37, 3],
		["Voland Heights", "Rook", classic.call("voland"), "rock", 3120, 402, 300],
		["Ruins of Ash", "Ember", classic.call("ash"), "ruins", 760, 96, 70],
		["Bunker Busters", "Tank", classic.call("bunker"), "urban", 410, 58, 20],
		["Sky Bridges", "Wren", editor_map.call(1234), "", 44, 9, 1],
	]
	var ids: Array = []
	for s in samples:
		var id: String = await _upload(api, s[0], s[1], s[2], s[3])
		ids.append(id)
		if _fake.levels.has(id):
			var e: Dictionary = _fake.levels[id]
			e["plays"] = int(s[4])
			for i in int(s[5]):
				e["likers"]["p%d" % i] = true
			e["likes"] = int(s[5])
			e["up"] = int(Time.get_unix_time_from_system() * 1000.0) - int(s[6]) * 3600000
	# This player liked + bookmarked one of them.
	_fake.levels[ids[0]]["likers"][st.level_pid()] = true
	_fake.levels[ids[0]]["likes"] += 1
	st.level_bookmarks = [{"id": ids[3], "code": _fake.levels[ids[3]]["code"], "title": "Jungle Gym", "author": "Moss", "modes": _fake.levels[ids[3]]["modes"]}]
	change_scene_to_file("res://scenes/menu.tscn")
	await _frames(60)
	var menu: Node = current_scene
	menu._open_levels("hot")
	var pn: Node = menu.get("_levels_panel")
	while pn.loaded < 0:
		await process_frame
	pn.select(ids[0])
	await _frames(40)
	var img := _shot("levels_hot")
	var jp := ProjectSettings.globalize_path(_jpg) if _jpg.begins_with("res://") else _jpg
	img.save_jpg(jp, 0.9)
	print("LEVELS-CAPTURE saved ", jp)
	for t in ["plays", "bookmarks"]:
		pn.set_tab(t)
		while pn.loaded < 0:
			await process_frame
		await _frames(30)
		_shot("levels_" + t)
	pn.set_tab("search")
	pn._search.text = "ru"
	pn.refresh_data()
	while pn.loaded < 0:
		await process_frame
	await _frames(30)
	_shot("levels_search")
	# The editor's PUBLISH dialog after a publish.
	change_scene_to_file("res://scenes/map_editor.tscn")
	await _frames(40)
	var ed: Node = current_scene
	ed.set("_map", gen.generate(99))
	var dlg: Node = load("res://scripts/level_publish.gd").open_publish(ed, ed.get_node("UI"))
	dlg.publish("Canyon Run")
	while dlg.last_reply.is_empty():
		await process_frame
	await _frames(30)
	_shot("publish")
	quit(0)
