extends Control
## Hold-to-show scoreboard (Tab / pad Back), also shown on the round-end
## screen. Per-soldier kills / deaths / captures from main.player_stats,
## grouped by team in team modes, one ranked list in free-for-all.

var hud: Node = null
var main: Node = null
var _team_of: Dictionary = {}   # name -> last seen team (bodies vanish while dead)
var _force_t := 0.0             # touch: tap the score strip to peek for a few s

const ROW_H := 24.0
const W := 620.0


func _ready() -> void:
	z_index = 20   # above objective banners / kill feed
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# Touch screens have no Tab key: tapping the score strip at the top peeks.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		var vp := get_viewport_rect().size
		var p: Vector2 = event.position
		if absf(p.x - vp.x * 0.5) < 260.0 and p.y < 140.0:
			peek(4.0)


func peek(secs: float = 4.0) -> void:
	_force_t = secs


func _process(delta: float) -> void:
	_force_t = maxf(0.0, _force_t - delta)
	if main == null or not is_instance_valid(main):
		visible = false
		return
	for s in get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(s):
			_team_of[str(s.get("display_name"))] = int(s.get("team"))
	var round_over: bool = main.get("round_active") == false
	var want: bool = _force_t > 0.0 or round_over \
			or (InputMap.has_action("scoreboard") and Input.is_action_pressed("scoreboard"))
	visible = want
	if want:
		queue_redraw()


func _rows() -> Array:
	var stats: Dictionary = main.get("player_stats") if main.get("player_stats") != null else {}
	var names := {}
	for n in _team_of.keys():
		names[n] = true
	for n in stats.keys():
		names[n] = true
	var out: Array = []
	for n in names.keys():
		var st: Dictionary = stats.get(n, {"k": 0, "d": 0, "c": 0})
		var k := int(st.get("k", 0))
		var d := int(st.get("d", 0))
		var c := int(st.get("c", 0))
		out.append({"name": str(n), "team": int(_team_of.get(n, 0)), "k": k, "d": d, "c": c, "score": k + 3 * c})
	out.sort_custom(func(a, b) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["d"] < b["d"])
	return out


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var rows := _rows()
	var team_mode: bool = Settings.is_team_mode()
	var show_caps: bool = Settings.game_mode in [Settings.MODE_CTF, Settings.MODE_INF, Settings.MODE_PM]
	var groups: Array = []
	if team_mode:
		for t in [1, 2]:
			var g: Array = rows.filter(func(r) -> bool: return r["team"] == t)
			groups.append([t, g])
	else:
		groups.append([-1, rows])
	var n_lines := 0
	for g in groups:
		n_lines += (g[1] as Array).size() + 1
	n_lines += groups.size() - 1
	var h := 52.0 + n_lines * ROW_H + 12.0
	var vp := get_viewport_rect().size
	var x0 := (vp.x - W) * 0.5
	var y0 := maxf(150.0, (vp.y - h) * 0.45)
	if main.get("round_active") == false:
		y0 = maxf(y0, vp.y * 0.5 + 70.0)   # below the winner banner
	draw_rect(Rect2(x0, y0, W, h), Color(0.04, 0.05, 0.08, 0.86))
	draw_rect(Rect2(x0, y0, W, h), Color(0.98, 0.66, 0.18, 0.7), false, 2.0)
	_text(font, Vector2(x0 + 18, y0 + 30), "SCOREBOARD", 20, Color(0.98, 0.66, 0.18))
	var me := ""
	var p = main.get("player")
	if p != null and is_instance_valid(p):
		me = str(p.get("display_name"))
	var y := y0 + 58.0
	var cols := [W - 200.0, W - 140.0, W - 80.0]
	for g in groups:
		var t: int = g[0]
		var list: Array = g[1]
		var head_col := Color(0.8, 0.82, 0.88)
		var title := "PLAYERS"
		if t > 0 and hud != null and hud.has_method("_team_display_info"):
			var info: Dictionary = hud._team_display_info(t)
			head_col = info["color"]
			var sc: Variant = (main.get("scores") as Dictionary).get(t, 0) if main.get("scores") != null else 0
			title = "%s   %s" % [str(info["name"]), str(sc)]
		_text(font, Vector2(x0 + 18, y), title, 16, head_col)
		_text(font, Vector2(x0 + cols[0], y), "K", 14, Color(0.7, 0.72, 0.8))
		_text(font, Vector2(x0 + cols[1], y), "D", 14, Color(0.7, 0.72, 0.8))
		if show_caps:
			_text(font, Vector2(x0 + cols[2], y), "CAPS", 14, Color(0.7, 0.72, 0.8))
		draw_line(Vector2(x0 + 14, y + 6), Vector2(x0 + W - 14, y + 6), Color(head_col, 0.5), 1.0)
		y += ROW_H
		for r in list:
			var col := Color(0.92, 0.93, 0.96)
			if not team_mode and hud != null and hud.has_method("_team_display_info"):
				col = (hud._team_display_info(int(r["team"]))["color"] as Color).lerp(Color.WHITE, 0.3)
			if str(r["name"]) == me:
				draw_rect(Rect2(x0 + 10, y - ROW_H + 7, W - 20, ROW_H), Color(1, 1, 1, 0.08))
				col = Color(1.0, 0.9, 0.5)
			_text(font, Vector2(x0 + 24, y), str(r["name"]).left(26), 15, col)
			_text(font, Vector2(x0 + cols[0], y), str(r["k"]), 15, col)
			_text(font, Vector2(x0 + cols[1], y), str(r["d"]), 15, col)
			if show_caps:
				_text(font, Vector2(x0 + cols[2], y), str(r["c"]), 15, col)
			y += ROW_H
		y += ROW_H


func _text(font: Font, at: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
