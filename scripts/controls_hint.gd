extends PanelContainer
## ControlsHint — a small "how to play" card at the bottom of the screen.
##
## Shows by itself for the first few matches (Settings.help_seen counts them),
## fades after HOLD seconds, and H (the "help" action) toggles it any time.
## Labels come from the live InputMap, so rebinds show up here. Hidden on touch
## devices, whose on-screen buttons are already labelled.

const ControlsMap = preload("res://scripts/controls_map.gd")
const HOLD := 12.0
const AUTO_MATCHES := 3

const ROWS := [
	["Move", "move_left|move_right"],
	["Jump", "jump"],
	["Jet boots", "jet"],
	["Fire (aim with the mouse)", "fire"],
	["Crouch / prone", "crouch|prone"],
	["Throw grenade / type", "grenade|grenade_toggle"],
	["Reload", "reload"],
	["Swap to secondary", "secondary_swap"],
	["Weapons", "weapon_1|weapon_10"],
	["Drop gun / mount M2", "weapon_throw"],
	["Scoreboard", "scoreboard"],
	["Chat / team chat", "chat|team_chat"],
	["Team radio", "radio"],
	["Menu", "pause"],
	["This help", "help"],
]

var _t := 0.0
var _auto := false
var _help_down := false
var _grid: GridContainer
var _goal: Label
const GameInfo = preload("res://scripts/game_info.gd")
const BonusPickup = preload("res://scripts/bonus_pickup.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.hud_strip_style())
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var title := Label.new()
	title.text = "CONTROLS"
	title.add_theme_color_override("font_color", UITheme.COL_ACCENT)
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)
	_goal = Label.new()
	_goal.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_goal.add_theme_font_size_override("font_size", 12)
	box.add_child(_goal)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 1)
	box.add_child(_grid)
	# What the things lying around the map do.
	var ph := Label.new()
	ph.text = "PICKUPS"
	ph.add_theme_color_override("font_color", UITheme.COL_ACCENT)
	ph.add_theme_font_size_override("font_size", 13)
	box.add_child(ph)
	var pg := GridContainer.new()
	pg.columns = 2
	pg.add_theme_constant_override("h_separation", 14)
	pg.add_theme_constant_override("v_separation", 1)
	for k in ["medkit", "grenades", "vest", "predator", "berserker", "cluster"]:
		var n := Label.new()
		n.text = GameInfo.item_label(k)
		n.add_theme_color_override("font_color", BonusPickup.kind_color(k))
		n.add_theme_font_size_override("font_size", 12)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var dsc := Label.new()
		dsc.text = GameInfo.item_desc(k)
		dsc.add_theme_color_override("font_color", UITheme.COL_TEXT)
		dsc.add_theme_font_size_override("font_size", 12)
		pg.add_child(n)
		pg.add_child(dsc)
	box.add_child(pg)
	_fill()
	visible = false
	if _touch() or Net.is_dedicated or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	if int(Settings.help_seen) < AUTO_MATCHES:
		Settings.help_seen = int(Settings.help_seen) + 1
		Settings.save()
		_show(true)


func _touch() -> bool:
	return OS.has_feature("android") or OS.has_feature("mobile") \
		or DisplayServer.is_touchscreen_available() or "--force-touch" in OS.get_cmdline_user_args()


func _label_for(action: String) -> String:
	var pad := not Input.get_connected_joypads().is_empty()
	var k := ControlsMap.primary_label(action)
	if pad:
		for ev in (InputMap.action_get_events(action) if InputMap.has_action(action) else []):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				var p := ControlsMap.event_display(ev)
				return p if k == "—" else "%s / %s" % [k, p]
	return k


func _fill() -> void:
	if _goal != null:
		_goal.text = "%s — %s" % [GameInfo.mode_title(Settings.game_mode), GameInfo.mode_goal(Settings.game_mode)]
	for c in _grid.get_children():
		c.queue_free()
	for row in ROWS:
		var keys: PackedStringArray = PackedStringArray()
		for a in str(row[1]).split("|"):
			keys.append(_label_for(a))
		var sep := " – " if str(row[0]) == "Weapons" else " / "
		var k := Label.new()
		k.text = sep.join(keys)
		k.add_theme_color_override("font_color", UITheme.COL_HUD_WEAPON)
		k.add_theme_font_size_override("font_size", 12)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var d := Label.new()
		d.text = str(row[0])
		d.add_theme_color_override("font_color", UITheme.COL_TEXT)
		d.add_theme_font_size_override("font_size", 12)
		_grid.add_child(k)
		_grid.add_child(d)


func _place() -> void:
	# Bottom-centre, sized to the content (no anchors: the HUD root isn't a
	# full-rect container on every path).
	reset_size()
	var vp := get_viewport_rect().size
	position = Vector2(roundf((vp.x - size.x) * 0.5), vp.y - size.y - 18.0)


func _show(auto: bool) -> void:
	_fill()   # pick up rebinds / a pad plugged in since last time
	call_deferred("_place")
	_auto = auto
	_t = 0.0
	modulate.a = 1.0
	visible = true


func _process(delta: float) -> void:
	var typing: bool = get_viewport().gui_get_focus_owner() is LineEdit
	var down := InputMap.has_action("help") and Input.is_action_pressed("help") and not typing
	if down and not _help_down:
		if visible:
			visible = false
		else:
			_show(false)
	_help_down = down
	if visible and _auto:
		_t += delta
		if _t > HOLD:
			modulate.a = clampf(1.0 - (_t - HOLD), 0.0, 1.0)
			if modulate.a <= 0.0:
				visible = false
