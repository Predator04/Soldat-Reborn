extends Control
## LEVELS browser (#288): Mario-Maker-style library of player-made levels on
## the master server (/levels API, scripts/levels_api.gd). Tabs Hot / New /
## Most played / Top liked / Bookmarked / Search, plus a course-code box;
## cards draw the level outline (level_thumb.gd); the detail panel has PLAY
## (bot match, sends the play report), HOST ONLINE (the menu's Host screen
## with the level picked — the same path every custom map uses), LIKE,
## BOOKMARK (stored in settings.cfg) and the share code.
## Opened from the main menu (menu.gd _open_levels) and from the map editor
## (level_publish.gd). Works offline: a friendly line, bookmarks still list,
## and levels played before (cached in user://levels/) still play.

signal closed
signal host_requested(path: String, title: String)   # menu: Host screen with this map
signal map_files_requested                             # menu: the classic map-file library

const UITheme = preload("res://scripts/ui_theme.gd")
const LevelsApi = preload("res://scripts/levels_api.gd")
const LevelThumb = preload("res://scripts/level_thumb.gd")
const MapIO = preload("res://scripts/map_io.gd")
const GameLists = preload("res://scripts/game_lists.gd")

const CACHE_DIR := "user://levels/"
const CARD_W := 236.0
const CARD_H := 196.0
const DETAIL_W := 340.0
const TABS := [
	["hot", "HOT"], ["new", "NEW"], ["plays", "MOST PLAYED"],
	["likes", "TOP LIKED"], ["bookmarks", "BOOKMARKED"], ["search", "SEARCH"],
]
## Mode hint key (server "modes") -> Settings mode index, in pick priority.
const MODE_KEYS := {"ctf": 2, "dom": 7, "htf": 4, "inf": 3, "rm": 5, "tdm": 1, "dm": 0}
const MODE_LABEL := {"dm": "DM", "tdm": "TDM", "ctf": "CTF", "inf": "INF", "htf": "HTF", "rm": "RM", "dom": "DOM"}

## Map editor -> menu hand-off for HOST ONLINE (the editor has no Host screen).
static var pending_host := ""
static var pending_host_title := ""

var play_hook: Callable          # menu: _go_to_match (LOADING overlay); else plain scene change
var gate: Callable               # menu: _with_name (online needs a name)
var in_menu := true              # false in the editor overlay (no MAP FILES link)

var tab := "hot"
var page := 0
var levels: Array = []           # dicts of the cards on screen
var selected: Dictionary = {}
var api: Node
# For tests / screenshots.
var loaded := -1                 # cards after the last load (-1 = loading)
var offline := false
var last_like := {}

