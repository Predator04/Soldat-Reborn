extends "res://scripts/timed_feed.gd"
## Kill feed (top right): Soldat-style "killer · weapon icon · victim" rows plus
## plain text lines for objective events and streak enders. Newest on top, five
## lines, four seconds each (timed_feed.gd).

const KILL_ICON_DIR := "res://assets/interface-gfx/guns/"
const KILL_ICONS := {
	"Minigun": "0", "Deagles": "1", "MP5": "2", "AK-74": "3", "Steyr AUG": "4",
	"Spas-12": "5", "Ruger 77": "6", "M79": "7", "Barrett": "8", "Minimi": "9",
	"USSOCOM": "10", "Knife": "knife", "Chainsaw": "chainsaw", "LAW": "law",
	"Flamethrower": "flamer", "Rambo Bow": "bow", "M2": "m2", "Fist": "fist",
}
var _kill_icon_cache: Dictionary = {}
const _UITheme = preload("res://scripts/ui_theme.gd")


func _init() -> void:
	max_lines = 5
	line_ttl = 4.0
	newest_first = true
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Offsets (not position) after the anchor preset: the old position=(-320,10)
	# landed the feed over the centre score strip.
	offset_left = -14
	offset_right = -14
	offset_top = 24
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 3)


## Kill-feed icons, loaded with the HUD instead of on the first kill.
func warm_icons() -> void:
	for w in KILL_ICONS.keys() + ["Grenade", "Cluster"]:
		kill_icon(str(w))


func kill_icon(weapon: String) -> Texture2D:
	var w := weapon.replace(" (headshot)", "")
	if _kill_icon_cache.has(w):
		return _kill_icon_cache[w]
	var path := ""
	if KILL_ICONS.has(w):
		path = KILL_ICON_DIR + str(KILL_ICONS[w]) + ".png"
	elif w == "Grenade":
		path = "res://assets/interface-gfx/nade.png"
	elif w == "Cluster":
		path = "res://assets/interface-gfx/cluster-nade.png"
	var tex: Texture2D = load(path) if path != "" and ResourceLoader.exists(path) else null
	_kill_icon_cache[w] = tex
	return tex


## Soldat-style row on a dark pill: killer · weapon icon · victim, with a
## crosshair marker for headshots (text fallback for weapons without an icon,
## e.g. the BR zone). kcol = the killer's team colour; `mine` (you killed or
## died) gets an ember edge (#272).
func add_kill(killer_name: String, victim_name: String, weapon_name: String, kcol: Color, mine := false, vcol := Color(0.9, 0.9, 0.92)) -> void:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_theme_stylebox_override("panel", _UITheme.hud_pill_style(_UITheme.COL_ACCENT if mine else Color(0, 0, 0, 0), 0.62 if mine else 0.5))
	var lbl := HBoxContainer.new()
	lbl.alignment = BoxContainer.ALIGNMENT_END
	lbl.add_theme_constant_override("separation", 7)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	var tex := kill_icon(weapon_name)
	var headshot := weapon_name.ends_with("(headshot)")
	var parts: Array = [killer_name, "", victim_name]
	for i in 3:
		if i == 1 and tex != null:
			var ic := TextureRect.new()
			ic.texture = tex
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.custom_minimum_size = Vector2(maxf(18.0, 18.0 * float(tex.get_width()) / maxf(1.0, float(tex.get_height()))), 18)
			ic.modulate = Color(0.95, 0.96, 0.98, 0.95)
			lbl.add_child(ic)
			if headshot:
				var hs := TextureRect.new()
				hs.texture = _UITheme.icon_texture("headshot", 16, _UITheme.COL_ALERT)
				hs.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				hs.custom_minimum_size = Vector2(16, 18)
				hs.tooltip_text = "headshot"
				lbl.add_child(hs)
			continue
		var t := Label.new()
		t.text = parts[i] if i != 1 else "[%s]" % weapon_name
		t.add_theme_font_override("font", _UITheme.font("semi"))
		t.add_theme_font_size_override("font_size", 15)
		t.add_theme_color_override("font_color", kcol if i == 0 else (vcol if i == 2 else _UITheme.COL_TEXT_DIM))
		t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		t.add_theme_constant_override("outline_size", 2)
		lbl.add_child(t)
	push_line(row)


## A plain text line (objective events, streak enders) in the same lane.
func add_text(txt: String, col: Color) -> void:
	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_override("font", _UITheme.font("semi"))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_stylebox_override("normal", _UITheme.hud_pill_style(Color(col, 0.8), 0.42))
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	push_line(lbl)
