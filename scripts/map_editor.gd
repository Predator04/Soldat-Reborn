extends Node2D
## MapEditor — in-game level editor (issue #31).
##
## Runs as its own scene. Left-click on the toolbar picks a tool; left-click
## in the map area applies it. Right-click deletes the thing under the mouse.
## Middle-mouse drags pan, scroll wheel zooms. ESC exits back to menu.
##
## The in-memory _map dict is the same shape as main.gd's MAPS entries, so
## Save/Load round-trip through res://scripts/map_io.gd JSON files under
## user://maps/, and Play-test writes a temp file + hands off to main.tscn
## via Settings.custom_map_path.

const MapIO = preload("res://scripts/map_io.gd")
const MapGen = preload("res://scripts/map_gen.gd")

const MAP_W := 4800.0
const MAP_H := 2000.0
const GROUND_Y := 1900.0
const GRID_STEP := 10.0
const HIT_RADIUS := 26.0

enum Tool {
	PLATFORM, MOVE, DELETE,
	PLAYER_SPAWN, BOT_SPAWN,
	FLAG_BLUE, FLAG_RED, FLAG_NEUTRAL,
	DOM_POINT, M2_MOUNT,
}

var _tool: int = Tool.PLATFORM
var _map: Dictionary = _fresh_map()

var _cam: Camera2D = null
var _dragging: bool = false
var _drag_kind: String = ""      # "platform" | "move"
var _drag_start: Vector2 = Vector2.ZERO
var _drag_key: String = ""
var _drag_index: int = -1
var _drag_offset: Vector2 = Vector2.ZERO
var _panning: bool = false

# UI handles
var _status: Label = null
var _tool_label: Label = null
var _name_edit: LineEdit = null
var _seed_edit: LineEdit = null
var _load_panel: Panel = null
var _load_list: VBoxContainer = null


func _fresh_map() -> Dictionary:
	return {
		"name": "Untitled",
		"platforms": [],
		"player_spawn": Vector2(220.0, GROUND_Y - 125.0),
		"bot_spawns": [],
	}


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(load("res://assets/interface-gfx/menucursor.png"),
			Input.CURSOR_ARROW, Vector2(0, 0))
	_cam = Camera2D.new()
	_cam.zoom = Vector2(0.45, 0.45)
	_cam.position = Vector2(MAP_W * 0.5, MAP_H * 0.55)
	_cam.limit_left = -400
	_cam.limit_right = int(MAP_W) + 400
	_cam.limit_top = -400
	_cam.limit_bottom = int(MAP_H) + 400
	add_child(_cam)
	_build_ui()
	_set_tool(Tool.PLATFORM)
	_set_status("Ready. LMB place/drag · RMB delete · MMB pan · wheel zoom · F5 play-test · ESC exit.")
	queue_redraw()


# ── Rendering ─────────────────────────────────────────

func _process(_delta: float) -> void:
	# Redraw continuously while dragging out a platform so the preview follows the cursor.
	if _dragging and _drag_kind == "platform":
		queue_redraw()


