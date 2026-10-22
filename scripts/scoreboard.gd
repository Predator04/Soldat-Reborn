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
		var vp := size
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * (event.position as Vector2)
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


const UITheme = preload("res://scripts/ui_theme.gd")


func _draw() -> void:
	# #272 look: glass card, letter-spaced caps header, team bars, your row
	# marked with an ember edge. Drawn in this control's (UI-scaled) space.
	var font := UITheme.font("semi")
	var head_font := UITheme.font("caps")
	var num_font := UITheme.font("hud")
	var rows := _rows()
	var team_mode: bool = Settings.is_team_mode()
	var show_caps: bool = Settings.game_mode in [Settings.MODE_CTF, Settings.MODE_INF, Settings.MODE_PM, Settings.MODE_BOMB, Settings.MODE_ZOMBIE]
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
	var h := 58.0 + n_lines * ROW_H + 14.0
	var vp := size
	var x0 := roundf((vp.x - W) * 0.5)
	var y0 := maxf(150.0, (vp.y - h) * 0.45)
	if main.get("round_active") == false:
		y0 = maxf(y0, vp.y * 0.5 + 70.0)   # below the winner banner
	var card := UITheme.panel_style(Color(0.03, 0.04, 0.06, 0.9), UITheme.COL_BORDER_HI, UITheme.RADIUS_PANEL)
	draw_style_box(card, Rect2(x0, y0, W, h))
	_text(head_font, Vector2(x0 + 20, y0 + 32), tr("SCOREBOARD"), 18, UITheme.COL_TEXT)
	draw_rect(Rect2(x0 + 20, y0 + 40, 26, 2), UITheme.COL_ACCENT)
	var me := ""
	var p = main.get("player")
	if p != null and is_instance_valid(p):
		me = str(p.get("display_name"))
	var y := y0 + 66.0
	var cols := [W - 200.0, W - 140.0, W - 80.0]
	var online: bool = Net.is_networked()
	var pings: Dictionary = main.get("peer_pings") if main.get("peer_pings") != null else {}
	var dim := UITheme.COL_TEXT_MUTED
	for g in groups:
		var t: int = g[0]
		var list: Array = g[1]
		var head_col := UITheme.COL_TEXT_DIM
		var title := tr("PLAYERS")
		var sc_txt := ""
		if t > 0 and hud != null and hud.has_method("_team_display_info"):
			var info: Dictionary = hud._team_display_info(t)
			head_col = info["color"]
			var sc: Variant = (main.get("scores") as Dictionary).get(t, 0) if main.get("scores") != null else 0
			title = str(info["name"])
			sc_txt = str(sc)
		# Team header: colour bar, name, score.
		draw_rect(Rect2(x0 + 14, y - 15, 4, 19), head_col)
		_text(head_font, Vector2(x0 + 26, y), title, 15, head_col)
		if sc_txt != "":
			var tw: float = head_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			_text(num_font, Vector2(x0 + 36 + tw, y + 1), sc_txt, 20, UITheme.COL_TEXT)
		_text(head_font, Vector2(x0 + cols[0], y), "K", 13, dim)
		_text(head_font, Vector2(x0 + cols[1], y), "D", 13, dim)
		if show_caps:
			_text(head_font, Vector2(x0 + cols[2], y), "TURNS" if Settings.game_mode == Settings.MODE_ZOMBIE else "CAPS", 13, dim)
		if online:
			_text(head_font, Vector2(x0 + cols[0] - 80.0, y), "PING", 13, dim)
		draw_line(Vector2(x0 + 14, y + 7), Vector2(x0 + W - 14, y + 7), Color(head_col, 0.35), 1.0)
		y += ROW_H
		var odd := false
		for r in list:
			var col := UITheme.COL_TEXT
			if not team_mode and hud != null and hud.has_method("_team_display_info"):
				col = (hud._team_display_info(int(r["team"]))["color"] as Color).lerp(Color.WHITE, 0.3)
			if odd:
				draw_rect(Rect2(x0 + 12, y - ROW_H + 8, W - 24, ROW_H), UITheme.COL_PANEL_ROW)
			odd = not odd
			if str(r["name"]) == me:
				draw_rect(Rect2(x0 + 12, y - ROW_H + 8, W - 24, ROW_H), Color(UITheme.COL_ACCENT, 0.12))
				draw_rect(Rect2(x0 + 12, y - ROW_H + 8, 3, ROW_H), UITheme.COL_ACCENT)
				col = UITheme.COL_ACCENT_HI
			_text(font, Vector2(x0 + 26, y), str(r["name"]).left(20 if online else 26), 15, col)
			if online:
				var pg = pings.get(str(r["name"]), null)
				var ptxt := "BOT" if pg == null else ("HOST" if int(pg) == 0 else "%d" % int(pg))
				var pcol := Color(0.6, 0.62, 0.7) if pg == null or int(pg) == 0 else (Color(0.55, 0.95, 0.5) if int(pg) < 80 else (Color(0.95, 0.85, 0.4) if int(pg) < 160 else Color(0.95, 0.45, 0.35)))
				_text(num_font, Vector2(x0 + cols[0] - 80.0, y), ptxt, 15, pcol)
			_text(num_font, Vector2(x0 + cols[0], y), str(r["k"]), 17, col)
			_text(num_font, Vector2(x0 + cols[1], y), str(r["d"]), 17, col)
			if show_caps:
				_text(num_font, Vector2(x0 + cols[2], y), str(r["c"]), 17, col)
			y += ROW_H
		y += ROW_H


func _text(font: Font, at: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.6))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
