extends Control
## Main menu — Play (vs bots), Host, Join, Settings, Quit.

const MAP_NAMES := ["Ascent", "Towers", "Pillars"]

var _menu_box: VBoxContainer
var _settings_panel: VBoxContainer
var _join_panel: VBoxContainer
var _host_panel: VBoxContainer
var _status_label: Label
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _connect_btn: Button
var _map_pick: OptionButton
var _connecting := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.set_custom_mouse_cursor(load("res://assets/interface-gfx/menucursor.png"), Input.CURSOR_ARROW, Vector2(36, 36))
	Settings.apply_display()
	Net.leave()  # clean state on returning to menu from a game
	_build_backdrop()
	_build_title()
	_build_menu()
	_build_settings()
	_build_host()
	_build_join()
	_build_status()
	_build_footer()
	Net.status_changed.connect(_on_net_status_changed)
	Net.connected.connect(_on_net_connected)
	Net.disconnected.connect(_on_net_disconnected)
	Net.map_received.connect(_on_map_received)


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
	title.offset_top = 60
	title.offset_bottom = 140
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 8)
	add_child(title)

	var sub := Label.new()
	sub.text = "jet boots · bunny hop · ragdoll gibs · online"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 145
	sub.offset_bottom = 175
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.65, 0.7, 0.82))
	add_child(sub)


func _build_menu() -> void:
	_menu_box = VBoxContainer.new()
	_menu_box.set_anchors_preset(Control.PRESET_CENTER)
	_menu_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu_box.add_theme_constant_override("separation", 12)
	add_child(_menu_box)

	var play := _make_button("PLAY vs BOTS")
	play.pressed.connect(func() -> void:
		Net.set_singleplayer()
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	_menu_box.add_child(play)

	var host := _make_button("HOST GAME")
	host.pressed.connect(func() -> void:
		_menu_box.visible = false
		_host_panel.visible = true)
	_menu_box.add_child(host)

	var join := _make_button("JOIN GAME")
	join.pressed.connect(func() -> void:
		_menu_box.visible = false
		_join_panel.visible = true)
	_menu_box.add_child(join)

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


func _build_host() -> void:
	_host_panel = VBoxContainer.new()
	_host_panel.set_anchors_preset(Control.PRESET_CENTER)
	_host_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_host_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_host_panel.add_theme_constant_override("separation", 10)
	_host_panel.custom_minimum_size = Vector2(400, 0)
	_host_panel.visible = false
	add_child(_host_panel)

	var head := Label.new()
	head.text = "HOST GAME"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	_host_panel.add_child(head)

	var map_lbl := Label.new()
	map_lbl.text = "Map"
	map_lbl.add_theme_font_size_override("font_size", 15)
	_host_panel.add_child(map_lbl)

	_map_pick = OptionButton.new()
	for name in MAP_NAMES:
		_map_pick.add_item(name)
	_map_pick.selected = clampi(Settings.map_index, 0, MAP_NAMES.size() - 1)
	_map_pick.custom_minimum_size = Vector2(0, 36)
	_host_panel.add_child(_map_pick)

	var start := _make_button("START HOSTING")
	start.pressed.connect(func() -> void:
		var idx := _map_pick.get_selected_id()
		if idx < 0:
			idx = _map_pick.selected
		idx = clampi(idx, 0, MAP_NAMES.size() - 1)
		Settings.map_index = idx
		Settings.save()
		start.disabled = true
		if Net.host_game(Net.DEFAULT_PORT, idx):
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		else:
			# Net.host_game already set the status text; re-enable so the user can retry.
			start.disabled = false
			_status_label.text = Net.status)
	_host_panel.add_child(start)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_host_panel.visible = false
		_menu_box.visible = true)
	_host_panel.add_child(back)


func _build_join() -> void:
	_join_panel = VBoxContainer.new()
	_join_panel.set_anchors_preset(Control.PRESET_CENTER)
	_join_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_join_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_join_panel.add_theme_constant_override("separation", 10)
	_join_panel.custom_minimum_size = Vector2(400, 0)
	_join_panel.visible = false
	add_child(_join_panel)

	var head := Label.new()
	head.text = "JOIN GAME"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	_join_panel.add_child(head)

	var ip_lbl := Label.new()
	ip_lbl.text = "Host IP"
	ip_lbl.add_theme_font_size_override("font_size", 15)
	_join_panel.add_child(ip_lbl)

	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(0, 36)
	_join_panel.add_child(_ip_edit)

	var port_lbl := Label.new()
	port_lbl.text = "Port"
	port_lbl.add_theme_font_size_override("font_size", 15)
	_join_panel.add_child(port_lbl)

	_port_edit = LineEdit.new()
	_port_edit.text = str(Net.DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(0, 36)
	_join_panel.add_child(_port_edit)

	_connect_btn = _make_button("CONNECT")
	_connect_btn.pressed.connect(_on_connect_pressed)
	_join_panel.add_child(_connect_btn)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		Net.leave()
		_connecting = false
		_connect_btn.disabled = false
		_join_panel.visible = false
		_menu_box.visible = true)
	_join_panel.add_child(back)


func _build_status() -> void:
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_label.offset_top = -78
	_status_label.offset_bottom = -58
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_status_label.add_theme_constant_override("outline_size", 3)
	add_child(_status_label)


func _build_footer() -> void:
	var foot := Label.new()
	foot.text = "WASD move · W jump · S crouch · X prone · RMB jet · LMB shoot · 1-0 primaries · Q secondary · R reload · E grenade"
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
	b.custom_minimum_size = Vector2(300, 48)
	b.add_theme_font_size_override("font_size", 22)
	return b


func _on_connect_pressed() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	var port := int(_port_edit.text) if _port_edit.text.is_valid_int() else Net.DEFAULT_PORT
	_connecting = true
	_connect_btn.disabled = true
	if not Net.join_game(ip, port):
		_connecting = false
		_connect_btn.disabled = false
		return
	# Watchdog: if neither connected nor disconnected fires within a few seconds,
	# re-enable the button so the user isn't stuck on a spinner forever.
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if _connecting and is_instance_valid(_connect_btn):
			_connecting = false
			_connect_btn.disabled = false
			Net.leave()
			_status_label.text = "Connection timed out")


func _on_net_status_changed() -> void:
	_status_label.text = Net.status


func _on_net_connected() -> void:
	# Client waits for the host's map RPC before loading main.tscn — see _on_map_received.
	pass


func _on_map_received() -> void:
	if Net.is_client() and _connecting:
		_connecting = false
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_net_disconnected() -> void:
	_connecting = false
	if is_instance_valid(_connect_btn):
		_connect_btn.disabled = false
