extends VBoxContainer
## SettingsPanel — glassmorphism accordion of setting sections.
##
## Six collapsible cards (Audio, Video, Controls, Game, Mods, Cosmetics) live
## inside a scrolling column. Cards are collapsed by default so the panel fits
## on a 720p screen without immediately drowning the player in sliders. Each
## card uses a dark semi-transparent StyleBoxFlat with rounded corners for the
## glass look. Both the main menu and the pause menu instantiate this.

signal back_pressed
signal controls_pressed  # menu / pause both hand controls off to their own screen

const ControlsMap = preload("res://scripts/controls_map.gd")

# Cards keep their toggle state in a local dict so re-opening the panel
# preserves whatever the user had expanded. Reset by construction each session.
var _card_open: Dictionary = {}
var _card_bodies: Dictionary = {}
var _card_arrows: Dictionary = {}
var _stats_body: RichTextLabel = null
var _sp_map_pick: OptionButton = null
var _sp_map_paths: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(540, 0)
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_build()


func _build() -> void:
	var head := Label.new()
	head.text = "SETTINGS"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 30)
	head.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	head.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	head.add_theme_constant_override("outline_size", 6)
	add_child(head)

	# Scroll region — fixed height so multiple expanded cards don't push the
	# BACK button off a 720p viewport. 400px comfortably shows a header + a
	# fully expanded Audio or Game card without cropping.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	col.process_mode = Node.PROCESS_MODE_ALWAYS
	scroll.add_child(col)

	col.add_child(_make_card("Audio", func(box: VBoxContainer) -> void: _build_audio(box)))
	col.add_child(_make_card("Video", func(box: VBoxContainer) -> void: _build_video(box)))
	col.add_child(_make_card("Controls", func(box: VBoxContainer) -> void: _build_controls_card(box)))
	col.add_child(_make_card("Game", func(box: VBoxContainer) -> void: _build_game(box)))
	col.add_child(_make_card("Mods", func(box: VBoxContainer) -> void: _build_mods(box)))
	col.add_child(_make_card("Cosmetics", func(box: VBoxContainer) -> void: _build_cosmetics(box)))

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)


# ── Card factory ──────────────────────────────────────────

func _glass_style(border_col: Color = Color(0.55, 0.65, 0.85, 0.4)) -> StyleBoxFlat:
	# Dark semi-transparent glass with rounded corners + subtle inner border.
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.14, 0.55)
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_color = border_col
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s


func _make_card(title: String, builder: Callable) -> Control:
	# Wrapper Panel gives us the glass background + margins. Contains a clickable
	# header row (title + chevron) and a body VBoxContainer hidden by default.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _glass_style())
	card.process_mode = Node.PROCESS_MODE_ALWAYS
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.process_mode = Node.PROCESS_MODE_ALWAYS
	card.add_child(col)

	var header := Button.new()
	header.flat = true
	header.text = "  ▸  " + title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.custom_minimum_size = Vector2(0, 36)
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	header.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.6))
	header.process_mode = Node.PROCESS_MODE_ALWAYS
	col.add_child(header)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.visible = false
	body.process_mode = Node.PROCESS_MODE_ALWAYS
	col.add_child(body)

	_card_open[title] = false
	_card_bodies[title] = body
	_card_arrows[title] = header

	header.pressed.connect(func() -> void:
		var open: bool = not bool(_card_open.get(title, false))
		_card_open[title] = open
		body.visible = open
		# ▸ collapsed / ▾ expanded — same UTF chevron style as gh's issues list.
		header.text = ("  ▾  " if open else "  ▸  ") + title
		if open and body.get_child_count() == 0:
			builder.call(body))
	return card


# ── Section builders ──────────────────────────────────────

func _build_audio(box: VBoxContainer) -> void:
	box.add_child(_labelled_slider("SFX Volume", 0.0, 1.0, 0.05,
		Settings.sfx_volume,
		func(v: float) -> void:
			Settings.sfx_volume = v
			Settings.save()))
	box.add_child(_labelled_slider("Music Volume", 0.0, 1.0, 0.05,
		Settings.music_volume,
		func(v: float) -> void:
			Settings.music_volume = v
			Settings.save()
			Music.apply_volume()))
	box.add_child(_check_button("Mute music", Settings.music_muted,
		func(on: bool) -> void:
			Settings.music_muted = on
			Settings.save()
			Music.apply_volume()))