var _frame: PanelContainer
var _tab_btns := {}
var _search_row: HBoxContainer
var _search: LineEdit
var _code: LineEdit
var _grid: GridContainer
var _scroll: ScrollContainer
var _empty: Label
var _status: Label
var _more: Button
var _cards := {}                 # id -> card Button
var _d_box: VBoxContainer
var _d_hint: Label
var _d_thumb: Control
var _d_title: Label
var _d_author: Label
var _d_code: Label
var _d_stats: Label
var _d_modes: Label
var _d_mode: OptionButton
var _d_mode_keys: Array = []
var _d_play: Button
var _d_host: Button
var _d_like: Button
var _d_mark: Button
var _d_status: Label
var _busy_play := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	api = LevelsApi.new()
	api.name = "LevelsApi"
	add_child(api)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6 if in_menu else 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_frame = PanelContainer.new()
	# Near-opaque: the menu's corner buttons mustn't show through the cards.
	_frame.add_theme_stylebox_override("panel", UITheme.panel_style(Color(UITheme.COL_PANEL, 0.97)))
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.offset_left = 28
	_frame.offset_right = -28
	_frame.offset_top = 18
	_frame.offset_bottom = -18
	add_child(_frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_frame.add_child(col)

	# Header: title + course code.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var tl := Label.new()
	tl.text = "LEVELS"
	UITheme.style_head(tl, UITheme.FS_H1)
	head.add_child(tl)
	var sub := Label.new()
	sub.text = "Play, like and share levels made by players"
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.clip_text = true
	UITheme.style_body(sub, UITheme.FS_CAPTION + 1, UITheme.COL_TEXT_DIM)
	head.add_child(sub)
	_code = LineEdit.new()
	_code.placeholder_text = tr("Course code")
	_code.max_length = 16
	_code.custom_minimum_size = Vector2(190, 40)
	UITheme.style_lineedit(_code)
	_code.text_submitted.connect(func(_t: String) -> void: open_code(_code.text))
	head.add_child(_code)
	var go := UITheme.make_small_button("FIND", 84, 40)
	go.tooltip_text = tr("Open the level with this share code (like 7KQ2-MX9P-4HDA).")
	go.pressed.connect(func() -> void: open_code(_code.text))
	head.add_child(go)
	col.add_child(UITheme.make_rule())

	# Tabs.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	for t in TABS:
		var b := UITheme.make_small_button(String(t[1]), 0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.name = "Tab_" + String(t[0])
		var key: String = t[0]
		b.pressed.connect(func() -> void: set_tab(key))
		tabs.add_child(b)
		_tab_btns[key] = b
	_search_row = HBoxContainer.new()
	_search_row.add_theme_constant_override("separation", 8)
	_search_row.visible = false
	col.add_child(_search_row)
	_search = LineEdit.new()
	_search.placeholder_text = tr("Title, author or course code")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(0, 40)
	UITheme.style_lineedit(_search)
	_search.text_submitted.connect(func(_t: String) -> void: refresh_data())
	_search_row.add_child(_search)
	var sb := UITheme.make_small_button("SEARCH", 120, 40)
	sb.pressed.connect(refresh_data)
	_search_row.add_child(sb)

	# Body: card grid | detail.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 12
	_scroll.follow_focus = true   # D-pad / keyboard through the cards
	body.add_child(_scroll)
	var grid_box := VBoxContainer.new()
	grid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_box.add_theme_constant_override("separation", 10)
	_scroll.add_child(grid_box)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	grid_box.add_child(_grid)
	_empty = Label.new()
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.custom_minimum_size = Vector2(0, 120)
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.style_body(_empty, UITheme.FS_BODY, UITheme.COL_TEXT_DIM)
	_empty.visible = false
	grid_box.add_child(_empty)
	_more = UITheme.make_small_button("MORE", 160, 40)
	_more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_more.visible = false
	_more.pressed.connect(func() -> void: _load(page + 1))
	grid_box.add_child(_more)
	_scroll.resized.connect(_fit_grid)

	# Footer.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.style_body(_status, 14, UITheme.COL_INFO)
	foot.add_child(_status)
	_d_status = _status   # detail messages use the footer line
	if in_menu:
		var files := Button.new()
		files.text = "MAP FILES"
		files.tooltip_text = tr("The classic map library: download map files to edit, or share a saved map.")
		UITheme.style_link(files, 14)
		files.pressed.connect(func() -> void:
			visible = false
			_release()
			map_files_requested.emit())
		foot.add_child(files)
	var back := UITheme.make_small_button("BACK", 150, 40)
	back.name = "Back"
	back.pressed.connect(close)
	foot.add_child(back)
	_build_detail(body)
	_style_tabs()
	visibility_changed.connect(func() -> void:
		if not visible:
			_release())


func _build_detail(body: HBoxContainer) -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.card_style())
	pc.custom_minimum_size = Vector2(DETAIL_W, 0)
	body.add_child(pc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(sc)
	_d_box = VBoxContainer.new()
	_d_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_box.add_theme_constant_override("separation", 6)
	sc.add_child(_d_box)
	_d_hint = Label.new()
	_d_hint.text = "Pick a level to see it here."
	_d_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_d_hint.custom_minimum_size = Vector2(0, 80)
	UITheme.style_body(_d_hint, UITheme.FS_BODY, UITheme.COL_TEXT_MUTED)
	_d_box.add_child(_d_hint)
	_d_thumb = LevelThumb.new()
	_d_thumb.custom_minimum_size = Vector2(0, 112)
	_d_box.add_child(_d_thumb)
	_d_title = Label.new()
	_d_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_head(_d_title, UITheme.FS_H2 + 2)
	_d_box.add_child(_d_title)
	_d_author = Label.new()
	UITheme.style_body(_d_author, 14, UITheme.COL_TEXT_DIM)
	_d_box.add_child(_d_author)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	_d_box.add_child(code_row)
	_d_code = Label.new()
	_d_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_code.add_theme_font_override("font", UITheme.font("caps"))
	_d_code.add_theme_font_size_override("font_size", 20)
	_d_code.add_theme_color_override("font_color", UITheme.COL_NEON)
	_d_code.tooltip_text = tr("Share code: friends type it into the course code box.")
	_d_code.mouse_filter = Control.MOUSE_FILTER_PASS
	code_row.add_child(_d_code)
	var copy := UITheme.make_small_button("COPY", 84, 32)
	copy.pressed.connect(func() -> void:
		if not selected.is_empty():
			DisplayServer.clipboard_set(str(selected.get("code", "")))
			_d_status.text = tr("Code copied - paste it to a friend."))
	code_row.add_child(copy)
	_d_stats = Label.new()
	UITheme.style_body(_d_stats, 15)
	_d_box.add_child(_d_stats)
	_d_modes = Label.new()
	_d_modes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_modes.add_theme_font_override("font", UITheme.font("caps"))
	_d_modes.add_theme_font_size_override("font_size", 13)
	_d_modes.add_theme_color_override("font_color", UITheme.COL_ACCENT)
	_d_box.add_child(_d_modes)
	_d_mode = OptionButton.new()
	_d_mode.custom_minimum_size = Vector2(0, 38)
	_d_mode.tooltip_text = tr("Game mode for PLAY and HOST ONLINE. Listed: the modes this level was built for.")
	UITheme.style_option_button(_d_mode)
	_d_box.add_child(_d_mode)
	_d_play = UITheme.make_button("PLAY", true, 0, 44)
	_d_play.name = "Play"
	_d_play.tooltip_text = tr("A bot match on this level.")
	_d_play.pressed.connect(func() -> void: play_selected())
	_d_box.add_child(_d_play)
	_d_host = UITheme.make_small_button("HOST ONLINE", 0, 38)
	_d_host.tooltip_text = tr("Host a game on this level that friends can join.")
	_d_host.pressed.connect(func() -> void: host_selected())
	_d_box.add_child(_d_host)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_d_box.add_child(row)
	_d_like = UITheme.make_small_button("LIKE", 0, 38)
	_d_like.name = "Like"
	_d_like.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_like.pressed.connect(func() -> void: toggle_like())
	row.add_child(_d_like)
	_d_mark = UITheme.make_small_button("BOOKMARK", 0, 38)
	_d_mark.name = "Bookmark"
	_d_mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_mark.pressed.connect(func() -> void: toggle_bookmark())
	row.add_child(_d_mark)
	# LIKE / BOOKMARK sit right under the numbers they change.
	_d_box.move_child(row, _d_stats.get_index() + 1)
	_show_detail({})


# ── Open / close ───────────────────────────────────────────────────────────

func open(which: String = "") -> void:
	visible = true
	if which != "":
		tab = which
	_style_tabs()
	refresh_data()
	UITheme.safe_grab_focus_deferred(_tab_btns.get(tab))


func close() -> void:
	visible = false
	closed.emit()


## Hidden: drop the cards and the detail so a closed browser holds nothing
## (the node count stays flat however often it is opened).
func _release() -> void:
	api.cancel("list")
	api.cancel("get")
	api.cancel("code")
	_clear_cards()
	levels = []
	_show_detail({})


func _unhandled_input(event: InputEvent) -> void:
	# The editor overlay closes itself; the menu routes ESC / back via _go_back.
	if in_menu or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func set_tab(key: String) -> void:
	tab = key
	_style_tabs()
	if tab == "search":
		UITheme.safe_grab_focus_deferred(_search)
		if _search.text.strip_edges() == "":
			_clear_cards()
			_status.text = tr("Search by title, author or course code.")
			loaded = 0
			return
	refresh_data()


func _style_tabs() -> void:
	for k in _tab_btns:
		UITheme.style_button(_tab_btns[k], 16, k == tab)
	if _search_row != null:
		_search_row.visible = tab == "search"


# ── Lists ──────────────────────────────────────────────────────────────────

func refresh_data() -> void:
	_load(0)


func _load(p: int) -> void:
	page = p
	if p == 0:
		_clear_cards()
		levels = []
		_scroll.scroll_vertical = 0
	loaded = -1
	offline = false
	_more.visible = false
	_empty.visible = false
	_status.text = tr("Loading levels...")
	var ids: Array = []
	if tab == "bookmarks":
		for b in Settings.level_bookmarks:
			ids.append(str(b.get("id", "")))
		if ids.is_empty():
			_show_list([], false)
			_status.text = ""
			_set_empty(tr("No bookmarks yet. Open a level and press BOOKMARK to keep it here."))
			return
		# Cached copies first, so the tab works offline; fresh numbers follow.
		_show_list(Settings.level_bookmarks.duplicate(true), false)
		loaded = -1
	var sort := tab if tab in ["hot", "new", "plays", "likes"] else "hot"
	var q := _search.text if tab == "search" else ""
	api.list(sort, q, p, _on_list.bind(p), ids)


func _on_list(ok: bool, d: Dictionary, err: String, p: int) -> void:
	if not ok:
		offline = true
		_status.text = err
		if tab == "bookmarks":
			loaded = levels.size()
		else:
			_set_empty(tr("Can't load levels right now."))
			loaded = levels.size() if p > 0 else 0
		return
	var got: Array = d.get("levels", [])
	if tab == "bookmarks":
		_refresh_bookmark_meta(got)
		_clear_cards()
		levels = []
		_show_list(got, false)
	else:
		_show_list(got, p > 0)
	_more.visible = bool(d.get("more", false))
	_status.text = ""
	if levels.is_empty():
		if tab == "search":
			_set_empty(tr("Nothing found for \"%s\".") % _search.text.strip_edges())
		else:
			_set_empty(tr("No levels here yet. Build one in the Map Editor and press Publish!"))
	elif not selected.is_empty():
		# Keep the detail only if that level is on this tab.
		if _cards.has(str(selected.get("id", ""))):
			_mark_selected()
		else:
			_show_detail({})


func _show_list(list: Array, append: bool) -> void:
	if not append:
		_clear_cards()
		levels = []
	for e in list:
		if not (e is Dictionary) or _cards.has(str(e.get("id", ""))):
			continue
		levels.append(e)
		var c := _card(e)
		_grid.add_child(c)
		_cards[str(e.get("id", ""))] = c
	_fit_grid()
	_empty.visible = levels.is_empty()
	loaded = levels.size()


func _set_empty(t: String) -> void:
	_empty.text = t
	_empty.visible = levels.is_empty()


func _clear_cards() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cards.clear()


func _fit_grid() -> void:
	if _scroll == null or _grid == null:
		return
	var w := _scroll.size.x - 14.0   # room for the scroll bar
	var cols := clampi(int(floor((w + 10.0) / (CARD_W + 10.0))), 1, 5)
	if _grid.columns != cols:
		_grid.columns = cols
	# Cards stretch to fill the row (no dead strip on the right).
	var cw := floorf((w - 10.0 * (cols - 1)) / cols)
	for c in _grid.get_children():
		if absf((c as Control).custom_minimum_size.x - cw) > 0.5:
			(c as Control).custom_minimum_size.x = cw


## "CTF  ·  DOM" from the server's mode hints (DM / TDM left out when the
## level was built for more); `most` > 0 caps the tags ("CTF · INF · +2").
static func modes_text(e: Dictionary, sep := "  ·  ", most := 0) -> String:
	var keys := str(e.get("modes", "")).split(" ", false)
	var out: Array = []
	for k in ["ctf", "dom", "htf", "inf", "rm", "tdm", "dm"]:
		if k in keys and not (k in ["dm", "tdm"] and keys.size() > 2):
			out.append(MODE_LABEL[k])
	if most > 0 and out.size() > most:
		var extra := out.size() - (most - 1)
		out = out.slice(0, most - 1)
		out.append("+%d" % extra)
	return sep.join(PackedStringArray(out))


func _card(e: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CARD_W, CARD_H)
	b.mouse_filter = Control.MOUSE_FILTER_PASS   # touch: drags still scroll the grid
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = str(e.get("title", e.get("name", "")))
	UITheme.style_button(b, 14, false)
	_skin_card(b, false)
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 8)
	b.add_child(mc)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 3)
	mc.add_child(v)
	var th: Control = LevelThumb.new()
	th.custom_minimum_size = Vector2(0, 104)
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(th)
	th.call("set_thumb", _thumb_of(e), str(e.get("theme", "")))
	var t := Label.new()
	t.text = str(e.get("title", e.get("name", "?")))
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.add_theme_font_override("font", UITheme.font("head"))
	t.add_theme_font_size_override("font_size", 19)
	t.add_theme_color_override("font_color", UITheme.COL_TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var arow := HBoxContainer.new()
	arow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arow.add_theme_constant_override("separation", 6)
	v.add_child(arow)
	var a := Label.new()
	var au := str(e.get("author", ""))
	a.text = (tr("by %s") % au) if au != "" else tr("by an unknown builder")
	a.clip_text = true
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.style_body(a, 13, UITheme.COL_TEXT_DIM)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arow.add_child(a)
	var mo := Label.new()
	mo.text = modes_text(e, " · ", 3)
	mo.add_theme_font_override("font", UITheme.font("caps"))
	mo.add_theme_font_size_override("font_size", 12)
	mo.add_theme_color_override("font_color", UITheme.COL_ACCENT)
	mo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arow.add_child(mo)
	var st := Control.new()
	st.custom_minimum_size = Vector2(0, 20)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st.name = "Stats"
	st.set_meta("level", e)
	st.draw.connect(_draw_stats.bind(st))
	v.add_child(st)
	var id := str(e.get("id", ""))
	b.pressed.connect(func() -> void: select(id))
	return b


func _skin_card(b: Button, on: bool) -> void:
	var n := UITheme.panel_style(UITheme.COL_PANEL_HI, UITheme.COL_NEON if on else UITheme.COL_BORDER, UITheme.RADIUS_PANEL)
	n.shadow_size = 0
	n.set_border_width_all(2 if on else 1)
	var h := n.duplicate() as StyleBoxFlat
	h.border_color = UITheme.COL_NEON if on else UITheme.COL_BORDER_HI
	h.bg_color = UITheme.COL_PANEL_HI.lightened(0.06)
	for k in ["normal", "pressed", "disabled"]:
		b.add_theme_stylebox_override(k, n)
	for k in ["hover", "hover_pressed"]:
		b.add_theme_stylebox_override(k, h)


# Card footer: plays + likes with small vector icons (+ a ribbon if bookmarked).
func _draw_stats(st: Control) -> void:
	var e: Dictionary = st.get_meta("level", {})
	var f := UITheme.font("semi")
	var fs := 14
	var y := st.size.y * 0.5
	var x := 2.0
	var dim := UITheme.COL_TEXT_DIM
	# Play triangle.
	st.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 5), Vector2(x + 9, y), Vector2(x, y + 5)]), dim)
	x += 13.0
	var pt := _compact(int(e.get("plays", 0)))
	st.draw_string(f, Vector2(x, y + fs * 0.36), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.COL_TEXT)
	x += f.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0
	_heart(st, Vector2(x + 5, y), 5.0, UITheme.COL_ACCENT if bool(e.get("liked", false)) else dim)
	x += 14.0
	var lt := _compact(int(e.get("likes", 0)))
	st.draw_string(f, Vector2(x, y + fs * 0.36), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.COL_TEXT)
	if _is_bookmarked(str(e.get("id", ""))):
		x += f.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0
		_ribbon(st, Vector2(x + 4, y), 6.0, UITheme.COL_NEON)


