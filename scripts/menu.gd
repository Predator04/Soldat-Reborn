extends Control
const NavGraph = preload("res://scripts/nav_graph.gd")
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

var _menu_box: VBoxContainer   # left column; visibility is driven via _menu_root
var _menu_box2: VBoxContainer  # right column (Network + System)
var _map_thumb: TextureRect = null
var _host_thumb: TextureRect = null
var _title_nodes: Array = []    # wordmark / tagline / version — main list only


# Taller sub-panels (Host, Join, Settings, Stats) sit over the wordmark; show
# the title stack only while the main list is up.
# Any centred panel taller than the window (small window, big UI text) is
# scaled down to fit instead of running off the bottom of the screen.
func _fit_panels() -> void:
	var avail: float = get_viewport_rect().size.y - 24.0
	for c in get_children():
		if not (c is PanelContainer) or not (c as Control).visible:
			continue
		var pc := c as PanelContainer
		var need: float = pc.get_combined_minimum_size().y
		var sc: float = clampf(avail / need, 0.5, 1.0) if need > 0.0 else 1.0
		if absf(pc.scale.x - sc) > 0.005:
			pc.pivot_offset = pc.size * 0.5
			pc.scale = Vector2(sc, sc)


func _process(_delta: float) -> void:
	_tick_rejoin(_delta)
	_fit_panels()
	if _menu_root != null and _menu_root.visible:
		_refresh_name_btn()   # picks up a rename from Settings too
	var show_title: bool = _menu_root != null and _menu_root.visible
	for n in _title_nodes:
		if is_instance_valid(n) and n.visible != show_title:
			n.visible = show_title
	# LAN games refresh live while the Browse screen is open.
	if _browse_root != null and _browse_root.visible:
		_lan_t -= _delta
		if _lan_t <= 0.0:
			_lan_t = 0.5
			_refresh_lan()
		_ping_t -= _delta
		if _ping_t <= 0.0:
			_ping_t = 1.0
			var targets: Array = []
			for d in (Net.lan_poll() if _lan_listening else []):
				targets.append([str(d.get("ip")), int(d.get("port"))])
			for d in _master_rows:
				targets.append([str(d.get("ip")), int(d.get("port"))])
			for d in _recent_rows():
				targets.append([str(d.get("ip")), int(d.get("port"))])
			Net.query_send(targets)
			_render_master()
			_render_recent()
		if _qj_active:
			_qj_t -= _delta
			if _qj_t <= 0.0:
				_quick_join_pick()
	elif _lan_listening:
		Net.lan_listen_stop()
		_lan_listening = false


func _open_settings() -> void:
	_menu_root.visible = false
	_settings_panel.visible = true


func _open_host() -> void:
	_menu_root.visible = false
	_host_root.visible = true
	if _host_pub_cb != null:
		var has_url: bool = Settings.master_url.strip_edges() != ""
		_host_pub_cb.disabled = not has_url
		_host_pub_cb.tooltip_text = "" if has_url else "Set a master server URL on the Join screen first."
		_host_pub_cb.text = "List on the master server" if has_url else "List on the master server (set its URL under Join first)"
	UITheme.safe_grab_focus_deferred(_host_first_focus)


var _lan_list: VBoxContainer
var _lan_t := 0.0
var _lan_listening := false
var _lan_sig := ""


func _refresh_lan() -> void:
	if _lan_list == null:
		return
	if not _lan_listening:
		_lan_listening = Net.lan_listen_start()
	var found: Array = Net.lan_poll() if _lan_listening else []
	var sig := str(found.map(func(d): return [d.get("ip"), d.get("port"), d.get("players"), d.get("map"), d.get("mode"), _ping_bucket(str(d.get("ip")), int(d.get("port")))]))
	if sig == _lan_sig and _lan_list.get_child_count() > 0:
		return
	_lan_sig = sig
	for c in _lan_list.get_children():
		c.queue_free()
	if found.is_empty():
		var l := Label.new()
		l.text = "Looking for games on your network..." if _lan_listening else "Can't listen for LAN games (port %d busy)." % Net.LAN_PORT
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
		_lan_list.add_child(l)
		return
	for d in found:
		_lan_list.add_child(_server_row(d))
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
var _mode_pick: OptionButton
var _mode_desc: Label = null
var _mode_desc_labels: Array = []
const GameInfo = preload("res://scripts/game_info.gd")
var _host_custom_paths: Array = []
var _host_pub_cb: CheckBox
var _host_mode_pick: OptionButton
var _connect_btn: Button
var _map_pick: OptionButton
var _sp_map_pick: OptionButton     # main-menu map selector (built-in + custom)
var _sp_map_paths: Array = []      # index → "" (auto / built-in) or a user://maps/ path
var _connecting := false
var _master_edit: LineEdit
var _browse_panel: VBoxContainer
var _browse_list: VBoxContainer
var _browse_http: HTTPRequest
# #93: keyboard focus seed — the first interactive control the arrow keys
# should land on when a panel is shown. Nulled defensively for panels the
# user never opens, so grab_focus never fires on a freed control.
var _menu_first_focus: Control = null
var _host_first_focus: Control = null
var _join_first_focus: Control = null


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
	_build_credits()
	_build_host()
	_build_join()
	_build_browse()
	_build_status()
	_build_footer()
	if not has_real_name() and DisplayServer.get_name() != "headless":
		_build_name_prompt()
	# Kicked / host lost / version mismatch: say why we're back at the menu.
	if Net.last_disconnect_reason != "" and _status_label != null:
		_status_label.text = Net.last_disconnect_reason
		Net.last_disconnect_reason = ""
	if Net.rejoin_offer and Net.last_server_ip != "":
		Net.rejoin_offer = false
		_build_rejoin()
	elif has_real_name() and DisplayServer.get_name() != "headless":
		_maybe_whats_new()
	Net.status_changed.connect(_on_net_status_changed)
	Net.connected.connect(_on_net_connected)
	Net.disconnected.connect(_on_net_disconnected)
	Net.map_received.connect(_on_map_received)
	# #93: seed keyboard focus so arrow keys / gamepad D-pad navigate before
	# the user has to mouse-click a widget.
	UITheme.safe_grab_focus_deferred(_menu_first_focus)


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
	_title_nodes.append(title)

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
	_title_nodes.append(sub)

	# Version/build sits low and muted, doesn't compete with the title stack.
	var ver := Label.new()
	var bn := _build_number()
	ver.text = "v%s" % str(ProjectSettings.get_setting("application/config/version", "?"))
	if bn > 0:
		ver.text += " · build %d" % bn
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ver.offset_top = 172
	ver.offset_bottom = 194
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", UITheme.COL_TEXT_MUTED)
	add_child(ver)
	_title_nodes.append(ver)
	# Your name, top right: click to change it.
	_name_btn = Button.new()
	_name_btn.tooltip_text = "Change the name shown in the kill feed, scoreboard and online."
	UITheme.style_button(_name_btn, 16, false)
	_name_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_name_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_name_btn.offset_top = 16
	_name_btn.offset_right = -16
	_name_btn.custom_minimum_size = Vector2(0, 38)
	_name_btn.pressed.connect(func() -> void: _build_name_prompt(Callable(), true))
	add_child(_name_btn)
	_title_nodes.append(_name_btn)
	_refresh_name_btn()
	_build_update_button()


