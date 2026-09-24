extends Control
## ObjectiveHud — everything the player needs to know about the objective:
##   • a status line under the score strip ("BLUE FLAG: HOME · RED FLAG: TAKEN
##     by Bot 3", DOM point chips, "YOU: BLUE")
##   • big announcement banners for grabs / drops / returns / captures
##   • off-screen edge arrows pointing at flags, carriers, DOM points and the
##     battle-royale safe zone, with distance
##   • a "RETURN TO THE ZONE" warning when outside the BR ring
## Pure _draw() + two labels; reads state straight from Main every frame so it
## works identically on host, clients and single-player.

var main: Node = null
var player_ref: Callable = Callable()   # returns the local player node
var _status: RichTextLabel
var _banner: Label
var _banner_tween: Tween = null
var _t := 0.0
const EDGE_PAD := 44.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status.offset_top = 112
	_status.offset_bottom = 136
	_status.add_theme_font_size_override("normal_font_size", 14)
	_status.add_theme_font_size_override("bold_font_size", 14)
	add_child(_status)
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 196
	_banner.offset_bottom = 236
	_banner.add_theme_font_size_override("font_size", 28)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 7)
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)


func _player() -> Node2D:
	if player_ref.is_valid():
		var p = player_ref.call()
		if p != null and is_instance_valid(p) and p is Node2D:
			return p
	return null


func _team_info(team: int) -> Dictionary:
	var hud := get_parent()
	if hud != null and hud.has_method("_team_display_info"):
		return hud._team_display_info(team)
	return {"name": "TEAM %d" % team, "color": Color.WHITE}


func _flag_name(team: int) -> String:
	if team == 0:
		return "THE FLAG"
	return "%s FLAG" % str(_team_info(team)["name"])


func _flag_color(team: int) -> Color:
	if team == 1:
		return Color(0.35, 0.6, 1.0)
	if team == 2:
		return Color(1.0, 0.35, 0.3)
	return Color(1.0, 0.85, 0.3)


# ── announcements ─────────────────────────────────────────────────────────

func announce(kind: String, team: int, who: String) -> void:
	var text := ""
	var col := Color(1, 1, 1)
	match kind:
		"grab":
			text = "%s TOOK %s" % [who.to_upper(), _flag_name(team)]
			col = _flag_color(team)
		"drop":
			text = "%s DROPPED" % _flag_name(team)
			col = _flag_color(team)
		"return":
			text = "%s RETURNED" % _flag_name(team)
			col = _flag_color(team)
		"capture":
			var info := _team_info(team)
			text = "%s SCORES!  (%s)" % [str(info["name"]), who]
			col = info["color"]
		"dom":
			var info2 := _team_info(team)
			text = "%s CAPTURED POINT %s" % [str(info2["name"]), who]
			col = info2["color"]
		_:
			return  # "point" pickups: sound + feed only
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.visible = true
	_banner.modulate.a = 1.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(2.2)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)
	_banner_tween.tween_callback(func() -> void: _banner.visible = false)


# ── per-frame status + markers ───────────────────────────────────────────

func _process(delta: float) -> void:
	_t += delta
	_status.text = "[center]" + _status_text() + "[/center]"
	queue_redraw()


func _carrier_of(f: Node) -> Node2D:
	if f == null or not is_instance_valid(f) or not f.has_meta("carrier"):
		return null
	var c: Variant = f.get_meta("carrier")
	if c == null or not is_instance_valid(c) or bool((c as Node).get("dead")):
		return null
	return c as Node2D


func _status_text() -> String:
	if main == null or not is_instance_valid(main):
		return ""
	var parts: PackedStringArray = PackedStringArray()
	var p := _player()
	if Settings.is_team_mode() and p != null:
		var mi := _team_info(int(p.get("team")))
		parts.append("[color=#%s]YOU: %s[/color]" % [(mi["color"] as Color).to_html(false), str(mi["name"])])
	var flags: Array = main.get("flags") if main.get("flags") != null else []
	for f in flags:
		if not is_instance_valid(f):
			continue
		var ft: int = int(f.get_meta("team")) if f.has_meta("team") else 0
		var c := _carrier_of(f)
		var state := ""
		if c != null:
			state = "YOU HAVE IT" if c == p else "TAKEN · %s" % str(c.get("display_name"))
		elif (f as Node2D).position.distance_to(f.get_meta("home")) <= 12.0:
			state = "HOME"
		else:
			state = "DROPPED"
		var hexc := _flag_color(ft).to_html(false)
		if c != null and c == p:
			var a := 0.6 + 0.4 * sin(_t * 6.0)
			hexc = Color(1, 1, 0.5, a).to_html(true)
		parts.append("[color=#%s][b]%s[/b]: %s[/color]" % [hexc, _flag_name(ft), state])
	if Settings.game_mode == Settings.MODE_DOM and main.has_method("dom_points"):
		var chips: PackedStringArray = PackedStringArray()
		for a in main.dom_points():
			if not is_instance_valid(a):
				continue
			var owner: int = int(a.get_meta("owner_team"))
			var col := Color(0.8, 0.8, 0.8) if owner == 0 else (_team_info(owner)["color"] as Color)
			var chip := str(a.get_meta("label"))
			var cap: int = int(a.get_meta("cap_team"))
			if cap != 0:
				chip += " %d%%" % int(float(a.get_meta("progress")) * 100.0)
			chips.append("[color=#%s][b]%s[/b][/color]" % [col.to_html(false), chip])
		parts.append("POINTS  " + "  ".join(chips))
	if Settings.game_mode == Settings.MODE_BR and main.has_method("br_zone") and p != null:
		var z: Dictionary = main.br_zone()
		var d: float = p.global_position.distance_to(z.get("center", p.global_position))
		var r: float = float(z.get("radius", 1e9))
		if d > r:
			var a2 := 0.55 + 0.45 * sin(_t * 8.0)
			parts.append("[color=#%s][b]RETURN TO THE ZONE — %d m[/b][/color]" % [Color(1, 0.3, 0.25, a2).to_html(true), int((d - r) / 16.0)])
	return "   ·   ".join(parts)


