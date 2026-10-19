extends Node
## Level server client (#288): non-blocking HTTPRequests against the master
## server's /levels API (see the master-server README). One request slot per
## kind — a new list request replaces the one in flight. Every callback gets
## (ok: bool, data: Dictionary, err: String); err is a friendly sentence.
## Uses the master URL from Settings. No RPCs.

const TIMEOUT := 12.0
const KINDS := ["list", "get", "like", "upload", "code"]

## Tests against a real server under --fixed-fps (frames faster than real
## time; HTTPRequest timeouts count game time) set this to 0 (no timeout).
static var timeout_override := -1.0

var _http := {}      # kind -> HTTPRequest
var _cb := {}        # kind -> Callable
var last_error := ""
var requests := 0    # for tests


func _ready() -> void:
	for k in KINDS:
		var h := HTTPRequest.new()
		h.name = "Http_" + k
		h.timeout = TIMEOUT if timeout_override < 0.0 else timeout_override
		h.use_threads = false
		add_child(h)
		_http[k] = h
		h.request_completed.connect(_on_done.bind(k))


static func base_url() -> String:
	return Settings.master_url.strip_edges().trim_suffix("/")


static func offline_text() -> String:
	return TranslationServer.translate("You're offline, or the level server can't be reached right now. Bookmarked levels you've played before still work.")


func busy(kind: String) -> bool:
	var h: HTTPRequest = _http.get(kind)
	return h != null and h.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED


func cancel(kind: String) -> void:
	var h: HTTPRequest = _http.get(kind)
	if h != null:
		h.cancel_request()
	_cb.erase(kind)


func _send(kind: String, path: String, cb: Callable, body: Variant = null) -> void:
	var h: HTTPRequest = _http[kind]
	h.cancel_request()
	_cb[kind] = cb
	requests += 1
	if base_url() == "":
		_finish(kind, false, {}, offline_text())
		return
	var err: int
	if body == null:
		err = h.request(base_url() + path)
	else:
		err = h.request(base_url() + path, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_finish.call_deferred(kind, false, {}, offline_text())


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, kind: String) -> void:
	var text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS or code == 0:
		_finish(kind, false, {}, offline_text())
		return
	if code == 429:
		_finish(kind, false, {}, TranslationServer.translate("Slow down a little - try again in a minute."))
		return
	if code == 404:
		if kind == "get" or kind == "code" or kind == "like":
			_finish(kind, false, {"not_found": true}, TranslationServer.translate("No level with that code."))
		else:
			# A master from before #288 has no /levels routes at all.
			_finish(kind, false, {"outdated": true}, TranslationServer.translate("This master server doesn't have the level library yet."))
		return
	var d = JSON.parse_string(text) if code == 200 else null
	if typeof(d) != TYPE_DICTIONARY:
		var msg := text.strip_edges().left(90) if code != 200 else ""
		_finish(kind, false, {}, (TranslationServer.translate("The level server said: %s") % msg) if msg != "" else offline_text())
		return
	_finish(kind, true, d, "")


func _finish(kind: String, ok: bool, d: Dictionary, err: String) -> void:
	last_error = err
	var cb: Callable = _cb.get(kind, Callable())
	_cb.erase(kind)
	if cb.is_valid():
		cb.call(ok, d, err)


## sort: hot | new | plays | likes.  ids: bookmarks (exact ids, given order).
func list(sort: String, q: String, page: int, cb: Callable, ids: Array = []) -> void:
	var path := "/levels?sort=%s&page=%d&per=24&pid=%s" % [sort, page, Settings.level_pid()]
	if q.strip_edges() != "":
		path += "&q=" + q.strip_edges().uri_encode()
	if not ids.is_empty():
		path += "&ids=" + ",".join(PackedStringArray(ids.slice(0, 48)))
	_send("list", path, cb)


## By id, or by share code (any spelling; the server normalises it).
func get_level(id: String, code: String, cb: Callable) -> void:
	var path := "/levels/get?pid=" + Settings.level_pid()
	path += ("&id=" + id.uri_encode()) if id != "" else ("&code=" + code.strip_edges().uri_encode())
	_send("code" if id == "" else "get", path, cb)


func like(id: String, on: bool, cb: Callable) -> void:
	_send("like", "/levels/like", cb, {"id": id, "pid": Settings.level_pid(), "like": on})


func upload(title: String, author: String, map_json: Dictionary, theme: String, cb: Callable) -> void:
	_send("upload", "/levels/upload", cb, {"title": title, "author": author, "theme": theme, "map": map_json})


## Play report: fire-and-forget on the scene tree root so it survives the
## switch into the match (the browser is freed with the menu).
static func report_play(tree: SceneTree, id: String) -> void:
	if base_url() == "" or tree == null:
		return
	var h := HTTPRequest.new()
	h.name = "LevelPlayReport"
	h.timeout = 8.0 if timeout_override < 0.0 else timeout_override
	tree.root.add_child(h)
	h.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void: h.queue_free())
	if h.request(base_url() + "/levels/play", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST,
			JSON.stringify({"id": id, "pid": Settings.level_pid()})) != OK:
		h.queue_free()
