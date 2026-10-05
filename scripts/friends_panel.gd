extends PanelContainer
## FRIENDS (main menu): everyone you've played with online, newest first, with
## favourites (★) on top. Shows who's online right now (from the master
## server's game list) and joins their game in one click.

signal closed
signal join_requested(ip: String, port: int)

var _list: VBoxContainer
var _status: Label
var _http: HTTPRequest
var _servers: Array = []
var _focus_btn: Control = null
var rows_shown := -1     # for tests
var online_shown := 0    # for tests


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style())
	set_anchors_preset(Control.PRESET_CENTER, true)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(600, 0)
	add_child(box)
	box.add_child(UITheme.make_screen_title("FRIENDS"))
	var note := Label.new()
	note.text = tr("People you've played with online. Star the ones you want to keep; join them when they're playing.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_body(note, 13, UITheme.COL_TEXT_DIM)
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_status = Label.new()
	UITheme.style_body(_status, 13, UITheme.COL_INFO)
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var refresh := UITheme.make_button("REFRESH")
	refresh.pressed.connect(refresh_data)
	row.add_child(refresh)
	var back := UITheme.make_button("BACK")
	back.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	row.add_child(back)
	_focus_btn = back
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		var d = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
		_servers = d.get("servers", []) if typeof(d) == TYPE_DICTIONARY else []
		_status.text = "" if typeof(d) == TYPE_DICTIONARY else tr("Couldn't reach the master server.")
		_render())


func refresh_data() -> void:
	UITheme.safe_grab_focus_deferred(_focus_btn)
	_status.text = tr("Loading...")
	_render()
	_http.cancel_request()
	_http.request(Settings.master_url.strip_edges().trim_suffix("/") + "/list")


## Where a name is playing right now, or {}.
func where_is(nm: String) -> Dictionary:
	for s in _servers:
		if s is Dictionary and (s.get("names", []) as Array).has(nm):
			return s
	return {}


func _render() -> void:
	for c in _list.get_children():
		c.queue_free()
	var list: Array = Settings.recent_players.duplicate()
	# Online first, then favourites, then most recent.
	list.sort_custom(func(a, b):
		var ao := not where_is(str(a.get("name", ""))).is_empty()
		var bo := not where_is(str(b.get("name", ""))).is_empty()
		if ao != bo:
			return ao
		if bool(a.get("fav", false)) != bool(b.get("fav", false)):
			return bool(a.get("fav", false))
		return int(a.get("last", 0)) > int(b.get("last", 0)))
	online_shown = 0
	if list.is_empty():
		var l := Label.new()
		l.text = tr("No one yet. Play online (QUICK PLAY) and the people you meet show up here.")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UITheme.style_body(l, 14, UITheme.COL_TEXT_DIM)
		_list.add_child(l)
	for e in list:
		_list.add_child(_row(e))
	rows_shown = list.size()


func _ago(t: int) -> String:
	var d := int(Time.get_unix_time_from_system()) - t
	if d < 3600:
		return tr("%d min ago") % maxi(1, d / 60)
	if d < 86400:
		return tr("%d h ago") % (d / 3600)
	return tr("%d days ago") % (d / 86400)


func _row(e: Dictionary) -> Control:
	var nm := str(e.get("name", "?"))
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.COL_PANEL_ROW))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)
	var star := Button.new()
	star.text = "★" if bool(e.get("fav", false)) else "☆"
	star.flat = true
	star.tooltip_text = tr("Keep on the list")
	star.add_theme_font_size_override("font_size", 20)
	star.add_theme_color_override("font_color", UITheme.COL_ACCENT if bool(e.get("fav", false)) else UITheme.COL_TEXT_MUTED)
	star.pressed.connect(func() -> void:
		e["fav"] = not bool(e.get("fav", false))
		Settings.save()
		_render())
	hb.add_child(star)
	var lbl := Label.new()
	var srv := where_is(nm)
	if srv.is_empty():
		lbl.text = "%s   ·   %s" % [nm, _ago(int(e.get("last", 0)))]
		UITheme.style_body(lbl, 15, UITheme.COL_TEXT_DIM)
	else:
		online_shown += 1
		lbl.text = "%s   ·   %s" % [nm, tr("playing on %s (%s)") % [str(srv.get("name", "?")), str(srv.get("map", ""))]]
		UITheme.style_body(lbl, 15, UITheme.COL_GOOD)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	hb.add_child(lbl)
	if not srv.is_empty():
		var join := UITheme.make_small_button("JOIN", 110, 30)
		join.pressed.connect(func() -> void:
			var relay := str(srv.get("relay", ""))
			if relay != "":
				join_requested.emit(relay, 0)
			else:
				join_requested.emit(str(srv.get("ip", "")), int(srv.get("port", 0))))
		hb.add_child(join)
	return pc
