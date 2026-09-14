extends Control
## Main menu — Play (vs bots), Host, Join, Settings, Quit.

const MapIO = preload("res://scripts/map_io.gd")
const MapGen = preload("res://scripts/map_gen.gd")
const ControlsMenu = preload("res://scripts/controls_menu.gd")
const SettingsPanel = preload("res://scripts/settings_panel.gd")
const UITheme = preload("res://scripts/ui_theme.gd")

# Slots 0..2 are the three procedural remakes; slots 3..12 are the classic
# Soldat maps bundled from res://assets/maps/*.json (see MapIO.BUNDLED_CLASSICS
# and #53). Order mirrors the append order in main.gd _ready(), so Settings.map_index
# resolves to the same map at host time and at scene-load time.
const MAP_NAMES := [
	"Ascent", "Towers", "Pillars",
	"Nuubia", "Maya", "Aftermath", "Hormone", "Viet",
	"Scorpion", "Warehouse", "Baire", "Airpirates", "Bunker",
	"Abel", "Aero", "Amnesia", "April", "Arch",
	"Arena", "Arena2", "Arena3", "Argy", "Ash",
	"B2B", "Belltower", "BigFalls", "Biologic", "Blade",
	"Blox", "Boxed", "Bridge", "Cambodia", "Campeche",
	"Changeling", "Cobra", "CrackedBoot", "Crucifix", "Daybreak",
	"Death", "Desert", "DesertWind", "Division", "Dorothy",
	"Dropdown", "Dusk", "Equinox", "Erbium", "Factory",
	"Feast", "Flashback", "Flute", "Fortress", "Guardian",
	"HH", "IceBeam", "Industrial", "Island2k5", "Jungle",
	"Kampf", "Krab", "Lagrange", "Lanubya", "Laos",
	"Leaf", "Mayapan", "Messner", "MFM", "Moonshine",
	"Mossy", "Motheaten", "MrSnowman", "Muygen", "Niall",
	"Nuclear", "Outpost", "Prison", "Raspberry", "RatCave",
	"Rescue", "Rise", "Rok", "Rotten", "RR",
	"Rubik", "Ruins", "Run", "Shau", "Snakebite",
	"Star", "Steel", "Tower", "Triumph", "TropicCave",
	"Unlim", "Veoto", "Void", "Voland", "Vortex",
	"Warlock", "Wretch", "X", "Zajacz",
]
const MODE_NAMES := [
	"Deathmatch", "Teammatch", "Capture the Flag",
	"Infiltration", "Hold the Flag", "Rambomatch", "Pointmatch",
	"Domination", "Battle Royale", "Gun Game",
]

var _menu_box: VBoxContainer   # inner column; visibility is driven via _menu_root
var _menu_root: PanelContainer # wrapper panel we hide/show
var _settings_panel: VBoxContainer
var _controls_panel: VBoxContainer
var _stats_panel: VBoxContainer
var _join_panel: VBoxContainer
var _host_panel: VBoxContainer
var _status_label: Label
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _host_port_edit: LineEdit
var _connect_btn: Button
var _map_pick: OptionButton
var _sp_map_pick: OptionButton     # main-menu map selector (built-in + custom)
var _sp_map_paths: Array = []      # index → "" (auto / built-in) or a user://maps/ path
var _connecting := false
var _master_edit: LineEdit
var _browse_panel: VBoxContainer
var _browse_list: VBoxContainer
var _browse_http: HTTPRequest


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.set_custom_mouse_cursor(load("res://assets/interface-gfx/menucursor.png"), Input.CURSOR_ARROW, Vector2(0, 0))
	Settings.apply_display()
	Net.leave()  # clean state on returning to menu from a game
	_build_backdrop()
	_build_title()
	_build_menu()
	_build_settings()
	_build_controls()
	_build_stats()
	_build_host()
	_build_join()
	_build_browse()
	_build_status()
	_build_footer()
	Net.status_changed.connect(_on_net_status_changed)
	Net.connected.connect(_on_net_connected)
	Net.disconnected.connect(_on_net_disconnected)
	Net.map_received.connect(_on_map_received)


func _build_backdrop() -> void:
	UITheme.build_menu_backdrop(self)


