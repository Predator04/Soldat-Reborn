extends Control
## Main menu — Play (vs bots), Host, Join, Settings, Quit.

const MapIO = preload("res://scripts/map_io.gd")
const MapGen = preload("res://scripts/map_gen.gd")
const ControlsMenu = preload("res://scripts/controls_menu.gd")

# Slots 0..2 are the three procedural remakes; slots 3..12 are the classic
# Soldat maps bundled from res://assets/maps/*.json (see MapIO.BUNDLED_CLASSICS
# and #53). Order mirrors the append order in main.gd _ready(), so Settings.map_index
# resolves to the same map at host time and at scene-load time.
const MAP_NAMES := [
	"Ascent", "Towers", "Pillars",
	"Nuubia", "Maya", "Aftermath", "Hormone", "Viet",
	"Scorpion", "Warehouse", "Baire", "Airpirates", "Bunker",
]
const MODE_NAMES := [
	"Deathmatch", "Teammatch", "Capture the Flag",
	"Infiltration", "Hold the Flag", "Rambomatch", "Pointmatch",
	"Domination", "Battle Royale",
]

var _menu_box: VBoxContainer
var _settings_panel: VBoxContainer
var _controls_panel: VBoxContainer
var _mods_panel: VBoxContainer
var _cos_panel: VBoxContainer
var _stats_panel: VBoxContainer
var _join_panel: VBoxContainer
var _host_panel: VBoxContainer
var _status_label: Label
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _connect_btn: Button
var _map_pick: OptionButton
var _sp_map_pick: OptionButton     # main-menu map selector (built-in + custom)
var _sp_map_paths: Array = []      # index → "" (auto / built-in) or a user://maps/ path
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
	_build_controls()
	_build_mods()
	_build_cosmetics()
	_build_stats()
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

	var ver := Label.new()
	ver.text = "v1.6.0 · build 111"
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ver.offset_top = 140
	ver.offset_bottom = 170
	ver.add_theme_font_size_override("font_size", 18)
	ver.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	add_child(ver)

	var sub := Label.new()
	sub.text = "jet boots · bunny hop · ragdoll gibs · online"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Sit below the version band (140-170) so the two labels don't overlap.
	sub.offset_top = 172
	sub.offset_bottom = 200
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

	var mode_pick := OptionButton.new()
	for name in MODE_NAMES:
		mode_pick.add_item(name)
	mode_pick.selected = clampi(Settings.game_mode, 0, MODE_NAMES.size() - 1)
	mode_pick.custom_minimum_size = Vector2(300, 36)
	mode_pick.item_selected.connect(func(idx: int) -> void:
		Settings.game_mode = idx
		Settings.save())
	_menu_box.add_child(mode_pick)

	# Sub-mode toggles — three quick chips under the main mode picker.
	var subs := HBoxContainer.new()
	subs.add_theme_constant_override("separation", 10)
	subs.custom_minimum_size = Vector2(300, 0)
	_menu_box.add_child(subs)
	var real_cb := CheckBox.new()
	real_cb.text = "Realistic"
	real_cb.button_pressed = Settings.realistic
	real_cb.toggled.connect(func(on: bool) -> void:
		Settings.realistic = on
		Settings.save())
	subs.add_child(real_cb)
	var surv_cb := CheckBox.new()
	surv_cb.text = "Survival"
	surv_cb.button_pressed = Settings.survival
	surv_cb.toggled.connect(func(on: bool) -> void:
		Settings.survival = on
		Settings.save())
	subs.add_child(surv_cb)
	var adv_cb := CheckBox.new()
	adv_cb.text = "Advance"
	adv_cb.button_pressed = Settings.advance
	adv_cb.toggled.connect(func(on: bool) -> void:
		Settings.advance = on
		Settings.save())
	subs.add_child(adv_cb)

	# Map picker (SP): built-in rotation + specific built-in + custom maps.
	_sp_map_pick = OptionButton.new()
	_sp_map_pick.custom_minimum_size = Vector2(300, 36)
	_menu_box.add_child(_sp_map_pick)
	_refresh_sp_map_pick()
	_sp_map_pick.item_selected.connect(_on_sp_map_selected)

	var play := _make_button("PLAY vs BOTS")
	play.pressed.connect(func() -> void:
		Net.set_singleplayer()
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	_menu_box.add_child(play)

	var editor := _make_button("MAP EDITOR")
	editor.pressed.connect(func() -> void:
		Net.set_singleplayer()
		get_tree().change_scene_to_file("res://scenes/map_editor.tscn"))
	_menu_box.add_child(editor)

	var gen := _make_button("GENERATE + PLAY")
	gen.pressed.connect(_on_generate_and_play)
	_menu_box.add_child(gen)

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

	var mods := _make_button("MODIFIERS")
	mods.pressed.connect(func() -> void:
		_menu_box.visible = false
		_mods_panel.visible = true)
	_menu_box.add_child(mods)

	var cos := _make_button("CUSTOMIZE")
	cos.pressed.connect(func() -> void:
		_menu_box.visible = false
		_cos_panel.visible = true)
	_menu_box.add_child(cos)

	var stats := _make_button("STATS")
	stats.pressed.connect(func() -> void:
		_refresh_stats_labels()
		_menu_box.visible = false
		_stats_panel.visible = true)
	_menu_box.add_child(stats)

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

	var lo := CheckButton.new()
	lo.text = "Lo-fi mode (no particles/gibs — low-end PCs)"
	lo.button_pressed = Settings.lofi
	lo.toggled.connect(func(on: bool) -> void:
		Settings.lofi = on
		Settings.save())
	_settings_panel.add_child(lo)

	# Controls — opens the rebind screen. Same scene/script as the ESC pause-menu
	# Settings entry, so both routes share user://controls.cfg via ControlsMap.save().
	var controls_btn := _make_button("CONTROLS")
	controls_btn.pressed.connect(func() -> void:
		_settings_panel.visible = false
		_controls_panel.visible = true)
	_settings_panel.add_child(controls_btn)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_settings_panel.visible = false
		_menu_box.visible = true)
	_settings_panel.add_child(back)


