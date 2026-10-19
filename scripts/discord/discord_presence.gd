extends Node
## Discord Rich Presence (#223): "Playing Capture the Flag on Ascent",
## "Blue 3 – 2 Red", elapsed time, the Tracerfall art, a mode icon, and the
## party size in online games — or "In the Maker editor" / "Browsing levels"
## / "In menus".
##
## Pure GDScript over Discord's local IPC (discord_ipc.gd framing +
## discord_transport.gd: the \\?\pipe\discord-ipc-N named pipe on Windows,
## the $XDG_RUNTIME_DIR/discord-ipc-N socket on Linux). No GDExtension, no
## native binaries, no export changes.
##
## Never blocks or slows the game: every byte of I/O happens on one worker
## thread; the main thread only builds a small Dictionary once a second and
## hands the newest one over (mutex + semaphore). Discord allows 5 updates
## per 20 s, so updates are coalesced to at most one per MIN_SEND_GAP_MS.
##
## Created by Settings._ready only on desktop (not Android / mobile, not
## headless, not a dedicated server — see platform_allows), and even then it
## stays idle until GameInfo.DISCORD_APP_ID holds the owner's application id
## (or --discord-app-id=… is passed) and Settings.discord_status is on.
## Cosmetic only: it reads match state, never writes any.

const Ipc = preload("res://scripts/discord/discord_ipc.gd")
const Transport = preload("res://scripts/discord/discord_transport.gd")
const GameInfoSrc = preload("res://scripts/game_info.gd")
const GameListsSrc = preload("res://scripts/game_lists.gd")

## Art keys uploaded to the Discord application (Rich Presence → Art Assets);
## docs/discord/ has the PNGs. Unknown keys just show no picture.
const LARGE_IMAGE := "tracerfall"
const MODE_IMAGES := ["mode_dm", "mode_tdm", "mode_ctf", "mode_inf", "mode_htf",
	"mode_rm", "mode_pm", "mode_dom", "mode_br", "mode_gg"]
const DOWNLOAD_URL := "https://github.com/Predator04/Tracerfall/releases/latest"
const GG_RUNGS := 16
const TICK_S := 1.0
const READ_TIMEOUT_MS := 3000

## Tests make it run headless; never set in the game.
static var force_platform_for_tests := false

var app_id := ""                    # resolved in _ready (tests set it directly)
var min_send_gap_ms := 4100         # 5 per 20 s is Discord's limit
var retry_ms := 15000               # look for Discord again this often
var refresh_ms := 60000             # re-send an unchanged status (Discord restarted?)
var transport_factory: Callable     # tests: returns a fake transport
var auto_tick := true               # tests call tick() themselves
var pid := 0

# Main thread only.
var _last_sig := ""
var _last_post := -1000000
var _closed := true
var _kind_key := ""
var _kind_start := 0
var _timer: Timer = null
var _me_scene := 0
var _me_team := -999
var _me_name := ""
var _me_bots := 0

# The I/O worker: its own RefCounted (see IpcWorker), so a thread stuck in a
# read can never touch a freed node.
var _thread: Thread = null
var _w: IpcWorker = null
## Workers stop() gave up on (only if Discord hangs): kept referenced so their
## thread never runs on freed memory; the OS reaps them at exit.
static var _orphans: Array = []


## Desktop Windows / Linux with a window, not a dedicated server.
static func platform_allows(os_name: String, display_name: String, dedicated: bool) -> bool:
	if dedicated or display_name == "headless":
		return false
	return os_name in ["Windows", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]


static func _dedicated_args() -> bool:
	var a := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	return "--dedicated" in a or "--server" in a or "--smoke-dedicated" in a


static func platform_ok() -> bool:
	if force_platform_for_tests:
		return true
	return platform_allows(OS.get_name(), DisplayServer.get_name(), _dedicated_args())


