extends SceneTree
## Discord Rich Presence (#223), gate F: scripts/discord/ against a fake Discord.
##  - platform gate: Windows / Linux desktop only; Android, headless and
##    dedicated servers never start it (this headless run has no presence node)
##  - no application id -> nothing happens (no thread, no pipe opened)
##  - the status text for every state (menu / levels / editor / match, team
##    score, Gun Game rung, online party size), straight from build_activity
##  - wire protocol through an injected in-memory transport: handshake
##    {"v":1,"client_id"}, SET_ACTIVITY {cmd, args{pid, activity}, nonce} for
##    the real menu / LEVELS browser / CTF match / Maker editor scenes, PING
##    answered with PONG, unchanged status not re-sent, updates throttled
##  - the settings toggle closes the pipe and reconnects
##  - "Invalid Client ID" stops it asking again
##  - the real Linux transport (StreamPeerUDS) against a UDSServer socket
##   godot --headless --fixed-fps 60 -s tools/discord_test.gd

const P_PATH := "res://scripts/discord/discord_presence.gd"
const APP := "111122223333444455"
const GL = preload("res://tools/gate_load.gd")   # #293: wall deadlines scale with GATE_LOAD

var P: GDScript
var Ipc: GDScript
var Transport: GDScript
var _log: Array = []
var _st: Node = null
var _net: Node = null
var _saved := {}
var _done := false


## A fake desktop Discord: decodes what the game writes, answers like Discord.
class FakeDiscord:
	extends RefCounted
	var ipc: GDScript
	var mx := Mutex.new()
	var sent: Array = []        # [op, payload] the game wrote
	var opens := 0
	var closes := 0
	var refuse := false
	var ping_first := true
	var _out := PackedByteArray()
	var _in := PackedByteArray()

	func _init(ipc_script: GDScript) -> void:
		ipc = ipc_script

	func make() -> RefCounted:
		return FakePipe.new(self)

	func ops(op: int) -> Array:
		mx.lock()
		var r := sent.filter(func(f: Array) -> bool: return int(f[0]) == op)
		mx.unlock()
		return r

	func activities() -> Array:
		var r: Array = []
		for f in ops(1):
			if str(f[1].get("cmd", "")) == "SET_ACTIVITY":
				r.append(f[1])
		return r

	func feed(b: PackedByteArray) -> void:   # called by the game's worker thread
		mx.lock()
		_in.append_array(b)
		var res: Array = ipc.split_frames(_in)
		_in = _in.slice(int(res[1]))
		for fr in res[0]:
			sent.append(fr)
			var op: int = fr[0]
			var d: Dictionary = fr[1]
			if op == 0:
				if refuse:
					_out.append_array(ipc.encode(2, {"code": 4000, "message": "Invalid Client ID"}))
				else:
					_out.append_array(ipc.encode(1, {"cmd": "DISPATCH", "evt": "READY", "data": {"v": 1, "user": {"username": "tester"}}}))
			elif op == 1 and str(d.get("cmd", "")) == "SET_ACTIVITY":
				if ping_first:
					ping_first = false
					_out.append_array(ipc.encode(3, {"ping": 1}))
				_out.append_array(ipc.encode(1, {"cmd": "SET_ACTIVITY", "nonce": d.get("nonce"), "evt": null, "data": d.get("args", {}).get("activity")}))
		mx.unlock()

	func take(n: int, timeout_ms: int) -> PackedByteArray:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < GL.wait_ms(timeout_ms):
			mx.lock()
			if _out.size() >= n:
				var r := _out.slice(0, n)
				_out = _out.slice(n)
				mx.unlock()
				return r
			mx.unlock()
			OS.delay_msec(2)
		return PackedByteArray()


class FakePipe:
	extends RefCounted
	var d: FakeDiscord

	func _init(fd: FakeDiscord) -> void:
		d = fd

	func open() -> bool:
		d.mx.lock()
		d.opens += 1
		d._out = PackedByteArray()
		d._in = PackedByteArray()
		d.mx.unlock()
		return true

	func write(b: PackedByteArray) -> bool:
		d.feed(b)
		return true

	func read_exact(n: int, timeout_ms: int) -> PackedByteArray:
		return d.take(n, timeout_ms)

	func close() -> void:
		d.mx.lock()
		d.closes += 1
		d.mx.unlock()

	func describe() -> String:
		return "fake"