func _draw() -> void:
	# Map background + grid.
	draw_rect(Rect2(0, 0, MAP_W, MAP_H), Color(0.05, 0.08, 0.14))
	var grid_col := Color(0.15, 0.18, 0.24, 0.6)
	var step := 200.0
	var x := 0.0
	while x <= MAP_W + 0.5:
		draw_line(Vector2(x, 0), Vector2(x, MAP_H), grid_col, 1.0)
		x += step
	var y := 0.0
	while y <= MAP_H + 0.5:
		draw_line(Vector2(0, y), Vector2(MAP_W, y), grid_col, 1.0)
		y += step
	# Ground reference line (matches main.gd's ground body top edge).
	draw_line(Vector2(0, GROUND_Y), Vector2(MAP_W, GROUND_Y), Color(0.28, 0.32, 0.4), 2.0)
	# Platforms.
	for pl in _map.get("platforms", []):
		var p: Vector2 = pl["p"]
		var s: Vector2 = pl["s"]
		var r := Rect2(p - s * 0.5, s)
		draw_rect(r, Color(0.28, 0.32, 0.4, 0.9))
		draw_rect(r, Color(0.55, 0.65, 0.85), false, 1.5)
	# Live drag preview for a new platform.
	if _dragging and _drag_kind == "platform":
		var mp := get_global_mouse_position()
		var r := _rect_from_drag(_drag_start, mp)
		draw_rect(r, Color(0.95, 0.82, 0.4, 0.35))
		draw_rect(r, Color(0.95, 0.82, 0.4), false, 1.5)
	# Markers.
	var ps: Vector2 = _map.get("player_spawn", Vector2.ZERO)
	_draw_marker(ps, Color(0.4, 0.7, 1.0), "P")
	var bi := 0
	for b in _map.get("bot_spawns", []):
		_draw_marker(b, Color(0.95, 0.35, 0.3), "B%d" % (bi + 1))
		bi += 1
	if _map.has("ctf_flags"):
		var flags: Array = _map["ctf_flags"]
		if flags.size() >= 1: _draw_marker(flags[0], Color(0.35, 0.55, 1.0), "FB")
		if flags.size() >= 2: _draw_marker(flags[1], Color(0.95, 0.3, 0.25), "FR")
	if _map.has("inf_flag"):
		_draw_marker(_map["inf_flag"], Color(1.0, 1.0, 0.4), "IF")
	if _map.has("htf_flag"):
		_draw_marker(_map["htf_flag"], Color(1.0, 0.7, 0.3), "HF")
	var di := 0
	for d in _map.get("dom_points", []):
		_draw_marker(d, Color(1.0, 0.85, 0.25), "D%s" % ["A", "B", "C"][mini(di, 2)], 32.0)
		di += 1
	for m in _map.get("m2_mounts", []):
		_draw_marker(m, Color(0.6, 0.9, 0.9), "M2", 22.0)


func _draw_marker(pos: Vector2, col: Color, label: String, size: float = 22.0) -> void:
	var pts := PackedVector2Array([
		pos + Vector2(0, -size),
		pos + Vector2(size, 0),
		pos + Vector2(0, size),
		pos + Vector2(-size, 0),
	])
	draw_colored_polygon(pts, col)
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	draw_polyline(outline, Color(0, 0, 0, 0.9), 1.5)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, pos + Vector2(-14, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0))


func _rect_from_drag(a: Vector2, b: Vector2) -> Rect2:
	var tl := Vector2(min(a.x, b.x), min(a.y, b.y))
	var br := Vector2(max(a.x, b.x), max(a.y, b.y))
	return Rect2(tl, br - tl)


# ── Input ─────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_mouse_button(ev: InputEventMouseButton) -> void:
	if ev.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = ev.pressed
		return
	if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
		_cam.zoom = (_cam.zoom * 1.1).clamp(Vector2(0.15, 0.15), Vector2(2.5, 2.5))
		return
	if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
		_cam.zoom = (_cam.zoom * 0.9).clamp(Vector2(0.15, 0.15), Vector2(2.5, 2.5))
		return
	if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		_try_delete_at(get_global_mouse_position())
		return
	if ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if ev.pressed:
		_on_lmb_press(get_global_mouse_position())
	else:
		_on_lmb_release(get_global_mouse_position())


func _handle_mouse_motion(ev: InputEventMouseMotion) -> void:
	if _panning:
		_cam.position -= ev.relative / _cam.zoom
		return
	if _dragging and _drag_kind == "move":
		var target := get_global_mouse_position() + _drag_offset
		_set_pos_of(_drag_key, _drag_index, _snap(target))
		queue_redraw()


func _handle_key(ev: InputEventKey) -> void:
	match ev.keycode:
		KEY_ESCAPE: _exit_to_menu()
		KEY_F5: _play_test()
		KEY_1: _set_tool(Tool.PLATFORM)
		KEY_2: _set_tool(Tool.MOVE)
		KEY_3: _set_tool(Tool.DELETE)
		KEY_4: _set_tool(Tool.PLAYER_SPAWN)
		KEY_5: _set_tool(Tool.BOT_SPAWN)