func _build_title() -> void:
	var title := Label.new()
	title.text = "SOLDAT REBORN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 50
	title.offset_bottom = 130
	UITheme.style_title(title, 62)
	add_child(title)

	# Sub-line with the tagline, tight under the wordmark.
	var sub := Label.new()
	sub.text = "JET BOOTS · BUNNY HOP · RAGDOLL GIBS · ONLINE"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 132
	sub.offset_bottom = 158
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	sub.add_theme_color_override("font_outline_color", UITheme.COL_SHADOW)
	sub.add_theme_constant_override("outline_size", 2)
	add_child(sub)

	# Version/build sits low and muted, doesn't compete with the title stack.
	var ver := Label.new()
	ver.text = "v1.12.1 · build %d" % _build_number()
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ver.offset_top = 172
	ver.offset_bottom = 194
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", UITheme.COL_TEXT_MUTED)
	add_child(ver)


func _build_number() -> int:
	# Runtime count instead of a hardcoded literal so every commit ships with the
	# real HEAD count without a manual bump. Falls back to 0 in the editor / when
	# git isn't reachable, which is fine for local dev builds.
	var out: Array = []
	# OS.execute returns the process exit code (0 = success), not a Godot Error.
	var code := OS.execute("git", ["rev-list", "--count", "HEAD"], out, true)
	if code == 0 and not out.is_empty():
		return int(String(out[0]).strip_edges())
	return 0


func _build_menu() -> void:
	# Wrap the main-menu column in a framed panel so it sits as a discrete
	# briefing-terminal card instead of floating buttons on the backdrop.
	_menu_root = PanelContainer.new()
	_menu_root.add_theme_stylebox_override("panel", UITheme.panel_style())
	_menu_root.set_anchors_preset(Control.PRESET_CENTER, true)
	_menu_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_menu_root)

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 8)
	_menu_box.custom_minimum_size = Vector2(340, 0)
	_menu_root.add_child(_menu_box)

	_menu_box.add_child(UITheme.make_section_header("Match"))

	var mode_pick := OptionButton.new()
	for name in MODE_NAMES:
		mode_pick.add_item(name)
	mode_pick.selected = clampi(Settings.game_mode, 0, MODE_NAMES.size() - 1)
	mode_pick.custom_minimum_size = Vector2(320, 34)
	UITheme.style_option_button(mode_pick)
	mode_pick.item_selected.connect(func(idx: int) -> void:
		Settings.game_mode = idx
		Settings.save())
	_menu_box.add_child(mode_pick)

	# Sub-mode toggles — three quick chips under the main mode picker.
	var subs := HBoxContainer.new()
	subs.add_theme_constant_override("separation", 8)
	subs.custom_minimum_size = Vector2(320, 0)
	_menu_box.add_child(subs)
	var real_cb := CheckBox.new()
	real_cb.text = "Realistic"
	real_cb.button_pressed = Settings.realistic
	UITheme.style_checkbox(real_cb)
	real_cb.toggled.connect(func(on: bool) -> void:
		Settings.realistic = on
		Settings.save())
	subs.add_child(real_cb)
	var surv_cb := CheckBox.new()
	surv_cb.text = "Survival"
	surv_cb.button_pressed = Settings.survival
	UITheme.style_checkbox(surv_cb)
	surv_cb.toggled.connect(func(on: bool) -> void:
		Settings.survival = on
		Settings.save())
	subs.add_child(surv_cb)
	var adv_cb := CheckBox.new()
	adv_cb.text = "Advance"
	adv_cb.button_pressed = Settings.advance
	UITheme.style_checkbox(adv_cb)
	adv_cb.toggled.connect(func(on: bool) -> void:
		Settings.advance = on
		Settings.save())
	subs.add_child(adv_cb)

	# Map picker (SP): built-in rotation + specific built-in + custom maps.
	_sp_map_pick = OptionButton.new()
	_sp_map_pick.custom_minimum_size = Vector2(320, 34)
	UITheme.style_option_button(_sp_map_pick)
	_menu_box.add_child(_sp_map_pick)
	_refresh_sp_map_pick()
	_sp_map_pick.item_selected.connect(_on_sp_map_selected)

	_menu_box.add_child(UITheme.spacer(4))
	_menu_box.add_child(UITheme.make_section_header("Deploy"))

	var play := _make_button("PLAY vs BOTS", true)
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

	_menu_box.add_child(UITheme.spacer(4))
	_menu_box.add_child(UITheme.make_section_header("Network"))

	var host := _make_button("HOST GAME")
	host.pressed.connect(func() -> void:
		_menu_root.visible = false
		_host_root.visible = true)
	_menu_box.add_child(host)

	var join := _make_button("JOIN GAME")
	join.pressed.connect(func() -> void:
		_menu_root.visible = false
		_join_root.visible = true)
	_menu_box.add_child(join)

	_menu_box.add_child(UITheme.spacer(4))
	_menu_box.add_child(UITheme.make_section_header("System"))

	var settings := _make_button("SETTINGS")
	settings.pressed.connect(func() -> void:
		_menu_root.visible = false
		_settings_panel.visible = true)
	_menu_box.add_child(settings)

	var stats := _make_button("STATS")
	stats.pressed.connect(func() -> void:
		_refresh_stats_labels()
		_menu_root.visible = false
		_stats_root.visible = true)
	_menu_box.add_child(stats)

	var quit := _make_button("QUIT")
	quit.pressed.connect(func() -> void: get_tree().quit())
	_menu_box.add_child(quit)