## The application id: GameInfo.DISCORD_APP_ID, or --discord-app-id=<id>.
static func configured_app_id() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--discord-app-id="):
			return a.substr(len("--discord-app-id=")).strip_edges()
	return str(GameInfoSrc.DISCORD_APP_ID).strip_edges()


func _ready() -> void:
	name = "DiscordPresence"
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep the status right while paused
	pid = OS.get_process_id()
	if app_id == "":
		app_id = configured_app_id()
	if not auto_tick:
		return
	_timer = Timer.new()
	_timer.wait_time = TICK_S
	_timer.autostart = true
	_timer.timeout.connect(tick)
	add_child(_timer)


func _exit_tree() -> void:
	stop()


## Is the feature live right now? (id present, setting on, desktop, not a server.)
func enabled_now() -> bool:
	if app_id == "" or not platform_ok():
		return false
	var st := get_node_or_null("/root/Settings")
	if st != null and st.get("discord_status") == false:
		return false
	var net := get_node_or_null("/root/Net")
	return not (net != null and bool(net.get("is_dedicated")))


## Settings toggled: off closes the pipe (Discord clears the status), on
## reconnects on the next tick.
func refresh_enabled() -> void:
	_last_sig = ""
	_last_post = -1000000
	tick()


func status() -> Dictionary:
	if _w == null:
		return IpcWorker.blank_status()
	return _w.status()


## Once a second: build the status and hand it to the worker when it changed.
func tick() -> void:
	if not enabled_now():
		if not _closed and _thread != null:
			_post({"close": true})
		_closed = true
		return
	var st := status()
	if bool(st.bad_id):
		return
	var act := activity_for(get_tree().current_scene if is_inside_tree() else null)
	var sig := JSON.stringify(act)
	var now := Time.get_ticks_msec()
	var due := sig != _last_sig or _closed \
		or (not bool(st.connected) and now - _last_post >= retry_ms) \
		or now - _last_post >= refresh_ms
	if due and now - _last_post >= min_send_gap_ms:
		_last_sig = sig
		_last_post = now
		_closed = false
		_post({"activity": act})


## Stop the worker. Never waits on Discord: a worker stuck in a read is left
## to the OS after 300 ms (only possible if Discord itself hangs).
func stop() -> void:
	if _thread == null:
		return
	_w.post(null, true)
	var t0 := Time.get_ticks_msec()
	while _thread.is_alive() and Time.get_ticks_msec() - t0 < 300:
		OS.delay_msec(2)
	if not _thread.is_alive():
		_thread.wait_to_finish()
	else:
		_orphans.append([_thread, _w])
	_thread = null


func _post(job: Dictionary) -> void:
	if _thread == null:
		var keep_status := _w.status() if _w != null else {}
		_w = IpcWorker.new(app_id, pid, transport_factory)
		_w.carry_over(keep_status)
		_thread = Thread.new()
		_thread.start(_w.run, Thread.PRIORITY_LOW)
	_w.post(job.duplicate(true), false)


# ── What we show ─────────────────────────────────────────────────────────

