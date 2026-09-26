extends Control
## WeaponMenu — Soldat-style limbo weapon panel on the HUD.
##
## Appears while you're dead (limbo), mirroring RenderWeaponMenuText / LimboMenu:
##   "Primary Weapon:"   → 10 primary rows (keys 1..0, click / tap)
##   "Secondary Weapon:" → 4 secondary rows (click / tap)
## The pick is what you respawn with (Settings.spawn_primary / spawn_secondary,
## saved). Hidden in Advance and Gun Game, where the mode decides the gun.
##
## Currently equipped row is drawn in Soldat's classic green (55,165,55).
## Hovering another row highlights it in a lighter green (85,105,55) and pops a
## tooltip with the weapon's damage/rate/mag/kind. Names + stats come straight
## from player.gd's `weapons` / `secondary` tables — no hardcoded lists.

# Reads the local player through our parent HUD each frame. Main.gd sets
# `hud.player` AFTER add_child, and it changes on respawn/scene reset — so caching
# it here would go stale.
var player: Node = null

const UITheme = preload("res://scripts/ui_theme.gd")

const PRIMARY_KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
var ROW_H := 16.0   # taller rows on touch screens (set in _ready)
const HDR_H := 20.0
const GAP := 8.0
const PANEL_W := 250.0
const PANEL_PAD := 8.0

# Selection colors stay green (Soldat-classic muscle memory for the equipped
# row); everything else pulls from the shared UITheme palette so hover/hdr/tip
# match the rest of the menus.
const COL_CURRENT := Color(55.0 / 255.0, 175.0 / 255.0, 55.0 / 255.0)
const COL_HOVER := Color(95.0 / 255.0, 115.0 / 255.0, 60.0 / 255.0)
const COL_HEADER := UITheme.COL_ACCENT
const COL_ROW := UITheme.COL_TEXT
const COL_ROW_KEY := UITheme.COL_TEXT_DIM
const COL_OUTLINE := UITheme.COL_SHADOW
const COL_TIP_BG := Color(0.05, 0.06, 0.09, 0.94)
const COL_TIP_BORDER := UITheme.COL_ACCENT_DIM
const COL_PANEL_BG := Color(0.03, 0.04, 0.06, 0.60)
const COL_PANEL_BORDER := Color(0.30, 0.34, 0.40, 0.55)

var _font: Font
var _font_size := 12
var _hdr_font_size := 13
var _hover_slot := -1  # 0..9 = primary index, 100..103 = secondary index+100, -1 = none

const PlayerScript = preload("res://scripts/player.gd")
var _weapons: Array = []
var _secondary: Array = []
var _keys_down: Dictionary = {}
const _KEY_ACTIONS := ["weapon_1", "weapon_2", "weapon_3", "weapon_4", "weapon_5",
	"weapon_6", "weapon_7", "weapon_8", "weapon_9", "weapon_10"]


func _ready() -> void:
	# Sit below the existing HP/fuel/ammo/weapon/grenades/rec stack (y ends ~155).
	# Keep the panel narrow so a 720p viewport still shows the tooltip to the right.
	position = Vector2(10, 168)
	size = Vector2(PANEL_W, 10)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	visible = false
	set_process(true)
	# Weapon tables straight from the soldier script (an unparented instance
	# never enters the tree, so _ready / physics never run).
	var tmp = PlayerScript.new()
	_weapons = (tmp.weapons as Array).duplicate(true)
	_secondary = (tmp.secondary as Array).duplicate(true)
	tmp.free()
	if OS.has_feature("android") or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() \
			or "--force-touch" in OS.get_cmdline_user_args():
		ROW_H = 26.0
		_font_size = 15
		position.x = 132.0   # clear of the left touch-button column
	# Cover the whole panel so clicks / taps on any row reach _gui_input.
	size = Vector2(PANEL_W, HDR_H + PRIMARY_KEYS.size() * ROW_H + GAP + HDR_H + _secondary.size() * ROW_H)
	# Touch overlay lets taps on this panel through instead of starting the
	# move stick (see touch_controls._on_touch).
	add_to_group("touch_passthrough")