func _build_number() -> int:
	# Runtime count instead of a hardcoded literal so every commit ships with the
	# real HEAD count without a manual bump. Falls back to 0 in the editor / when
	# git isn't reachable, which is fine for local dev builds.
	# Only dev runs from the editor/source tree shell out to git — exported
	# builds (Android especially) must not spawn processes at boot.
	if not OS.has_feature("editor"):
		return 0
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
	# Two columns (Match + Deploy | Network + System) between the title stack
	# and the footer. The single tall column ran off both edges at 720p (QUIT
	# sat under the footer). A scroll container keeps short screens usable.
	_menu_root.anchor_left = 0.5
	_menu_root.anchor_right = 0.5
	_menu_root.anchor_top = 0.0
	_menu_root.anchor_bottom = 0.0
	_menu_root.offset_left = -372
	_menu_root.offset_right = 372
	_menu_root.offset_top = 204
	_menu_root.offset_bottom = 596  # base height is 720 (stretch "expand")
	add_child(_menu_root)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_root.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 8)
	_menu_box.custom_minimum_size = Vector2(340, 0)
	cols.add_child(_menu_box)
	_menu_box2 = VBoxContainer.new()
	_menu_box2.add_theme_constant_override("separation", 8)
	_menu_box2.custom_minimum_size = Vector2(340, 0)
	cols.add_child(_menu_box2)

	_menu_box.add_child(UITheme.make_section_header("Match"))

	var mode_pick := OptionButton.new()
	_mode_pick = mode_pick
	for name in MODE_NAMES:
		mode_pick.add_item(name)
	mode_pick.selected = clampi(Settings.game_mode, 0, MODE_NAMES.size() - 1)
	mode_pick.custom_minimum_size = Vector2(320, 34)
	UITheme.style_option_button(mode_pick)
	mode_pick.item_selected.connect(func(idx: int) -> void:
		Settings.game_mode = idx
		Settings.save()
		_refresh_mode_desc()
		if _host_mode_pick != null:
			_host_mode_pick.selected = idx)
	_menu_box.add_child(mode_pick)
	_mode_desc = _make_mode_desc()
	_menu_box.add_child(_mode_desc)
	_tooltip_modes(mode_pick)

	# Sub-mode toggles — three quick chips under the main mode picker.
	var subs := HBoxContainer.new()
	subs.add_theme_constant_override("separation", 8)
	subs.custom_minimum_size = Vector2(320, 0)
	_menu_box.add_child(subs)
	var real_cb := CheckBox.new()
	real_cb.text = "Realistic"
	real_cb.tooltip_text = GameInfo.SUBMODES["realistic"]
	real_cb.button_pressed = Settings.realistic
	UITheme.style_checkbox(real_cb)
	real_cb.toggled.connect(func(on: bool) -> void:
		Settings.realistic = on
		Settings.save())
	subs.add_child(real_cb)
	var surv_cb := CheckBox.new()
	surv_cb.text = "Survival"
	surv_cb.tooltip_text = GameInfo.SUBMODES["survival"]
	surv_cb.button_pressed = Settings.survival
	UITheme.style_checkbox(surv_cb)
	surv_cb.toggled.connect(func(on: bool) -> void:
		Settings.survival = on
		Settings.save())
	subs.add_child(surv_cb)
	var adv_cb := CheckBox.new()
	adv_cb.text = "Advance"
	adv_cb.tooltip_text = GameInfo.SUBMODES["advance"]
	adv_cb.button_pressed = Settings.advance
	UITheme.style_checkbox(adv_cb)
	adv_cb.toggled.connect(func(on: bool) -> void:
		Settings.advance = on
		Settings.save())
	subs.add_child(adv_cb)
	_surv_cb = surv_cb
	_adv_cb = adv_cb
	_refresh_submode_boxes()

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
	play.tooltip_text = "Single-player match against bots with the mode, map and options above."
	play.pressed.connect(func() -> void:
		Net.set_singleplayer()
		_go_to_match())
	_menu_first_focus = play
	# PLAY vs BOTS | RANDOM MAP, then TRAINING | MAP EDITOR (two rows, so the
	# whole column fits without scrolling).
	var gen := _make_button("RANDOM MAP")
	gen.tooltip_text = "Builds a brand-new random map and starts a bot match on it with your current mode. Saved as \"generated\" (the next press replaces it) — open it in the Map Editor to keep it."
	gen.pressed.connect(_on_generate_and_play)
	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 8)
	for b in [play, gen]:
		b.custom_minimum_size = Vector2(0, b.custom_minimum_size.y)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play_row.add_child(b)
	play.size_flags_stretch_ratio = 1.3
	_menu_box.add_child(play_row)

	var editor := _make_button("MAP EDITOR")
	editor.tooltip_text = "Build your own map: platforms, spawns, flags, kits. Save it, then play or host it."
	editor.pressed.connect(func() -> void:
		Net.set_singleplayer()
		get_tree().change_scene_to_file("res://scenes/map_editor.tscn"))
	var train := _make_button("TRAINING")
	train.tooltip_text = "Guided first match: learn to move, jet, shoot, reload, switch and throw grenades."
	train.pressed.connect(func() -> void: _with_name(start_training_match))
	var deploy_row := HBoxContainer.new()
	deploy_row.add_theme_constant_override("separation", 8)
	for b in [train, editor]:
		b.custom_minimum_size = Vector2(0, b.custom_minimum_size.y)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		deploy_row.add_child(b)
	_menu_box.add_child(deploy_row)


	_menu_box2.add_child(UITheme.make_section_header("Network"))

	var host := _make_button("HOST GAME")
	host.tooltip_text = "Start an online / LAN server that friends can join."
	host.pressed.connect(func() -> void: _with_name(_open_host))
	_menu_box2.add_child(host)

	var join := _make_button("JOIN GAME")
	join.tooltip_text = "Find a LAN or online game, or type an address."
	join.pressed.connect(func() -> void: _with_name(func() -> void:
		_menu_root.visible = false
		_join_root.visible = true
		UITheme.safe_grab_focus_deferred(_join_first_focus)))
	_menu_box2.add_child(join)

	var qj := _make_button("QUICK JOIN")
	qj.tooltip_text = "Jump into the best open game: same version, not full, lowest ping (LAN and master server)."
	qj.pressed.connect(func() -> void: _with_name(func() -> void:
		_menu_root.visible = false
		_quick_join()))
	_menu_box2.add_child(qj)

	_menu_box2.add_child(UITheme.spacer(4))
	_menu_box2.add_child(UITheme.make_section_header("System"))

	var settings := _make_button("SETTINGS")
	settings.pressed.connect(_open_settings)
	var sys_row := HBoxContainer.new()
	sys_row.add_theme_constant_override("separation", 8)
	_menu_box2.add_child(sys_row)
	for b in [settings]:
		b.custom_minimum_size = Vector2(0, b.custom_minimum_size.y)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sys_row.add_child(settings)

	var stats := _make_button("STATS")
	stats.tooltip_text = "Your career totals: kills, deaths, K/D and accuracy."
	stats.pressed.connect(func() -> void:
		_refresh_stats_labels()
		_menu_root.visible = false
		_stats_root.visible = true)
	var quit := _make_button("QUIT")
	quit.pressed.connect(func() -> void: get_tree().quit())
	# Settings / Stats / Quit share one row so the map preview fits below.
	for b in [stats, quit]:
		b.custom_minimum_size = Vector2(0, b.custom_minimum_size.y)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sys_row.add_child(b)

	# Preview of the picked map (thumbnails baked by tools/make_thumbs.py).
	_map_thumb = TextureRect.new()
	_map_thumb.custom_minimum_size = Vector2(272, 102)
	_map_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_box2.add_child(UITheme.spacer(4))
	_menu_box2.add_child(_map_thumb)
	var credits_btn := Button.new()
	credits_btn.text = "Credits & licenses"
	credits_btn.flat = true
	credits_btn.add_theme_font_size_override("font_size", 13)
	credits_btn.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	credits_btn.add_theme_color_override("font_hover_color", UITheme.COL_ACCENT_HI)
	credits_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	credits_btn.pressed.connect(_open_credits)
	_menu_box2.add_child(credits_btn)
	_update_map_thumb()


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