static func _heart(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(-r * 0.5, -r * 0.25), r * 0.55, col)
	ci.draw_circle(c + Vector2(r * 0.5, -r * 0.25), r * 0.55, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.02, -r * 0.05), c + Vector2(r * 1.02, -r * 0.05), c + Vector2(0, r * 0.95)]), col)


static func _ribbon(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, -r), c + Vector2(r * 0.6, -r), c + Vector2(r * 0.6, r),
		c + Vector2(0, r * 0.45), c + Vector2(-r * 0.6, r)]), col)


static func _compact(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 10000:
		return "%dk" % (n / 1000)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)


func _thumb_of(e: Dictionary) -> Dictionary:
	var t = e.get("thumb")
	if t is Dictionary and not (t as Dictionary).is_empty():
		return t
	# Offline bookmark / no server thumb: draw it from the cached map.
	var path := cache_path(str(e.get("id", "")))
	if path != "":
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			return LevelThumb.from_map(d)
	return {}


# ── Detail ─────────────────────────────────────────────────────────────────

func select(id: String) -> void:
	for e in levels:
		if str(e.get("id", "")) == id:
			_show_detail(e)
			_mark_selected()
			return


func _mark_selected() -> void:
	var sid := str(selected.get("id", ""))
	for id in _cards:
		_skin_card(_cards[id], id == sid)


