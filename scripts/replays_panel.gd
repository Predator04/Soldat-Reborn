extends PanelContainer
## REPLAYS (main menu): your recorded matches, newest first. WATCH plays one
## back on its map; DELETE removes it. The last 20 are kept automatically.

signal closed

const Recorder := preload("res://scripts/replay_recorder.gd")
const MODE_NAMES := ["Deathmatch", "Teammatch", "Capture the Flag", "Infiltration", "Hold the Flag", "Rambomatch", "Pointmatch", "Domination", "Battle Royale", "Gun Game"]

var _list: VBoxContainer
var _focus_btn: Control = null
var rows_shown := -1     # for tests


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style())
	set_anchors_preset(Control.PRESET_CENTER, true)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(620, 0)
	add_child(box)
	box.add_child(UITheme.make_screen_title("REPLAYS"))
	var note := Label.new()
	note.text = tr("Every match you play is recorded (the last 20 are kept). Watch from any player's view, at any speed.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_body(note, 13, UITheme.COL_TEXT_DIM)
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	var back := UITheme.make_button("BACK")
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	box.add_child(back)
	_focus_btn = back


func refresh_data() -> void:
	UITheme.safe_grab_focus_deferred(_focus_btn)
	for c in _list.get_children():
		c.queue_free()
	var files := Recorder.list_files()
	if files.is_empty():
		var l := Label.new()
		l.text = tr("No replays yet. Play a match and it shows up here.")
		UITheme.style_body(l, 14, UITheme.COL_TEXT_DIM)
		_list.add_child(l)
	for path in files:
		_list.add_child(_row(path))
	rows_shown = files.size()


func _row(path: String) -> Control:
	# File names carry date + map; the header has the rest, but reading every
	# file is slow, so the list shows the name and loads on WATCH.
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.COL_PANEL_ROW))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)
	var fn := path.get_file().get_basename()   # 2026-10-05_20-11-03_ascent
	var parts := fn.split("_", false, 2)
	var lbl := Label.new()
	if parts.size() >= 3:
		lbl.text = "%s  %s   ·   %s" % [parts[0], parts[1].replace("-", ":").left(5), parts[2].capitalize()]
	else:
		lbl.text = fn
	var kb := FileAccess.get_file_as_bytes(path).size() / 1024 if FileAccess.file_exists(path) else 0
	lbl.text += "   ·   %d KB" % kb
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_body(lbl, 14)
	hb.add_child(lbl)
	var watch := UITheme.make_small_button("WATCH", 110, 30)
	watch.pressed.connect(func() -> void: watch_replay(path))
	hb.add_child(watch)
	var del := UITheme.make_small_button("DELETE", 100, 30)
	del.pressed.connect(func() -> void:
		DirAccess.remove_absolute(path)
		refresh_data())
	hb.add_child(del)
	return pc


func watch_replay(path: String) -> bool:
	var d := Recorder.load_file(path)
	if d.is_empty():
		return false
	var h: Dictionary = d.get("header", {})
	Net.replay_restore = {"map_index": Settings.map_index, "custom_map_path": Settings.custom_map_path, "game_mode": Settings.game_mode}
	Net.set_singleplayer()
	Settings.game_mode = int(h.get("mode", 0))
	if int(h.get("map_index", -1)) >= 0:
		Settings.map_index = int(h.map_index)
		Settings.custom_map_path = ""
	else:
		var mp := Recorder.DIR + "_replay_map.json"
		var f := FileAccess.open(mp, FileAccess.WRITE)
		f.store_string(str(h.get("map_json", "")))
		f.close()
		Settings.custom_map_path = mp
	Net.replay_path = path
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	return true
