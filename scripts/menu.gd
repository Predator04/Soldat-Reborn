extends Control
## Main menu — title, Play, Settings (SFX volume / screen shake / fullscreen), Quit.

var _menu_box: VBoxContainer
var _settings_panel: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Settings.apply_display()
	_build_backdrop()
	_build_title()
	_build_menu()
	_build_settings()
	_build_footer()


func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _build_title() -> void:
	var title := Label.new()
	title.text = "SOLDAT REBORN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 70
	title.offset_bottom = 150
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 8)
	add_child(title)

	var sub := Label.new()
	sub.text = "jet boots · bunny hop · ragdoll gibs"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 155
	sub.offset_bottom = 185
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.65, 0.7, 0.82))
	add_child(sub)


func _build_menu() -> void:
	_menu_box = VBoxContainer.new()
	_menu_box.set_anchors_preset(Control.PRESET_CENTER)
	_menu_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu_box.add_theme_constant_override("separation", 14)
	add_child(_menu_box)

	var play := _make_button("PLAY")
	play.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	_menu_box.add_child(play)

	var settings := _make_button("SETTINGS")
	settings.pressed.connect(func() -> void:
		_menu_box.visible = false
		_settings_panel.visible = true)
	_menu_box.add_child(settings)

	var quit := _make_button("QUIT")
	quit.pressed.connect(func() -> void: get_tree().quit())
	_menu_box.add_child(quit)


func _build_settings() -> void:
	_settings_panel = VBoxContainer.new()
	_settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	_settings_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings_panel.add_theme_constant_override("separation", 16)
	_settings_panel.custom_minimum_size = Vector2(440, 0)
	_settings_panel.visible = false
	add_child(_settings_panel)

	var head := Label.new()
	head.text = "SETTINGS"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	_settings_panel.add_child(head)

	var vol_lbl := Label.new()
	vol_lbl.text = "SFX volume"
	vol_lbl.add_theme_font_size_override("font_size", 16)
	_settings_panel.add_child(vol_lbl)

	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Settings.sfx_volume
	vol.value_changed.connect(func(v: float) -> void:
		Settings.sfx_volume = v
		Settings.save())
	_settings_panel.add_child(vol)

	var shake := CheckButton.new()
	shake.text = "Screen shake"
	shake.button_pressed = Settings.screen_shake
	shake.toggled.connect(func(on: bool) -> void:
		Settings.screen_shake = on
		Settings.save())
	_settings_panel.add_child(shake)

	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.save()
		Settings.apply_display())
	_settings_panel.add_child(fs)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_settings_panel.visible = false
		_menu_box.visible = true)
	_settings_panel.add_child(back)


func _build_footer() -> void:
	var foot := Label.new()
	foot.text = "WASD move · SPACE/W jet · mouse aim · LMB shoot · 1-4 weapons · R reload · G grenade"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -40
	foot.offset_bottom = -12
	foot.add_theme_font_size_override("font_size", 14)
	foot.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	add_child(foot)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 52)
	b.add_theme_font_size_override("font_size", 22)
	return b
