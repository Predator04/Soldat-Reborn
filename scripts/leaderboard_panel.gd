extends PanelContainer
## Online leaderboard (main menu): top players on the official server and
## your own rank. Data comes from the master server (/leaderboard, /profile).

signal closed

var _focus_btn: Control = null

const TIERS := [[0, "Recruit"], [500, "Private"], [1500, "Corporal"], [4000, "Sergeant"],
	[10000, "Lieutenant"], [25000, "Captain"], [50000, "Major"], [100000, "Colonel"], [200000, "General"]]

var _me: RichTextLabel
var _list: RichTextLabel
var _http_board: HTTPRequest
var _http_me: HTTPRequest
var loaded_rows := -1    # for tests: rows shown after the last refresh


static func tier_for(xp: int) -> String:
	var t := "Recruit"
	for row in TIERS:
		if xp >= int(row[0]):
			t = str(row[1])
	return t


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style())
	set_anchors_preset(Control.PRESET_CENTER, true)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(620, 0)
	add_child(box)
	box.add_child(UITheme.make_screen_title("LEADERBOARD"))
	var note := Label.new()
	note.text = tr("Ranked on the official server: kill +10, capture +50, match +20, win +100.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_body(note, 13, UITheme.COL_TEXT_DIM)
	box.add_child(note)
	_me = _rtl(56)
	box.add_child(_me)
	box.add_child(UITheme.make_section_header("Top 50"))
	_list = _rtl(360)
	_list.scroll_active = true
	box.add_child(_list)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var refresh := UITheme.make_button("REFRESH")
	refresh.pressed.connect(refresh_data)
	row.add_child(refresh)
	var back := UITheme.make_button("BACK")
	_focus_btn = back
	back.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	row.add_child(back)
	_http_board = HTTPRequest.new()
	_http_board.timeout = 8.0
	add_child(_http_board)
	_http_board.request_completed.connect(_on_board)
	_http_me = HTTPRequest.new()
	_http_me.timeout = 8.0
	add_child(_http_me)
	_http_me.request_completed.connect(_on_me)


func _rtl(h: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.custom_minimum_size = Vector2(0, h)
	r.add_theme_font_size_override("normal_font_size", 15)
	r.add_theme_font_size_override("bold_font_size", 15)
	r.add_theme_color_override("default_color", UITheme.COL_TEXT)
	return r


func refresh_data() -> void:
	if _focus_btn != null:
		UITheme.safe_grab_focus_deferred(_focus_btn)   # gamepad / keyboard navigation
	var url := Settings.master_url.strip_edges().trim_suffix("/")
	_list.text = "[color=#a8b0bc]%s[/color]" % tr("Loading...")
	_me.text = ""
	loaded_rows = -1
	_http_board.cancel_request()
	_http_me.cancel_request()
	_http_board.request(url + "/leaderboard?n=50")
	_http_me.request(url + "/profile?id=" + Settings.profile_hash())


func _parse(code: int, body: PackedByteArray) -> Variant:
	if code != 200:
		return null
	return JSON.parse_string(body.get_string_from_utf8())


func _on_board(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var d = _parse(code, body)
	if typeof(d) != TYPE_DICTIONARY:
		_list.text = "[color=#f26b52]%s[/color]" % tr("Couldn't reach the master server.")
		loaded_rows = 0
		return
	var rows: Array = d.get("players", [])
	if rows.is_empty():
		_list.text = "[color=#a8b0bc]%s[/color]" % tr("No ranked players yet. Play on the official server to be the first!")
		loaded_rows = 0
		return
	var me_name := Settings.player_name
	var t := "[table=6]"
	for hdr in ["#", tr("Name"), "XP", tr("Rank"), "K/D", tr("Wins")]:
		t += "[cell][b][color=#f5a623]%s[/color][/b]   [/cell]" % hdr
	for row in rows:
		var nm := str(row.get("name", "?")).replace("[", "(").replace("]", ")")
		var k := int(row.get("k", 0))
		var de := maxi(1, int(row.get("d", 0)))
		var col := "#ffd257" if nm == me_name else "#e6edf5"
		t += "[cell]%d   [/cell][cell][color=%s]%s[/color]   [/cell][cell]%d   [/cell][cell]%s   [/cell][cell]%.2f   [/cell][cell]%d[/cell]" % [
			int(row.get("rank", 0)), col, nm, int(row.get("xp", 0)), tr(tier_for(int(row.get("xp", 0)))), float(k) / de, int(row.get("w", 0))]
	t += "[/table]"
	_list.text = t
	loaded_rows = rows.size()


func _on_me(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var d = _parse(code, body)
	if typeof(d) != TYPE_DICTIONARY:
		return
	if not bool(d.get("found", false)):
		_me.text = "[b]%s[/b]  ·  [color=#a8b0bc]%s[/color]" % [Settings.player_name.replace("[", "("), tr("Unranked - finish a round on the official server to get on the board.")]
		return
	var p: Dictionary = d.get("profile", {})
	var xp := int(p.get("xp", 0))
	_me.text = "[b][color=#ffd257]%s[/color][/b]  ·  %s  ·  #%d / %d  ·  %d XP\n[color=#a8b0bc]%d %s · %d %s · %d %s · %d %s[/color]" % [
		str(p.get("name", "")).replace("[", "("), tr(tier_for(xp)), int(d.get("rank", 0)), int(d.get("total", 0)), xp,
		int(p.get("k", 0)), tr("kills"), int(p.get("c", 0)), tr("caps"), int(p.get("w", 0)), tr("wins"), int(p.get("m", 0)), tr("matches")]
