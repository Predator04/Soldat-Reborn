extends CanvasLayer
## HUD — health, fuel, ammo, weapon, grenades.

var player: Node2D
var lbl_health: Label
var lbl_fuel: Label
var lbl_ammo: Label
var lbl_weapon: Label
var lbl_grenades: Label


func _ready() -> void:
	lbl_health = _make_label(Vector2(14, 10), Color(1.0, 0.35, 0.35))
	lbl_fuel = _make_label(Vector2(14, 34), Color(0.4, 0.8, 1.0))
	lbl_ammo = _make_label(Vector2(14, 58), Color(1, 1, 1))
	lbl_weapon = _make_label(Vector2(14, 82), Color(0.9, 0.85, 0.6))
	lbl_grenades = _make_label(Vector2(14, 106), Color(0.6, 1.0, 0.6))


func _make_label(pos: Vector2, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	lbl_health.text = "HP  %d" % int(player.health)
	lbl_fuel.text = "FUEL %d%%" % int(player.fuel)
	var w = player.weapons[player.weapon_index]
	var mag: int = player.ammo[player.weapon_index]
	lbl_ammo.text = "%d / %d" % [mag, int(w["mag"])] + ("  · RELOADING" if player.reloading else "")
	lbl_weapon.text = str(w["name"])
	lbl_grenades.text = "GRENADES %d" % player.grenades
