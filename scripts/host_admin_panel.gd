extends VBoxContainer
## HostAdminPanel — in-game host admin UI (ESC → Host Settings, #74).
##
## Only shown when the local peer is host (or singleplayer — SP is effectively
## the local host of a 1-player match). Sliders / toggles here mutate Settings
## + MatchConfig.host_friendly_fire, then broadcast to every client via
## MatchConfig.host_broadcast(). Map / mode changes trigger a full match
## restart via Main.net_match_restart so both peers reload the same scene.

signal back_pressed
signal restart_requested

# Map + mode name lists mirrored from menu.gd. Duplication here (instead of a
# preload) keeps the pause-menu bundle small and avoids pulling in the whole
# menu scene for its constants.
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
	"Domination", "Battle Royale",
]

var _pending_map_idx: int = 0
var _pending_mode_idx: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(500, 0)
	set_anchors_preset(Control.PRESET_CENTER, true)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_pending_map_idx = clampi(Settings.map_index, 0, MAP_NAMES.size() - 1)
	_pending_mode_idx = clampi(Settings.game_mode, 0, MODE_NAMES.size() - 1)
	_build()


func _build() -> void:
	var head := Label.new()
	head.text = "HOST SETTINGS"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Color(0.95, 0.5, 0.35))
	head.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	head.add_theme_constant_override("outline_size", 6)
	add_child(head)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "Broadcasts to every client. FFA modes (DM/RM/BR) ignore the FF toggle."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	add_child(hint)

	# Scroll region so a fully expanded panel + restart buttons still fit on 720p.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	col.process_mode = Node.PROCESS_MODE_ALWAYS
	scroll.add_child(col)

	# Friendly fire — the headline new toggle. Default OFF; in FFA modes the
	# effective FF is always on regardless of this bool (see MatchConfig).
	var ff_cb := CheckButton.new()
	ff_cb.text = "Friendly fire (team modes)"
	ff_cb.button_pressed = MatchConfig.host_friendly_fire
	ff_cb.toggled.connect(func(on: bool) -> void:
		MatchConfig.host_friendly_fire = on
		MatchConfig.save_host_ff()
		MatchConfig.host_broadcast())
	col.add_child(ff_cb)

	col.add_child(_labelled_slider("Gravity", 0.5, 2.0, 0.05,
		float(Settings.mod_gravity),
		func(v: float) -> void:
			Settings.mod_gravity = v
			Settings.save()
			MatchConfig.host_broadcast(),
		"%.2fx"))
	col.add_child(_labelled_slider("Jet regen", 0.5, 2.0, 0.05,
		float(Settings.mod_jet),
		func(v: float) -> void:
			Settings.mod_jet = v
			Settings.save()
			MatchConfig.host_broadcast(),
		"%.2fx"))
	col.add_child(_labelled_slider("Damage", 0.5, 2.0, 0.05,
		float(Settings.mod_damage),
		func(v: float) -> void:
			Settings.mod_damage = v
			Settings.save()
			MatchConfig.host_broadcast(),
		"%.2fx"))
	col.add_child(_labelled_slider("Speed", 0.5, 1.5, 0.05,
		float(Settings.mod_speed),
		func(v: float) -> void:
			Settings.mod_speed = v
			Settings.save()
			MatchConfig.host_broadcast(),
		"%.2fx"))

	# Bot roster (host-side only — clients don't spawn bots so this only
	# actually matters on the next match restart).
	var bc_row := HBoxContainer.new()
	bc_row.add_theme_constant_override("separation", 12)
	col.add_child(bc_row)
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
	bc_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		Settings.save()
		MatchConfig.host_broadcast())

	col.add_child(_labelled_slider("Bot skill", 1.0, 5.0, 1.0,
		float(Settings.bot_skill),
		func(v: float) -> void:
			Settings.bot_skill = clampi(int(round(v)), 1, 5)
			Settings.save()
			MatchConfig.host_broadcast(),
		"%d"))

	col.add_child(_pad(6))

	# Mode + Map pickers. Changes here are staged locally — user hits RESTART
	# MATCH to broadcast the switch, which reloads main.tscn on every peer.
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	col.add_child(mode_row)
	var mode_lbl := Label.new()
	mode_lbl.text = "Mode"
	mode_lbl.custom_minimum_size = Vector2(170, 0)
	mode_lbl.add_theme_font_size_override("font_size", 14)
	mode_row.add_child(mode_lbl)
	var mode_pick := OptionButton.new()
	for name in MODE_NAMES:
		mode_pick.add_item(name)
	mode_pick.selected = clampi(_pending_mode_idx, 0, MODE_NAMES.size() - 1)
	mode_pick.custom_minimum_size = Vector2(300, 32)
	mode_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_pick.item_selected.connect(func(idx: int) -> void:
		_pending_mode_idx = idx)
	mode_row.add_child(mode_pick)

	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 12)
	col.add_child(map_row)
	var map_lbl := Label.new()
	map_lbl.text = "Map"
	map_lbl.custom_minimum_size = Vector2(170, 0)
	map_lbl.add_theme_font_size_override("font_size", 14)
	map_row.add_child(map_lbl)
	var map_pick := OptionButton.new()
	for name in MAP_NAMES:
		map_pick.add_item(name)
	map_pick.selected = clampi(_pending_map_idx, 0, MAP_NAMES.size() - 1)
	map_pick.custom_minimum_size = Vector2(300, 32)
	map_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_pick.item_selected.connect(func(idx: int) -> void:
		_pending_map_idx = idx)
	map_row.add_child(map_pick)

	col.add_child(_pad(4))

	var restart := _make_button("RESTART MATCH")
	restart.pressed.connect(_do_restart)
	col.add_child(restart)

	var back := _make_button("BACK")
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)


func _do_restart() -> void:
	# Apply the staged map/mode, broadcast to peers, and reload main.tscn.
	# In SP just reload; in MP the main.net_match_restart RPC handles both peers.
	var map_idx: int = clampi(_pending_map_idx, 0, MAP_NAMES.size() - 1)
	var mode_idx: int = clampi(_pending_mode_idx, 0, MODE_NAMES.size() - 1)
	if Net.is_host():
		var main := get_tree().current_scene
		if main != null and main.has_method("net_match_restart"):
			# call_local ensures the host also runs it locally.
			main.rpc("net_match_restart", map_idx, mode_idx)
		return
	# Singleplayer path — just apply and reload.
	Settings.map_index = map_idx
	Settings.custom_map_path = ""
	Settings.game_mode = mode_idx
	Settings.save()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


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


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 42)
	b.add_theme_font_size_override("font_size", 18)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	return b


func _pad(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	return c