func _on_lmb_press(mp: Vector2) -> void:
	match _tool:
		Tool.PLATFORM:
			_drag_start = mp
			_dragging = true
			_drag_kind = "platform"
		Tool.MOVE:
			var found := _find_at(mp)
			if found.size() > 0:
				_drag_kind = "move"
				_drag_key = String(found[0])
				_drag_index = int(found[1])
				_drag_offset = _pos_of(_drag_key, _drag_index) - mp
				_dragging = true
		Tool.DELETE:
			_try_delete_at(mp)
		Tool.PLAYER_SPAWN:
			_map["player_spawn"] = _snap(mp)
		Tool.BOT_SPAWN:
			var arr: Array = _map.get("bot_spawns", [])
			arr.append(_snap(mp))
			_map["bot_spawns"] = arr
		Tool.FLAG_BLUE:
			_set_ctf_flag(0, _snap(mp))
		Tool.FLAG_RED:
			_set_ctf_flag(1, _snap(mp))
		Tool.FLAG_NEUTRAL:
			var p := _snap(mp)
			_map["inf_flag"] = p
			_map["htf_flag"] = p
			_map["rambo_pos"] = p
		Tool.DOM_POINT:
			var arr: Array = _map.get("dom_points", [])
			if arr.size() >= 3:
				arr.clear()
			arr.append(_snap(mp))
			_map["dom_points"] = arr
		Tool.M2_MOUNT:
			var arr: Array = _map.get("m2_mounts", [])
			arr.append(_snap(mp))
			_map["m2_mounts"] = arr
	queue_redraw()


func _on_lmb_release(mp: Vector2) -> void:
	if not _dragging:
		return
	if _drag_kind == "platform":
		var r := _rect_from_drag(_drag_start, mp)
		var size := r.size
		var center := r.position + size * 0.5
		if size.x < 20.0 or size.y < 6.0:
			size = Vector2(160.0, 22.0)
			center = _snap(mp)
		size = Vector2(max(20.0, round(size.x / GRID_STEP) * GRID_STEP),
			max(6.0, round(size.y / 2.0) * 2.0))
		center = _snap(center)
		var arr: Array = _map.get("platforms", [])
		arr.append({"p": center, "s": size})
		_map["platforms"] = arr
	_dragging = false
	_drag_kind = ""
	_drag_key = ""
	_drag_index = -1
	queue_redraw()


func _set_ctf_flag(idx: int, pos: Vector2) -> void:
	var flags: Array = _map.get("ctf_flags", [])
	while flags.size() < 2:
		flags.append(Vector2(300.0 if flags.size() == 0 else MAP_W - 300.0, GROUND_Y - 30.0))
	flags[idx] = pos
	_map["ctf_flags"] = flags


func _snap(v: Vector2) -> Vector2:
	return Vector2(round(v.x / GRID_STEP) * GRID_STEP, round(v.y / GRID_STEP) * GRID_STEP)


func _find_at(mp: Vector2) -> Array:
	# Markers first, platforms last, so overlapping items pick the marker.
	var ps: Vector2 = _map.get("player_spawn", Vector2.ZERO)
	if mp.distance_to(ps) < HIT_RADIUS:
		return ["player_spawn", 0]
	var bs: Array = _map.get("bot_spawns", [])
	for i in bs.size():
		if mp.distance_to(bs[i]) < HIT_RADIUS:
			return ["bot_spawns", i]
	if _map.has("ctf_flags"):
		var flags: Array = _map["ctf_flags"]
		for i in flags.size():
			if mp.distance_to(flags[i]) < HIT_RADIUS:
				return ["ctf_flags", i]
	for key in ["inf_flag", "htf_flag", "rambo_pos"]:
		if _map.has(key) and mp.distance_to(_map[key]) < HIT_RADIUS:
			return [key, 0]
	var dp: Array = _map.get("dom_points", [])
	for i in dp.size():
		if mp.distance_to(dp[i]) < 36.0:
			return ["dom_points", i]
	var m2: Array = _map.get("m2_mounts", [])
	for i in m2.size():
		if mp.distance_to(m2[i]) < HIT_RADIUS:
			return ["m2_mounts", i]
	var pls: Array = _map.get("platforms", [])
	for i in pls.size():
		var pl: Dictionary = pls[i]
		var r := Rect2(pl["p"] - pl["s"] * 0.5, pl["s"])
		# Expand a hair so thin platforms are still grabbable.
		r = r.grow(4.0)
		if r.has_point(mp):
			return ["platforms", i]
	return []


func _pos_of(key: String, index: int) -> Vector2:
	if key == "player_spawn": return _map["player_spawn"]
	if key == "inf_flag" or key == "htf_flag" or key == "rambo_pos": return _map[key]
	if key == "platforms": return _map["platforms"][index]["p"]
	return _map[key][index]


