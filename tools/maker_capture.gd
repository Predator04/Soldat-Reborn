extends SceneTree
## Dev capture for Maker mode (#286; not shipped): builds a demo level with the
## Maker API, saves the editor (a piece mid-drag, one selected), then presses
## PLAY and saves the match a few seconds in, then EDIT back.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##       --resolution 1280x720 -s tools/maker_capture.gd -- --out=DIR [--theme=grassland] [--no-play]
var _out := "user://maker_shots"
var _theme := "grassland"
var _play := true
var _themes := false   # --themes: one zoomed shot per theme, no play
var _ti := 0
var _locale := ""
var _adv := false   # --advanced: also a shot of the classic tools on the same map
var _st := 0
var _t := 0
var _n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--theme="): _theme = a.substr(8)
		elif a == "--no-play": _play = false
		elif a == "--themes": _themes = true
		elif a == "--advanced": _adv = true
		elif a.begins_with("--locale="): _locale = a.substr(9)
	DirAccess.make_dir_recursive_absolute(_out)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var p := _out.path_join(name + ".png")
	img.save_png(p)
	print("MAKER-CAPTURE saved ", p, " ", img.get_size())


func _wait(frames: int) -> bool:
	_t += 1
	if _t < frames:
		return true
	_t = 0
	return false


static func demo(mk: Node, theme: String) -> void:
	mk.new_map()
	mk.set_theme(theme)
	var e = mk.ed
	# Lava under the west bridge, spikes on the middle block, jump pads, a
	# ladder up to a ledge, cover, decoration, pickups and a buggy.
	mk.place("lava", Vector2(1600, 1600))
	mk.place("spikes", Vector2(2880, 1520))
	mk.place("pad", Vector2(1160, 1500))
	mk.place("pad_big", Vector2(3640, 1500))
	mk.place("crate", Vector2(980, 1470))
	mk.place("crate", Vector2(1040, 1470))
	mk.place("crate_big", Vector2(4300, 1450))
	mk.place("sandbags", Vector2(2040, 1530))
	mk.place("ledge", Vector2(2400, 1120))
	mk.place("ladder", Vector2(2620, 1250))
	mk.place("sc_0", Vector2(600, 1500))
	mk.place("sc_5", Vector2(1900, 1540))
	mk.place("sc_1", Vector2(4050, 1500))
	mk.place("sc_7", Vector2(3480, 1500))
	mk.place("medkit", Vector2(2400, 1100))
	mk.place("w_minimi", Vector2(1640, 1200))
	mk.place("w_barrett", Vector2(3160, 1200))
	mk.place("buggy", Vector2(780, 1500))
	mk.place("dom", Vector2(2400, 1300))
	mk.place("spawn_any", Vector2(1980, 1540))
	e._map["player_spawn"] = Vector2(560, 1500)
	mk.commit()


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
			st.bot_count = 3
			st.custom_map_path = ""
			if _locale != "":
				TranslationServer.set_locale(_locale)
			change_scene_to_file("res://scenes/map_editor.tscn")
			_st = 1
		1:
			if _wait(30):
				return false
			var mk = current_scene.get("_maker")
			demo(mk, _theme)
			mk.fit_view()
			var cam: Camera2D = current_scene.get("_cam")
			cam.zoom = Vector2(0.62, 0.62)
			cam.position = Vector2(1900, 1380)
			# Something selected, a piece mid-drag from the palette.
			mk.sel = [{"k": "pc", "i": 3}]
			mk._place_selbar()
			mk.set_tab("terrain")
			mk._ghost_id = "float"
			mk._ghost_w = Vector2(1250, 1060)
			current_scene.queue_redraw()
			_st = 2
		2:
			if _wait(40):
				return false
			if _themes:
				_st = 10
				return false
			_shot("maker_build")
			var mk = current_scene.get("_maker")
			mk._ghost_id = ""
			mk.sel = []
			mk._place_selbar()
			mk.set_tab("objectives")
			mk.fit_view()
			current_scene.queue_redraw()
			_st = 3
		3:
			if _wait(30):
				return false
			_shot("maker_fit")
			if _adv:
				current_scene.call("_set_maker", false)
				_st = 20
				return false
			if not _play:
				quit()
				return true
			var mk = current_scene.get("_maker")
			var cam: Camera2D = current_scene.get("_cam")
			cam.zoom = Vector2(0.62, 0.62)
			cam.position = Vector2(1330, 1420)
			mk.test_mode = 0
			print("MAKER-CAPTURE play -> ", mk.play(true))
			_st = 4
		4:
			var m := current_scene
			if _n % 60 == 0:
				print("MAKER-CAPTURE waiting scene=", m.name if m != null else "-")
			if m == null or m.get("MAPS") == null or m.get("player") == null:
				return false
			if _t == 30:
				# Frame the lava pit + bridge (a bot may have killed us already).
				(m.get("player") as Node2D).global_position = Vector2(1330, 1505)
				m.get("player").set("velocity", Vector2.ZERO)
			if _wait(110):
				return false
			_shot("maker_play")
			m.call("maker_edit")
			_st = 5
		5:
			if current_scene == null or current_scene.get("_maker") == null:
				return false
			if _wait(40):
				return false
			_shot("maker_back")
			quit()
			return true
		20:
			if _wait(30):
				return false
			_shot("advanced")
			current_scene.call("_set_maker", true)
			_adv = false
			_st = 3
			_t = 29
		10:
			# One shot per theme, same framing.
			var mk = current_scene.get("_maker")
			var ids: Array = load("res://scripts/maker/maker_themes.gd").ORDER
			if _ti >= ids.size():
				quit()
				return true
			mk._ghost_id = ""
			mk.sel = []
			mk._place_selbar()
			mk.set_theme(ids[_ti])
			var cam: Camera2D = current_scene.get("_cam")
			cam.zoom = Vector2(0.62, 0.62)
			cam.position = Vector2(1900, 1380)
			current_scene.queue_redraw()
			_st = 11
		11:
			if _wait(25):
				return false
			var ids2: Array = load("res://scripts/maker/maker_themes.gd").ORDER
			_shot("theme_%s" % ids2[_ti])
			_ti += 1
			_st = 10
	return false