func _build_controls() -> void:
	# Reuse the pause-menu Controls screen verbatim — same list, same persistence.
	_controls_panel = ControlsMenu.new()
	_controls_panel.visible = false
	_controls_panel.back_pressed.connect(func() -> void:
		_controls_panel.visible = false
		_settings_panel.visible = true)
	add_child(_controls_panel)


func _build_mods() -> void:
	_mods_panel = VBoxContainer.new()
	_mods_panel.set_anchors_preset(Control.PRESET_CENTER)
	_mods_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mods_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mods_panel.add_theme_constant_override("separation", 10)
	_mods_panel.custom_minimum_size = Vector2(460, 0)
	_mods_panel.visible = false
	add_child(_mods_panel)

	var head := Label.new()
	head.text = "MODIFIERS"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	_mods_panel.add_child(head)

	_add_mod_slider("Gravity", 0.5, 2.0, 0.05, func() -> float: return Settings.mod_gravity,
		func(v: float) -> void:
			Settings.mod_gravity = v
			Settings.save())
	_add_mod_slider("Jet fuel regen", 0.5, 2.0, 0.05, func() -> float: return Settings.mod_jet,
		func(v: float) -> void:
			Settings.mod_jet = v
			Settings.save())
	_add_mod_slider("Weapon damage", 0.5, 2.0, 0.05, func() -> float: return Settings.mod_damage,
		func(v: float) -> void:
			Settings.mod_damage = v
			Settings.save())
	_add_mod_slider("Player speed", 0.5, 1.5, 0.05, func() -> float: return Settings.mod_speed,
		func(v: float) -> void:
			Settings.mod_speed = v
			Settings.save())

	var reset := _make_button("RESET TO STOCK")
	reset.pressed.connect(func() -> void:
		Settings.mod_gravity = 1.0
		Settings.mod_jet = 1.0
		Settings.mod_damage = 1.0
		Settings.mod_speed = 1.0
		Settings.save()
		# Rebuild the panel so slider values reflect the reset.
		for c in _mods_panel.get_children():
			c.queue_free()
		_mods_panel.queue_free()
		_build_mods()
		_mods_panel.visible = true)
	_mods_panel.add_child(reset)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_mods_panel.visible = false
		_menu_box.visible = true)
	_mods_panel.add_child(back)


func _add_mod_slider(label_text: String, mn: float, mx: float, step: float,
	get_val: Callable, set_val: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_mods_panel.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(160, 0)
	lbl.add_theme_font_size_override("font_size", 15)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = mn
	slider.max_value = mx
	slider.step = step
	slider.value = float(get_val.call())
	slider.custom_minimum_size = Vector2(220, 0)
	row.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.text = "%.2fx" % float(slider.value)
	val_lbl.custom_minimum_size = Vector2(56, 0)
	val_lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(val_lbl)
	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = "%.2fx" % v
		set_val.call(v))


var _stats_body: RichTextLabel = null


