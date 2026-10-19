extends SceneTree
## Level sharing (#288), gate F: the LEVELS browser end to end against a
## level server — by default the in-process fake (tools/levels_fake_master.gd),
## or a real master with --master=http://127.0.0.1:PORT (same assertions).
## Seeds three levels with likes / plays, then: every sort tab orders them,
## search by title and by share code, the course-code box, LIKE on / off,
## BOOKMARK survives a settings reload and lists (also offline), the offline
## message, node count flat over open / close, the editor's PUBLISH round
## trip (+ the client-side title filter), the editor's LEVELS overlay, and
## PLAY starting a bot match on the level (with the play report counted).
##   godot --headless --fixed-fps 60 -s tools/levels_test.gd [-- --master=URL]

var _log: Array = []
var _st: Node = null
var _saved := {}
var _fake: Node = null
var _api: Node = null
var _tok := ""
var _ids := {}       # "A"/"B"/"C"/"D" -> level id
var _codes := {}
var _titles := {}


var _done := false


func _initialize() -> void:
	_run()


# Watchdog: a script error stops the coroutine — report instead of hanging.
func _process(_d: float) -> bool:
	if not _done and Time.get_ticks_msec() > 85000:
		_finish(false, "timed out after: " + " | ".join(_log))
	return false


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


## Wait until cond() is true, at least `frames` frames and at least 15 s of
## wall time (headless --fixed-fps runs frames faster than real time; HTTP
## doesn't). A wall-clock watchdog (80 s, under the gate's 90) fails the run
## rather than letting a stuck step hang it.
func _until(cond: Callable, frames: int = 600) -> bool:
	var t0 := Time.get_ticks_msec()
	var n := 0
	while not cond.call():
		if Time.get_ticks_msec() > 80000:
			_fail("timed out after: " + " | ".join(_log))
			return false
		if n >= frames and Time.get_ticks_msec() - t0 > 15000:
			return false
		n += 1
		await process_frame
	return true


func _fail(msg: String) -> bool:
	_finish(false, msg)
	return false


func _finish(ok: bool, msg: String) -> void:
	if _done:
		return
	_done = true
	if _st != null:
		for k in _saved:
			_st.set(k, _saved[k])
		_st.save()
	print("LEVELS-TEST %s %s | %.1f s" % ["ok" if ok else "FAIL", msg, Time.get_ticks_msec() / 1000.0])
	quit(0 if ok else 1)


# Raw request (likes / plays from made-up players, checks): -> [code, dict]
func _http(method: int, path: String, body: Variant = null) -> Array:
	var h := HTTPRequest.new()
	h.timeout = 10.0 if _fake != null else 0.0
	root.add_child(h)
	var url := str(_st.master_url).trim_suffix("/") + path
	if body == null:
		h.request(url)
	else:
		h.request(url, PackedStringArray(["Content-Type: application/json"]), method, JSON.stringify(body))
	var r: Array = await h.request_completed
	h.queue_free()
	var d = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	return [int(r[1]), d if d is Dictionary else {}, int(r[0])]


func _upload(key: String, title: String, m: Dictionary) -> bool:
	var r: Array = await _http(HTTPClient.METHOD_POST, "/levels/upload", {"title": title, "author": "Gate Bot", "map": m})
	if r[0] != 200 or str(r[1].get("code", "")) == "":
		_fail("upload %s: %s" % [title, str(r)])
		return false
	_ids[key] = str(r[1]["id"])
	_codes[key] = str(r[1]["code"])
	_titles[key] = title
	return true


func _map(extra: Dictionary) -> Dictionary:
	var m := {"name": "x", "platforms": [{"p": [0, 1500], "s": [2400, 60]}], "player_spawn": [100, 1400],
		"bot_spawns": [[600, 1400], [1800, 1400]]}
	m.merge(extra, true)
	return m


func _order(panel: Node) -> String:
	var s := ""
	for e in panel.levels:
		for k in _ids:
			if _ids[k] == str(e.get("id", "")):
				s += k
	return s


