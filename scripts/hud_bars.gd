extends Control
## Vitals card (top left, graphics Phase C #272): glass card, clean vector
## icons (health / jet / ammo / grenade, UITheme.draw_icon), eased bars with a
## white damage ghost, a low-health pulse on the card edge, the current gun's
## icon and the magazine bar. hud.gd's labels draw the numbers on top.
## Reads the local player every frame; Realistic hides the jet + ammo rows.

const UITheme = preload("res://scripts/ui_theme.gd")
const CARD := Rect2(8, 8, 252, 120)
const BAR_X := 40.0
const BAR_W := 150.0
const BAR_H := 8.0

var hud: Node = null
var _t := 0.0
var _hp := -1.0         # displayed (eased) values, 0..1
var _ghost := -1.0
var _ghost_hold := 0.0
var _fuel := -1.0
var _mag := -1.0
# Reused styleboxes (no per-frame allocation).
var _card: StyleBoxFlat = UITheme.hud_strip_style()
var _card_border: Color = _card.border_color
var _sb_track: StyleBoxFlat = UITheme._flat(Color(1, 1, 1, 0.08), 3)
var _sb_ghost: StyleBoxFlat = UITheme._flat(Color(1, 1, 1, 0.55), 3)
var _sb_fill: StyleBoxFlat = UITheme._flat(Color.WHITE, 3)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(CARD.end.x + 8.0, CARD.end.y + 8.0)


func _player() -> Node:
	if hud == null:
		return null
	var p = hud.get("player")
	if p == null or not is_instance_valid(p) or bool(p.get("dead")):
		return null
	return p


func _process(delta: float) -> void:
	_t += delta
	var p := _player()
	if p != null:
		var hp: float = clampf(float(p.get("health")) / 100.0, 0.0, 1.0)
		if _hp < 0.0:
			_hp = hp
			_ghost = hp
		if hp < _hp - 0.001:
			# Took damage: the bar drops fast, the ghost holds then follows.
			_ghost = maxf(_ghost, _hp)
			_ghost_hold = 0.45
		_hp = lerpf(_hp, hp, 1.0 - exp(-delta * 16.0))
		_ghost_hold -= delta
		if _ghost_hold <= 0.0:
			_ghost = lerpf(_ghost, _hp, 1.0 - exp(-delta * 5.0))
		if _ghost < _hp:
			_ghost = _hp
		var fuel: float = clampf(float(p.get("fuel")) / 100.0, 0.0, 1.0)
		_fuel = fuel if _fuel < 0.0 else lerpf(_fuel, fuel, 1.0 - exp(-delta * 14.0))
	queue_redraw()


func _weapon(p: Node) -> Array:
	# [weapon dict, rounds in the magazine]
	if bool(p.get("using_secondary")):
		var si: int = int(p.get("secondary_index"))
		if si >= 0 and si < p.secondary.size() and si < p.secondary_ammo.size():
			return [p.secondary[si], int(p.secondary_ammo[si])]
	else:
		var wi: int = int(p.get("weapon_index"))
		if wi >= 0 and wi < p.weapons.size() and wi < p.ammo.size():
			return [p.weapons[wi], int(p.ammo[wi])]
	return [{}, 0]


func _draw() -> void:
	var p := _player()
	if p == null:
		return
	var low: bool = _hp < 0.3
	var pulse := 0.5 + 0.5 * sin(_t * 8.0)
	var card := _card
	card.border_color = Color(UITheme.COL_ALERT, 0.35 + 0.45 * pulse) if low else _card_border
	card.shadow_color = Color(UITheme.COL_ALERT, 0.18 * pulse)
	card.shadow_size = 10 if low else 0
	draw_style_box(card, CARD)
	var real: bool = Settings.realistic
	# Health
	var hp_col := UITheme.COL_HUD_HEALTH
	if _hp < 0.6:
		hp_col = Color(1.0, 0.72, 0.30)
	if low:
		hp_col = UITheme.COL_ALERT.lerp(Color(1, 0.75, 0.7), 0.35 * pulse)
	UITheme.draw_icon(self, "health", Vector2(24, 22), 14.0, hp_col)
	_bar(Vector2(BAR_X, 18), _hp, hp_col, _ghost)
	# Jet fuel
	if not real:
		var fcol := UITheme.COL_HUD_FUEL if _fuel > 0.2 else Color(1.0, 0.6, 0.2)
		UITheme.draw_icon(self, "jet", Vector2(24, 48), 14.0, fcol)
		_bar(Vector2(BAR_X, 44), _fuel, fcol, -1.0)
	# Divider
	draw_rect(Rect2(16, 64, CARD.size.x - 16, 1), UITheme.COL_BORDER)
	var wm: Array = _weapon(p)
	var w: Dictionary = wm[0]
	var mag: int = wm[1]
	# Current gun icon (same art as the kill feed), right-aligned on its row.
	if not w.is_empty() and hud.has_method("_kill_icon") and Settings.game_mode != Settings.MODE_GG:
		var tex: Texture2D = hud._kill_icon(str(w.get("name", "")))
		if tex != null:
			var th := 18.0
			var tw := minf(84.0, th * float(tex.get_width()) / maxf(1.0, float(tex.get_height())))
			draw_texture_rect(tex, Rect2(Vector2(CARD.end.x - 10.0 - tw, 69), Vector2(tw, th)), false, Color(1, 1, 1, 0.92))
	# Ammo + magazine bar
	if not real:
		var ac := UITheme.COL_HUD_AMMO
		if bool(p.get("reloading")):
			ac = Color(UITheme.COL_TEXT_DIM, 0.6 + 0.4 * sin(_t * 12.0))
		UITheme.draw_icon(self, "ammo", Vector2(24, 103), 15.0, ac)
		if not w.is_empty() and int(w.get("mag", 0)) > 0:
			var frac := clampf(float(mag) / float(w["mag"]), 0.0, 1.0)
			_mag = frac if _mag < 0.0 else lerpf(_mag, frac, 0.35)
			draw_rect(Rect2(40, 119, 104, 2), Color(1, 1, 1, 0.10))
			draw_rect(Rect2(40, 119, 104 * _mag, 2), ac)
	# Grenades
	UITheme.draw_icon(self, "grenade", Vector2(166, 104), 13.0, UITheme.COL_HUD_GRENADE)


func _bar(at: Vector2, frac: float, col: Color, ghost: float) -> void:
	var r := Rect2(at, Vector2(BAR_W, BAR_H))
	draw_style_box(_sb_track, r)
	if ghost > frac + 0.002:
		draw_style_box(_sb_ghost, Rect2(at, Vector2(BAR_W * clampf(ghost, 0.0, 1.0), BAR_H)))
	if frac > 0.005:
		var fill := Rect2(at, Vector2(maxf(BAR_H * 0.75, BAR_W * clampf(frac, 0.0, 1.0)), BAR_H))
		_sb_fill.bg_color = col
		draw_style_box(_sb_fill, fill)
		draw_rect(Rect2(fill.position + Vector2(2, 1), Vector2(fill.size.x - 4, 2)), Color(1, 1, 1, 0.22))