func _process(_delta: float) -> void:
	# Pull the local player pointer off the parent HUD (may swap on respawn).
	var parent := get_parent()
	if parent != null and "player" in parent:
		var pp = parent.get("player")
		player = pp if is_instance_valid(pp) else null
	var alive: bool = player != null and not bool(player.get("dead"))
	var limbo: bool = parent != null and bool(parent.get("_dead")) and not alive \
			and not Settings.advance and Settings.game_mode != Settings.MODE_GG
	# Rising edge on the number keys (tracked here rather than
	# is_action_just_pressed, which misses presses injected mid-frame).
	for i in _KEY_ACTIONS.size():
		var a: String = _KEY_ACTIONS[i]
		var down: bool = i < _weapons.size() and InputMap.has_action(a) and Input.is_action_pressed(a)
		if limbo and down and not _keys_down.get(a, false):
			_pick(i)
		_keys_down[a] = down
	if not limbo:
		visible = false
		_hover_slot = -1
		return
	visible = true
	var new_slot := _slot_at(get_local_mouse_position())
	if new_slot != _hover_slot:
		_hover_slot = new_slot
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var press: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)
	if not press:
		return
	var slot := _slot_at(event.position)
	if slot >= 0:
		_pick(slot)
		accept_event()


## slot 0..9 = primary, 100+ = secondary. Takes effect on the next spawn.
func _pick(slot: int) -> void:
	if slot >= 100:
		Settings.spawn_secondary = clampi(slot - 100, 0, _secondary.size() - 1)
	else:
		Settings.spawn_primary = clampi(slot, 0, mini(PRIMARY_KEYS.size(), _weapons.size()) - 1)
	Settings.save()
	Sfx.ui()
	queue_redraw()


func _slot_at(local_pos: Vector2) -> int:
	var weapons: Array = _weapons
	var secondary: Array = _secondary
	if local_pos.x < 0.0 or local_pos.x > PANEL_W:
		return -1
	var y: float = 0.0
	# Primary header
	y += HDR_H
	for i in PRIMARY_KEYS.size():
		if i >= weapons.size():
			break
		var row_top: float = y
		y += ROW_H
		if local_pos.y >= row_top and local_pos.y < y:
			return i
	y += GAP
	# Secondary header
	y += HDR_H
	for j in secondary.size():
		var row_top2: float = y
		y += ROW_H
		if local_pos.y >= row_top2 and local_pos.y < y:
			return 100 + j
	return -1


func _draw() -> void:
	if not visible:
		return
	var weapons: Array = _weapons
	var secondary: Array = _secondary
	var wi: int = Settings.spawn_primary
	var si: int = Settings.spawn_secondary

	# Backing panel — tinted rect + hairline border so the limbo menu reads as
	# a discrete UI element instead of raw text over gameplay.
	var total_h: float = HDR_H + PRIMARY_KEYS.size() * ROW_H + GAP + HDR_H + secondary.size() * ROW_H + PANEL_PAD
	var bg_rect := Rect2(-PANEL_PAD, -PANEL_PAD, PANEL_W + PANEL_PAD * 2, total_h + PANEL_PAD)
	draw_rect(bg_rect, COL_PANEL_BG, true)
	draw_rect(bg_rect, COL_PANEL_BORDER, false, 1.0)
	# Amber left rule so it visually anchors with the HUD's accent color.
	draw_rect(Rect2(-PANEL_PAD, -PANEL_PAD, 2.0, total_h + PANEL_PAD), UITheme.COL_ACCENT, true)

	var y: float = 0.0
	_draw_header("Primary Weapon", y)
	y += HDR_H
	for i in PRIMARY_KEYS.size():
		if i >= weapons.size():
			break
		var w: Dictionary = weapons[i]
		var is_current: bool = wi == i
		var is_hover: bool = _hover_slot == i
		_draw_row(String(PRIMARY_KEYS[i]), str(w["name"]), y, is_current, is_hover)
		y += ROW_H
	y += GAP
	_draw_header("Secondary Weapon", y)
	y += HDR_H
	for j in secondary.size():
		var w2: Dictionary = secondary[j]
		var is_current2: bool = si == j
		var is_hover2: bool = _hover_slot == 100 + j
		_draw_row(str(j + 1), str(w2["name"]), y, is_current2, is_hover2)
		y += ROW_H

	# Tooltip — draw last so it always sits on top.
	if _hover_slot >= 0:
		var tip_w: Dictionary
		if _hover_slot >= 100:
			var idx2 := _hover_slot - 100
			if idx2 < secondary.size():
				tip_w = secondary[idx2]
		elif _hover_slot < weapons.size():
			tip_w = weapons[_hover_slot]
		if not tip_w.is_empty():
			_draw_tooltip(tip_w, get_local_mouse_position())


func _draw_header(text: String, y: float) -> void:
	# Uppercase amber header + a thin underline rule so section boundaries read
	# cleanly and match the section headers used in every menu.
	_draw_outlined_text(text.to_upper(), Vector2(4, y + _hdr_font_size), _hdr_font_size, COL_HEADER)
	draw_rect(Rect2(2, y + _hdr_font_size + 3, PANEL_W - 4, 1), UITheme.COL_ACCENT_DIM, true)


