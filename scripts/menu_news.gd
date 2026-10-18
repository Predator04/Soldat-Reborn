extends HBoxContainer
## MenuNews (#261) — one dismissible news line under the version button on
## the main menu, from the master server's GET /news ({"text","url",
## "until_ms"}; {} = nothing to say). Fetched when the menu loads and at most
## once every 10 minutes (the result is cached across menu reloads). Clicking
## the line opens its link; × hides that message for good (Settings.
## news_dismissed remembers its text, so a new message shows again).
## Failures are silent: the request is async and nothing waits on it.
## Headless runs only fetch with --menu-news (tests), so boot checks never
## talk to the live server.

const UITheme = preload("res://scripts/ui_theme.gd")
const REFRESH_MS := 10 * 60 * 1000
const MAX_TEXT := 120

# Survive menu reloads (back from a match) so the 10-minute cap holds.
static var _last_fetch_ms := -1
static var _cached: Dictionary = {}

var menu: Node = null             # the main menu (for "is the main list up")
var shown_text := ""              # for tests: what the line says ("" = hidden)
var shown_url := ""
var fetches := 0                  # for tests: requests this node started
var _news: Dictionary = {}
var _http: HTTPRequest = null
var _text_btn: Button
var _x_btn: Button
var _tick := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16
	offset_top = 62
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var touch := UITheme.is_touch()
	var h := 44 if touch else 32
	_text_btn = Button.new()
	_text_btn.name = "NewsText"
	UITheme.style_button(_text_btn, 13, false)
	_text_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_text_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_btn.custom_minimum_size = Vector2(280, h)   # clear of the centred wordmark
	_text_btn.add_theme_color_override("font_color", UITheme.COL_INFO)
	_text_btn.focus_mode = Control.FOCUS_NONE
	_text_btn.pressed.connect(_on_open)
	add_child(_text_btn)
	_x_btn = Button.new()
	_x_btn.name = "NewsDismiss"
	_x_btn.text = "×"
	_x_btn.tooltip_text = tr("Hide this message")
	UITheme.style_button(_x_btn, 16, false)
	_x_btn.custom_minimum_size = Vector2(h, h)
	_x_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_x_btn.focus_mode = Control.FOCUS_NONE
	_x_btn.pressed.connect(dismiss)
	add_child(_x_btn)
	visible = false
	if not _cached.is_empty():
		_apply(_cached)
	_maybe_fetch()


func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = 5.0
		_maybe_fetch()
		if not _news.is_empty() and not _active(_news):
			_apply({})   # expired while the menu was open
	var want: bool = shown_text != "" and (menu == null or menu.get("_menu_root") == null or menu._menu_root.visible)
	if visible != want:
		visible = want


func _fetch_allowed() -> bool:
	if Net.is_dedicated:
		return false
	if DisplayServer.get_name() == "headless" and not "--menu-news" in OS.get_cmdline_user_args():
		return false
	return Settings.master_url.strip_edges() != ""


func _maybe_fetch() -> void:
	if not _fetch_allowed():
		return
	if _http != null and _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var now := Time.get_ticks_msec()
	if _last_fetch_ms >= 0 and now - _last_fetch_ms < REFRESH_MS:
		return
	fetch()


## Ask the master now (ignores the 10-minute cap; tests use this).
func fetch() -> void:
	if not _fetch_allowed():
		return
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 6.0
		_http.body_size_limit = 8192
		add_child(_http)
		_http.request_completed.connect(_on_done)
	_http.cancel_request()
	_last_fetch_ms = Time.get_ticks_msec()
	var url := Settings.master_url.strip_edges().trim_suffix("/") + "/news"
	if _http.request(url) == OK:
		fetches += 1


func _on_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return   # keep whatever we had; try again in 10 minutes
	var d = JSON.parse_string(body.get_string_from_utf8())
	var news := parse_news(d)
	_cached = news
	_apply(news)


## Validate a /news reply: {} unless it has text and hasn't expired.
static func parse_news(d) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	var text := clean_text(str(d.get("text", "")) if d.get("text") is String else "")
	if text == "":
		return {}
	var url := str(d.get("url", "")) if d.get("url") is String else ""
	url = url.strip_edges()
	if not (url.begins_with("https://") or url.begins_with("http://")) or url.length() > 300:
		url = ""
	var until := 0
	var u = d.get("until_ms", 0)
	if typeof(u) == TYPE_INT or typeof(u) == TYPE_FLOAT:
		until = int(u)
	var out := {"text": text, "url": url, "until_ms": until}
	return out if _active(out) else {}


static func clean_text(s: String) -> String:
	var out := ""
	for ch in s:
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	return out.strip_edges().left(MAX_TEXT)


static func _active(n: Dictionary) -> bool:
	var until := int(n.get("until_ms", 0))
	return until == 0 or until > int(Time.get_unix_time_from_system() * 1000.0)


func _apply(news: Dictionary) -> void:
	_news = news
	var text := str(news.get("text", ""))
	if text != "" and text == Settings.news_dismissed:
		text = ""
	shown_text = text
	shown_url = str(news.get("url", "")) if text != "" else ""
	_text_btn.text = text
	_text_btn.tooltip_text = tr("Open in your browser") if shown_url != "" else ""
	_text_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if shown_url != "" else Control.CURSOR_ARROW


func _on_open() -> void:
	if shown_url != "" and DisplayServer.get_name() != "headless":
		OS.shell_open(shown_url)


## × : hide this message (and only this one) from now on.
func dismiss() -> void:
	if shown_text == "":
		return
	Settings.news_dismissed = shown_text
	Settings.save()
	_apply(_news)