func _show_detail(e: Dictionary) -> void:
	selected = e
	var has := not e.is_empty()
	_d_hint.visible = not has
	for n in [_d_thumb, _d_title, _d_author, _d_code, _d_stats, _d_modes, _d_mode, _d_play, _d_host, _d_like, _d_mark]:
		n.visible = has
	(_d_code.get_parent() as Control).visible = has
	(_d_like.get_parent() as Control).visible = has
	_d_status.text = ""
	if not has:
		_d_thumb.call("set_thumb", {}, "")
		return
	_d_thumb.call("set_thumb", _thumb_of(e), str(e.get("theme", "")))
	_d_title.text = str(e.get("title", e.get("name", "?")))
	var au := str(e.get("author", ""))
	_d_author.text = (tr("by %s") % au) if au != "" else tr("by an unknown builder")
	_d_code.text = str(e.get("code", ""))
	_refresh_detail_stats()
	_d_modes.text = tr("Built for: %s") % modes_text(e)
	_d_mode.clear()
	_d_mode_keys.clear()
	var keys := str(e.get("modes", "dm")).split(" ", false)
	if keys.is_empty():
		keys = PackedStringArray(["dm"])
	var pick := -1
	for k in ["ctf", "dom", "htf", "inf", "rm", "tdm", "dm"]:
		if k in keys:
			_d_mode.add_item(GameLists.MODE_NAMES[MODE_KEYS[k]])
			_d_mode_keys.append(k)
			# Your current mode when the level was built for it (DM / TDM run
			# anywhere, so they don't count): else what the level was made for.
			if MODE_KEYS[k] == Settings.game_mode and pick < 0 and not (k in ["dm", "tdm"]):
				pick = _d_mode_keys.size() - 1
	_d_mode.selected = maxi(pick, 0)


