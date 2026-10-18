extends PanelContainer
## End-of-round map vote (winner screen): three buttons + 1/2/3 keys (D-pad
## ↑ → ↓ on a pad). Built lazily by the HUD the first time a round ends with
## choices; refresh(main) mirrors main.next_map_choices / next_map_tally.

var _nm_btns: Array = []
var _nm_title: Label = null


func _init() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.05, 0.05, 0.09, 0.85), UITheme.COL_ACCENT_DIM))
	# Top centre, under the score strip: the end-of-round scoreboard covers
	# the bottom half.
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -330
	offset_right = 330
	offset_top = 150
	offset_bottom = 240
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	_nm_title = Label.new()
	_nm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_body(_nm_title, 15, UITheme.COL_ACCENT_HI)
	vb.add_child(_nm_title)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	for i in 3:
		var b := UITheme.make_small_button("", 200, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		var idx := i
		b.pressed.connect(func() -> void: _vote(idx))
		hb.add_child(b)
		_nm_btns.append(b)
	visible = false
	add_to_group("touch_passthrough")   # taps reach the buttons


## Main is the HUD's parent (the panel is a child of the HUD).
func _main() -> Node:
	var h := get_parent()
	return h.get_parent() if h != null else null


func _vote(idx: int) -> void:
	var m := _main()
	if m != null and m.has_method("vote_next_map"):
		m.vote_next_map(idx)


func refresh(main: Node) -> void:
	visible = true
	var choices: Array = main.get("next_map_choices") if main.get("next_map_choices") != null else []
	var tally: Array = main.next_map_tally
	var mine: int = int(main.my_next_map_vote)
	var pad := not Input.get_connected_joypads().is_empty()
	var keys := ["↑", "→", "↓"]
	_nm_title.text = tr("NEXT MAP - vote: %s") % ("1 / 2 / 3" + ("  ·  D-pad ↑ → ↓" if pad else "")) + "   ·   %ds" % int(ceil(float(main.winner_end_t)))
	for i in 3:
		var b: Button = _nm_btns[i]
		b.visible = i < choices.size()
		if not b.visible:
			continue
		var n := int(tally[i]) if i < tally.size() else 0
		b.text = "%d%s  %s%s" % [i + 1, ("/" + keys[i]) if pad else "", main.next_map_name(i), ("   (%d)" % n) if n > 0 else ""]
		b.modulate = Color(1.0, 0.85, 0.4) if i == mine else Color(1, 1, 1)


## 1/2/3 (keypad too) or D-pad ↑ → ↓ while the panel is up. True = consumed.
func handle_key(event: InputEvent) -> bool:
	if not visible:
		return false
	var pick := -1
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = (event as InputEventKey).physical_keycode
		if kc >= KEY_1 and kc <= KEY_3:
			pick = kc - KEY_1
		elif kc >= KEY_KP_1 and kc <= KEY_KP_3:
			pick = kc - KEY_KP_1
	elif event is InputEventJoypadButton and event.pressed:
		pick = {JOY_BUTTON_DPAD_UP: 0, JOY_BUTTON_DPAD_RIGHT: 1, JOY_BUTTON_DPAD_DOWN: 2}.get((event as InputEventJoypadButton).button_index, -1)
	if pick < 0:
		return false
	_vote(pick)
	get_viewport().set_input_as_handled()
	return true
