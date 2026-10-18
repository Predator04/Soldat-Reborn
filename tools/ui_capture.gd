extends SceneTree
## Dev capture for the UI (graphics Phase C, #272; not shipped): opens the main
## menu, settings, server browser, then a CTF bot match for the HUD, the
## scoreboard, the pause menu and the death screen, and saves one PNG of each.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       --resolution 1280x720 -s tools/ui_capture.gd -- --out=DIR [--tag=desk]
## Works on older builds too (only calls menu / hud methods that predate #272),
## so a pristine checkout renders the matching "before" set.
var _out := "user://ui_shots"
var _tag := ""
var _n := 0
var _st := 0
var _t := 0
var _m: Node = null
var _tour := false   # --tour: also every other menu screen (new builds only), no match
var _tour_i := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--tag="): _tag = a.substr(6)
		elif a == "--tour": _tour = true
	DirAccess.make_dir_recursive_absolute(_out)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var p := _out.path_join(("%s_%s.png" % [_tag, name]) if _tag != "" else name + ".png")
	img.save_png(p)
	print("UI-CAPTURE saved ", p, " ", img.get_size())


func _wait(frames: int) -> bool:
	_t += 1
	if _t < frames:
		return true
	_t = 0
	return false


func _find_button(n: Node, needle: String) -> Button:
	for c in n.get_children():
		if c is Button and str((c as Button).text).to_upper().contains(needle):
			return c
		var r := _find_button(c, needle)
		if r != null:
			return r
	return null


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	match _st:
		0:
			if _n < 2:
				return false
			st.name_set = true
			st.player_name = "Ace"
			st.bot_count = 6
			st.game_mode = 2
			st.map_index = 19
			st.custom_map_path = ""
			st.killcam_replay = false
			st.master_url = ""
			st.recent_servers = ["203.0.113.7:7777"]
			st.last_seen_version = str(ProjectSettings.get_setting("application/config/version", ""))
			change_scene_to_file("res://scenes/menu.tscn")
			_st = 1
		1:
			if _wait(90):
				return false
			_m = current_scene
			_shot("main")
			_m._open_settings()
			var sp: Node = _m.get("_settings_panel")
			var vid := _find_button(sp, "VIDEO")
			if vid != null:
				vid.pressed.emit()
			_st = 2
		2:
			if _wait(45):
				return false
			_shot("settings")
			_m._go_back()
			_m._menu_root.visible = false
			_m._master_edit.text = ""
			_m._browser._on_browse_pressed()
			var rows := [
				{"name": "Tracerfall EU #1", "ip": "198.51.100.4", "port": 7777, "players": 6, "max": 8, "map": "ctf_Ash", "mode": "CTF", "v": ""},
				{"name": "Night Raid DM", "ip": "198.51.100.9", "port": 7777, "players": 3, "max": 8, "map": "Arena", "mode": "DM", "v": ""},
				{"name": "Gun Game 24/7", "ip": "198.51.100.12", "port": 7790, "players": 8, "max": 8, "map": "Kampf", "mode": "GG", "v": ""},
				{"name": "Old build server", "ip": "198.51.100.30", "port": 7777, "players": 1, "max": 8, "map": "Lagoon", "mode": "TDM", "v": "0.9.0"},
			]
			_m._master_rows.clear()
			for r in rows:
				_m._master_rows.append(r)
			_st = 3
		3:
			if _wait(4):
				return false
			_m._browser._render_master()
			_st = 4
		4:
			if _wait(40):
				return false
			_shot("browser")
			_m._browse_root.visible = false
			_m._menu_root.visible = true
			if _tour:
				_st = 100
				return false
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 5
		5:
			if _wait(420):
				return false
			_m = current_scene
			_shot("hud")
			_m.hud.scoreboard.peek(1.0)
			_st = 6
		6:
			if _wait(8):
				return false
			_shot("scoreboard")
			_m.hud.scoreboard.peek(0.0)
			_st = 60
		60:
			if _wait(4):
				return false
			_m.get_node("PauseMenu").open()
			_st = 7
		7:
			if _wait(30):
				return false
			_shot("pause")
			_m.get_node("PauseMenu").close()
			_m.hud.scoreboard.peek(0.0)
			if is_instance_valid(_m.player):
				_m.player.take_damage(999.0, "Red_Bot_2", "AK-74", 2)
			_st = 8
		8:
			if _wait(45):
				return false
			_shot("death")
			print("UI-CAPTURE done")
			quit()
		100:
			# Tour: open one screen, shoot it, close it.
			var names := ["host", "join", "stats", "credits", "customize", "leaderboard", "friends", "replays", "library", "controls", "name"]
			if _tour_i >= names.size():
				print("UI-CAPTURE done")
				quit()
				return false
			var nm: String = names[_tour_i]
			match nm:
				"host": _m._open_host()
				"join":
					_m._menu_root.visible = false
					_m._join_root.visible = true
				"stats":
					_m._refresh_stats_labels()
					_m._menu_root.visible = false
					_m._stats_root.visible = true
				"credits": _m._open_credits()
				"customize": _m._open_customize()
				"leaderboard": _m._open_leaderboard()
				"friends": _m._open_friends()
				"replays": _m._open_replays()
				"library": _m._open_map_library()
				"controls":
					_m._open_settings()
					_m._settings_panel.controls_pressed.emit()
				"name": _m._build_name_prompt(Callable(), true)
			_st = 101
		101:
			if _wait(40):
				return false
			var names2 := ["host", "join", "stats", "credits", "customize", "leaderboard", "friends", "replays", "library", "controls", "name"]
			_shot("tour_" + names2[_tour_i])
			if names2[_tour_i] == "name":
				_m._name_prompt_root.queue_free()
			elif names2[_tour_i] == "controls":
				_m._go_back()
				_m._go_back()
			else:
				_m._go_back()
			_tour_i += 1
			_st = 100
	return false