func _refresh_detail_stats() -> void:
	if selected.is_empty():
		return
	_d_stats.text = tr("%s plays   ·   %s likes") % [_compact(int(selected.get("plays", 0))), _compact(int(selected.get("likes", 0)))]
	var liked := bool(selected.get("liked", false))
	_d_like.text = tr("LIKED") if liked else tr("LIKE")
	UITheme.style_button(_d_like, 16, liked)
	var marked := _is_bookmarked(str(selected.get("id", "")))
	_d_mark.text = tr("BOOKMARKED") if marked else tr("BOOKMARK")
	UITheme.style_button(_d_mark, 16, marked)
	var c: Button = _cards.get(str(selected.get("id", "")))
	if c != null:
		var st := c.find_child("Stats", true, false) as Control
		if st != null:
			st.set_meta("level", selected)
			st.queue_redraw()


func selected_mode() -> int:
	var i := _d_mode.selected
	if i < 0 or i >= _d_mode_keys.size():
		return Settings.MODE_DM
	return int(MODE_KEYS[_d_mode_keys[i]])


## Share-code box: fetch that level and show it in the detail panel.
func open_code(text: String) -> void:
	var code := text.strip_edges()
	if code == "":
		return
	_status.text = tr("Looking up %s...") % code.to_upper()
	api.get_level("", code, func(ok: bool, d: Dictionary, err: String) -> void:
		if not ok:
			_status.text = err
			return
		var lv: Dictionary = d.get("level", {})
		_cache_map(str(lv.get("id", "")), d.get("map"))
		_status.text = ""
		if not _cards.has(str(lv.get("id", ""))):
			levels.push_front(lv)
			var c := _card(lv)
			_grid.add_child(c)
			_grid.move_child(c, 0)
			_cards[str(lv.get("id", ""))] = c
			_empty.visible = false
			loaded = levels.size()
		select(str(lv.get("id", ""))))


