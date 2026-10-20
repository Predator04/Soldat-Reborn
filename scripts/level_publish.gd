extends PanelContainer
## Map editor → level sharing (#288): the PUBLISH dialog (title prompt,
## filtered on the client too, upload, the share code to pass on) and the
## LEVELS browser as an overlay. attach() is the editor's whole hook: one
## call from map_editor.gd adds the two toolbar buttons; everything else
## lives here, so the editor itself stays untouched by level sharing.

const UITheme = preload("res://scripts/ui_theme.gd")
const LevelsApi = preload("res://scripts/levels_api.gd")
const LevelThumb = preload("res://scripts/level_thumb.gd")
const NameFilter = preload("res://scripts/name_filter.gd")
const MapIO = preload("res://scripts/map_io.gd")
const UIBack = preload("res://scripts/ui_back.gd")
const TITLE_MAX := 32

var editor: Node
var api: Node
var last_reply := {}   # for tests: the last upload reply ({error} on failure)
var _title: LineEdit
var _thumb: Control
var _modes: Label
var _status: Label
var _code: Label
var _publish: Button
var _copy: Button
var _open: Button
var _map_json: Dictionary = {}


## Adds PUBLISH + LEVELS to the editor toolbar `bar`; dialogs go on `ui`.
static func attach(ed: Node, bar: Control, ui: CanvasLayer) -> void:
	var pub := Button.new()
	pub.name = "PublishButton"
	pub.text = "Publish"
	pub.tooltip_text = "Share this map as a level: everyone can find, play and like it in LEVELS, and you get a code to give friends."
	pub.custom_minimum_size = Vector2(88, 32)
	pub.pressed.connect(func() -> void: open_publish(ed, ui))
	bar.add_child(pub)
	var lv := Button.new()
	lv.name = "LevelsButton"
	lv.text = "Levels"
	lv.tooltip_text = "Browse, play and like levels other players made."
	lv.custom_minimum_size = Vector2(88, 32)
	lv.pressed.connect(func() -> void: open_levels(ui, ed))
	bar.add_child(lv)


static func open_publish(ed: Node, ui: CanvasLayer) -> Node:
	var d: Node = ui.get_node_or_null("PublishDialog")
	if d == null:
		d = load("res://scripts/level_publish.gd").new()
		d.name = "PublishDialog"
		d.editor = ed
		ui.add_child(d)
	d.call("open")
	return d


static func open_levels(ui: CanvasLayer, ed: Node = null) -> Node:
	var p: Node = ui.get_node_or_null("LevelsBrowser")
	if p == null:
		p = load("res://scripts/levels_panel.gd").new()
		p.name = "LevelsBrowser"
		p.in_menu = false
		# FEATURED > EDIT A COPY (#295): open it right here, in Maker mode.
		var maker: Node = ed.get("_maker") if ed != null else null
		if maker != null:
			p.edit_hook = func(slug: String) -> void:
				ed.call("_set_maker", true)
				maker.call("start_from", slug)
		ui.add_child(p)
	p.call("open")
	return p


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style())
	set_anchors_preset(Control.PRESET_CENTER, true)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	api = LevelsApi.new()
	add_child(api)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(460, 0)
	add_child(col)
	col.add_child(UITheme.make_screen_title("PUBLISH LEVEL"))
	col.add_child(UITheme.make_rule())
	_thumb = LevelThumb.new()
	_thumb.custom_minimum_size = Vector2(0, 130)
	col.add_child(_thumb)
	_modes = Label.new()
	_modes.add_theme_font_override("font", UITheme.font("caps"))
	_modes.add_theme_font_size_override("font_size", 13)
	_modes.add_theme_color_override("font_color", UITheme.COL_ACCENT)
	col.add_child(_modes)
	var tl := Label.new()
	tl.text = "Title"
	UITheme.style_body(tl)
	col.add_child(tl)
	_title = LineEdit.new()
	_title.max_length = TITLE_MAX
	_title.custom_minimum_size = Vector2(0, 40)
	_title.placeholder_text = tr("A name players will search for")
	UITheme.style_lineedit(_title)
	_title.text_submitted.connect(func(_t: String) -> void: publish())
	col.add_child(_title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_body(_status, 14, UITheme.COL_INFO)
	col.add_child(_status)
	_code = Label.new()
	_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.add_theme_font_override("font", UITheme.font("caps"))
	_code.add_theme_font_size_override("font_size", 30)
	_code.add_theme_color_override("font_color", UITheme.COL_NEON)
	_code.visible = false
	col.add_child(_code)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var cancel := UITheme.make_small_button("CLOSE", 0, 42)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: visible = false)
	row.add_child(cancel)
	_copy = UITheme.make_small_button("COPY CODE", 0, 42)
	_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_copy.visible = false
	_copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_code.text)
		_status.text = tr("Code copied - paste it to a friend."))
	row.add_child(_copy)
	_open = UITheme.make_small_button("SEE IN LEVELS", 0, 42)
	_open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open.visible = false
	_open.pressed.connect(func() -> void:
		visible = false
		var ui := get_parent() as CanvasLayer
		if ui != null:
			var p: Node = open_levels(ui)
			p.call("set_tab", "bookmarks"))
	row.add_child(_open)
	_publish = UITheme.make_button("PUBLISH", true, 0, 42)
	_publish.name = "Publish"
	_publish.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_publish.pressed.connect(publish)
	row.add_child(_publish)
	# BACK / Esc = CLOSE, via the editor's dispatcher (scripts/ui_back.gd).
	UIBack.register(self, func() -> void: visible = false)