func _run():
	await _frames(2)
	while root.get_node_or_null("Settings") == null:
		await process_frame
	_st = root.get_node("Settings")
	# Client-side name filter: same verdicts as the server's filter.go tests.
	var nf = load("res://scripts/name_filter.gd")
	var cases := {"Fuck Valley": "**** Valley", "f u c k this": "* * * * this", "FUUUUCK": "*******",
		"a$$hole arena": "******* arena", "Classic Ass": "Classic ***", "boooobs": "*******",
		"Bullshit Bridge": "******** Bridge", "Cockpit Run": "Cockpit Run", "Grape Escape": "Grape Escape",
		"Title Fight": "Title Fight", "Spicy Map": "Spicy Map", "Bob's Base": "Bob's Base",
		"Niigata Docks": "Niigata Docks", "Assault Course": "Assault Course"}
	for c in cases:
		if nf.mask(c) != cases[c]:
			return _fail("name filter: '%s' -> '%s', want '%s'" % [c, nf.mask(c), cases[c]])
	_log.append("filter ok")
	for k in ["master_url", "level_bookmarks", "game_mode", "custom_map_path", "map_index"]:
		_saved[k] = _st.get(k)
	_st.level_bookmarks = []
	_st.game_mode = 0
	var master := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--master="):
			master = a.substr(9)
	if master != "":
		# --fixed-fps runs frames faster than real time and HTTPRequest
		# timeouts count game time: no timeouts against a real server (the
		# wall-clock watchdog still ends a stuck run).
		load("res://scripts/levels_api.gd").timeout_override = 0.0
	if master == "":
		_fake = load("res://tools/levels_fake_master.gd").new()
		_fake.name = "FakeLevelServer"
		root.add_child(_fake)
		if not _fake.start():
			return _fail("fake server could not listen")
		master = _fake.url()
	_st.master_url = master
	_st.save()
	_log.append("server=%s" % ("fake" if _fake != null else "real"))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_tok = "Q%d" % (rng.randi() % 9000 + 1000)

	# ── Seed: A (CTF + DOM), B, C (polygons); likes B x2 + A x1, plays C x3.
	if not await _upload("A", "zz Alpha Ridge " + _tok, _map({"ctf_flags": [[80, 1450], [2300, 1450]], "dom_points": [[1200, 1400]]})):
		return
	await _frames(2)
	if not await _upload("B", "zz Bravo Bunker " + _tok, _map({"ladders": [{"x": 900, "y": 1300, "w": 20, "h": 200}]})):
		return
	await _frames(2)
	if not await _upload("C", "zz Charlie Caves " + _tok, {"name": "c", "platforms": [], "world": {"w": 3000, "h": 1600},
			"player_spawn": [200, 900], "bot_spawns": [[900, 900]],
			"polys": [{"points": [0, 1000, 3000, 1000, 3000, 1300, 0, 1300], "color": [0.4, 0.5, 0.3, 1]},
				{"points": [800, 700, 1400, 700, 1100, 1000], "vc": ["806040ff", "806040ff", "604020ff"]}]}):
		return
	var pids := ["11111111111111111111111111111111", "22222222222222222222222222222222", "33333333333333333333333333333333"]
	for i in 2:
		await _http(HTTPClient.METHOD_POST, "/levels/like", {"id": _ids["B"], "pid": pids[i], "like": true})
	await _http(HTTPClient.METHOD_POST, "/levels/like", {"id": _ids["A"], "pid": pids[2], "like": true})
	for p in pids:
		await _http(HTTPClient.METHOD_POST, "/levels/play", {"id": _ids["C"], "pid": p})
	var again: Array = await _http(HTTPClient.METHOD_POST, "/levels/play", {"id": _ids["C"], "pid": pids[0]})
	if bool(again[1].get("counted", true)):
		return _fail("a second play the same day counted: %s" % str(again))

	# ── Browser from the main menu.
	change_scene_to_file("res://scenes/menu.tscn")
	if not await _until(func() -> bool: return current_scene != null and current_scene.get("_menu_root") != null, 300):
		return _fail("menu never loaded")
	await _frames(10)
	var menu: Node = current_scene
	var btn := menu.find_child("LevelsButton", true, false)
	if btn == null:
		return _fail("no LEVELS button on the main menu")
	(btn as Button).pressed.emit()
	var pn: Node = menu.get("_levels_panel")
	if pn == null or not pn.visible:
		return _fail("LEVELS button didn't open the browser")
	var want := {"likes": "BAC", "plays": "CBA", "new": "CBA", "hot": "BCA"}
	var got := []
	for t in ["likes", "plays", "new", "hot"]:
		pn.set_tab(t)
		if not await _until(func() -> bool: return pn.loaded >= 0):
			return _fail("tab %s never loaded: %s" % [t, pn._status.text])
		var o := _order(pn)
		got.append("%s=%s" % [t, o])
		if o != want[t]:
			return _fail("tab %s order %s, want %s" % [t, o, want[t]])
	_log.append("tabs " + " ".join(got))
	# Cards draw their outline.
	var card: Node = pn._cards.get(_ids["C"])
	var th: Node = card.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n.get("tris") != null)[0] if card != null else null
	if th == null or int(th.tris) < 2:
		return _fail("card thumbnail has no geometry (%s)" % str(th.tris if th != null else "none"))

	# Search: title, then share code typed sloppily.
	pn.set_tab("search")
	pn._search.text = "bravo bunker " + _tok.to_lower()
	pn.refresh_data()
	if not await _until(func() -> bool: return pn.loaded >= 0) or _order(pn) != "B":
		return _fail("search by title: %s" % _order(pn))
	pn._search.text = _codes["A"].replace("-", " ").to_lower()
	pn.refresh_data()
	if not await _until(func() -> bool: return pn.loaded >= 0) or not _order(pn).begins_with("A"):
		return _fail("search by code %s: %s" % [pn._search.text, _order(pn)])
	_log.append("search ok")
	# Course-code box.
	pn.open_code(_codes["C"].replace("-", "").to_lower())
	if not await _until(func() -> bool: return str(pn.selected.get("id", "")) == _ids["C"]):
		return _fail("course code %s never opened: %s" % [_codes["C"], pn._status.text])
	_log.append("code ok")

	# LIKE on / off (this install hasn't liked A; A has 1 like).
	pn.set_tab("likes")
	await _until(func() -> bool: return pn.loaded >= 0)
	pn.select(_ids["A"])
	if bool(pn.selected.get("liked", false)) or int(pn.selected.get("likes", -1)) != 1:
		return _fail("A before like: %s" % str(pn.selected))
	pn.last_like = {}
	pn.toggle_like()
	if not await _until(func() -> bool: return not pn.last_like.is_empty()):
		return _fail("like never answered")
	if not bool(pn.last_like.get("liked", false)) or int(pn.last_like.get("likes", 0)) != 2 or pn._d_like.text != tr("LIKED"):
		return _fail("like on: %s button=%s" % [str(pn.last_like), pn._d_like.text])
	pn.last_like = {}
	pn.toggle_like()
	if not await _until(func() -> bool: return not pn.last_like.is_empty()):
		return _fail("unlike never answered")
	if bool(pn.last_like.get("liked", true)) or int(pn.last_like.get("likes", 0)) != 1:
		return _fail("like off: %s" % str(pn.last_like))
	_log.append("like toggle ok")

	# BOOKMARK: saved with the settings, survives a reload, lists.
	pn.select(_ids["B"])
	pn.toggle_bookmark()
	_st.level_bookmarks = []
	_st.load_settings()
	if _st.level_bookmarks.size() != 1 or str(_st.level_bookmarks[0].get("id", "")) != _ids["B"]:
		return _fail("bookmark not persisted: %s" % str(_st.level_bookmarks))
	pn.set_tab("bookmarks")
	if not await _until(func() -> bool: return pn.loaded >= 0) or _order(pn) != "B":
		return _fail("bookmarks tab: %s" % _order(pn))
	_log.append("bookmark persisted + listed")

	# Offline: friendly line; bookmarks still list from the saved copy.
	_st.master_url = "http://127.0.0.1:9"
	pn.set_tab("hot")
	if not await _until(func() -> bool: return pn.loaded >= 0, 900):
		return _fail("offline load never settled")
	var off_text: String = load("res://scripts/levels_api.gd").offline_text()
	if not pn.offline or pn._status.text != off_text:
		return _fail("offline message: '%s'" % pn._status.text)
	pn.set_tab("bookmarks")
	if not await _until(func() -> bool: return pn.loaded >= 0, 900) or _order(pn) != "B":
		return _fail("offline bookmarks: %s (%s)" % [_order(pn), pn._status.text])
	_st.master_url = master
	_log.append("offline ok")

	# Node count flat across open / close.
	pn.close()
	await _frames(4)
	var counts: Array = []
	for i in 3:
		menu._open_levels("hot")
		if not await _until(func() -> bool: return pn.loaded > 0):
			return _fail("reopen %d never loaded" % i)
		pn.select(_ids["A"])
		await _frames(3)
		pn.close()
		await _frames(4)
		counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	if counts[0] != counts[1] or counts[1] != counts[2]:
		return _fail("node count grows across open/close: %s" % str(counts))
	_log.append("nodes flat %s" % str(counts))

	# ── Editor: PUBLISH round trip + the client filter + the LEVELS overlay.
	change_scene_to_file("res://scenes/map_editor.tscn")
	if not await _until(func() -> bool: return current_scene != null and current_scene.get("_map") != null and current_scene.get_node_or_null("UI") != null, 300):
		return _fail("editor never loaded")
	await _frames(5)
	var ed: Node = current_scene
	if ed.find_child("PublishButton", true, false) == null or ed.find_child("LevelsButton", true, false) == null:
		return _fail("editor toolbar lacks Publish / Levels")
	ed.set("_map", {"name": "d", "platforms": [{"p": Vector2(0, 1700), "s": Vector2(1500, 50)}, {"p": Vector2(1800, 1500), "s": Vector2(600, 40)}],
		"player_spawn": Vector2(100, 1600), "bot_spawns": [Vector2(1900, 1400)], "ladders": []})
	(ed.find_child("PublishButton", true, false) as Button).pressed.emit()
	var dlg: Node = ed.get_node("UI").get_node_or_null("PublishDialog")
	if dlg == null or not dlg.visible:
		return _fail("Publish didn't open the dialog")
	var reqs_before: int = dlg.api.requests
	dlg.publish("Sh1t Hole")
	if str(dlg.last_reply.get("error", "")) != "filtered" or dlg.api.requests != reqs_before:
		return _fail("filtered title got through: %s" % str(dlg.last_reply))
	dlg.last_reply = {}
	_titles["D"] = "zz Delta Drop " + _tok
	dlg.publish(_titles["D"])
	if not await _until(func() -> bool: return not dlg.last_reply.is_empty()):
		return _fail("publish never answered")
	var code := str(dlg.last_reply.get("code", ""))
	if code == "" or dlg._code.text != code or not dlg._code.visible:
		return _fail("publish reply: %s" % str(dlg.last_reply))
	_ids["D"] = str(dlg.last_reply.get("id", ""))
	var back: Array = await _http(HTTPClient.METHOD_GET, "/levels/get?code=" + code.replace("-", "").to_lower())
	if back[0] != 200 or (back[1].get("map", {}).get("platforms", []) as Array).size() != 2 or str(back[1].get("level", {}).get("title", "")) != _titles["D"]:
		return _fail("published level doesn't round-trip: %s" % str(back).left(200))
	if str(_st.level_bookmarks[0].get("id", "")) != _ids["D"]:
		return _fail("own level not bookmarked")
	_log.append("publish %s" % code)
	dlg.visible = false
	(ed.find_child("LevelsButton", true, false) as Button).pressed.emit()
	var ov: Node = ed.get_node("UI").get_node_or_null("LevelsBrowser")
	if ov == null or not await _until(func() -> bool: return ov.loaded > 0) or not _order(ov).contains("D"):
		return _fail("editor LEVELS overlay: %s" % (_order(ov) if ov != null else "missing"))
	ov.close()
	_log.append("editor overlay ok")

	# ── PLAY from the menu: a bot match on the level, play counted.
	change_scene_to_file("res://scenes/menu.tscn")
	if not await _until(func() -> bool: return current_scene != null and current_scene.get("_menu_root") != null, 300):
		return _fail("menu never came back")
	await _frames(10)
	menu = current_scene
	menu._open_levels("new")
	pn = menu.get("_levels_panel")
	if not await _until(func() -> bool: return pn.loaded > 0):
		return _fail("new tab before play never loaded")
	pn.select(_ids["A"])
	if pn.selected_mode() != 2:
		return _fail("A (built for CTF) picked mode %d" % pn.selected_mode())
	(pn.find_child("Play", true, false) as Button).pressed.emit()
	if not await _until(func() -> bool: return current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn" and current_scene.get("_map") is Dictionary and not (current_scene.get("_map") as Dictionary).is_empty(), 900):
		return _fail("PLAY never started the match")
	await _frames(30)
	var mp: Dictionary = current_scene.get("_map")
	if str(mp.get("name", "")) != _titles["A"] or (mp.get("platforms", []) as Array).size() != 1 or int(_st.game_mode) != 2:
		return _fail("match map %s platforms=%d mode=%d" % [str(mp.get("name")), (mp.get("platforms", []) as Array).size(), int(_st.game_mode)])
	var played: Array = await _http(HTTPClient.METHOD_GET, "/levels?ids=" + _ids["A"])
	var pl: Array = played[1].get("levels", [])
	if pl.is_empty() or int(pl[0].get("plays", 0)) != 1:
		return _fail("play report not counted: %s" % str(played).left(200))
	_log.append("play -> match on %s (CTF), plays=1" % _titles["A"])
	_finish(true, " | ".join(_log))