var _credits_root: PanelContainer = null

const CREDITS_TEXT := """[b]Soldat Reborn[/b] %s — a Godot 4 rebuild of the classic run-and-gun Soldat.
Game code: Soldat Reborn contributors (MIT license).

[b]Soldat[/b] was created by Michał "MM" Marcinkowski (Transhuman Design) with the Soldat community.
Sounds, weapon / soldier / interface graphics, animations and the classic maps are from the Soldat base content — [color=#9fd0ff]github.com/Soldat/base[/color] — licensed CC BY 4.0 ([color=#9fd0ff]creativecommons.org/licenses/by/4.0[/color]). Repackaged for Godot; see CREDITS.md in the source for details.

Built with the [b]Godot Engine[/b] (MIT license, godotengine.org).

This is an unofficial fan rebuild and is not endorsed by the original Soldat authors."""


func _build_credits() -> void:
	_credits_root = PanelContainer.new()
	_credits_root.add_theme_stylebox_override("panel", UITheme.panel_style())
	_credits_root.set_anchors_preset(Control.PRESET_CENTER, true)
	_credits_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_credits_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_credits_root.visible = false
	add_child(_credits_root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(620, 0)
	_credits_root.add_child(box)
	box.add_child(UITheme.make_screen_title("CREDITS"))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(0, 280)
	body.add_theme_font_size_override("normal_font_size", 15)
	body.add_theme_font_size_override("bold_font_size", 15)
	body.add_theme_color_override("default_color", UITheme.COL_TEXT)
	body.text = CREDITS_TEXT % ("v" + str(ProjectSettings.get_setting("application/config/version", "")))
	box.add_child(body)
	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_credits_root.visible = false
		_menu_root.visible = true)
	box.add_child(back)


## First launch: ask what to call the player (used in kill feed, scoreboard,
## multiplayer). Skippable; Settings -> Game changes it later.
static func has_real_name() -> bool:
	var n := Settings.player_name.strip_edges()
	return Settings.name_set and n != "" and n != "Player"


# Name prompt. First launch: pick a name, then Training or the menu (no skip).
# Later: CHANGE NAME on the menu, or any Training / online button while the
# name is still the default, opens it with `then` run after saving.
func _build_name_prompt(then: Callable = Callable(), changing := false) -> void:
	var root := PanelContainer.new()
	root.add_theme_stylebox_override("panel", UITheme.panel_style())
	root.set_anchors_preset(Control.PRESET_CENTER, true)
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(440, 0)
	root.add_child(box)
	box.add_child(UITheme.make_screen_title("YOUR NAME" if changing else "WELCOME, SOLDIER"))
	var lbl := Label.new()
	lbl.text = "What should we call you? It shows in the kill feed, the scoreboard and online."
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_body(lbl)
	box.add_child(lbl)
	var edit := LineEdit.new()
	edit.max_length = 24
	edit.placeholder_text = "Type your name"
	edit.text = Settings.player_name if has_real_name() else ""
	edit.custom_minimum_size = Vector2(0, 38)
	UITheme.style_lineedit(edit)
	box.add_child(edit)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	box.add_child(hint)
	var buttons: Array = []
	var first := not changing and then.is_null()
	var train: Button = null
	if first:
		train = _make_button("START WITH TRAINING", true)
		box.add_child(train)
		buttons.append(train)
	var go := _make_button("TO THE MENU" if first else ("SAVE" if then.is_null() else "SAVE AND CONTINUE"), not first)
	box.add_child(go)
	buttons.append(go)
	var cancel: Button = null
	if not first:
		cancel = _make_button("CANCEL")
		box.add_child(cancel)
	_menu_root.visible = false
	var valid := func(t: String) -> bool:
		var c := t.strip_edges()
		return c != "" and c.to_lower() != "player"
	var refresh := func(t: String) -> void:
		var ok: bool = valid.call(t)
		for b in buttons:
			(b as Button).disabled = not ok
		hint.text = "" if ok else ("Pick something other than \"Player\"." if t.strip_edges().to_lower() == "player" else "Type a name to continue.")
	edit.text_changed.connect(refresh)
	refresh.call(edit.text)
	var close := func() -> void:
		root.queue_free()
		_menu_root.visible = true
		_refresh_name_btn()
		UITheme.safe_grab_focus_deferred(_menu_first_focus)
	var finish := func(after: Callable) -> void:
		if not valid.call(edit.text):
			refresh.call(edit.text)
			return
		Settings.player_name = edit.text.strip_edges().left(24)
		Settings.name_set = true
		Settings.save()
		close.call()
		if not after.is_null():
			after.call()
	go.pressed.connect(func() -> void: finish.call(then))
	if train != null:
		train.pressed.connect(func() -> void: finish.call(start_training_match))
	edit.text_submitted.connect(func(_t: String) -> void: finish.call(then))
	if cancel != null:
		cancel.pressed.connect(close)
	_name_prompt_root = root
	UITheme.safe_grab_focus_deferred(edit)