func _is_bookmarked(id: String) -> bool:
	for b in Settings.level_bookmarks:
		if str(b.get("id", "")) == id:
			return true
	return false


func toggle_bookmark() -> void:
	if selected.is_empty():
		return
	var id := str(selected.get("id", ""))
	if _is_bookmarked(id):
		for i in range(Settings.level_bookmarks.size() - 1, -1, -1):
			if str(Settings.level_bookmarks[i].get("id", "")) == id:
				Settings.level_bookmarks.remove_at(i)
		_d_status.text = tr("Removed from your bookmarks.")
	else:
		Settings.level_bookmarks.push_front(_bookmark_entry(selected))
		Settings.level_bookmarks = Settings.level_bookmarks.slice(0, Settings.LEVEL_BOOKMARKS_MAX)
		_d_status.text = tr("Bookmarked. Find it under BOOKMARKED, even offline.")
	Settings.save()
	_refresh_detail_stats()


static func _bookmark_entry(e: Dictionary) -> Dictionary:
	var out := {}
	for k in ["id", "code", "title", "author", "modes", "plays", "likes", "theme"]:
		if e.has(k):
			out[k] = e[k]
	return out


func _refresh_bookmark_meta(fresh: Array) -> void:
	var by_id := {}
	for e in fresh:
		by_id[str(e.get("id", ""))] = e
	var changed := false
	for i in Settings.level_bookmarks.size():
		var id := str(Settings.level_bookmarks[i].get("id", ""))
		if by_id.has(id):
			var nb := _bookmark_entry(by_id[id])
			if nb != Settings.level_bookmarks[i]:
				Settings.level_bookmarks[i] = nb
				changed = true
	if changed:
		Settings.save()


