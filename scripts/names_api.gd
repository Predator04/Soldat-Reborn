extends Node
## Reserved names (#318), the player's side: ask the master server whether
## your name is reserved and reserve it against your profile
## (master-server `names.go`: POST /names/reserve, POST /names/mine,
## GET /names/check). The raw profile id goes to the master, which keeps only
## its sha256 — the same hash game servers already get when you join, so they
## can tell you from someone using your name. No RPCs.
##
## Callbacks get one Dictionary: {state, name, text, cooldown_s, taken_by}.
## state: reserved (yours) | free | taken | cooldown | invalid | offline |
## outdated (a master from before #318) | error.

const TIMEOUT := 10.0
const KINDS := ["check", "reserve", "mine"]

## Tests under --fixed-fps set 0 (HTTPRequest timeouts count game time).
static var timeout_override := -1.0
## Tests point this at a fake master; "" = Settings.master_url.
static var url_override := ""

var _http := {}
var _cb := {}
var requests := 0


func _ready() -> void:
	for k in KINDS:
		var h := HTTPRequest.new()
		h.name = "Names_" + k
		h.timeout = TIMEOUT if timeout_override < 0.0 else timeout_override
		h.use_threads = false
		add_child(h)
		_http[k] = h
		h.request_completed.connect(_on_done.bind(k))


static func base_url() -> String:
	if url_override != "":
		return url_override.trim_suffix("/")
	return Settings.master_url.strip_edges().trim_suffix("/")


## The name you'd reserve: your player name without the clan tag.
static func my_name() -> String:
	return Settings.player_name.strip_edges()


## Status of your current name (reserved by you / free / taken).
func check_mine(cb: Callable) -> void:
	_send("check", "/names/check?name=%s&pid=%s" % [my_name().uri_encode(), Settings.profile_hash()], cb)


func reserve(cb: Callable) -> void:
	_send("reserve", "/names/reserve", cb, {"id": Settings.profile_id, "name": my_name()})


func release(cb: Callable) -> void:
	_send("reserve", "/names/reserve", cb, {"id": Settings.profile_id, "release": true})


## Your reservation, whatever your current name is.
func mine(cb: Callable) -> void:
	_send("mine", "/names/mine", cb, {"id": Settings.profile_id})


func _send(kind: String, path: String, cb: Callable, body: Variant = null) -> void:
	var h: HTTPRequest = _http[kind]
	h.cancel_request()
	_cb[kind] = cb
	requests += 1
	if base_url() == "":
		_finish.call_deferred(kind, {"state": "offline", "text": status_text("offline")})
		return
	var err: int
	if body == null:
		err = h.request(base_url() + path)
	else:
		err = h.request(base_url() + path, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_finish.call_deferred(kind, {"state": "offline", "text": status_text("offline")})


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, kind: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code == 0:
		_finish(kind, {"state": "offline", "text": status_text("offline")})
		return
	if code == 404:
		_finish(kind, {"state": "outdated", "text": status_text("outdated")})
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY:
		_finish(kind, {"state": "error", "text": status_text("slow" if code == 429 else "error")})
		return
	_finish(kind, parse_reply(kind, d))


## Turns a /names reply into the panel's status (pure; tests call it too).
static func parse_reply(kind: String, d: Dictionary) -> Dictionary:
	var out := {"name": str(d.get("name", "")), "cooldown_s": int(d.get("cooldown_s", 0)), "taken_by": str(d.get("taken_by", d.get("display", "")))}
	var st := ""
	match kind:
		"check":
			st = {"mine": "reserved", "free": "free", "taken": "taken", "invalid": "invalid"}.get(str(d.get("status", "")), "error")
		"mine":
			st = "reserved" if out["name"] != "" else "none"
		_:
			st = str(d.get("status", "error"))
			if st in ["short", "offensive", "blocked"]:
				st = "invalid"
			elif st == "limit" or st == "full":
				st = "error"
	out["state"] = st
	out["text"] = status_text(st, out)
	return out


static func status_text(state: String, d: Dictionary = {}) -> String:
	match state:
		"reserved":
			return _t("Reserved: servers rename anyone else who uses this name.")
		"released":
			return _t("Released: your name isn't reserved any more.")
		"free":
			return _t("Not reserved yet: anyone can play under this name.")
		"none":
			return _t("You haven't reserved a name yet.")
		"taken":
			return _t("Taken: another player reserved this name. Pick another one.")
		"cooldown":
			var h := ceili(float(d.get("cooldown_s", 0)) / 3600.0)
			return _t("You changed your reserved name recently. Try again in %d h.") % maxi(1, h)
		"invalid":
			return _t("This name can't be reserved (too short, offensive, or one the game uses).")
		"offline":
			return _t("Offline: the master server can't be reached right now.")
		"outdated":
			return _t("This master server doesn't support reserved names yet.")
		"slow":
			return _t("Slow down a little - try again in a minute.")
	return _t("Something went wrong. Try again later.")


static func _t(s: String) -> String:
	return TranslationServer.translate(s)


func _finish(kind: String, d: Dictionary) -> void:
	var cb: Callable = _cb.get(kind, Callable())
	_cb.erase(kind)
	if cb.is_valid():
		cb.call(d)