func _build_video(box: VBoxContainer) -> void:
	box.add_child(_check_button("Fullscreen", Settings.fullscreen,
		func(on: bool) -> void:
			Settings.fullscreen = on
			Settings.save()
			Settings.apply_display()))
	box.add_child(_check_button("Lo-fi mode (no particles/gibs — low-end PCs)", Settings.lofi,
		func(on: bool) -> void:
			Settings.lofi = on
			Settings.save()))
	box.add_child(_check_button("Show FPS overlay", Settings.show_fps,
		func(on: bool) -> void:
			Settings.show_fps = on
			Settings.save()))


func _build_controls_card(box: VBoxContainer) -> void:
	box.add_child(_labelled_slider("Mouse Sensitivity", 0.25, 3.0, 0.05,
		Settings.mouse_sensitivity,
		func(v: float) -> void:
			Settings.mouse_sensitivity = v
			Settings.save(),
		"%.2fx"))
	var open_btn := _make_button("REBIND KEYS…")
	open_btn.pressed.connect(func() -> void: controls_pressed.emit())
	box.add_child(open_btn)


func _build_game(box: VBoxContainer) -> void:
	# Screen shake — now a 0-2 intensity slider. Setting to 0 disables shake
	# (matches the old bool-off behavior); >0 keeps `screen_shake=true` set so
	# any legacy code paths still fire, but the intensity scales the amount.
	box.add_child(_labelled_slider("Screen Shake", 0.0, 2.0, 0.05,
		Settings.screen_shake_intensity,
		func(v: float) -> void:
			Settings.screen_shake_intensity = v
			Settings.screen_shake = v > 0.01
			Settings.save(),
		"%.2fx"))
	box.add_child(_labelled_slider("Blood / Gore intensity", 0.0, 1.5, 0.05,
		Settings.blood_intensity,
		func(v: float) -> void:
			Settings.blood_intensity = v
			# Lo-fi tracks blood_intensity==0 for cleanliness: no gibs, no particles.
			Settings.lofi = v <= 0.01 or Settings.lofi
			Settings.save(),
		"%.2fx"))
	# Sub-mode chips — Realistic / Survival / Advance stay here since they're
	# game-side toggles, not audio/video/controls.
	box.add_child(_check_button("Realistic (no jet, no HUD ammo, 1HK headshots)",
		Settings.realistic,
		func(on: bool) -> void:
			Settings.realistic = on
			Settings.save()))
	box.add_child(_check_button("Survival (no respawn until round end)",
		Settings.survival,
		func(on: bool) -> void:
			Settings.survival = on
			Settings.save()))
	box.add_child(_check_button("Advance (weapon unlock ladder)",
		Settings.advance,
		func(on: bool) -> void:
			Settings.advance = on
			Settings.save()))