func _draw_row(key: String, name: String, y: float, is_current: bool, is_hover: bool) -> void:
	# Background chip for current / hovered rows. Slight bleed left so the panel edge reads.
	if is_current or is_hover:
		var bg := COL_CURRENT if is_current else COL_HOVER
		bg.a = 0.30
		draw_rect(Rect2(0, y + 1, PANEL_W, ROW_H - 1), bg, true)
		# Left accent bar in the solid color so the eye locks onto the picked row.
		var bar := COL_CURRENT if is_current else COL_HOVER
		draw_rect(Rect2(0, y + 1, 3, ROW_H - 1), bar, true)
	var name_col := COL_ROW
	if is_current:
		name_col = COL_CURRENT
	elif is_hover:
		name_col = COL_HOVER
	var text_y: float = y + (ROW_H + _font_size) * 0.5 - 1.0
	_draw_outlined_text(key + ".", Vector2(10, text_y), _font_size, COL_ROW_KEY)
	_draw_outlined_text(name, Vector2(28, text_y), _font_size, name_col)


func _draw_tooltip(w: Dictionary, near: Vector2) -> void:
	# Compose a short stats block from the weapon dict. Anchored to the right of
	# the panel by default so the cursor doesn't cover the row it's hovering.
	var kind := str(w.get("kind", "bullet"))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[ %s ]" % str(w["name"]))
	lines.append("kind: %s" % kind)
	lines.append("damage: %.0f" % float(w.get("damage", 0.0)))
	lines.append("fire rate: %.2fs" % float(w.get("rate", 0.0)))
	if int(w.get("mag", 0)) > 0:
		lines.append("mag: %d" % int(w.get("mag", 0)))
	if float(w.get("reload", 0.0)) > 0.0:
		lines.append("reload: %.2fs" % float(w.get("reload", 0.0)))
	if float(w.get("speed", 0.0)) > 0.0:
		lines.append("speed: %.0f" % float(w.get("speed", 0.0)))
	if float(w.get("spread", 0.0)) > 0.0:
		lines.append("spread: %.3f" % float(w.get("spread", 0.0)))
	if int(w.get("pellets", 1)) > 1:
		lines.append("pellets: %d" % int(w.get("pellets", 1)))
	if float(w.get("bink", 0.0)) > 0.0:
		lines.append("bink: %d" % int(w.get("bink", 0.0)))
	if float(w.get("startup", 0.0)) > 0.0:
		lines.append("startup: %.2fs" % float(w.get("startup", 0.0)))
	if float(w.get("range", 0.0)) > 0.0:
		lines.append("range: %.0f" % float(w.get("range", 0.0)))
	# Measure widest line so the tooltip box wraps cleanly.
	var pad := 8.0
	var line_h: float = float(_font_size) + 4.0
	var max_w: float = 0.0
	for line in lines:
		var sz: Vector2 = _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
		if sz.x > max_w:
			max_w = sz.x
	var box_w: float = max_w + pad * 2.0
	var box_h: float = float(lines.size()) * line_h + pad
	# Prefer showing the box to the right of the panel; if it would run off a
	# 720p viewport (viewport ~1280 wide, panel starts at x=10), fall back left.
	var vp_w: float = float(get_viewport_rect().size.x)
	var origin_x: float = PANEL_W + 8.0
	if position.x + origin_x + box_w > vp_w - 8.0:
		origin_x = -box_w - 8.0
	var origin_y: float = clampf(near.y - box_h * 0.5, 0.0, 720.0 - box_h - 8.0)
	var rect := Rect2(origin_x, origin_y, box_w, box_h)
	draw_rect(rect, COL_TIP_BG, true)
	draw_rect(rect, COL_TIP_BORDER, false, 1.0)
	var ty: float = origin_y + line_h - 2.0
	for i in lines.size():
		var col := COL_HEADER if i == 0 else COL_ROW
		_draw_outlined_text(String(lines[i]), Vector2(origin_x + pad, ty), _font_size, col)
		ty += line_h


func _draw_outlined_text(text: String, pos: Vector2, sz: int, col: Color) -> void:
	# Cheap 1px offset outline in 4 directions — matches the HUD label look without
	# needing a Label node per row (we'd blow past 30 nodes just for the panel).
	for dx in [-1, 1]:
		draw_string(_font, pos + Vector2(dx, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, COL_OUTLINE)
	for dy in [-1, 1]:
		draw_string(_font, pos + Vector2(0, dy), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, COL_OUTLINE)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