func _build_stats() -> void:
	_stats_panel = VBoxContainer.new()
	_stats_panel.set_anchors_preset(Control.PRESET_CENTER)
	_stats_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stats_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_stats_panel.add_theme_constant_override("separation", 12)
	_stats_panel.custom_minimum_size = Vector2(480, 0)
	_stats_panel.visible = false
	add_child(_stats_panel)

	var head := Label.new()
	head.text = "STATS"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	_stats_panel.add_child(head)

	_stats_body = RichTextLabel.new()
	_stats_body.bbcode_enabled = true
	_stats_body.fit_content = true
	_stats_body.scroll_active = false
	_stats_body.custom_minimum_size = Vector2(0, 240)
	_stats_body.add_theme_font_size_override("normal_font_size", 15)
	_stats_body.add_theme_color_override("default_color", Color(0.9, 0.9, 0.92))
	_stats_panel.add_child(_stats_body)

	var reset := _make_button("RESET STATS")
	reset.pressed.connect(func() -> void:
		Stats.reset()
		_refresh_stats_labels())
	_stats_panel.add_child(reset)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_stats_panel.visible = false
		_menu_box.visible = true)
	_stats_panel.add_child(back)


func _refresh_stats_labels() -> void:
	if _stats_body == null:
		return
	var acc := Stats.accuracy() * 100.0
	var kd := Stats.kd()
	var lines := PackedStringArray()
	lines.append("[b]Kills[/b] %d  ·  [b]Deaths[/b] %d  ·  [b]K/D[/b] %.2f" % [Stats.kills, Stats.deaths, kd])
	lines.append("[b]Suicides[/b] %d" % Stats.suicides)
	lines.append("[b]Shots[/b] %d  ·  [b]Hits[/b] %d  ·  [b]Accuracy[/b] %.1f%%" % [Stats.shots, Stats.hits, acc])
	lines.append("[b]Matches[/b] %d  ·  [b]Wins[/b] %d  ·  [b]Losses[/b] %d" % [Stats.matches_played, Stats.wins, Stats.losses])
	lines.append("")
	lines.append("[i]Kills by weapon[/i]")
	var pairs: Array = []
	for k in Stats.kills_by_weapon.keys():
		pairs.append([str(k), int(Stats.kills_by_weapon[k])])
	pairs.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for pair in pairs:
		lines.append("  %s: %d" % [pair[0], pair[1]])
	_stats_body.text = "\n".join(lines)


func _build_cosmetics() -> void:
	_cos_panel = VBoxContainer.new()
	_cos_panel.set_anchors_preset(Control.PRESET_CENTER)
	_cos_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cos_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_cos_panel.add_theme_constant_override("separation", 12)
	_cos_panel.custom_minimum_size = Vector2(460, 0)
	_cos_panel.visible = false
	add_child(_cos_panel)

	var head := Label.new()
	head.text = "CUSTOMIZE"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	_cos_panel.add_child(head)

	# Head slot — 7 options (helm / kap / hair1-4 / bald).
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 12)
	_cos_panel.add_child(head_row)
	var head_lbl := Label.new()
	head_lbl.text = "Head"
	head_lbl.custom_minimum_size = Vector2(120, 0)
	head_row.add_child(head_lbl)
	var head_pick := OptionButton.new()
	var head_opts := ["helm", "kap", "hair1", "hair2", "hair3", "hair4", "none"]
	for h in head_opts:
		head_pick.add_item(h.capitalize())
	head_pick.selected = clampi(head_opts.find(Settings.cos_head), 0, head_opts.size() - 1)
	head_pick.custom_minimum_size = Vector2(260, 32)
	head_pick.item_selected.connect(func(idx: int) -> void:
		Settings.cos_head = head_opts[idx]
		Settings.save())
	head_row.add_child(head_pick)

	# Chain slot — 3 options.
	var chain_row := HBoxContainer.new()
	chain_row.add_theme_constant_override("separation", 12)
	_cos_panel.add_child(chain_row)
	var chain_lbl := Label.new()
	chain_lbl.text = "Chain"
	chain_lbl.custom_minimum_size = Vector2(120, 0)
	chain_row.add_child(chain_lbl)
	var chain_pick := OptionButton.new()
	var chain_opts := ["none", "silver", "gold"]
	for c in chain_opts:
		chain_pick.add_item(c.capitalize())
	chain_pick.selected = clampi(chain_opts.find(Settings.cos_chain), 0, chain_opts.size() - 1)
	chain_pick.custom_minimum_size = Vector2(260, 32)
	chain_pick.item_selected.connect(func(idx: int) -> void:
		Settings.cos_chain = chain_opts[idx]
		Settings.save())
	chain_row.add_child(chain_pick)

	var vest := CheckButton.new()
	vest.text = "Vest (kamizelka)"
	vest.button_pressed = Settings.cos_vest
	vest.toggled.connect(func(on: bool) -> void:
		Settings.cos_vest = on
		Settings.save())
	_cos_panel.add_child(vest)

	var cigar := CheckButton.new()
	cigar.text = "Cigar (cygaro)"
	cigar.button_pressed = Settings.cos_cigar
	cigar.toggled.connect(func(on: bool) -> void:
		Settings.cos_cigar = on
		Settings.save())
	_cos_panel.add_child(cigar)

	var dreadlocks := CheckButton.new()
	dreadlocks.text = "Dreadlocks (dred)"
	dreadlocks.button_pressed = Settings.cos_dreadlocks
	dreadlocks.toggled.connect(func(on: bool) -> void:
		Settings.cos_dreadlocks = on
		Settings.save())
	_cos_panel.add_child(dreadlocks)

	var dogtag := CheckButton.new()
	dogtag.text = "Dogtag (metal)"
	dogtag.button_pressed = Settings.cos_dogtag
	dogtag.toggled.connect(func(on: bool) -> void:
		Settings.cos_dogtag = on
		Settings.save())
	_cos_panel.add_child(dogtag)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_cos_panel.visible = false
		_menu_box.visible = true)
	_cos_panel.add_child(back)


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
	foot.text = "WASD · W jump · S crouch/roll · X prone · RMB jet · LMB shoot · 1-0 · Q sec · R reload · E nade · F throw · G nade type · / command · F9 GIF"
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