# ── Updates (scripts/updater.gd lives on the tree root so a download survives
# going into a match) ─────────────────────────────────────────────────────
const Updater = preload("res://scripts/updater.gd")
var _upd_btn: Button = null
var _upd_panel: PanelContainer = null


static func updater(tree: SceneTree) -> Node:
	var u := tree.root.get_node_or_null("Updater")
	if u == null:
		u = Updater.new()
		u.name = "Updater"
		tree.root.add_child.call_deferred(u)
	return u


func _build_update_button() -> void:
	_upd_btn = Button.new()
	UITheme.style_button(_upd_btn, 16, true)
	_upd_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_upd_btn.offset_top = 16
	_upd_btn.offset_left = 16
	_upd_btn.custom_minimum_size = Vector2(0, 38)
	_upd_btn.visible = false
	_upd_btn.pressed.connect(_on_update_pressed)
	add_child(_upd_btn)
	var u := updater(get_tree())
	u.state_changed.connect(_refresh_update_ui)
	_refresh_update_ui.call_deferred()
	var forced := str(OS.get_cmdline_user_args()).contains("--update-url=")
	if Settings.check_updates and DisplayServer.get_name() != "headless" and (forced or not OS.has_feature("editor")) \
			and not Net.is_dedicated and str(u.get("state")) == "idle":
		u.check.call_deferred()


func _refresh_update_ui() -> void:
	if _upd_btn == null or not is_inside_tree():
		return
	var u := updater(get_tree())
	var st := str(u.get("state"))
	var ver := Updater.current_version()
	_upd_btn.disabled = false
	_upd_btn.tooltip_text = "Checks GitHub for a newer version of the game."
	match st:
		"available":
			_upd_btn.text = "  UPDATE AVAILABLE: v%s  " % str(u.get("latest"))
		"downloading":
			_upd_btn.text = "  DOWNLOADING UPDATE %d%%  " % int(float(u.get("progress")) * 100.0)
			_upd_btn.disabled = true
		"ready":
			_upd_btn.text = "  RESTART TO UPDATE TO v%s  " % str(u.get("latest"))
		"checking":
			_upd_btn.text = "  v%s · CHECKING FOR UPDATES...  " % ver
			_upd_btn.disabled = true
		"none":
			_upd_btn.text = "  v%s · UP TO DATE  " % ver
		"failed":
			if str(u.get("latest")) != "":
				_upd_btn.text = "  UPDATE FAILED · RETRY  "
			else:
				_upd_btn.text = "  v%s · CHECK FOR UPDATES  " % ver
			_upd_btn.tooltip_text = str(u.get("error"))
		_:
			_upd_btn.text = "  v%s · CHECK FOR UPDATES  " % ver
	# Always shown: the current version, and one click to check again.
	_upd_btn.visible = true


func _on_update_pressed() -> void:
	var u := updater(get_tree())
	var st := str(u.get("state"))
	if st == "ready":
		u.apply_and_restart()
		return
	if st == "failed" and str(u.get("latest")) != "":
		u.start()
		return
	if st in ["idle", "none", "failed"]:
		u.check()
		return
	if _upd_panel != null:
		_upd_panel.queue_free()
	_upd_panel = PanelContainer.new()
	_upd_panel.add_theme_stylebox_override("panel", UITheme.panel_style())
	_upd_panel.set_anchors_preset(Control.PRESET_CENTER, true)
	_upd_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_upd_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_upd_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(560, 0)
	_upd_panel.add_child(box)
	box.add_child(UITheme.make_screen_title("UPDATE TO v%s" % str(u.get("latest"))))
	var sub := Label.new()
	sub.text = "You have v%s." % Updater.current_version()
	UITheme.style_body(sub)
	box.add_child(sub)
	var notes := RichTextLabel.new()
	notes.bbcode_enabled = true
	var txt := str(u.get("notes"))
	notes.text = md_to_bb(txt.left(2400)) + ("..." if txt.length() > 2400 else "")
	notes.custom_minimum_size = Vector2(540, 260)
	notes.add_theme_font_size_override("normal_font_size", 13)
	notes.add_theme_color_override("default_color", UITheme.COL_TEXT)
	box.add_child(notes)
	var how := Label.new()
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.add_theme_font_size_override("font_size", 13)
	how.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	how.text = "The new version downloads in the background (you can keep playing). Then press RESTART TO UPDATE: the game closes, swaps itself and starts again. Your settings, stats and maps are kept." \
			if Updater.can_self_update() else "This opens the download in your browser. Install the downloaded file to update; your settings, stats and maps are kept."
	box.add_child(how)
	var go := _make_button("UPDATE NOW" if Updater.can_self_update() else "DOWNLOAD", true)
	go.pressed.connect(func() -> void:
		_upd_panel.queue_free()
		_upd_panel = null
		_menu_root.visible = true
		u.start())
	box.add_child(go)
	var later := _make_button("LATER")
	later.pressed.connect(func() -> void:
		_upd_panel.queue_free()
		_upd_panel = null
		_menu_root.visible = true)
	box.add_child(later)
	_menu_root.visible = false
	UITheme.safe_grab_focus_deferred(go)


var _name_prompt_root: Control = null
var _name_btn: Button = null


func _refresh_name_btn() -> void:
	if _name_btn != null:
		var t := "  %s  ·  LV %d  ·  CHANGE NAME  " % [Settings.player_name if has_real_name() else "No name yet", Stats.level_for(Stats.xp())]
		if _name_btn.text != t:
			_name_btn.text = t


## Run `action` once the player has a real name (asks first if not).
func _with_name(action: Callable) -> void:
	if has_real_name():
		action.call()
	else:
		_build_name_prompt(action, false)


# Show LOADING first (the match can take a few seconds to build), then switch
# scenes; if the switch fails, say so instead of silently staying here.
var _loading_lbl: Label = null


func _go_to_match() -> void:
	if _loading_lbl == null:
		_loading_lbl = Label.new()
		_loading_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		_loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_loading_lbl.add_theme_font_size_override("font_size", 40)
		_loading_lbl.add_theme_color_override("font_color", UITheme.COL_ACCENT)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.65)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		_loading_lbl.add_child(bg)
		bg.show_behind_parent = true
		add_child(_loading_lbl)
	_loading_lbl.text = "LOADING MATCH..."
	_loading_lbl.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var err := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_loading_lbl.visible = false
		if Net.is_networked():
			Net.leave()
		_status_label.text = "Couldn't load the match (%s). If you just rebuilt or updated the game, close it and start it again." % error_string(err)
		if _menu_root != null:
			_menu_root.visible = true
		if _host_root != null:
			_host_root.visible = false
		if _join_root != null:
			_join_root.visible = false


func start_training_match() -> void:
	preload("res://scripts/training.gd").start_training()
	Net.set_singleplayer()
	_go_to_match()