func _build_settings() -> void:
	# Glassmorphism accordion of Audio/Video/Controls/Game/Mods/Cosmetics cards (#73).
	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	add_child(_settings_panel)
	_settings_panel.back_pressed.connect(func() -> void:
		_settings_panel.visible = false
		_menu_root.visible = true)
	_settings_panel.controls_pressed.connect(func() -> void:
		_settings_panel.visible = false
		_controls_panel.visible = true)


func _build_controls() -> void:
	# Reuse the pause-menu Controls screen verbatim — same list, same persistence.
	_controls_panel = ControlsMenu.new()
	_controls_panel.visible = false
	_controls_panel.back_pressed.connect(func() -> void:
		_controls_panel.visible = false
		_settings_panel.visible = true)
	add_child(_controls_panel)


var _stats_body: RichTextLabel = null


var _stats_root: PanelContainer = null


func _build_stats() -> void:
	_stats_root = PanelContainer.new()
	_stats_root.add_theme_stylebox_override("panel", UITheme.panel_style())
	_stats_root.set_anchors_preset(Control.PRESET_CENTER, true)
	_stats_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stats_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_stats_root.visible = false
	add_child(_stats_root)

	_stats_panel = VBoxContainer.new()
	_stats_panel.add_theme_constant_override("separation", 10)
	_stats_panel.custom_minimum_size = Vector2(500, 0)
	_stats_root.add_child(_stats_panel)

	_stats_panel.add_child(UITheme.make_screen_title("STATS"))
	_stats_panel.add_child(UITheme.make_section_header("Career"))

	_stats_body = RichTextLabel.new()
	_stats_body.bbcode_enabled = true
	_stats_body.fit_content = true
	_stats_body.scroll_active = false
	_stats_body.custom_minimum_size = Vector2(0, 260)
	_stats_body.add_theme_font_size_override("normal_font_size", 15)
	_stats_body.add_theme_font_size_override("bold_font_size", 15)
	_stats_body.add_theme_color_override("default_color", UITheme.COL_TEXT)
	_stats_panel.add_child(_stats_body)

	_stats_panel.add_child(UITheme.spacer(4))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_stats_panel.add_child(row)
	var reset := _make_button("RESET STATS", false)
	reset.pressed.connect(func() -> void:
		Stats.reset()
		_refresh_stats_labels())
	row.add_child(reset)
	var back := _make_button("BACK", false)
	back.pressed.connect(func() -> void:
		_stats_root.visible = false
		_menu_root.visible = true)
	row.add_child(back)


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


var _host_root: PanelContainer = null


func _build_host() -> void:
	_host_root = PanelContainer.new()
	_host_root.add_theme_stylebox_override("panel", UITheme.panel_style())
	_host_root.set_anchors_preset(Control.PRESET_CENTER, true)
	_host_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_host_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_host_root.visible = false
	add_child(_host_root)

	_host_panel = VBoxContainer.new()
	_host_panel.add_theme_constant_override("separation", 10)
	_host_panel.custom_minimum_size = Vector2(420, 0)
	_host_root.add_child(_host_panel)

	_host_panel.add_child(UITheme.make_screen_title("HOST GAME"))
	_host_panel.add_child(UITheme.make_section_header("Match"))

	var map_lbl := Label.new()
	map_lbl.text = "Map"
	UITheme.style_body(map_lbl)
	_host_panel.add_child(map_lbl)

	_map_pick = OptionButton.new()
	for name in MAP_NAMES:
		_map_pick.add_item(name)
	_map_pick.selected = clampi(Settings.map_index, 0, MAP_NAMES.size() - 1)
	_map_pick.custom_minimum_size = Vector2(0, 34)
	UITheme.style_option_button(_map_pick)
	_host_panel.add_child(_map_pick)

	_host_panel.add_child(UITheme.make_section_header("Network"))

	var port_lbl := Label.new()
	port_lbl.text = "Port"
	UITheme.style_body(port_lbl)
	_host_panel.add_child(port_lbl)

	_host_port_edit = LineEdit.new()
	_host_port_edit.text = str(Net.DEFAULT_PORT)
	_host_port_edit.placeholder_text = str(Net.DEFAULT_PORT)
	_host_port_edit.custom_minimum_size = Vector2(0, 34)
	UITheme.style_lineedit(_host_port_edit)
	_host_panel.add_child(_host_port_edit)

	_host_panel.add_child(UITheme.spacer(6))

	var start := _make_button("START HOSTING", true)
	start.pressed.connect(func() -> void:
		var idx := _map_pick.get_selected_id()
		if idx < 0:
			idx = _map_pick.selected
		idx = clampi(idx, 0, MAP_NAMES.size() - 1)
		Settings.map_index = idx
		Settings.save()
		start.disabled = true
		var port := int(_host_port_edit.text) if _host_port_edit.text.is_valid_int() else Net.DEFAULT_PORT
		if Net.host_game(port, idx):
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		else:
			# Net.host_game already set the status text; re-enable so the user can retry.
			start.disabled = false
			_status_label.text = Net.status)
	_host_panel.add_child(start)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_host_root.visible = false
		_menu_root.visible = true)
	_host_panel.add_child(back)