## The editor's current map as plain JSON (what gets uploaded).
func _editor_map() -> Dictionary:
	var m = editor.get("_map") if editor != null else null
	if not (m is Dictionary):
		return {}
	var d = JSON.parse_string(MapIO.map_to_json(m))
	return d if d is Dictionary else {}


func open() -> void:
	visible = true
	_map_json = _editor_map()
	var ne = editor.get("_name_edit") if editor != null else null
	var nm := str(ne.text) if ne is LineEdit else str(_map_json.get("name", ""))
	if nm.strip_edges() in ["", "my_map", "Untitled", "map"]:
		nm = ""
	_title.text = nm.strip_edges().left(TITLE_MAX)
	_thumb.call("set_thumb", LevelThumb.from_map(_map_json), "")
	var hints := LevelThumb.mode_hints(_map_json)
	_modes.text = tr("Built for: %s") % preload("res://scripts/levels_panel.gd").modes_text({"modes": hints})
	_code.visible = false
	_copy.visible = false
	_open.visible = false
	_publish.disabled = false
	_publish.visible = true
	_status.text = tr("Everyone will be able to find, play and like it. You get a code to share.")
	UITheme.safe_grab_focus_deferred(_title)


## Validates and uploads; `title` overrides the text box (tests).
func publish(title: String = "") -> void:
	if title != "":
		_title.text = title
	var t := _title.text.strip_edges()
	if _map_json.is_empty():
		_map_json = _editor_map()
	var ground := (_map_json.get("platforms", []) as Array).size() + ((_map_json.get("polys", []) as Array).size() if _map_json.get("polys") is Array else 0)
	if ground == 0:
		_status.text = tr("Add at least one platform first (or Generate).")
		return
	if t == "":
		_status.text = tr("Give your level a title first.")
		return
	if not NameFilter.is_clean(t):
		_status.text = tr("That title isn't allowed - please pick another.")
		last_reply = {"error": "filtered"}
		return
	_map_json["name"] = t
	var theme := ""
	var tt = load("res://scripts/gfx/terrain_theme.gd")
	if tt != null:
		theme = str(tt.theme_for(MapIO.json_to_map(JSON.stringify(_map_json))))
	_publish.disabled = true
	_status.text = tr("Publishing...")
	api.upload(t, Settings.display_name(), _map_json, theme, func(ok: bool, d: Dictionary, err: String) -> void:
		_publish.disabled = false
		last_reply = d if ok else {"error": err}
		if not ok:
			_status.text = err
			return
		var code := str(d.get("code", ""))
		_code.text = code
		_code.visible = code != ""
		_copy.visible = code != ""
		_open.visible = true
		_publish.visible = false
		_status.text = tr("Already published - here's its code again.") if bool(d.get("existing", false)) else tr("Published! Give friends this code, or find it in LEVELS.")
		# Your own level goes on your bookmarks so it's easy to find again.
		var id := str(d.get("id", ""))
		var known := false
		for b in Settings.level_bookmarks:
			known = known or str(b.get("id", "")) == id
		if id.length() == 16 and not known:
			Settings.level_bookmarks.push_front({"id": id, "code": code, "title": str(d.get("title", t)),
				"author": Settings.display_name(), "modes": str(d.get("modes", "")), "plays": 0, "likes": 0, "theme": theme})
			Settings.level_bookmarks = Settings.level_bookmarks.slice(0, Settings.LEVEL_BOOKMARKS_MAX)
			Settings.save())
