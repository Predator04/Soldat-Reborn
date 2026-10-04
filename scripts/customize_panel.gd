extends PanelContainer
## CUSTOMIZE (main menu): pick your soldier's look and weapon skin from the
## catalog in customization.gd, with a live preview. Locked items show what
## unlocks them. Settings > Cosmetics reuses build_rows().

signal closed

const Custom := preload("res://scripts/customization.gd")
const SoldierArt := preload("res://scripts/soldier_art.gd")
const PlayerScript := preload("res://scripts/player.gd")

var _preview: Node2D
var _team := 1
var _focus_btn: Control = null
var _rows_box: VBoxContainer


class Preview extends Node2D:
	var team_color := Color(0.35, 0.55, 1.0)
	var weapon := "AK-74"
	var t := 0.0

	func _process(d: float) -> void:
		t += d
		queue_redraw()

	func _draw() -> void:
		var aim := Vector2(1.0, -0.12 + 0.12 * sin(t * 0.8)).normalized()
		SoldierArt.draw_soldier(self, team_color, 1.0, aim, Vector2.ZERO, false, false, Color.WHITE, "bullet",
			0.0, 100.0, 0.0, false, weapon, true, false, false, false, false, "", false, false,
			PlayerScript.my_cosmetics(), "USSOCOM", 3, false, false, false)


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style())
	set_anchors_preset(Control.PRESET_CENTER, true)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	box.add_child(UITheme.make_screen_title("CUSTOMIZE"))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	box.add_child(hb)

	# Left: live preview + team switch + level line.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(230, 270)
	stage.clip_contents = true
	left.add_child(stage)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(bg)
	_preview = Preview.new()
	_preview.position = Vector2(112, 235)
	_preview.scale = Vector2(6.5, 6.5)
	_preview.weapon = _spawn_weapon_name()
	stage.add_child(_preview)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 6)
	left.add_child(teams)
	for t in [[1, "BLUE", Color(0.35, 0.55, 1.0)], [2, "RED", preload("res://scripts/team_colors.gd").red()]]:
		var b := UITheme.make_small_button(t[1], 110, 32)
		var col: Color = t[2]
		b.pressed.connect(func() -> void: _preview.team_color = col)
		teams.add_child(b)
	var lvl := Label.new()
	var lp: Array = Stats.level_progress()
	lvl.text = tr("Career level %d  ·  %d / %d XP to the next") % [Stats.level_for(Stats.xp()), lp[0], lp[1]]
	lvl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_body(lvl, 13, UITheme.COL_TEXT_DIM)
	left.add_child(lvl)
	var note := Label.new()
	note.text = tr("Level up and earn achievements to unlock more. Everyone online sees your look.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_body(note, 13, UITheme.COL_TEXT_MUTED)
	left.add_child(note)

	# Right: the option rows.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows_box)
	build_rows(_rows_box)

	var back := UITheme.make_button("BACK")
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	box.add_child(back)
	_focus_btn = back


func refresh_data() -> void:
	for c in _rows_box.get_children():
		c.queue_free()
	build_rows(_rows_box)
	_preview.weapon = _spawn_weapon_name()
	UITheme.safe_grab_focus_deferred(_focus_btn)


static func _spawn_weapon_name() -> String:
	var tmp = PlayerScript.new()
	var ws: Array = tmp.weapons
	var nm := "AK-74"
	if Settings.spawn_primary >= 0 and Settings.spawn_primary < ws.size():
		nm = str(ws[Settings.spawn_primary]["name"])
	tmp.free()
	return nm


static func cos_get(kind: String) -> String:
	match kind:
		"skin": return Settings.cos_skin
		"head": return Settings.cos_head
		"finish": return Settings.cos_finish
		"vest": return "on" if Settings.cos_vest else "off"
		"vfinish": return Settings.cos_vfinish
		"pants": return Settings.cos_pants
		"chain": return Settings.cos_chain
		"wskin": return Settings.cos_wskin
	return ""


static func cos_set(kind: String, v: String) -> void:
	match kind:
		"skin": Settings.cos_skin = v
		"head": Settings.cos_head = v
		"finish": Settings.cos_finish = v
		"vest": Settings.cos_vest = v == "on"
		"vfinish": Settings.cos_vfinish = v
		"pants": Settings.cos_pants = v
		"chain": Settings.cos_chain = v
		"wskin": Settings.cos_wskin = v
	Settings.save()


## One row per customization slot. Locked options are greyed out and say
## what unlocks them.
static func build_rows(box: VBoxContainer) -> void:
	for row in Custom.ROWS:
		var kind: String = row[0]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var lbl := Label.new()
		lbl.text = TranslationServer.translate(row[1])
		lbl.custom_minimum_size = Vector2(130, 0)
		UITheme.style_body(lbl)
		h.add_child(lbl)
		if kind == "extras":
			var flow := HBoxContainer.new()
			flow.add_theme_constant_override("separation", 8)
			for ex in [["cigar", "Cigar"], ["dreadlocks", "Dreadlocks"], ["dogtag", "Dogtag"]]:
				var cb := CheckBox.new()
				cb.text = TranslationServer.translate(ex[1])
				cb.button_pressed = bool(Settings.get("cos_" + ex[0]))
				UITheme.style_checkbox(cb)
				var prop: String = "cos_" + ex[0]
				cb.toggled.connect(func(on: bool) -> void:
					Settings.set(prop, on)
					Settings.save())
				flow.add_child(cb)
			h.add_child(flow)
			box.add_child(h)
			continue
		var pick := OptionButton.new()
		var keys: Array = []
		for opt in row[2]:
			var key: String = opt[0]
			var nm: String = TranslationServer.translate(opt[1])
			var ok := Custom.is_unlocked(kind, key)
			pick.add_item(nm if ok else "%s  (%s)" % [nm, Custom.lock_text(kind, key)])
			pick.set_item_disabled(pick.item_count - 1, not ok)
			keys.append(key)
		var cur := cos_get(kind)
		var sel := keys.find(cur)
		if sel < 0 or not Custom.is_unlocked(kind, cur):
			sel = 0
		pick.selected = sel
		pick.custom_minimum_size = Vector2(240, 32)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_option_button(pick)
		pick.item_selected.connect(func(idx: int) -> void:
			if idx >= 0 and idx < keys.size():
				cos_set(kind, str(keys[idx])))
		h.add_child(pick)
		box.add_child(h)