func _open_credits() -> void:
	_menu_root.visible = false
	_credits_root.visible = true


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
	_stats_body.fit_content = false
	_stats_body.scroll_active = true
	_stats_body.custom_minimum_size = Vector2(0, 400)
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
	var lp: Array = Stats.level_progress()
	lines.append("[b]Rank[/b] level %d  ·  %d / %d XP to level %d  ·  [color=#a8b0bc]kill +10, headshot +5, capture +50, match +20, win +80[/color]" % [Stats.level_for(Stats.xp()), lp[0], lp[1], Stats.level_for(Stats.xp()) + 1])
	lines.append("")
	lines.append("[b][color=#f5a623]ACHIEVEMENTS  %d / %d[/color][/b]" % [Stats.unlocked.size(), Stats.ACHIEVEMENTS.size()])
	for a in Stats.ACHIEVEMENTS:
		var pr: Array = Stats.achievement_progress(a)
		if Stats.unlocked.has(a[0]):
			lines.append("[color=#8ce07a]✔ %s[/color]  [color=#a8b0bc]%s[/color]" % [a[1], a[2]])
		else:
			lines.append("[color=#8a8f99]○ %s  %s  (%d/%d)[/color]" % [a[1], a[2], pr[0], pr[1]])
	lines.append("")
	lines.append("[i]Kills by weapon[/i]")
	var pairs: Array = []
	for k in Stats.kills_by_weapon.keys():
		pairs.append([str(k), int(Stats.kills_by_weapon[k])])
	pairs.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	var row := ""
	for pi in pairs.size():
		var cell := "%s: %d" % [pairs[pi][0], pairs[pi][1]]
		row += ("  " + cell) if pi % 3 == 0 else ("   ·   " + cell)
		if pi % 3 == 2 or pi == pairs.size() - 1:
			lines.append(row)
			row = ""
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
	map_lbl.text = "Mode  ·  Map"
	UITheme.style_body(map_lbl)
	_host_panel.add_child(map_lbl)

	# Mode and map side by side; the mode mirrors the main menu's picker.
	var pick_row := HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 8)
	_host_panel.add_child(pick_row)
	_host_panel.add_child(_make_mode_desc())
	_host_mode_pick = OptionButton.new()
	for mname in MODE_NAMES:
		_host_mode_pick.add_item(mname)
	_host_mode_pick.selected = clampi(Settings.game_mode, 0, MODE_NAMES.size() - 1)
	_host_mode_pick.custom_minimum_size = Vector2(0, 34)
	_host_mode_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_option_button(_host_mode_pick)
	_host_mode_pick.item_selected.connect(func(idx: int) -> void:
		Settings.game_mode = idx
		Settings.save()
		_refresh_mode_desc()
		if _mode_pick != null:
			_mode_pick.selected = idx)
	pick_row.add_child(_host_mode_pick)
	_tooltip_modes(_host_mode_pick)

	_map_pick = OptionButton.new()
	for name in MAP_NAMES:
		_map_pick.add_item(name)
	# Your own maps (editor saves / Generate) can be hosted too — they travel
	# to clients as JSON. Ids 10000+ index into _host_custom_paths.
	_host_custom_paths.clear()
	for path_v in MapIO.list_files():
		var cpath: String = String(path_v)
		if cpath.ends_with("/_playtest.json"):
			continue
		_map_pick.add_item("Custom: %s" % cpath.get_file().get_basename(), 10000 + _host_custom_paths.size())
		_host_custom_paths.append(cpath)
	_map_pick.selected = clampi(Settings.map_index, 0, MAP_NAMES.size() - 1)
	_map_pick.custom_minimum_size = Vector2(0, 34)
	UITheme.style_option_button(_map_pick)
	_map_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick_row.add_child(_map_pick)
	_host_thumb = TextureRect.new()
	_host_thumb.custom_minimum_size = Vector2(272, 102)
	_host_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_host_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_host_thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_host_panel.add_child(_host_thumb)
	var upd := func(_i: int = 0) -> void:
		var path := "res://assets/map_thumbs/%s.png" % NavGraph.key_for(_map_pick.get_item_text(_map_pick.selected))
		_host_thumb.visible = ResourceLoader.exists(path)
		_host_thumb.texture = load(path) if _host_thumb.visible else null
	_map_pick.item_selected.connect(upd)
	upd.call()

	_host_panel.add_child(UITheme.make_section_header("Network"))

	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 8)
	var port_lbl := Label.new()
	port_lbl.text = "Port"
	UITheme.style_body(port_lbl)
	port_row.add_child(port_lbl)
	_host_port_edit = LineEdit.new()
	_host_port_edit.text = str(Net.DEFAULT_PORT)
	_host_port_edit.placeholder_text = str(Net.DEFAULT_PORT)
	_host_port_edit.custom_minimum_size = Vector2(110, 34)
	UITheme.style_lineedit(_host_port_edit)
	port_row.add_child(_host_port_edit)
	if OS.get_name() == "Windows":
		var fw := _make_button("FIX FIREWALL")
		fw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fw.tooltip_text = "If friends on your Wi-Fi can't see or join your game, Windows Firewall is usually blocking it. This adds a rule for Soldat Reborn (Windows asks for permission once)."
		fw.pressed.connect(func() -> void:
			_status_label.text = "Approve the Windows prompt to allow Soldat Reborn through the firewall." if Net.allow_through_firewall() \
					else "Couldn't start the firewall helper.")
		port_row.add_child(fw)
	_host_panel.add_child(port_row)
	var ips: Array = Net.lan_ips()
	var ip_note := Label.new()
	ip_note.text = "Same network: no setup, friends find it under Join → Find Games / Quick Join. Elsewhere: the router port opens itself (UPnP) and the pause menu has a join code to copy."
	if not ips.is_empty():
		ip_note.text += "  LAN address: %s" % " / ".join(ips)
	ip_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ip_note.add_theme_font_size_override("font_size", 13)
	ip_note.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	_host_panel.add_child(ip_note)
	var upnp_cb := CheckBox.new()
	upnp_cb.text = "Open the port on my router automatically (UPnP)"
	upnp_cb.tooltip_text = "Lets friends outside your network join with a code. Turn off if your router or network admin doesn't allow it."
	upnp_cb.button_pressed = Settings.upnp
	UITheme.style_checkbox(upnp_cb)
	upnp_cb.toggled.connect(func(on: bool) -> void:
		Settings.upnp = on
		Settings.save())
	_host_panel.add_child(upnp_cb)
	# Optional internet listing through the master server (URL lives on the
	# Join screen). Players outside your LAN still need the port forwarded.
	var pub_cb := CheckBox.new()
	pub_cb.text = "List on the master server"
	pub_cb.button_pressed = Settings.host_public
	UITheme.style_checkbox(pub_cb)
	pub_cb.toggled.connect(func(on: bool) -> void:
		Settings.host_public = on
		Settings.save())
	_host_panel.add_child(pub_cb)
	_host_pub_cb = pub_cb

	_host_panel.add_child(UITheme.spacer(6))

	var start := _make_button("START HOSTING", true)
	_host_first_focus = start
	start.pressed.connect(func() -> void:
		var idx := _map_pick.get_selected_id()
		if idx < 0:
			idx = _map_pick.selected
		# A custom map sets the path; a built-in pick clears any leftover one
		# (e.g. the editor play-test) so the chosen map actually loads.
		Settings.custom_map_path = ""
		if idx >= 10000 and idx - 10000 < _host_custom_paths.size():
			Settings.custom_map_path = _host_custom_paths[idx - 10000]
			idx = 0
		idx = clampi(idx, 0, MAP_NAMES.size() - 1)
		Settings.map_index = idx
		Settings.save()
		start.disabled = true
		var port := int(_host_port_edit.text) if _host_port_edit.text.is_valid_int() else Net.DEFAULT_PORT
		if Net.host_game(port, idx):
			if Settings.host_public and Settings.master_url.strip_edges() != "":
				Net.register_url = Settings.master_url.strip_edges()
				Net._start_master_heartbeat(port)
			_go_to_match()
		else:
			# Net.host_game already set the status text; re-enable so the user can retry.
			start.disabled = false
			_status_label.text = Net.status)
	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_host_root.visible = false
		_menu_root.visible = true)
	# One row (START wider) so the panel stays short enough for small windows.
	var host_btns := HBoxContainer.new()
	host_btns.add_theme_constant_override("separation", 8)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.size_flags_stretch_ratio = 2.0
	host_btns.add_child(back)
	host_btns.add_child(start)
	_host_panel.add_child(host_btns)


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
	ip_lbl.text = "Join code or host IP"
	UITheme.style_body(ip_lbl)
	_join_panel.add_child(ip_lbl)

	_ip_edit = LineEdit.new()
	_ip_edit.text = Settings.last_join_ip
	_ip_edit.placeholder_text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(0, 34)
	UITheme.style_lineedit(_ip_edit)
	_join_panel.add_child(_ip_edit)

	var port_lbl := Label.new()
	port_lbl.text = "Port"
	UITheme.style_body(port_lbl)
	_join_panel.add_child(port_lbl)

	_port_edit = LineEdit.new()
	_port_edit.text = str(Settings.last_join_port)
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

	var browse := _make_button("FIND GAMES  (LAN / ONLINE)")
	browse.pressed.connect(_on_browse_pressed)
	_join_panel.add_child(browse)

	var qj2 := _make_button("QUICK JOIN")
	qj2.tooltip_text = "Join the best open game automatically."
	qj2.pressed.connect(func() -> void:
		Settings.master_url = _master_edit.text.strip_edges()
		Settings.save()
		_join_root.visible = false
		_quick_join())
	_join_panel.add_child(qj2)

	_connect_btn = _make_button("CONNECT", true)
	_connect_btn.pressed.connect(_on_connect_pressed)
	_join_panel.add_child(_connect_btn)
	_join_first_focus = _connect_btn

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
	_browse_panel.add_child(UITheme.make_section_header("Local Network"))
	_lan_list = VBoxContainer.new()
	_lan_list.add_theme_constant_override("separation", 4)
	_browse_panel.add_child(_lan_list)
	_browse_panel.add_child(UITheme.make_section_header("Recent"))
	_recent_list = VBoxContainer.new()
	_recent_list.add_theme_constant_override("separation", 4)
	_browse_panel.add_child(_recent_list)
	_browse_panel.add_child(UITheme.make_section_header("Master Server"))

	_browse_list = VBoxContainer.new()
	_browse_list.add_theme_constant_override("separation", 4)
	_browse_panel.add_child(_browse_list)

	_browse_panel.add_child(UITheme.spacer(4))
	var hint := Label.new()
	hint.text = "Grey rows are full or a different version.  \"— ms\": no ping reply (internet hosts forward UDP port+1 too)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	_browse_panel.add_child(hint)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	var refresh := _make_button("REFRESH")
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.pressed.connect(_refresh_browse)
	brow.add_child(refresh)
	var qj := _make_button("QUICK JOIN", true)
	qj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qj.pressed.connect(_quick_join)
	brow.add_child(qj)
	_browse_panel.add_child(brow)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void:
		_qj_active = false
		_browse_root.visible = false
		_join_root.visible = true)
	_browse_panel.add_child(back)