var _join_root: PanelContainer = null


func _build_join() -> void:
	_join_root = PanelContainer.new()
	_join_root.add_theme_stylebox_override("panel", UITheme.panel_style())
	_join_root.set_anchors_preset(Control.PRESET_CENTER, true)
	_join_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_join_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_join_root.visible = false
	add_child(_join_root)

	_join_panel = VBoxContainer.new()
	_join_panel.add_theme_constant_override("separation", 10)
	_join_panel.custom_minimum_size = Vector2(420, 0)
	_join_root.add_child(_join_panel)

	_join_panel.add_child(UITheme.make_screen_title("JOIN GAME"))
	_join_panel.add_child(UITheme.make_section_header("Direct Connect"))

	var ip_lbl := Label.new()
	ip_lbl.text = "Host IP"
	UITheme.style_body(ip_lbl)
	_join_panel.add_child(ip_lbl)

	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(0, 34)
	UITheme.style_lineedit(_ip_edit)
	_join_panel.add_child(_ip_edit)

	var port_lbl := Label.new()
	port_lbl.text = "Port"
	UITheme.style_body(port_lbl)
	_join_panel.add_child(port_lbl)

	_port_edit = LineEdit.new()
	_port_edit.text = str(Net.DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(0, 34)
	UITheme.style_lineedit(_port_edit)
	_join_panel.add_child(_port_edit)

	_join_panel.add_child(UITheme.make_section_header("Master Server"))

	var master_lbl := Label.new()
	master_lbl.text = "Master Server URL (for Browse)"
	UITheme.style_body(master_lbl)
	_join_panel.add_child(master_lbl)

	_master_edit = LineEdit.new()
	_master_edit.text = Settings.master_url
	_master_edit.placeholder_text = "http://192.168.1.50:8080"
	_master_edit.custom_minimum_size = Vector2(0, 34)
	UITheme.style_lineedit(_master_edit)
	_master_edit.text_submitted.connect(func(_t: String) -> void: _on_browse_pressed())
	_join_panel.add_child(_master_edit)

	_join_panel.add_child(UITheme.spacer(4))

	var browse := _make_button("BROWSE SERVERS")
	browse.pressed.connect(_on_browse_pressed)
	_join_panel.add_child(browse)

	_connect_btn = _make_button("CONNECT", true)
	_connect_btn.pressed.connect(_on_connect_pressed)
	_join_panel.add_child(_connect_btn)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		Net.leave()
		_connecting = false
		_connect_btn.disabled = false
		_join_root.visible = false
		_menu_root.visible = true)
	_join_panel.add_child(back)


var _browse_root: PanelContainer = null


func _build_browse() -> void:
	_browse_http = HTTPRequest.new()
	_browse_http.request_completed.connect(_on_browse_http_done)
	add_child(_browse_http)

	_browse_root = PanelContainer.new()
	_browse_root.add_theme_stylebox_override("panel", UITheme.panel_style())
	_browse_root.set_anchors_preset(Control.PRESET_CENTER, true)
	_browse_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_browse_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_browse_root.visible = false
	add_child(_browse_root)

	_browse_panel = VBoxContainer.new()
	_browse_panel.add_theme_constant_override("separation", 8)
	_browse_panel.custom_minimum_size = Vector2(600, 0)
	_browse_root.add_child(_browse_panel)

	_browse_panel.add_child(UITheme.make_screen_title("BROWSE SERVERS"))
	_browse_panel.add_child(UITheme.make_section_header("Available Servers"))

	_browse_list = VBoxContainer.new()
	_browse_list.add_theme_constant_override("separation", 4)
	_browse_panel.add_child(_browse_list)

	_browse_panel.add_child(UITheme.spacer(4))

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_browse_root.visible = false
		_join_root.visible = true)
	_browse_panel.add_child(back)