func _draw() -> void:
	if main == null or not is_instance_valid(main):
		return
	var targets: Array = []  # [world_pos, color, label]
	var p := _player()
	for f in (main.get("flags") if main.get("flags") != null else []):
		if not is_instance_valid(f):
			continue
		var c := _carrier_of(f)
		if c == p and p != null:
			# Carrying: point home instead (our own base = the other flag's home).
			for o in main.flags:
				if o != f and is_instance_valid(o) and int(o.get_meta("team")) == int(p.get("team")):
					targets.append([o.get_meta("home"), Color(0.5, 1.0, 0.5), "BASE"])
			if f.has_meta("capture_point"):
				targets.append([f.get_meta("capture_point"), Color(0.5, 1.0, 0.5), "BASE"])
			continue
		var ft: int = int(f.get_meta("team")) if f.has_meta("team") else 0
		var pos: Vector2 = (c.global_position if c != null else (f as Node2D).global_position)
		targets.append([pos + Vector2(0, -20), _flag_color(ft), "FLAG"])
	if Settings.game_mode == Settings.MODE_DOM and main.has_method("dom_points"):
		for a in main.dom_points():
			if not is_instance_valid(a):
				continue
			var owner: int = int(a.get_meta("owner_team"))
			var col := Color(0.85, 0.85, 0.85) if owner == 0 else (_team_info(owner)["color"] as Color)
			targets.append([a.global_position, col, str(a.get_meta("label"))])
	if Settings.game_mode == Settings.MODE_BR and main.has_method("br_zone") and p != null:
		var z: Dictionary = main.br_zone()
		if p.global_position.distance_to(z.get("center", p.global_position)) > float(z.get("radius", 1e9)):
			targets.append([z.get("center"), Color(1, 0.35, 0.3), "ZONE"])
	if targets.is_empty():
		return
	var xf := get_viewport().get_canvas_transform()
	var vr := get_viewport_rect()
	var inner := vr.grow(-EDGE_PAD)
	var center := vr.size * 0.5
	var font := get_theme_default_font()
	for tgt in targets:
		var sp: Vector2 = xf * (tgt[0] as Vector2)
		if vr.has_point(sp):
			continue
		# Clamp the direction from screen centre onto the inner rect.
		var dir: Vector2 = (sp - center)
		if dir.length() < 1.0:
			continue
		var sx: float = (inner.size.x * 0.5) / maxf(absf(dir.x), 0.001)
		var sy: float = (inner.size.y * 0.5) / maxf(absf(dir.y), 0.001)
		var k := minf(sx, sy)
		var at: Vector2 = center + dir * k
		var ang := dir.angle()
		var col: Color = tgt[1]
		var tip := at + Vector2.RIGHT.rotated(ang) * 14.0
		var l := at + Vector2(-8, -9).rotated(ang)
		var r := at + Vector2(-8, 9).rotated(ang)
		draw_colored_polygon(PackedVector2Array([tip, l, r]), col)
		draw_polyline(PackedVector2Array([tip, l, r, tip]), Color(0, 0, 0, 0.8), 1.5, true)
		if p != null and font != null:
			var dist_m := int(p.global_position.distance_to(tgt[0]) / 16.0)
			var txt := "%s %dm" % [str(tgt[2]), dist_m]
			var tpos := at - Vector2(Vector2.RIGHT.rotated(ang).x * 30.0 + 20.0, Vector2.RIGHT.rotated(ang).y * 22.0 - 4.0)
			draw_string_outline(font, tpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.9))
			draw_string(font, tpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