# Dropped out of a match: offer (and after a short countdown, try) a rejoin.
var _rejoin_root: PanelContainer = null
var _rejoin_lbl: Label = null
var _rejoin_t := 0.0


func _build_rejoin() -> void:
	_rejoin_root = PanelContainer.new()
	_rejoin_root.add_theme_stylebox_override("panel", UITheme.panel_style())
	_rejoin_root.set_anchors_preset(Control.PRESET_CENTER, true)
	_rejoin_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rejoin_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_rejoin_root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(420, 0)
	_rejoin_root.add_child(box)
	box.add_child(UITheme.make_screen_title("CONNECTION LOST"))
	_rejoin_lbl = Label.new()
	_rejoin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_body(_rejoin_lbl)
	box.add_child(_rejoin_lbl)
	var go := _make_button("REJOIN", true)
	go.pressed.connect(_do_rejoin)
	box.add_child(go)
	var no := _make_button("BACK TO MENU")
	no.pressed.connect(func() -> void:
		_rejoin_t = 0.0
		_rejoin_root.visible = false
		_menu_root.visible = true)
	box.add_child(no)
	_menu_root.visible = false
	_rejoin_t = 5.0
	_tick_rejoin(0.0)
	UITheme.safe_grab_focus_deferred(go)


func _tick_rejoin(delta: float) -> void:
	if _rejoin_root == null or not _rejoin_root.visible or _rejoin_t <= 0.0:
		return
	_rejoin_t -= delta
	_rejoin_lbl.text = "Dropped from %s:%d.\nRejoining in %d s... (your score and team are kept)" % [Net.last_server_ip, Net.last_server_port, int(ceil(maxf(_rejoin_t, 0.0)))]
	if _rejoin_t <= 0.0:
		_do_rejoin()


func _do_rejoin() -> void:
	_rejoin_t = 0.0
	_rejoin_root.visible = false
	_join_server(Net.last_server_ip, Net.last_server_port)