func toggle_like() -> void:
	if selected.is_empty():
		return
	var lv := selected
	var want := not bool(lv.get("liked", false))
	# Optimistic: flip now, settle on the server's answer.
	lv["liked"] = want
	lv["likes"] = maxi(0, int(lv.get("likes", 0)) + (1 if want else -1))
	_refresh_detail_stats()
	api.like(str(lv.get("id", "")), want, func(ok: bool, d: Dictionary, err: String) -> void:
		last_like = d if ok else {"error": err}
		if ok:
			lv["liked"] = bool(d.get("liked", want))
			lv["likes"] = int(d.get("likes", lv.get("likes", 0)))
		else:
			lv["liked"] = not want
			lv["likes"] = maxi(0, int(lv.get("likes", 0)) + (-1 if want else 1))
			if selected == lv:
				_d_status.text = err
		if selected == lv:
			_refresh_detail_stats())


# ── Play / host ────────────────────────────────────────────────────────────

## Cached copy: user://levels/<id>/<title>.json (the file name is what a
## hosted game shows in the server list: "Custom: <title>"). "" = none.
static func cache_path(id: String) -> String:
	var d := CACHE_DIR + id + "/"
	if id.length() == 16 and DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".json"):
				return d + f
	return ""


static func _cache_map(id: String, m: Variant) -> String:
	if id.length() != 16 or not id.is_valid_hex_number() or not (m is Dictionary):
		return ""
	var d := CACHE_DIR + id + "/"
	DirAccess.make_dir_recursive_absolute(d)
	for old in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d + old)
	var path := d + MapIO.safe_filename(str(m.get("name", "level"))) + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(m))
	f.close()
	return path


## The level's map as a local file (downloaded once, then cached), then cb(path).
func _with_map(lv: Dictionary, cb: Callable) -> void:
	var id := str(lv.get("id", ""))
	_d_status.text = tr("Downloading the level...")
	api.get_level(id, "", func(ok: bool, d: Dictionary, err: String) -> void:
		var path := ""
		if ok:
			path = _cache_map(id, d.get("map"))
		elif cache_path(id) != "":
			path = cache_path(id)   # offline: the copy from the last time
		if path == "" or MapIO.load_from_file(path).is_empty():
			_busy_play = false
			_d_status.text = err if err != "" else tr("That level couldn't be downloaded.")
			return
		_d_status.text = ""
		cb.call(path))


func play_selected() -> void:
	if selected.is_empty() or _busy_play:
		return
	_busy_play = true
	var lv := selected
	var mode := selected_mode()
	_with_map(lv, func(path: String) -> void:
		LevelsApi.report_play(get_tree(), str(lv.get("id", "")))
		Settings.game_mode = mode
		Settings.custom_map_path = path
		Settings.save()
		Net.set_singleplayer()
		_busy_play = false
		if play_hook.is_valid():
			play_hook.call()
		else:
			get_tree().change_scene_to_file("res://scenes/main.tscn"))


func host_selected() -> void:
	if selected.is_empty() or _busy_play:
		return
	var go := func() -> void:
		_busy_play = true
		var lv := selected
		var mode := selected_mode()
		_with_map(lv, func(path: String) -> void:
			_busy_play = false
			Settings.game_mode = mode
			Settings.save()
			var title := str(lv.get("title", lv.get("name", "Level")))
			if host_requested.get_connections().is_empty():
				# Map editor: hand over to the menu's Host screen.
				pending_host = path
				pending_host_title = title
				get_tree().change_scene_to_file("res://scenes/menu.tscn")
			else:
				visible = false
				host_requested.emit(path, title))
	if gate.is_valid():
		gate.call(go)
	else:
		go.call()