## The activity for whatever scene is running (main thread).
func activity_for(scene: Node) -> Dictionary:
	var f := facts_for(scene)
	var key := str(f.get("key", f.get("kind", "")))
	if key != _kind_key:
		_kind_key = key
		_kind_start = int(Time.get_unix_time_from_system())
	f["start"] = _kind_start
	f["version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	return build_activity(f)


## Read the running scene (duck-typed: nothing here is called on it).
func facts_for(scene: Node) -> Dictionary:
	if scene == null:
		return {"kind": "menu"}
	var path := scene.scene_file_path
	if path.ends_with("map_editor.tscn"):
		return {"kind": "editor"}
	if path.ends_with("main.tscn"):
		return _match_facts(scene)
	if path.ends_with("menu.tscn"):
		var lp: Variant = scene.get("_levels_panel")
		if is_instance_valid(lp) and lp is Control and (lp as Control).is_visible_in_tree():
			return {"kind": "levels"}
	return {"kind": "menu"}


func _match_facts(main: Node) -> Dictionary:
	var net := get_node_or_null("/root/Net")
	var st := get_node_or_null("/root/Settings")
	if main.get("replay_mode") == true:
		return {"kind": "replay"}
	if net != null and net.get("maker_return") is Dictionary and not (net.get("maker_return") as Dictionary).is_empty():
		return {"kind": "playtest"}
	if st != null and st.get("training") == true:
		return {"kind": "training"}
	var mode: int = int(st.get("game_mode")) if st != null else 0
	var f := {"kind": "match", "mode": mode, "map": _map_name(main, st)}
	f["key"] = "match:%d:%s:%d" % [main.get_instance_id(), f.map, mode]
	if _me_scene != main.get_instance_id():
		_me_scene = main.get_instance_id()
		_me_team = -999
		_me_name = ""
		_me_bots = 0
	var team_mode: bool = st != null and bool(st.call("is_team_mode"))
	var scores: Variant = main.get("scores")
	# The local soldier node is freed while you're dead: remember who you are.
	var me: Variant = main.get("player")
	if is_instance_valid(me) and me is Node:
		_me_team = int(me.get("team"))
		_me_name = str(me.get("display_name"))
	if scores is Dictionary:
		if team_mode:
			f["blue"] = int((scores as Dictionary).get(1, 0))
			f["red"] = int((scores as Dictionary).get(2, 0))
		elif mode == 9:
			var lv: Variant = main.get("_gg_levels")
			if lv is Dictionary and _me_name != "":
				f["rung"] = int((lv as Dictionary).get(_me_name, 0)) + 1
		elif _me_team != -999:
			f["score"] = int((scores as Dictionary).get(_me_team, 0))
	# Bots on the field (dead ones are freed until they respawn, so keep the
	# most seen this match — a steady line instead of an update per death).
	var nb := 0
	for n in main.get_tree().get_nodes_in_group("soldier"):
		var sc: Variant = n.get_script()
		if sc is Script and (sc as Script).resource_path.ends_with("/bot.gd"):
			nb += 1
	_me_bots = maxi(_me_bots, nb)
	f["bots"] = _me_bots
	var online: bool = net != null and bool(net.call("is_networked"))
	f["online"] = online
	if online:
		var humans: Variant = main.get("_players_by_id")
		var n: int = maxi(1, (humans as Dictionary).size() if humans is Dictionary else 1)
		var cap: int = int(net.get("MAX_PEERS")) + (1 if bool(net.call("is_host")) else 0)
		f["players"] = n
		f["max"] = maxi(n, cap)
		var ident := ""
		if bool(net.call("is_host")) and st != null:
			ident = "h:" + str(st.call("profile_hash"))
		elif st != null:
			ident = "c:%s:%s" % [str(st.get("last_join_ip")), str(st.get("last_join_port"))]
		f["party"] = ("tf-party:" + ident).sha256_text().left(32)
	return f


func _map_name(main: Node, st: Node) -> String:
	var idx := int(main.get("cur_map_index")) if main.get("cur_map_index") != null else -1
	if idx >= 0 and idx < GameListsSrc.MAP_NAMES.size():
		return str(GameListsSrc.MAP_NAMES[idx])
	var nm := ""
	var cp := str(st.get("custom_map_path")) if st != null else ""
	if cp != "" and not cp.get_file().begins_with("_"):
		nm = cp.get_file().get_basename()
	var m: Variant = main.get("_map")
	if nm == "" and m is Dictionary:
		nm = str((m as Dictionary).get("name", ""))
	nm = nm.strip_edges().left(40)
	return nm if nm.length() >= 2 else _t("a custom map")


## Facts -> the Discord activity object (pure; the test checks it directly).
## facts: kind = menu | levels | editor | playtest | training | replay | match,
## and for a match: mode, map, blue / red | score | rung, bots, online,
## players, max, party; plus start (unix s) and version.
static func build_activity(f: Dictionary) -> Dictionary:
	var details := ""
	var state := ""
	var small := ""
	var small_text := ""
	match str(f.get("kind", "menu")):
		"levels":
			details = _t("Browsing levels")
		"editor":
			details = _t("In the Maker editor")
		"playtest":
			details = _t("In the Maker editor")
			state = _t("Play-testing a level")
		"training":
			details = _t("In training")
		"replay":
			details = _t("Watching a replay")
		"match":
			var mode := clampi(int(f.get("mode", 0)), 0, GameListsSrc.MODE_NAMES.size() - 1)
			var mode_name := _t(str(GameListsSrc.MODE_NAMES[mode]))
			details = _t("Playing %s on %s") % [mode_name, str(f.get("map", "?"))]
			var bits := PackedStringArray()
			if f.has("blue"):
				bits.append("%s %d – %d %s" % [_t("Blue"), int(f["blue"]), int(f["red"]), _t("Red")])
			elif f.has("rung"):
				bits.append(_t("Rung %d / %d") % [int(f["rung"]), GG_RUNGS])
			elif f.has("score"):
				bits.append(_t("Score %d") % int(f["score"]))
			if not bool(f.get("online", false)) and int(f.get("bots", 0)) > 0:
				bits.append(_t("Bots: %d") % int(f["bots"]))
			state = " · ".join(bits)
			small = str(MODE_IMAGES[mode])
			small_text = mode_name
		_:
			details = _t("In menus")
	var act := {"details": _clip(details)}
	if state.length() >= 2:
		act["state"] = _clip(state)
	if int(f.get("start", 0)) > 0:
		act["timestamps"] = {"start": int(f["start"])}
	var assets := {"large_image": LARGE_IMAGE, "large_text": _clip("%s %s" % [GameInfoSrc.TITLE, str(f.get("version", ""))])}
	if small != "":
		assets["small_image"] = small
		assets["small_text"] = _clip(small_text)
	act["assets"] = assets
	if bool(f.get("online", false)) and f.has("party"):
		act["party"] = {"id": str(f["party"]), "size": [int(f.get("players", 1)), int(f.get("max", 1))]}
	act["buttons"] = [{"label": _clip(_t("Get Tracerfall"), 32), "url": DOWNLOAD_URL}]
	act["instance"] = false
	return act


static func _t(s: String) -> String:
	return str(TranslationServer.translate(s))


## Discord rejects strings over 128 chars (button labels: 32).
static func _clip(s: String, n: int = 128) -> String:
	s = s.strip_edges()
	return s if s.length() <= n else s.left(n - 1) + "…"


# ── Worker thread: all Discord I/O ───────────────────────────────────────

## Everything the worker thread touches. The node talks to it only through
## post() / status() (mutex + semaphore).
class IpcWorker:
	extends RefCounted
	var app_id := ""
	var pid := 0
	var factory: Callable
	var _mx := Mutex.new()
	var _sem := Semaphore.new()
	var _job: Variant = null            # null | {"close": true} | {"activity": {...}}
	var _quit := false
	var _st := {}
	var _tp: RefCounted = null          # worker thread only
	var _nonce := 0

	static func blank_status() -> Dictionary:
		return {"connected": false, "user": "", "error": "", "bad_id": false,
			"sent": 0, "attempts": 0, "where": ""}

	func _init(id: String, p: int, f: Callable) -> void:
		_st = blank_status()
		app_id = id
		pid = p
		factory = f

	## A new worker after stop() keeps the refused-id verdict and the counters.
	func carry_over(old: Dictionary) -> void:
		for k in ["bad_id", "sent", "attempts"]:
			if old.has(k):
				_st[k] = old[k]

	func status() -> Dictionary:
		_mx.lock()
		var s := _st.duplicate()
		_mx.unlock()
		return s

	## Newest job wins (an unsent status is simply replaced); quit ends run().
	func post(job: Variant, quit: bool) -> void:
		_mx.lock()
		if quit:
			_quit = true
		else:
			_job = job
		_mx.unlock()
		_sem.post()

	func run() -> void:
		while true:
			_sem.wait()
			_mx.lock()
			var quit := _quit
			var job: Variant = _job
			_job = null
			_mx.unlock()
			if quit:
				break
			if job == null:
				continue
			if (job as Dictionary).has("close"):
				_w_close("")
				continue
			if _tp == null and not _w_connect():
				continue
			if not _w_send((job as Dictionary).get("activity", {})):
				_w_close("Discord closed the connection")
		_w_close("")


	func _w_status(k: String, v: Variant) -> void:
		_mx.lock()
		_st[k] = v
		_mx.unlock()


	func _w_connect() -> bool:
		_mx.lock()
		_st.attempts = int(_st.attempts) + 1
		_mx.unlock()
		var tp: RefCounted = factory.call() if factory.is_valid() else Transport.for_platform()
		if tp == null or not bool(tp.call("open")):
			_w_status("error", "Discord is not running")
			return false
		_tp = tp
		if not bool(_tp.call("write", Ipc.handshake(app_id))):
			_w_close("handshake write failed")
			return false
		var fr := _w_read()
		var d: Dictionary = fr[1]
		if int(fr[0]) == Ipc.OP_FRAME and str(d.get("evt", "")) == "READY":
			var data: Variant = d.get("data")
			var user: Variant = (data as Dictionary).get("user") if data is Dictionary else null
			var uname := str((user as Dictionary).get("username", "")) if user is Dictionary else ""
			_mx.lock()
			_st.connected = true
			_st.user = uname
			_st.error = ""
			_st.where = str(_tp.call("describe"))
			_mx.unlock()
			print("Discord: connected (%s)" % str(_tp.call("describe")))
			return true
		var why := "no answer from Discord"
		if int(fr[0]) == Ipc.OP_CLOSE:
			why = "Discord refused: %s (%d)" % [str(d.get("message", "")), int(d.get("code", 0))]
			if int(d.get("code", 0)) == 4000:
				_w_status("bad_id", true)   # wrong application id: stop asking
		print("Discord: " + why)
		_w_close(why)
		return false


	## [op, payload] of the next frame (answers PINGs on the way); [-1, {}] on failure.
	func _w_read() -> Array:
		for _i in 8:
			var hd := Ipc.parse_header(_tp.call("read_exact", 8, READ_TIMEOUT_MS))
			var op: int = hd[0]
			if op < 0:
				return [-1, {}]
			var body: PackedByteArray = PackedByteArray()
			if int(hd[1]) > 0:
				body = _tp.call("read_exact", int(hd[1]), READ_TIMEOUT_MS)
				if body.size() != int(hd[1]):
					return [-1, {}]
			var d := Ipc.parse_payload(body)
			if op == Ipc.OP_PING:
				_tp.call("write", Ipc.encode(Ipc.OP_PONG, d))
				continue
			return [op, d]
		return [-1, {}]


	func _w_send(activity: Dictionary) -> bool:
		_nonce += 1
		var n := "tf-%d" % _nonce
		if not bool(_tp.call("write", Ipc.set_activity(pid, activity, n))):
			return false
		for _i in 6:
			var fr := _w_read()
			if int(fr[0]) != Ipc.OP_FRAME:
				return false
			var d: Dictionary = fr[1]
			if str(d.get("nonce", "")) != n:
				continue   # an event we didn't ask for
			if str(d.get("evt", "")) == "ERROR":
				var data: Variant = d.get("data")
				_w_status("error", str((data as Dictionary).get("message", "error")) if data is Dictionary else "error")
			else:
				_mx.lock()
				_st.sent = int(_st.sent) + 1
				_st.error = ""
				_mx.unlock()
			return true
		return true


	func _w_close(why: String) -> void:
		if _tp != null:
			_tp.call("close")
		_tp = null
		_mx.lock()
		_st.connected = false
		if why != "":
			_st.error = why
		_mx.unlock()