func _set_pos_of(key: String, index: int, pos: Vector2) -> void:
	if key == "player_spawn":
		_map["player_spawn"] = pos
	elif key == "inf_flag" or key == "htf_flag" or key == "rambo_pos":
		_map[key] = pos
	elif key == "platforms":
		_map["platforms"][index]["p"] = pos
	else:
		_map[key][index] = pos


func _try_delete_at(mp: Vector2) -> void:
	var found := _find_at(mp)
	if found.size() == 0:
		return
	var key: String = String(found[0])
	var idx: int = int(found[1])
	if key == "player_spawn":
		_set_status("Player spawn can't be deleted — move it instead.")
		return
	if key == "inf_flag" or key == "htf_flag" or key == "rambo_pos":
		_map.erase(key)
	elif key == "platforms":
		_map["platforms"].remove_at(idx)
	else:
		_map[key].remove_at(idx)
		if _map[key].is_empty():
			_map.erase(key)
	queue_redraw()


# ── UI ────────────────────────────────────────────────

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	var bg_top := ColorRect.new()
	bg_top.color = Color(0.06, 0.08, 0.12, 0.92)
	bg_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg_top.offset_top = 0
	bg_top.offset_bottom = 92
	ui.add_child(bg_top)

	var top := HFlowContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 6
	top.offset_bottom = 86
	top.offset_left = 10
	top.offset_right = -10
	top.add_theme_constant_override("h_separation", 6)
	top.add_theme_constant_override("v_separation", 4)
	ui.add_child(top)

	var tool_specs := [
		["Platform", Tool.PLATFORM],
		["Move", Tool.MOVE],
		["Delete", Tool.DELETE],
		["Player", Tool.PLAYER_SPAWN],
		["Bot", Tool.BOT_SPAWN],
		["Flag Blue", Tool.FLAG_BLUE],
		["Flag Red", Tool.FLAG_RED],
		["Flag Ctr", Tool.FLAG_NEUTRAL],
		["Dom Pt", Tool.DOM_POINT],
		["M2", Tool.M2_MOUNT],
	]
	for spec in tool_specs:
		var b := Button.new()
		b.text = String(spec[0])
		b.custom_minimum_size = Vector2(84, 32)
		var tid: int = int(spec[1])
		b.pressed.connect(func() -> void: _set_tool(tid))
		top.add_child(b)

	top.add_child(VSeparator.new())

	var op_specs := [
		["New", "_new_map"],
		["Save", "_save_map"],
		["Load", "_open_load"],
		["Generate", "_generate"],
		["Play-test", "_play_test"],
		["Exit", "_exit_to_menu"],
	]
	for spec in op_specs:
		var b := Button.new()
		b.text = String(spec[0])
		b.custom_minimum_size = Vector2(88, 32)
		b.pressed.connect(Callable(self, String(spec[1])))
		top.add_child(b)

	top.add_child(VSeparator.new())

	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	top.add_child(name_lbl)
	_name_edit = LineEdit.new()
	_name_edit.text = "my_map"
	_name_edit.custom_minimum_size = Vector2(140, 32)
	top.add_child(_name_edit)

	var seed_lbl := Label.new()
	seed_lbl.text = "Seed:"
	top.add_child(seed_lbl)
	_seed_edit = LineEdit.new()
	_seed_edit.text = "1"
	_seed_edit.custom_minimum_size = Vector2(70, 32)
	top.add_child(_seed_edit)

	# Bottom status bar.
	var bg_bot := ColorRect.new()
	bg_bot.color = Color(0.06, 0.08, 0.12, 0.9)
	bg_bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bg_bot.offset_top = -30
	bg_bot.offset_bottom = 0
	ui.add_child(bg_bot)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -26
	_status.offset_bottom = -6
	_status.offset_left = 12
	_status.offset_right = -280
	_status.add_theme_font_size_override("font_size", 13)
	ui.add_child(_status)

	_tool_label = Label.new()
	_tool_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tool_label.offset_top = -26
	_tool_label.offset_bottom = -6
	_tool_label.offset_left = -270
	_tool_label.offset_right = -12
	_tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tool_label.add_theme_font_size_override("font_size", 13)
	ui.add_child(_tool_label)

	_build_load_panel(ui)


