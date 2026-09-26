extends Control
## Health / jet fuel / magazine bars beside the HUD readouts (top-left strip).
## Reads the local player every frame; the numbers stay in the labels.

var hud: Node = null
var _t := 0.0
const X0 := 98.0
const W := 100.0
const H := 9.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(220, 140)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if hud == null:
		return
	var p = hud.get("player")
	if p == null or not is_instance_valid(p) or bool(p.get("dead")):
		return
	var hp: float = clampf(float(p.get("health")) / 100.0, 0.0, 1.0)
	var hp_col := Color(0.35, 0.9, 0.45).lerp(Color(1.0, 0.25, 0.2), 1.0 - hp)
	if hp < 0.3:
		hp_col = hp_col.lerp(Color(1, 1, 1), 0.35 * (0.5 + 0.5 * sin(_t * 10.0)))
	_bar(Vector2(X0, 17), hp, hp_col)
	if not Settings.realistic:
		var fuel: float = clampf(float(p.get("fuel")) / 100.0, 0.0, 1.0)
		_bar(Vector2(X0, 41), fuel, Color(0.4, 0.75, 1.0) if fuel > 0.2 else Color(1.0, 0.6, 0.2))
		var w: Dictionary = {}
		var mag := 0
		if bool(p.get("using_secondary")):
			var si: int = int(p.get("secondary_index"))
			if si >= 0 and si < p.secondary.size() and si < p.secondary_ammo.size():
				w = p.secondary[si]
				mag = int(p.secondary_ammo[si])
		else:
			var wi: int = int(p.get("weapon_index"))
			if wi >= 0 and wi < p.weapons.size() and wi < p.ammo.size():
				w = p.weapons[wi]
				mag = int(p.ammo[wi])
		# Current gun icon beside its name (same icons as the kill feed).
		if not w.is_empty() and hud.has_method("_kill_icon") and Settings.game_mode != Settings.MODE_GG:
			var tex: Texture2D = hud._kill_icon(str(w.get("name", "")))
			if tex != null:
				var th := 20.0
				var tw := minf(W, th * float(tex.get_width()) / maxf(1.0, float(tex.get_height())))
				draw_texture_rect(tex, Rect2(Vector2(X0 + W - tw, 84), Vector2(tw, th)), false)
		if not w.is_empty() and int(w.get("mag", 0)) > 0:
			var frac := clampf(float(mag) / float(w["mag"]), 0.0, 1.0)
			var acol := Color(0.95, 0.85, 0.45)
			if bool(p.get("reloading")):
				acol = Color(0.7, 0.7, 0.75, 0.6 + 0.4 * sin(_t * 12.0))
			_bar(Vector2(X0, 65), frac, acol)


func _bar(at: Vector2, frac: float, col: Color) -> void:
	draw_rect(Rect2(at, Vector2(W, H)), Color(0, 0, 0, 0.55))
	if frac > 0.0:
		draw_rect(Rect2(at + Vector2(1, 1), Vector2((W - 2) * frac, H - 2)), col)
		draw_rect(Rect2(at + Vector2(1, 1), Vector2((W - 2) * frac, 2)), Color(1, 1, 1, 0.25))
	draw_rect(Rect2(at, Vector2(W, H)), Color(1, 1, 1, 0.18), false, 1.0)
