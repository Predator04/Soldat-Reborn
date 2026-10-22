extends Node
## Reserved names (#318), the host's side (Main helper `_names`, listen host
## and dedicated server). Before a joiner gets a body, its name is looked up
## on the master server (GET /names/check, master-server `names.go`): a name
## reserved by another profile is an impostor -> the joiner plays as
## "Player####" (stable per profile, so a rejoin keeps it) and is told why in
## chat. Profiles are compared by the hash the host already keeps
## (`Net.peer_profiles`, from the `net_profile` RPC the client sends right
## after `net_client_ready`).
##
## Asked only when this host talks to a master (it lists there: dedicated
## `--register` / server.cfg `register`, a listen host's "List on the master
## server" or relay) and server.cfg `reserved_names` isn't false. Replies are
## cached per name; a master that doesn't answer within TIMEOUT (or errors)
## lets the joiner in under their own name (fail OPEN) and the host stops
## asking for OFFLINE_SECS. No RPCs (renaming happens before the spawn).

const NameFilter = preload("res://scripts/name_filter.gd")
const ServerConfig = preload("res://scripts/server_config.gd")

const TIMEOUT := 2.5          # s per master request
const CACHE_SECS := 120.0     # a looked-up name is trusted this long
const OFFLINE_SECS := 60.0    # after a failed lookup: let joins through without asking
const PROFILE_WAIT := 1.5     # s to wait for the joiner's net_profile after its reply

## Shared across matches (map changes rebuild Main).
static var _cache := {}       # name key -> {"reserved": bool, "owner": String, "ms": int}
static var _offline_until := 0
## Tests: master URL to use regardless of listing ("" = normal rules).
static var url_override := ""

var main: Node
var _pending := {}            # peer id -> {name, key, done, t0, reply, http}
var checks := 0               # master lookups started (tests / logs)
var impostors := 0


static func strip_tag(n: String) -> String:
	n = n.strip_edges()
	if n.begins_with("«") and n.find("»") > 0:
		n = n.substr(n.find("»") + 1).strip_edges()
	return n


static func key_of(n: String) -> String:
	return NameFilter.norm(strip_tag(n))


## The master this host asks ("" = don't check names).
func master_url() -> String:
	if not Net.is_host() or not Net.is_networked():
		return ""
	if not bool(Net.rule("reserved_names", true)):
		return ""
	if url_override != "":
		return url_override.trim_suffix("/")
	var u := Net.register_url.strip_edges()
	if u == "" and not Net.is_dedicated and Settings.host_relay:
		u = Settings.master_url.strip_edges()
	return u.trim_suffix("/")


func is_pending(pid: int) -> bool:
	return _pending.has(pid)


## Calls done(final_name) now (no check needed / cached) or once the master
## has answered. `done` is not called if the joiner leaves meanwhile.
func vet(pid: int, name: String, done: Callable) -> void:
	var url := master_url()
	var key := key_of(name)
	if url == "" or key.length() < 3:
		done.call(name)
		return
	var now := Time.get_ticks_msec()
	if now < _offline_until:
		print("NAMES master offline, %s joins unchecked" % name)
		done.call(name)
		return
	var job := {"name": name, "key": key, "done": done, "t0": now, "reply": null, "http": null}
	var c: Dictionary = _cache.get(key, {})
	if not c.is_empty() and now - int(c["ms"]) < int(CACHE_SECS * 1000.0):
		job["reply"] = c
	else:
		var h := HTTPRequest.new()
		h.timeout = TIMEOUT
		h.use_threads = false
		add_child(h)
		job["http"] = h
		h.request_completed.connect(_on_reply.bind(pid, h))
		checks += 1
		if h.request(url + "/names/check?name=" + strip_tag(name).uri_encode()) != OK:
			h.queue_free()
			job["http"] = null
			job["reply"] = {"fail": "request"}
	_pending[pid] = job
	_settle(pid)


func _on_reply(result: int, code: int, _hd: PackedStringArray, body: PackedByteArray, pid: int, h: HTTPRequest) -> void:
	h.queue_free()
	if not _pending.has(pid) or _pending[pid]["http"] != h:
		return
	var job: Dictionary = _pending[pid]
	job["http"] = null
	var d = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if result == HTTPRequest.RESULT_SUCCESS and code == 404:
		# A master from before #318: nothing is reserved there.
		d = {"reserved": false}
	if typeof(d) != TYPE_DICTIONARY:
		job["reply"] = {"fail": "http %d result %d" % [code, result]}
	else:
		var rep := {"reserved": bool(d.get("reserved", false)), "owner": str(d.get("owner", "")).to_lower(), "ms": Time.get_ticks_msec()}
		_cache[str(job["key"])] = rep
		job["reply"] = rep
	_settle(pid)


func _process(_d: float) -> void:
	for pid in _pending.keys():
		_settle(int(pid))


func _settle(pid: int) -> void:
	var job: Dictionary = _pending.get(pid, {})
	if job.is_empty():
		return
	if not main.multiplayer.has_multiplayer_peer() or not main.multiplayer.get_peers().has(pid):
		_drop(pid)
		return
	var rep = job["reply"]
	var waited := (Time.get_ticks_msec() - int(job["t0"])) / 1000.0
	if rep == null:
		if waited < TIMEOUT + 1.0:
			return
		rep = {"fail": "timeout"}   # HTTPRequest's own timeout should have fired
	var name: String = job["name"]
	if (rep as Dictionary).has("fail"):
		_offline_until = Time.get_ticks_msec() + int(OFFLINE_SECS * 1000.0)
		print("NAMES master unreachable (%s): %s joins unchecked" % [str(rep["fail"]), name])
		_finish(pid, name)
		return
	if not bool(rep["reserved"]):
		_finish(pid, name)
		return
	var mine := str(Net.peer_profiles.get(pid, ""))
	if mine == "" and waited < PROFILE_WAIT:
		return   # its net_profile is still on the way
	if mine != "" and mine == str(rep["owner"]):
		print("NAMES owner peer=%d %s" % [pid, name])
		_finish(pid, name)
		return
	var new_name := impostor_name(mine, pid)
	impostors += 1
	print("NAMES impostor peer=%d \"%s\" -> \"%s\"" % [pid, name, new_name])
	_finish(pid, new_name)
	var msg := "The name \"%s\" is reserved by another player, so you're playing as %s. Reserve your own name in Settings > Game." % [strip_tag(name), new_name]
	ServerConfig.tell(main, pid, msg)


## "Player####", the same for one profile every time (a rejoin keeps it).
static func impostor_name(profile_hash: String, pid: int) -> String:
	var seed_src := profile_hash if profile_hash != "" else str(pid)
	return "Player%04d" % (1000 + int(seed_src.sha256_text().substr(0, 6).hex_to_int() % 9000))


func _finish(pid: int, final_name: String) -> void:
	var job: Dictionary = _pending.get(pid, {})
	_pending.erase(pid)
	var cb: Callable = job.get("done", Callable())
	if cb.is_valid():
		cb.call(final_name)


func _drop(pid: int) -> void:
	var job: Dictionary = _pending.get(pid, {})
	_pending.erase(pid)
	var h = job.get("http")
	if h != null and is_instance_valid(h):
		(h as HTTPRequest).cancel_request()
		(h as HTTPRequest).queue_free()


## Tests: forget cached replies and the offline window.
static func reset_cache() -> void:
	_cache.clear()
	_offline_until = 0