func _build_mods(box: VBoxContainer) -> void:
	box.add_child(_labelled_slider("Gravity", 0.5, 2.0, 0.05,
		Settings.mod_gravity,
		func(v: float) -> void:
			Settings.mod_gravity = v
			Settings.save(),
		"%.2fx"))
	box.add_child(_labelled_slider("Jet fuel regen", 0.5, 2.0, 0.05,
		Settings.mod_jet,
		func(v: float) -> void:
			Settings.mod_jet = v
			Settings.save(),
		"%.2fx"))
	box.add_child(_labelled_slider("Weapon damage", 0.5, 2.0, 0.05,
		Settings.mod_damage,
		func(v: float) -> void:
			Settings.mod_damage = v
			Settings.save(),
		"%.2fx"))
	box.add_child(_labelled_slider("Player speed", 0.5, 1.5, 0.05,
		Settings.mod_speed,
		func(v: float) -> void:
			Settings.mod_speed = v
			Settings.save(),
		"%.2fx"))
	# Bot count slider — -1 renders as "Auto", 0-8 as their integer.
	var bc_row := HBoxContainer.new()
	bc_row.add_theme_constant_override("separation", 12)
	box.add_child(bc_row)
	var bc_lbl := Label.new()
	bc_lbl.text = "Bots"
	bc_lbl.custom_minimum_size = Vector2(170, 0)
	bc_lbl.add_theme_font_size_override("font_size", 14)
	bc_row.add_child(bc_lbl)
	var bc_slider := HSlider.new()
	bc_slider.min_value = -1
	bc_slider.max_value = 8
	bc_slider.step = 1
	bc_slider.value = float(Settings.bot_count)
	bc_slider.custom_minimum_size = Vector2(220, 0)
	bc_row.add_child(bc_slider)
	var bc_val := Label.new()
	bc_val.text = "Auto" if Settings.bot_count < 0 else str(Settings.bot_count)
	bc_val.custom_minimum_size = Vector2(56, 0)
	bc_val.add_theme_font_size_override("font_size", 14)
	bc_row.add_child(bc_val)
	bc_slider.value_changed.connect(func(v: float) -> void:
		var n: int = int(round(v))
		bc_val.text = "Auto" if n < 0 else str(n)
		Settings.bot_count = n
		Settings.save())

	box.add_child(_labelled_slider("Bot skill", 1.0, 5.0, 1.0,
		float(Settings.bot_skill),
		func(v: float) -> void:
			Settings.bot_skill = clampi(int(round(v)), 1, 5)
			Settings.save(),
		"%d"))

	var reset := _make_button("RESET MODS")
	reset.pressed.connect(func() -> void:
		Settings.mod_gravity = 1.0
		Settings.mod_jet = 1.0
		Settings.mod_damage = 1.0
		Settings.mod_speed = 1.0
		Settings.bot_count = -1
		Settings.bot_skill = 3
		Settings.save()
		# Rebuild the card body so slider positions reflect the reset.
		for c in box.get_children():
			c.queue_free()
		call_deferred("_build_mods", box))
	box.add_child(reset)


func _build_cosmetics(box: VBoxContainer) -> void:
	var head_opts := ["helm", "kap", "hair1", "hair2", "hair3", "hair4", "none"]
	box.add_child(_option_row("Head", head_opts, Settings.cos_head,
		func(v: String) -> void:
			Settings.cos_head = v
			Settings.save()))
	var chain_opts := ["none", "silver", "gold"]
	box.add_child(_option_row("Chain", chain_opts, Settings.cos_chain,
		func(v: String) -> void:
			Settings.cos_chain = v
			Settings.save()))
	box.add_child(_check_button("Vest (kamizelka)", Settings.cos_vest,
		func(on: bool) -> void:
			Settings.cos_vest = on
			Settings.save()))
	box.add_child(_check_button("Cigar (cygaro)", Settings.cos_cigar,
		func(on: bool) -> void:
			Settings.cos_cigar = on
			Settings.save()))
	box.add_child(_check_button("Dreadlocks (dred)", Settings.cos_dreadlocks,
		func(on: bool) -> void:
			Settings.cos_dreadlocks = on
			Settings.save()))
	box.add_child(_check_button("Dogtag (metal)", Settings.cos_dogtag,
		func(on: bool) -> void:
			Settings.cos_dogtag = on
			Settings.save()))


# ── Widget helpers ────────────────────────────────────────

func _labelled_slider(label_text: String, mn: float, mx: float, step: float,
		val: float, on_change: Callable, val_fmt: String = "%.2f") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(170, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = mn
	slider.max_value = mx
	slider.step = step
	slider.value = val
	slider.custom_minimum_size = Vector2(220, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var vlbl := Label.new()
	vlbl.text = val_fmt % val
	vlbl.custom_minimum_size = Vector2(56, 0)
	vlbl.add_theme_font_size_override("font_size", 14)
	row.add_child(vlbl)
	slider.value_changed.connect(func(v: float) -> void:
		vlbl.text = val_fmt % v
		on_change.call(v))
	return row


func _check_button(text: String, val: bool, on_change: Callable) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = val
	cb.toggled.connect(on_change)
	return cb


func _option_row(label_text: String, options: Array, current: String, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl)
	var pick := OptionButton.new()
	for opt in options:
		pick.add_item(String(opt).capitalize())
	pick.selected = clampi(options.find(current), 0, options.size() - 1)
	pick.custom_minimum_size = Vector2(240, 32)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pick)
	pick.item_selected.connect(func(idx: int) -> void:
		if idx >= 0 and idx < options.size():
			on_change.call(String(options[idx])))
	return row


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 40)
	b.add_theme_font_size_override("font_size", 18)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	return b
