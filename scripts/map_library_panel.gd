extends PanelContainer
## Map library (main menu): browse and download maps other players shared,
## and share your own editor maps. Backed by the master server's /maps API.

signal closed

const MapIO := preload("res://scripts/map_io.gd")

var _list: VBoxContainer
var _status: Label
var _search: LineEdit
var _sort: OptionButton
var _share_pick: OptionButton
var _share_paths: Array = []
var _http_list: HTTPRequest
var _http_get: HTTPRequest
var _http_up: HTTPRequest
var _pending_name := ""
var _pending_id := ""
var loaded_rows := -1      # for tests
var last_saved := ""       # for tests: path of the last downloaded map
var last_upload := {}      # for tests: last /maps/upload reply


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style())
	set_anchors_preset(Control.PRESET_CENTER, true)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(640, 0)
	add_child(box)
	box.add_child(UITheme.make_screen_title("MAP LIBRARY"))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	_search = LineEdit.new()
	_search.placeholder_text = tr("Search maps or authors")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(0, 34)
	UITheme.style_lineedit(_search)
	_search.text_submitted.connect(func(_t: String) -> void: refresh_data())
	top.add_child(_search)
	_sort = OptionButton.new()
	_sort.add_item(tr("Newest"))
	_sort.add_item(tr("Most downloaded"))
	UITheme.style_option_button(_sort)
	_sort.item_selected.connect(func(_i: int) -> void: refresh_data())
	top.add_child(_sort)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	box.add_child(UITheme.make_section_header("Share one of your maps"))
	var share_row := HBoxContainer.new()
	share_row.add_theme_constant_override("separation", 8)
	box.add_child(share_row)
	_share_pick = OptionButton.new()
	_share_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_option_button(_share_pick)
	share_row.add_child(_share_pick)
	var share := UITheme.make_small_button("SHARE", 120)
	share.pressed.connect(_on_share)
	share_row.add_child(share)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_body(_status, 14, UITheme.COL_INFO)
	box.add_child(_status)

	var back := UITheme.make_button("BACK")
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	box.add_child(back)

	for i in 3:
		var h := HTTPRequest.new()
		h.timeout = 15.0
		add_child(h)
		if i == 0:
			_http_list = h
		elif i == 1:
			_http_get = h
		else:
			_http_up = h
	_http_list.request_completed.connect(_on_list)
	_http_get.request_completed.connect(_on_got)
	_http_up.request_completed.connect(_on_uploaded)


func _base() -> String:
	return Settings.master_url.strip_edges().trim_suffix("/")


func refresh_data() -> void:
	_refresh_share_pick()
	loaded_rows = -1
	for c in _list.get_children():
		c.queue_free()
	_status.text = tr("Loading...")
	_http_list.cancel_request()
	var q := _search.text.strip_edges().uri_encode()
	_http_list.request("%s/maps?sort=%s&q=%s" % [_base(), "top" if _sort.selected == 1 else "new", q])


func _refresh_share_pick() -> void:
	_share_pick.clear()
	_share_paths.clear()
	for p in MapIO.list_files():
		var path := String(p)
		if path.ends_with("/_playtest.json"):
			continue
		_share_pick.add_item(path.get_file().get_basename())
		_share_paths.append(path)
	if _share_paths.is_empty():
		_share_pick.add_item(tr("(make a map in the Map Editor first)"))
		_share_pick.disabled = true
	else:
		_share_pick.disabled = false


func _on_list(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var d = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	if typeof(d) != TYPE_DICTIONARY:
		_status.text = tr("Couldn't reach the master server.")
		loaded_rows = 0
		return
	var maps: Array = d.get("maps", [])
	_status.text = "" if not maps.is_empty() else tr("No shared maps yet. Be the first: share one below.")
	for e in maps:
		_list.add_child(_row(e))
	loaded_rows = maps.size()


func _row(e: Dictionary) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.COL_PANEL_ROW))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)
	var lbl := Label.new()
	var modes := str(e.get("modes", "")).to_upper()
	lbl.text = "%s   %s %s   ·   %s%d %s" % [str(e.get("name", "?")), tr("by"), str(e.get("author", "")) if str(e.get("author", "")) != "" else "?",
		(modes + "  ·  ") if modes != "" else "", int(e.get("downloads", 0)), tr("downloads")]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	UITheme.style_body(lbl, 14)
	hb.add_child(lbl)
	var dl := UITheme.make_small_button("DOWNLOAD", 130, 30)
	var id := str(e.get("id", ""))
	var nm := str(e.get("name", "map"))
	dl.pressed.connect(func() -> void: download(id, nm))
	hb.add_child(dl)
	return pc


func download(id: String, nm: String) -> void:
	_pending_id = id
	_pending_name = nm
	_status.text = tr("Downloading %s...") % nm
	_http_get.cancel_request()
	_http_get.request("%s/maps/get?id=%s" % [_base(), id.uri_encode()])


func _on_got(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	var m: Dictionary = MapIO.json_to_map(text) if code == 200 else {}
	if m.is_empty() or (m.get("platforms", []) as Array).is_empty():
		_status.text = tr("That map couldn't be downloaded.")
		return
	MapIO.ensure_dir()
	var stem := MapIO.safe_filename(_pending_name)
	var path := MapIO.MAPS_DIR + stem + ".json"
	if FileAccess.file_exists(path):
		path = MapIO.MAPS_DIR + "%s_%s.json" % [stem, _pending_id.left(4)]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = tr("That map couldn't be downloaded.")
		return
	f.store_string(MapIO.map_to_json(m))
	f.close()
	last_saved = path
	_status.text = tr("Saved \"%s\". Pick it from the map list to play it or host it.") % _pending_name
	_refresh_share_pick()


func _on_share() -> void:
	var i := _share_pick.selected
	if i < 0 or i >= _share_paths.size():
		return
	share_file(String(_share_paths[i]))


func share_file(path: String) -> void:
	var m := MapIO.load_from_file(path)
	if m.is_empty() or (m.get("platforms", []) as Array).is_empty():
		_status.text = tr("That map is empty.")
		return
	var body := JSON.stringify({"name": path.get_file().get_basename(), "author": Settings.player_name,
		"map": JSON.parse_string(MapIO.map_to_json(m))})
	_status.text = tr("Uploading...")
	_http_up.cancel_request()
	_http_up.request(_base() + "/maps/upload", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)


func _on_uploaded(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var txt := body.get_string_from_utf8()
	var d = JSON.parse_string(txt)
	last_upload = d if typeof(d) == TYPE_DICTIONARY else {"error": txt}
	if code == 200 and typeof(d) == TYPE_DICTIONARY:
		_status.text = tr("Already in the library - thanks!") if bool(d.get("existing", false)) else tr("Shared! Everyone can download it now.")
		refresh_data()
	else:
		_status.text = tr("Upload failed: %s") % txt.strip_edges().left(80)