func _on_browse_pressed() -> void:
	Settings.master_url = _master_edit.text.strip_edges()
	Settings.save()
	_join_root.visible = false
	_browse_root.visible = true
	_refresh_browse()


func _refresh_browse() -> void:
	for c in _browse_list.get_children():
		c.queue_free()
	var wait := Label.new()
	wait.text = "Fetching server list..."
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait.add_theme_font_size_override("font_size", 15)
	wait.add_theme_color_override("font_color", UITheme.COL_INFO)
	_browse_list.add_child(wait)
	var url: String = Settings.master_url
	if url == "":
		wait.text = "Set a master server URL first."
		return
	if _browse_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_browse_http.cancel_request()
	_browse_http.request(url.rstrip("/") + "/list")


func _on_browse_http_done(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not is_instance_valid(_browse_list) or not _browse_root.visible:
		return
	for c in _browse_list.get_children():
		c.queue_free()
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null or not (parsed is Dictionary) or not parsed.has("servers"):
		var err := Label.new()
		err.text = "No response from master server."
		err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err.add_theme_font_size_override("font_size", 15)
		err.add_theme_color_override("font_color", UITheme.COL_ALERT)
		_browse_list.add_child(err)
		return
	if not (parsed.get("servers", []) is Array):
		var err2 := Label.new()
		err2.text = "Malformed master server response."
		err2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err2.add_theme_font_size_override("font_size", 15)
		err2.add_theme_color_override("font_color", UITheme.COL_ALERT)
		_browse_list.add_child(err2)
		return
	var servers: Array = parsed["servers"]
	if servers.is_empty():
		var empty := Label.new()
		empty.text = "No servers online."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", UITheme.COL_INFO)
		_browse_list.add_child(empty)
		return
	for s in servers:
		if not (s is Dictionary):
			continue
		var ip: String = str(s.get("ip", ""))
		var port: int = int(s.get("port", 0))
		var name: String = str(s.get("name", "Unnamed"))
		var mapn: String = str(s.get("map", "?"))
		var mname: String = str(s.get("mode", "?"))
		var players: int = int(s.get("players", 0))
		var maxp: int = int(s.get("max", 0))
		var pwd: bool = bool(s.get("password", false))
		var btn := Button.new()
		btn.text = "  %s   [%d/%d]   %s · %s%s" % [name, players, maxp, mapn, mname, "  (locked)" if pwd else ""]
		btn.custom_minimum_size = Vector2(580, 40)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UITheme.style_button(btn, 15, false)
		btn.pressed.connect(_join_server.bind(ip, port))
		_browse_list.add_child(btn)


func _join_server(ip: String, port: int) -> void:
	_ip_edit.text = ip
	_port_edit.text = str(port)
	_browse_root.visible = false
	_join_root.visible = true
	_on_connect_pressed()


func _build_status() -> void:
	# Status line sits just above the footer band — network status / errors.
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_label.offset_top = -88
	_status_label.offset_bottom = -68
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", UITheme.COL_INFO)
	_status_label.add_theme_color_override("font_outline_color", UITheme.COL_SHADOW)
	_status_label.add_theme_constant_override("outline_size", 3)
	add_child(_status_label)


func _build_footer() -> void:
	var foot := Label.new()
	foot.text = "WASD · W jump · S crouch/roll · X prone · RMB jet · LMB shoot · 1-0 · Q sec · R reload · E nade · F throw · G nade type · / command · F9 GIF"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -42
	foot.offset_bottom = -18
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", UITheme.COL_TEXT_MUTED)
	add_child(foot)


func _make_button(text: String, primary: bool = false) -> Button:
	return UITheme.make_button(text, primary)


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
		_menu_root.visible = true
	elif _stats_root != null and _stats_root.visible:
		_stats_root.visible = false
		_menu_root.visible = true
	elif _host_root != null and _host_root.visible:
		_host_root.visible = false
		_menu_root.visible = true
	elif _join_root != null and _join_root.visible:
		Net.leave()
		_connecting = false
		if is_instance_valid(_connect_btn):
			_connect_btn.disabled = false
		_join_root.visible = false
		_menu_root.visible = true
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