func _build_load_panel(ui: CanvasLayer) -> void:
	_load_panel = Panel.new()
	_load_panel.set_anchors_preset(Control.PRESET_CENTER)
	_load_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_load_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_load_panel.custom_minimum_size = Vector2(460, 400)
	_load_panel.visible = false
	ui.add_child(_load_panel)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 16
	vb.offset_top = 16
	vb.offset_right = -16
	vb.offset_bottom = -16
	vb.add_theme_constant_override("separation", 8)
	_load_panel.add_child(vb)

	var h := Label.new()
	h.text = "LOAD MAP"
	h.add_theme_font_size_override("font_size", 22)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(h)

	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 280)
	vb.add_child(sc)
	_load_list = VBoxContainer.new()
	_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_list.add_theme_constant_override("separation", 4)
	sc.add_child(_load_list)

	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0, 36)
	close.pressed.connect(func() -> void: _load_panel.visible = false)
	vb.add_child(close)


# ── Menu callbacks ────────────────────────────────────

func _new_map() -> void:
	_map = _fresh_map()
	_set_status("New empty map.")
	queue_redraw()


func _save_map() -> void:
	var display_name: String = _name_edit.text.strip_edges()
	if display_name == "":
		display_name = "map"
	_map["name"] = display_name
	var path := MapIO.save_to_file(display_name, _map)
	if path == "":
		_set_status("Save failed.")
	else:
		_set_status("Saved to %s" % path)


func _open_load() -> void:
	for c in _load_list.get_children():
		c.queue_free()
	var files := MapIO.list_files()
	if files.is_empty():
		var lbl := Label.new()
		lbl.text = "(no saved maps yet — Save first)"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_load_list.add_child(lbl)
	for path_v in files:
		var path: String = String(path_v)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = path.get_file()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var load_btn := Button.new()
		load_btn.text = "Load"
		load_btn.custom_minimum_size = Vector2(80, 30)
		var p := path
		load_btn.pressed.connect(func() -> void: _load_map(p))
		row.add_child(load_btn)
		var del_btn := Button.new()
		del_btn.text = "X"
		del_btn.custom_minimum_size = Vector2(36, 30)
		var p2 := path
		del_btn.pressed.connect(func() -> void: _delete_map(p2))
		row.add_child(del_btn)
		_load_list.add_child(row)
	_load_panel.visible = true


func _load_map(path: String) -> void:
	var m := MapIO.load_from_file(path)
	if m.is_empty():
		_set_status("Load failed: %s" % path.get_file())
		return
	_map = m
	_name_edit.text = str(m.get("name", "map"))
	_load_panel.visible = false
	_set_status("Loaded %s" % path.get_file())
	queue_redraw()


func _delete_map(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_open_load()


func _generate() -> void:
	var seed_val: int
	if _seed_edit.text.strip_edges().is_valid_int():
		seed_val = int(_seed_edit.text)
	else:
		seed_val = int(Time.get_unix_time_from_system())
		_seed_edit.text = str(seed_val)
	_map = MapGen.generate(seed_val)
	_name_edit.text = str(_map.get("name", "generated"))
	_set_status("Generated with seed %d. Edit & Save, or Play-test." % seed_val)
	queue_redraw()


func _play_test() -> void:
	if _map.get("platforms", []).is_empty():
		_set_status("Add at least one platform first (or Generate).")
		return
	var path := MapIO.save_to_file("_playtest", _map)
	if path == "":
		_set_status("Play-test save failed.")
		return
	Settings.custom_map_path = path
	Settings.save()
	Net.set_singleplayer()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _exit_to_menu() -> void:
	# Leave custom_map_path as-is; menu's Map picker still points at whatever
	# the user last selected. Editor doesn't own that setting.
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _set_tool(t: int) -> void:
	_tool = t
	if _tool_label != null:
		_tool_label.text = "Tool: %s" % _tool_name(t)


func _tool_name(t: int) -> String:
	match t:
		Tool.PLATFORM: return "Platform (drag)"
		Tool.MOVE: return "Move (drag)"
		Tool.DELETE: return "Delete"
		Tool.PLAYER_SPAWN: return "Player Spawn"
		Tool.BOT_SPAWN: return "Bot Spawn"
		Tool.FLAG_BLUE: return "Blue Flag"
		Tool.FLAG_RED: return "Red Flag"
		Tool.FLAG_NEUTRAL: return "Neutral Flag (INF/HTF/RM)"
		Tool.DOM_POINT: return "Dom Point"
		Tool.M2_MOUNT: return "M2 Mount"
	return "?"


func _set_status(s: String) -> void:
	if _status != null:
		_status.text = s
