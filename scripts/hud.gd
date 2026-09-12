extends CanvasLayer
## HUD — health, fuel, ammo, weapon, grenades, kill feed.

var player: Node2D
var map_name := ""
var lbl_health: Label
var lbl_fuel: Label
var lbl_ammo: Label
var lbl_weapon: Label
var lbl_grenades: Label
var lbl_map: Label
var lbl_status: Label
var feed: VBoxContainer

const FEED_MAX := 5
const FEED_TTL := 4.0

var _feed_entries: Array = []


func _ready() -> void:
	lbl_health = _make_label(Vector2(14, 10), Color(1.0, 0.35, 0.35))
	lbl_fuel = _make_label(Vector2(14, 34), Color(0.4, 0.8, 1.0))
	lbl_ammo = _make_label(Vector2(14, 58), Color(1, 1, 1))
	lbl_weapon = _make_label(Vector2(14, 82), Color(0.9, 0.85, 0.6))
	lbl_grenades = _make_label(Vector2(14, 106), Color(0.6, 1.0, 0.6))
	feed = VBoxContainer.new()
	feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	feed.position = Vector2(-320, 10)
	feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.add_theme_constant_override("separation", 3)
	add_child(feed)
	lbl_map = Label.new()
	lbl_map.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_map.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_map.offset_top = 8
	lbl_map.offset_bottom = 30
	lbl_map.add_theme_font_size_override("font_size", 16)
	lbl_map.add_theme_color_override("font_color", Color(0.75, 0.78, 0.88))
	lbl_map.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl_map.add_theme_constant_override("outline_size", 3)
	add_child(lbl_map)
	lbl_status = Label.new()
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_status.offset_top = 30
	lbl_status.offset_bottom = 52
	lbl_status.add_theme_font_size_override("font_size", 13)
	lbl_status.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	lbl_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl_status.add_theme_constant_override("outline_size", 3)
	add_child(lbl_status)


func _make_label(pos: Vector2, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func _on_kill(killer_name: String, victim_name: String, weapon_name: String, killer_team: int) -> void:
	var kcol := Color(0.45, 0.95, 0.45) if killer_team == 0 else Color(1.0, 0.45, 0.45)
	var lbl := Label.new()
	lbl.text = "%s  [%s]  %s" % [killer_name, weapon_name, victim_name]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", kcol)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	feed.add_child(lbl)
	feed.move_child(lbl, 0)
	_feed_entries.push_front(lbl)
	while _feed_entries.size() > FEED_MAX:
		var old: Label = _feed_entries.pop_back()
		if is_instance_valid(old):
			old.queue_free()
	get_tree().create_timer(FEED_TTL).timeout.connect(func() -> void:
		_feed_entries.erase(lbl)
		if is_instance_valid(lbl):
			lbl.queue_free()
	)


func _process(_delta: float) -> void:
	lbl_map.text = map_name
	lbl_status.text = Net.status if Net.is_networked() else ""
	if not is_instance_valid(player):
		return
	lbl_health.text = "HP  %d" % int(player.health)
	lbl_fuel.text = "FUEL %d%%" % int(player.fuel)
	var w = player.weapons[player.weapon_index]
	var mag: int = player.ammo[player.weapon_index]
	lbl_ammo.text = "%d / %d" % [mag, int(w["mag"])] + ("  · RELOADING" if player.reloading else "")
	lbl_weapon.text = str(w["name"])
	lbl_grenades.text = "GRENADES %d" % player.grenades