# After an update (auto-updater or a new download): show this version's
# changelog section once. First-ever launch just records the version.
static func changelog_section(version: String) -> String:
	var f := FileAccess.open("res://CHANGELOG.md", FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	var head := "## [%s]" % version
	var i := txt.find(head)
	if i < 0:
		return ""
	var j := txt.find("\n## [", i + head.length())
	var sec := txt.substr(i, (j - i) if j > 0 else -1)
	sec = sec.substr(sec.find("\n") + 1).strip_edges()
	return md_to_bb(sec)


## Changelog markdown -> RichTextLabel bbcode (headers, bullets).
static func md_to_bb(sec: String) -> String:
	var out := PackedStringArray()
	for line in sec.replace("**", "").replace("`", "").split("\n"):
		var l := line.strip_edges(false, true)
		if l.begins_with("### "):
			out.append("\n[b][color=#f5a623]%s[/color][/b]" % l.substr(4).to_upper())
		elif l.strip_edges().begins_with("- "):
			var ind := l.length() - l.strip_edges(true, false).length()
			out.append("%s• %s" % ["    ".repeat(ind / 2), l.strip_edges().substr(2)])
		else:
			out.append(l)
	return "\n".join(out).strip_edges()


func _maybe_whats_new() -> void:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	if Settings.last_seen_version == v:
		return
	var first := Settings.last_seen_version == ""
	Settings.last_seen_version = v
	Settings.save()
	if first:
		return
	var sec := changelog_section(v)
	if sec == "":
		return
	var root := PanelContainer.new()
	root.add_theme_stylebox_override("panel", UITheme.panel_style())
	root.set_anchors_preset(Control.PRESET_CENTER, true)
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(600, 0)
	root.add_child(box)
	box.add_child(UITheme.make_screen_title("WHAT'S NEW IN v%s" % v))
	var notes := RichTextLabel.new()
	notes.bbcode_enabled = true
	notes.text = sec.left(2400)
	notes.custom_minimum_size = Vector2(580, 320)
	notes.add_theme_font_size_override("normal_font_size", 13)
	notes.add_theme_color_override("default_color", UITheme.COL_TEXT)
	box.add_child(notes)
	var ok := _make_button("GOT IT", true)
	ok.pressed.connect(func() -> void:
		root.queue_free()
		_menu_root.visible = true)
	box.add_child(ok)
	_menu_root.visible = false
	UITheme.safe_grab_focus_deferred(ok)


func _on_browse_pressed() -> void:
	Settings.master_url = _master_edit.text.strip_edges()
	Settings.save()
	_join_root.visible = false
	_browse_root.visible = true
	_refresh_browse()


func _refresh_browse() -> void:
	_master_rows.clear()
	_master_sig = ""
	_recent_sig = ""
	_render_recent()
	for c in _browse_list.get_children():
		c.queue_free()
	var wait := Label.new()
	wait.text = "Fetching server list..."
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait.add_theme_font_size_override("font_size", 15)
	wait.add_theme_color_override("font_color", UITheme.COL_INFO)
	_browse_list.add_child(wait)
	var url: String = Settings.master_url
	_lan_t = 0.0
	_lan_sig = ""
	if url == "":
		wait.text = "No master server set (Join screen) — LAN games show above."
		wait.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
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
	_master_rows.clear()
	for sv in servers:
		if sv is Dictionary:
			var row: Dictionary = (sv as Dictionary).duplicate()
			row["v"] = str(sv.get("version", sv.get("v", "")))
			_master_rows.append(row)
	_master_sig = ""
	_ping_t = 0.0
	if servers.is_empty():
		var empty := Label.new()
		empty.text = "No servers online."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", UITheme.COL_INFO)
		_browse_list.add_child(empty)
		return
	_render_master()


var _recent_list: VBoxContainer
var _recent_sig := ""


func _recent_rows() -> Array:
	var out: Array = []
	for k in Settings.recent_servers:
		var parts := str(k).rsplit(":", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			out.append({"ip": parts[0], "port": int(parts[1]), "name": str(k), "map": "?", "mode": "?", "players": 0, "max": 0, "v": ""})
	return out


# Games you joined before, with a live ping when they're up.
func _render_recent() -> void:
	if _recent_list == null:
		return
	var rows := _recent_rows()
	var sig := str(rows.map(func(d): return [d.get("ip"), d.get("port"), _ping_bucket(str(d.get("ip")), int(d.get("port"))), str(_live(d).get("players"))]))
	if sig == _recent_sig and _recent_list.get_child_count() > 0:
		return
	_recent_sig = sig
	for c in _recent_list.get_children():
		c.queue_free()
	if rows.is_empty():
		var l := Label.new()
		l.text = "Games you join show up here."
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
		_recent_list.add_child(l)
		return
	for d in rows:
		var up := Net.ping_of(str(d.get("ip")), int(d.get("port"))) >= 0
		var b := _server_row(d)
		if not up:
			b.text = "  %s   — offline or not answering   " % str(d.get("name"))
			b.disabled = false   # still let people try (hosts behind a firewall don't answer pings)
		_recent_list.add_child(b)


var _master_rows: Array = []
var _master_sig := ""
var _ping_t := 0.0
var _qj_active := false
var _qj_t := 0.0


func _ping_bucket(ip: String, port: int) -> int:
	var p := Net.ping_of(ip, port)
	return -1 if p < 0 else p / 10


# Live numbers from the server's own query reply win over the (up to 30 s old)
# master listing / LAN beacon.
func _live(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	var info := Net.query_info(str(d.get("ip")), int(d.get("port")))
	if not info.is_empty() and Net.ping_of(str(d.get("ip")), int(d.get("port"))) >= 0:
		for k in ["players", "max", "map", "mode", "v", "name"]:
			if info.has(k):
				out[k] = info[k]
	return out


func _row_ok(d: Dictionary) -> bool:
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	var v := str(d.get("v", ""))
	var full: bool = int(d.get("max", 0)) > 0 and int(d.get("players", 0)) >= int(d.get("max", 0))
	return (v == "" or v == mine) and not full and not bool(d.get("password", false))


func _server_row(d0: Dictionary) -> Button:
	var d := _live(d0)
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	var ver := str(d.get("v", ""))
	var ping := Net.ping_of(str(d.get("ip")), int(d.get("port")))
	var full: bool = int(d.get("max", 0)) > 0 and int(d.get("players", 0)) >= int(d.get("max", 0))
	var note := ""
	if ver != "" and ver != mine:
		note = "   (v%s)" % ver
	elif full:
		note = "   FULL"
	elif bool(d.get("password", false)):
		note = "   (locked)"
	var btn := Button.new()
	btn.text = "  %s   [%d/%d]   %s · %s   %s%s" % [str(d.get("name", "?")), int(d.get("players", 0)), int(d.get("max", 0)),
			str(d.get("map", "?")), str(d.get("mode", "?")), ("%d ms" % ping) if ping >= 0 else "— ms", note]
	btn.tooltip_text = "%s:%d" % [str(d.get("ip")), int(d.get("port"))]
	btn.custom_minimum_size = Vector2(580, 40)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.style_button(btn, 15, false)
	btn.disabled = not _row_ok(d)   # the host would refuse a different build / no room
	btn.pressed.connect(_join_server.bind(str(d.get("ip")), int(d.get("port"))))
	if ping >= 0 and not btn.disabled:
		btn.add_theme_color_override("font_color", Color(0.55, 0.95, 0.5) if ping < 80 else (Color(0.95, 0.85, 0.4) if ping < 160 else Color(0.95, 0.45, 0.35)))
	return btn


func _render_master() -> void:
	if _browse_list == null or _master_rows.is_empty():
		return
	var rows: Array = _master_rows.map(func(d): return _live(d))
	var sig := str(rows.map(func(d): return [d.get("ip"), d.get("port"), d.get("players"), d.get("map"), _ping_bucket(str(d.get("ip")), int(d.get("port")))]))
	if sig == _master_sig:
		return
	_master_sig = sig
	for c in _browse_list.get_children():
		c.queue_free()
	# Joinable first, then busiest, then lowest ping.
	var order: Array = _master_rows.duplicate()
	order.sort_custom(func(a, b) -> bool:
		var la := _live(a)
		var lb := _live(b)
		if _row_ok(la) != _row_ok(lb):
			return _row_ok(la)
		if int(la.get("players", 0)) != int(lb.get("players", 0)):
			return int(la.get("players", 0)) > int(lb.get("players", 0))
		var pa := Net.ping_of(str(a.get("ip")), int(a.get("port")))
		var pb := Net.ping_of(str(b.get("ip")), int(b.get("port")))
		return (pa if pa >= 0 else 9999) < (pb if pb >= 0 else 9999))
	for d in order:
		_browse_list.add_child(_server_row(d))


# QUICK JOIN: listen / fetch for a moment, then join the best open game.
func _quick_join() -> void:
	_browse_root.visible = true
	_refresh_browse()
	_qj_active = true
	_qj_t = 2.5
	_status_label.text = "Quick join: looking for an open game..."


func _quick_join_pick() -> void:
	_qj_active = false
	var cands: Array = []
	for d in (Net.lan_poll() if _lan_listening else []):
		cands.append(d)
	for d in _master_rows:
		cands.append(d)
	var best = null
	var best_score := INF
	for d0 in cands:
		var d := _live(d0)
		if not _row_ok(d):
			continue
		var ping := Net.ping_of(str(d.get("ip")), int(d.get("port")))
		var score: float = (float(ping) if ping >= 0 else 400.0)
		if int(d.get("players", 0)) > 0:
			score -= 150.0   # a game with people in it beats an empty one
		if score < best_score:
			best_score = score
			best = d
	if best == null:
		_status_label.text = "No open games found. Host one with HOST GAME, or try again."
		return
	_status_label.text = "Quick join: %s" % str(best.get("name", "?"))
	_join_server(str(best.get("ip")), int(best.get("port")))


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
	foot.text = "WASD · W jump · S crouch/roll · X prone · RMB jet · LMB shoot · 1-0 · Q sec · R reload · E nade · F throw · G nade type · Tab scores · H help · F9 GIF"
	if OS.has_feature("android") or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		foot.text = "Left side: move / jump · right side: aim + hold to fire · on-screen buttons: jet, grenade, reload, swap, throw, prone · tap the top bar for scores"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -42
	foot.offset_bottom = -18
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", UITheme.COL_TEXT_MUTED)
	add_child(foot)
	# Only on the main list: sub-panels (Host, Join, Stats ...) reach down there.
	_title_nodes.append(foot)


func _make_button(text: String, primary: bool = false) -> Button:
	return UITheme.make_button(text, primary)


func _on_connect_pressed() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	var port := int(_port_edit.text) if _port_edit.text.is_valid_int() else Net.DEFAULT_PORT
	var code: Array = Net.parse_join_code(ip) if not ip.contains(".") else []
	if not code.is_empty():
		ip = str(code[0])
		port = int(code[1])
		_port_edit.text = str(port)
	Settings.last_join_ip = ip
	Settings.last_join_port = port
	Settings.save()
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
		var key := "%s:%d" % [Net.last_server_ip, Net.last_server_port]
		Settings.recent_servers.erase(key)
		Settings.recent_servers.push_front(key)
		Settings.recent_servers = Settings.recent_servers.slice(0, 5)
		Settings.save()
		_go_to_match()


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
	_go_back()
	get_viewport().set_input_as_handled()


# Android back button / gesture behaves like ESC (quit_on_go_back is off).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		_go_back()


func _go_back() -> void:
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
	elif _credits_root != null and _credits_root.visible:
		_credits_root.visible = false
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
		else:
			# Not in the list (the editor's _playtest slot, or a deleted file):
			# the picker would say "Rotation" while PLAY loaded that map.
			Settings.custom_map_path = ""
			Settings.save()
	elif Settings.map_index >= 0 and Settings.map_index < MAP_NAMES.size():
		# Rotation mode leaves map_index cycling, so we can't distinguish "pinned"
		# from "rotating" — keep slot 0 selected by default.
		sel = 0
	_sp_map_pick.selected = sel


# ── Mode descriptions (v1.18) ────────────────────────────
func _make_mode_desc() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(320, 0)
	UITheme.style_body(l, 13, Color(0.78, 0.82, 0.88))
	l.text = GameInfo.mode_goal(Settings.game_mode)
	_mode_desc_labels.append(l)
	return l


var _surv_cb: CheckBox = null
var _adv_cb: CheckBox = null


# Gun Game ignores Survival / Advance (see Settings.survival): show that.
func _refresh_submode_boxes() -> void:
	var gg := Settings.game_mode == Settings.MODE_GG
	for pair in [[_surv_cb, "survival"], [_adv_cb, "advance"]]:
		var cb: CheckBox = pair[0]
		if cb == null:
			continue
		cb.disabled = gg
		cb.set_pressed_no_signal(Settings.get(pair[1] + "_pref") and not gg)
		cb.tooltip_text = "Not used in Gun Game (it's a free-for-all: climb the whole weapon ladder to win)." if gg else GameInfo.SUBMODES[pair[1]]


func _refresh_mode_desc() -> void:
	_refresh_submode_boxes()
	for l in _mode_desc_labels:
		if is_instance_valid(l):
			l.text = GameInfo.mode_goal(Settings.game_mode)


func _tooltip_modes(ob: OptionButton) -> void:
	var pop := ob.get_popup()
	for i in pop.item_count:
		pop.set_item_tooltip(i, "%s\n%s" % [GameInfo.mode_goal(i), GameInfo.mode_detail(i)])


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
	_go_to_match()


func _update_map_thumb() -> void:
	if _map_thumb == null:
		return
	var name := ""
	if Settings.custom_map_path == "":
		var idx := _sp_map_pick.selected if _sp_map_pick != null else 0
		if idx > 0 and idx < _sp_map_paths.size() and str(_sp_map_paths[idx]).begins_with("builtin:"):
			name = str(_sp_map_paths[idx]).substr(len("builtin:"))
	var path := "res://assets/map_thumbs/%s.png" % NavGraph.key_for(name)
	if name != "" and ResourceLoader.exists(path):
		_map_thumb.texture = load(path)
		_map_thumb.visible = true
	else:
		_map_thumb.texture = null
		_map_thumb.visible = false


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
	_update_map_thumb()
