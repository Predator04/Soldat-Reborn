extends VBoxContainer
## Controls settings panel — scrollable action list with click-to-rebind.
##
## Lives inside the pause menu Settings screen. Each row: action label +
## a button showing the current primary binding. Click the button, then press
## any key or mouse button to rebind it. ESC cancels a capture in progress.
## "Reset to Defaults" wipes overrides. Bindings persist via ControlsMap.save().

const ControlsMap = preload("res://scripts/controls_map.gd")
const UITheme = preload("res://scripts/ui_theme.gd")

signal back_pressed

var _capturing_action := ""
var _capturing_btn: Button = null
var _rows: Array = []          # array of dicts: {action, button, status_label}
var _status_label: Label
var _prompt_layer: Control


var _root_panel: PanelContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(560, 0)
	set_anchors_preset(Control.PRESET_CENTER, true)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_build()


func _build() -> void:
	_root_panel = PanelContainer.new()
	_root_panel.add_theme_stylebox_override("panel", UITheme.panel_style())
	_root_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.process_mode = Node.PROCESS_MODE_ALWAYS
	_root_panel.add_child(col)

	col.add_child(UITheme.make_screen_title("CONTROLS"))

	var rule := ColorRect.new()
	rule.color = UITheme.COL_ACCENT_DIM
	rule.custom_minimum_size = Vector2(0, 1)
	col.add_child(rule)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", UITheme.COL_INFO)
	_status_label.custom_minimum_size = Vector2(0, 20)
	_status_label.text = "Click a binding, then press a key or mouse button (ESC = cancel)."
	col.add_child(_status_label)

	# Scroll region so 25+ actions fit on a 720p screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	col.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	list.process_mode = Node.PROCESS_MODE_ALWAYS
	scroll.add_child(list)

	# Group rows by section (Movement / Combat / Weapons / Chat / Utility).
	# Preserves the action ordering inside each section so muscle-memory rows
	# (weapon slots 1-0, etc.) still appear in their expected order.
	var grouped: Dictionary = {}
	var order: Array = []
	for aid in ControlsMap.action_ids():
		var sec := ControlsMap.section_for(String(aid))
		if not grouped.has(sec):
			grouped[sec] = []
			order.append(sec)
		grouped[sec].append(String(aid))
	var row_idx: int = 0
	for sec in order:
		list.add_child(UITheme.make_section_header(String(sec)))
		row_idx = 0
		for aid in grouped[sec]:
			list.add_child(_make_row(String(aid), row_idx))
			row_idx += 1

	col.add_child(UITheme.spacer(4))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.process_mode = Node.PROCESS_MODE_ALWAYS
	col.add_child(buttons)

	var reset := _make_button("RESET TO DEFAULTS")
	reset.pressed.connect(_on_reset)
	buttons.add_child(reset)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_abort_capture()
		back_pressed.emit())
	buttons.add_child(back)
	# #93: seed focus on BACK so arrow keys work before a mouse click.
	back.call_deferred("grab_focus")


func _make_row(action_id: String, row_idx: int) -> Control:
	# Rows sit in a PanelContainer so we can alternate row shading for scan-ability.
	# The row itself is an HBox: action label on the left, binding button on the right.
	var pc := PanelContainer.new()
	pc.process_mode = Node.PROCESS_MODE_ALWAYS
	if row_idx % 2 == 1:
		var s := StyleBoxFlat.new()
		s.bg_color = UITheme.COL_PANEL_ROW
		s.corner_radius_top_left = 2
		s.corner_radius_top_right = 2
		s.corner_radius_bottom_left = 2
		s.corner_radius_bottom_right = 2
		s.content_margin_left = 6
		s.content_margin_right = 6
		s.content_margin_top = 2
		s.content_margin_bottom = 2
		pc.add_theme_stylebox_override("panel", s)
	else:
		var s2 := StyleBoxFlat.new()
		s2.bg_color = Color(0, 0, 0, 0)
		s2.content_margin_left = 6
		s2.content_margin_right = 6
		s2.content_margin_top = 2
		s2.content_margin_bottom = 2
		pc.add_theme_stylebox_override("panel", s2)

	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 30)
	row.add_theme_constant_override("separation", 12)
	row.process_mode = Node.PROCESS_MODE_ALWAYS
	pc.add_child(row)

	var lbl := Label.new()
	lbl.text = ControlsMap.label_for(action_id)
	lbl.custom_minimum_size = Vector2(240, 0)
	UITheme.style_body(lbl, 14, UITheme.COL_TEXT)
	row.add_child(lbl)

	var btn := Button.new()
	btn.text = ControlsMap.primary_label(action_id)
	btn.custom_minimum_size = Vector2(240, 28)
	UITheme.style_button(btn, 14, false)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.pressed.connect(func() -> void: _begin_capture(action_id, btn))
	row.add_child(btn)

	_rows.append({"action": action_id, "button": btn})
	return pc


func _make_button(text: String) -> Button:
	var b := UITheme.make_button(text, false, 220, 38)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	return b


func _begin_capture(action_id: String, btn: Button) -> void:
	if _capturing_action != "":
		# Already capturing — clicking another row cancels the first.
		_abort_capture()
	_capturing_action = action_id
	_capturing_btn = btn
	btn.text = "…press key or mouse…"
	_status_label.text = "Press a key or mouse button for '%s' (ESC to cancel)." \
		% ControlsMap.label_for(action_id)


func _abort_capture() -> void:
	if _capturing_action == "":
		return
	if is_instance_valid(_capturing_btn):
		_capturing_btn.text = ControlsMap.primary_label(_capturing_action)
	_capturing_action = ""
	_capturing_btn = null
	_status_label.text = "Click a binding, then press a key or mouse button (ESC = cancel)."


func _refresh_all_rows() -> void:
	for r in _rows:
		var b: Button = r["button"]
		if is_instance_valid(b):
			b.text = ControlsMap.primary_label(String(r["action"]))


func _on_reset() -> void:
	_abort_capture()
	ControlsMap.reset_all()
	_refresh_all_rows()
	_status_label.text = "Bindings reset to defaults."


func _input(event: InputEvent) -> void:
	if _capturing_action == "":
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	if not event.pressed:
		return
	if event is InputEventKey:
		if (event as InputEventKey).echo:
			return
		# ESC is reserved for the pause menu / cancel — never rebindable.
		# pause_menu._input reads _capturing_action and calls _abort_capture()
		# for us, so just ignore ESC here (don't consume it).
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			return
	get_viewport().set_input_as_handled()

	var target := _capturing_action
	var conflict := ControlsMap.find_conflict(event, target)
	ControlsMap.rebind(target, event)
	ControlsMap.save()

	_capturing_action = ""
	_capturing_btn = null
	_refresh_all_rows()
	if conflict != "":
		_status_label.text = "Bound '%s' → %s. Unbound from '%s' (was a duplicate)." \
			% [ControlsMap.label_for(target), ControlsMap.event_display(event), ControlsMap.label_for(conflict)]
	else:
		_status_label.text = "Bound '%s' → %s." \
			% [ControlsMap.label_for(target), ControlsMap.event_display(event)]