func _initialize() -> void:
	_run()


func _process(_d: float) -> bool:
	if not _done and Time.get_ticks_msec() > GL.wait_ms(80000):
		_finish(false, "timed out after: " + " | ".join(_log))
	return false


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


## Wait (wall clock, the worker is a real thread) until cond() or timeout.
func _until(cond: Callable, ms: int = 4000) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > GL.wait_ms(ms):
			return false
		await process_frame
	return true


func _sleep(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _fail(msg: String) -> bool:
	_finish(false, msg)
	return false


func _finish(ok: bool, msg: String) -> void:
	if _done:
		return
	_done = true
	if P != null:
		P.set("force_platform_for_tests", false)
	if _st != null:
		for k in _saved:
			_st.set(k, _saved[k])
		_st.save()
	P = null
	Ipc = null
	Transport = null
	print("DISCORD-TEST %s %s | %s | %.1f s" % ["ok" if ok else "FAIL", msg, " | ".join(_log), Time.get_ticks_msec() / 1000.0])
	quit(0 if ok else 1)


func _new_presence(fake: FakeDiscord, app: String) -> Node:
	var n: Node = P.new()
	n.set("app_id", app)
	n.set("auto_tick", false)
	n.set("min_send_gap_ms", 250)
	if fake != null:
		n.set("transport_factory", fake.make)
	root.add_child(n)
	return n


func _last_act(fake: FakeDiscord) -> Dictionary:
	var a := fake.activities()
	return a[-1] if not a.is_empty() else {}


func _details(act_frame: Dictionary) -> String:
	var a: Variant = act_frame.get("args", {}).get("activity")
	return str(a.get("details", "")) if a is Dictionary else ""


## tick() until the fake has `n` SET_ACTIVITY frames (ticks respect the throttle).
func _tick_until_acts(node: Node, fake: FakeDiscord, n: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while fake.activities().size() < n:
		if Time.get_ticks_msec() - t0 > GL.wait_ms(5000):
			return false
		node.call("tick")
		await process_frame
	return true


func _scene_is(file: String) -> bool:
	return current_scene != null and current_scene.scene_file_path.ends_with(file)


func _run():
	await _frames(3)
	_st = root.get_node_or_null("Settings")
	_net = root.get_node_or_null("Net")
	if _st == null or _net == null:
		return _fail("autoloads missing")
	for k in ["discord_status", "game_mode", "map_index", "custom_map_path", "master_url", "bot_count", "training"]:
		_saved[k] = _st.get(k)
	P = load(P_PATH)
	Ipc = load("res://scripts/discord/discord_ipc.gd")
	Transport = load("res://scripts/discord/discord_transport.gd")

	# ── 1. platform gate ──────────────────────────────────────────────
	var allow := [["Windows", "Windows", false, true], ["Linux", "X11", false, true],
		["Linux", "Wayland", false, true], ["Android", "Android", false, false],
		["iOS", "iOS", false, false], ["Web", "Web", false, false],
		["Windows", "headless", false, false], ["Linux", "headless", false, false],
		["Windows", "Windows", true, false], ["Linux", "X11", true, false]]
	for c in allow:
		if bool(P.call("platform_allows", c[0], c[1], c[2])) != bool(c[3]):
			return _fail("platform_allows%s wrong" % str(c))
	if bool(P.call("platform_ok")):
		return _fail("platform_ok() true in a headless run")
	if _st.get_node_or_null("DiscordPresence") != null:
		return _fail("Settings started a presence node headless")
	var idle_fake := FakeDiscord.new(Ipc)
	var idle := _new_presence(idle_fake, APP)
	idle.call("tick")
	await _sleep(200)
	if idle.get("_thread") != null or idle_fake.opens != 0:
		return _fail("headless presence did I/O")
	idle.queue_free()
	_log.append("platform gate (android / headless / dedicated off)")

	P.set("force_platform_for_tests", true)
	# Dedicated host: off even when forced on.
	var ded_fake := FakeDiscord.new(Ipc)
	var ded := _new_presence(ded_fake, APP)
	_net.set("is_dedicated", true)
	ded.call("tick")
	await _sleep(200)
	_net.set("is_dedicated", false)
	if ded.get("_thread") != null or ded_fake.opens != 0:
		return _fail("dedicated server presence did I/O")
	ded.queue_free()

	# ── 2. no application id ──────────────────────────────────────────
	var noid_fake := FakeDiscord.new(Ipc)
	var noid := _new_presence(noid_fake, "")
	if str(P.call("configured_app_id")) != "":
		return _fail("GameInfo.DISCORD_APP_ID must ship empty (owner pastes it)")
	for _i in 3:
		noid.call("tick")
	await _sleep(200)
	if noid.get("_thread") != null or noid_fake.opens != 0 or bool(noid.call("enabled_now")):
		return _fail("presence without an application id did I/O")
	noid.queue_free()
	_log.append("no id -> silent")

	# ── 3. status text (pure) ─────────────────────────────────────────
	var a: Dictionary = P.call("build_activity", {"kind": "match", "mode": 2, "map": "Ascent", "blue": 3, "red": 2,
		"bots": 0, "online": true, "players": 3, "max": 9, "party": "abc", "start": 1700000000, "version": "1.37.0"})
	if str(a.get("details")) != "Playing Capture the Flag on Ascent" or str(a.get("state")) != "Blue 3 – 2 Red" \
			or a.get("party", {}).get("size") != [3, 9] or str(a.assets.small_image) != "mode_ctf" \
			or str(a.assets.large_image) != "tracerfall" or int(a.timestamps.start) != 1700000000:
		return _fail("team match activity wrong: %s" % JSON.stringify(a))
	var sp: Dictionary = P.call("build_activity", {"kind": "match", "mode": 0, "map": "Towers", "score": 7, "bots": 5, "online": false})
	if str(sp.get("state")) != "Score 7 · Bots: 5" or sp.has("party"):
		return _fail("SP deathmatch activity wrong: %s" % JSON.stringify(sp))
	var gg: Dictionary = P.call("build_activity", {"kind": "match", "mode": 9, "map": "Arena", "rung": 4, "online": false})
	if str(gg.get("state")) != "Rung 4 / 16" or str(gg.assets.small_image) != "mode_gg":
		return _fail("Gun Game activity wrong: %s" % JSON.stringify(gg))
	for kv in [["menu", "In menus"], ["levels", "Browsing levels"], ["editor", "In the Maker editor"]]:
		var o: Dictionary = P.call("build_activity", {"kind": kv[0]})
		if str(o.get("details")) != kv[1] or o.has("state") or o.assets.has("small_image"):
			return _fail("%s activity wrong: %s" % [kv[0], JSON.stringify(o)])
	_log.append("status text ok")

	# ── 4. the protocol over a fake pipe, real scenes ─────────────────
	_st.set("discord_status", true)
	_st.set("master_url", "http://127.0.0.1:9")   # LEVELS browser: offline, fast
	_st.set("training", false)
	var fake := FakeDiscord.new(Ipc)
	var pr := _new_presence(fake, APP)
	change_scene_to_file("res://scenes/menu.tscn")
	if not await _until(_scene_is.bind("menu.tscn"), 8000):
		return _fail("menu never loaded")
	await _frames(5)
	if not await _tick_until_acts(pr, fake, 1):
		return _fail("no SET_ACTIVITY in menus (opens=%d sent=%d %s)" % [fake.opens, fake.sent.size(), str(pr.call("status"))])
	var hs := fake.ops(0)
	if hs.size() != 1 or int(hs[0][1].get("v", 0)) != 1 or str(hs[0][1].get("client_id", "")) != APP:
		return _fail("handshake wrong: %s" % str(hs))
	if int(fake.sent[0][0]) != 0:
		return _fail("first frame was not the handshake")
	var f1: Dictionary = fake.activities()[0]
	var act1: Dictionary = f1.args.activity
	if _details(f1) != "In menus" or int(f1.args.pid) != OS.get_process_id() or str(f1.get("nonce", "")) == "" \
			or str(act1.assets.large_image) != "tracerfall" or int(act1.timestamps.start) <= 0 \
			or not (act1.get("buttons", []) is Array and act1.buttons.size() == 1):
		return _fail("menu SET_ACTIVITY wrong: %s" % JSON.stringify(f1))
	var ponged := func() -> bool: return fake.ops(4).size() == 1 and bool(pr.call("status").connected)
	if not await _until(ponged, 3000):
		return _fail("PING not answered with PONG / not connected: %s" % str(pr.call("status")))
	# Unchanged status is not sent again.
	await _sleep(400)
	for _i in 5:
		pr.call("tick")
	await _sleep(300)
	if fake.activities().size() != 1:
		return _fail("unchanged status re-sent (%d)" % fake.activities().size())
	_log.append("handshake + menu + pong + dedupe")

	current_scene.call("_open_levels", "hot")
	await _frames(3)
	# Throttle: a change right after a send waits for the gap.
	pr.set("min_send_gap_ms", 1500)
	pr.set("_last_post", Time.get_ticks_msec())
	pr.call("tick")
	await _sleep(300)
	if fake.activities().size() != 1:
		return _fail("throttle ignored")
	if not await _tick_until_acts(pr, fake, 2):
		return _fail("no update for the LEVELS browser")
	if _details(_last_act(fake)) != "Browsing levels":
		return _fail("levels SET_ACTIVITY wrong: %s" % JSON.stringify(_last_act(fake)))
	pr.set("min_send_gap_ms", 250)
	_log.append("levels + throttle")

	_st.set("game_mode", 2)
	_st.set("map_index", 0)
	_st.set("custom_map_path", "")
	_st.set("bot_count", 2)
	change_scene_to_file("res://scenes/main.tscn")
	var in_match := func() -> bool: return _scene_is("main.tscn") and current_scene.get("player") != null
	if not await _until(in_match, 10000):
		return _fail("match never started")
	await _frames(30)
	if not await _tick_until_acts(pr, fake, 3):
		return _fail("no update for the match")
	var fm := _last_act(fake)
	var am: Dictionary = fm.args.activity
	if _details(fm) != "Playing Capture the Flag on Ascent" or not str(am.get("state", "")).begins_with("Blue ") \
			or not str(am.get("state", "")).contains("Bots: ") \
			or str(am.assets.get("small_image", "")) != "mode_ctf" or am.has("party"):
		return _fail("match SET_ACTIVITY wrong: %s" % JSON.stringify(fm))
	_log.append("match: %s / %s" % [_details(fm), str(am.get("state"))])
	# While you're dead the local soldier node is freed: no script error, score kept.
	var real_player: Variant = current_scene.get("player")
	var ghost := Node2D.new()
	ghost.free()
	current_scene.set("player", ghost)
	var dead: Dictionary = pr.call("facts_for", current_scene)
	_st.set("game_mode", 0)   # the free-for-all path reads your own score
	var dead_ffa: Dictionary = pr.call("facts_for", current_scene)
	_st.set("game_mode", 2)
	current_scene.set("player", real_player)
	if str(dead.get("kind")) != "match" or not dead.has("blue") or not dead_ffa.has("score"):
		return _fail("facts with a freed local soldier wrong: %s / %s" % [str(dead), str(dead_ffa)])

	change_scene_to_file("res://scenes/map_editor.tscn")
	if not await _until(_scene_is.bind("map_editor.tscn"), 8000):
		return _fail("editor never loaded")
	await _frames(5)
	if not await _tick_until_acts(pr, fake, 4):
		return _fail("no update for the editor")
	if _details(_last_act(fake)) != "In the Maker editor":
		return _fail("editor SET_ACTIVITY wrong: %s" % JSON.stringify(_last_act(fake)))
	_log.append("editor")

	# ── 5. the settings toggle ────────────────────────────────────────
	_st.set("discord_status", false)
	pr.call("refresh_enabled")
	var closed := func() -> bool: return fake.closes >= 1 and not bool(pr.call("status").connected)
	if not await _until(closed, 3000):
		return _fail("toggle off did not close the pipe")
	var n_acts := fake.activities().size()
	pr.call("tick")
	await _sleep(300)
	if fake.activities().size() != n_acts or fake.opens != 1:
		return _fail("disabled presence still talks to Discord")
	_st.set("discord_status", true)
	pr.call("refresh_enabled")
	if not await _tick_until_acts(pr, fake, n_acts + 1):
		return _fail("toggle on did not reconnect")
	if fake.opens != 2 or fake.ops(0).size() != 2:
		return _fail("reconnect without a new handshake (opens=%d)" % fake.opens)
	_log.append("toggle off closes / on reconnects")
	pr.queue_free()
	await _frames(2)

	# ── 6. wrong application id ───────────────────────────────────────
	var bad := FakeDiscord.new(Ipc)
	bad.refuse = true
	var bp := _new_presence(bad, "42")
	bp.call("tick")
	var refused := func() -> bool: return bool(bp.call("status").bad_id)
	if not await _until(refused, 3000):
		return _fail("Invalid Client ID not detected: %s" % str(bp.call("status")))
	await _sleep(400)
	for _i in 3:
		bp.call("tick")
	await _sleep(300)
	if bad.opens != 1 or not bad.activities().is_empty():
		return _fail("kept asking with a refused id (opens=%d)" % bad.opens)
	bp.queue_free()
	_log.append("refused id stops")

	# ── 7. the real Linux transport over a Unix socket ────────────────
	if OS.get_name() == "Linux" and ClassDB.class_exists("UDSServer"):
		var r: String = await _uds_case()
		if r != "":
			return _fail(r)
	else:
		_log.append("UDS case skipped (%s)" % OS.get_name())

	if Transport.WindowsPipe.pipe_paths()[0] != "\\\\?\\pipe\\discord-ipc-0":
		return _fail("Windows pipe path wrong")
	_finish(true, "all cases")


func _uds_case() -> String:
	# Short path: a Unix socket path must fit in 108 bytes.
	var dir: String = "/tmp/tf-discord-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var sock := dir.path_join("discord-ipc-0")
	DirAccess.remove_absolute(sock)
	var srv: Object = ClassDB.instantiate("UDSServer")
	if int(srv.call("listen", sock)) != OK:
		return "UDSServer.listen(%s) failed" % sock
	var node := _new_presence(null, APP)
	node.set("transport_factory", func() -> RefCounted:
		var t: RefCounted = Transport.UnixSocket.new()
		t.set("dirs_override", PackedStringArray([dir]))
		return t)
	node.call("tick")
	var peer: Object = null
	var buf := PackedByteArray()
	var got: Array = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < GL.wait_ms(6000):
		if peer == null and bool(srv.call("is_connection_available")):
			peer = srv.call("take_connection")
		if peer != null:
			peer.call("poll")
			var av := int(peer.call("get_available_bytes"))
			if av > 0:
				buf.append_array(peer.call("get_partial_data", av)[1])
				var res: Array = Ipc.split_frames(buf)
				buf = buf.slice(int(res[1]))
				for fr in res[0]:
					got.append(fr)
					if int(fr[0]) == 0:
						peer.call("put_data", Ipc.encode(1, {"cmd": "DISPATCH", "evt": "READY", "data": {"user": {"username": "uds"}}}))
					elif int(fr[0]) == 1:
						peer.call("put_data", Ipc.encode(1, {"cmd": "SET_ACTIVITY", "nonce": fr[1].get("nonce"), "evt": null, "data": {}}))
		if got.size() >= 2 and int(node.call("status").sent) >= 1:
			break
		await process_frame
	var s: Dictionary = node.call("status")
	node.queue_free()
	await _frames(2)
	if peer != null:
		peer.call("disconnect_from_host")
	srv.call("stop")
	DirAccess.remove_absolute(sock)
	DirAccess.remove_absolute(dir)
	if got.size() < 2 or int(got[0][0]) != 0 or str(got[0][1].get("client_id", "")) != APP \
			or str(got[1][1].get("cmd", "")) != "SET_ACTIVITY":
		return "UDS: frames wrong %s" % str(got)
	if not bool(s.connected) or int(s.sent) < 1 or str(s.where) != sock:
		return "UDS: status wrong %s" % str(s)
	_log.append("unix socket transport (%s)" % sock)
	return ""