func _unhandled_input(event: InputEvent) -> void:
	# ESC in the main menu = back-out. Sub-panels return to the main list; from
	# the root list we quit the game.
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode != KEY_ESCAPE:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and focused is LineEdit:
		return
	if _controls_panel != null and _controls_panel.visible:
		# Mid-rebind: let the capture eat ESC so the user doesn't lose the session
		# on the first press (matches the pause-menu handling).
		if _controls_panel._capturing_action != "":
			_controls_panel._abort_capture()
		else:
			_controls_panel.visible = false
			_settings_panel.visible = true
	elif _settings_panel != null and _settings_panel.visible:
		_settings_panel.visible = false
		_menu_box.visible = true
	elif _mods_panel != null and _mods_panel.visible:
		_mods_panel.visible = false
		_menu_box.visible = true
	elif _cos_panel != null and _cos_panel.visible:
		_cos_panel.visible = false
		_menu_box.visible = true
	elif _stats_panel != null and _stats_panel.visible:
		_stats_panel.visible = false
		_menu_box.visible = true
	elif _host_panel != null and _host_panel.visible:
		_host_panel.visible = false
		_menu_box.visible = true
	elif _join_panel != null and _join_panel.visible:
		Net.leave()
		_connecting = false
		if is_instance_valid(_connect_btn):
			_connect_btn.disabled = false
		_join_panel.visible = false
		_menu_box.visible = true
	else:
		get_tree().quit()
	get_viewport().set_input_as_handled()


# ── SP map picker ─────────────────────────────────────

func _refresh_sp_map_pick() -> void:
	if _sp_map_pick == null:
		return
	_sp_map_pick.clear()
	_sp_map_paths.clear()
	# Slot 0: rotate through built-in maps (legacy behavior).
	_sp_map_pick.add_item("Map: Rotate built-in")
	_sp_map_paths.append("")
	# Slots 1..N: pinned built-in.
	for name in MAP_NAMES:
		_sp_map_pick.add_item("Map: %s" % name)
		_sp_map_paths.append("builtin:%s" % name)
	# Slots N+1..: custom maps in user://maps/, excluding the play-test temp.
	for path_v in MapIO.list_files():
		var path: String = String(path_v)
		if path.ends_with("/_playtest.json"):
			continue
		_sp_map_pick.add_item("Custom: %s" % path.get_file().get_basename())
		_sp_map_paths.append(path)
	# Select whichever slot matches the current Settings state.
	var sel := 0
	if Settings.custom_map_path != "":
		var idx := _sp_map_paths.find(Settings.custom_map_path)
		if idx >= 0:
			sel = idx
	elif Settings.map_index >= 0 and Settings.map_index < MAP_NAMES.size():
		# Rotation mode leaves map_index cycling, so we can't distinguish "pinned"
		# from "rotating" — keep slot 0 selected by default.
		sel = 0
	_sp_map_pick.selected = sel


func _on_generate_and_play() -> void:
	# Roll a fresh seed, generate a map, save it under a stable "generated" slot
	# in user://maps/ so it stays around after play, then jump into main.tscn.
	var seed_val := int(Time.get_unix_time_from_system())
	var m := MapGen.generate(seed_val)
	var path := MapIO.save_to_file("generated", m)
	if path == "":
		_status_label.text = "Generator failed to save map."
		return
	Settings.custom_map_path = path
	Settings.save()
	Net.set_singleplayer()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_sp_map_selected(idx: int) -> void:
	if idx < 0 or idx >= _sp_map_paths.size():
		return
	var v: String = _sp_map_paths[idx]
	if v == "":
		Settings.custom_map_path = ""
	elif v.begins_with("builtin:"):
		Settings.custom_map_path = ""
		var name := v.substr(len("builtin:"))
		Settings.map_index = maxi(MAP_NAMES.find(name), 0)
	else:
		Settings.custom_map_path = v
	Settings.save()
