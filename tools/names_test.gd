extends SceneTree
## Gate F `names` (#318 reserved names + #315 new-player protection).
##   godot --headless --fixed-fps 60 -s tools/names_test.gd -- --master=http://127.0.0.1:PORT
## --master = tools/names_fake_master.py (or a real master with /names).
## Names: name keys (case / leet / clan tag), the impostor name, reply
## parsing, then the Settings > Game "RESERVE MY NAME" row end to end:
## free -> reserved -> another profile sees it taken (and can't reserve it)
## -> offline when the master can't be reached.
## Catch-up: the streak rules (starts after 3 deaths without a kill, grows,
## caps, goes away after a kill, team kills don't count), off for bots / in
## Gun Game / when the setting is off / for self-damage; then in a real
## match the hit path takes the cut (HostHits.damage on the player).

const GL = preload("res://tools/gate_load.gd")

var _st: Node = null
var _saved := {}
var _done := false
var _log: Array = []
var _master := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--master="):
			_master = a.substr(9)
	_run()


func _process(_d: float) -> bool:
	if not _done and Time.get_ticks_msec() > GL.wait_ms(100000):
		_finish(false, "timed out after: " + " | ".join(_log))
	return false


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _until(cond: Callable, ms: int = 15000) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > GL.wait_ms(ms):
			return false
		await process_frame
	return true


func _fail(msg: String) -> void:
	_finish(false, msg)


func _finish(ok: bool, msg: String) -> void:
	if _done:
		return
	_done = true
	if _st != null:
		for k in _saved:
			_st.set(k, _saved[k])
		_st.save()
	print("NAMES-TEST %s %s | %.1f s" % ["ok" if ok else "FAIL", msg, Time.get_ticks_msec() / 1000.0])
	quit(0 if ok else 1)


func _soldier(nm: String, bot: bool) -> Node:
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar display_name := \"\"\n" + ("var bot_id := 7\n" if bot else "")
	gs.reload()
	var n: Node = gs.new()
	n.set("display_name", nm)
	return n


func _run() -> void:
	await _frames(2)
	while root.get_node_or_null("Settings") == null:
		await process_frame
	_st = root.get_node("Settings")
	for k in ["player_name", "profile_id", "master_url", "catchup", "game_mode", "map_index", "custom_map_path", "bot_count", "clan_tag"]:
		_saved[k] = _st.get(k)
	if not await _names_units():
		return
	if not await _names_panel():
		return
	if not _catchup_units():
		return
	if not await _catchup_match():
		return
	_finish(true, " | ".join(_log))


func _names_units() -> bool:
	var NG = load("res://scripts/name_guard.gd")
	var NA = load("res://scripts/names_api.gd")
	for c in [["Bob", "bob"], ["B0B", "bob"], ["b.o.b", "bob"], ["«ABC» Bob", "bob"], ["Sn1p3r", "sniper"]]:
		if NG.key_of(c[0]) != c[1]:
			_fail("key_of(%s) = %s" % [c[0], NG.key_of(c[0])])
			return false
	var h := "ab".repeat(32)
	var nm: String = NG.impostor_name(h, 5)
	if not nm.begins_with("Player") or nm.length() != 10 or NG.impostor_name(h, 9) != nm or NG.impostor_name("cd".repeat(32), 5) == nm:
		_fail("impostor name %s" % nm)
		return false
	var r: Dictionary = NA.parse_reply("check", {"status": "taken", "display": "Bob"})
	if r["state"] != "taken" or r["taken_by"] != "Bob" or str(r["text"]) == "":
		_fail("parse taken %s" % str(r))
		return false
	if NA.parse_reply("reserve", {"status": "offensive"})["state"] != "invalid" or NA.parse_reply("reserve", {"status": "cooldown", "cooldown_s": 7200})["text"].find("2") < 0:
		_fail("parse reserve")
		return false
	_log.append("units ok (%s)" % nm)
	return true


func _names_panel() -> bool:
	if _master == "":
		_log.append("panel skipped (no --master)")
		return true
	var NA = load("res://scripts/names_api.gd")
	NA.timeout_override = 0.0
	NA.url_override = _master
	var id_a := "a1".repeat(16)
	var id_b := "b2".repeat(16)
	_st.player_name = "Gatekeeper"
	_st.profile_id = id_a
	_st.clan_tag = ""
	change_scene_to_file("res://scenes/menu.tscn")
	if not await _until(func() -> bool: return current_scene != null and current_scene.get("_settings_panel") != null):
		_fail("menu didn't load")
		return false
	await _frames(5)
	var m := current_scene
	m._open_settings()
	await _frames(3)
	var sp: Node = m._settings_panel
	for hb in sp.find_children("*", "Button", true, false):
		if (hb as Button).text.strip_edges().ends_with("GAME"):
			(hb as Button).pressed.emit()   # the card builds its body when opened
			break
	await _frames(3)
	var btn: Button = sp.find_child("ReserveName", true, false)
	var lbl: Label = sp.find_child("ReserveStatus", true, false)
	if btn == null or lbl == null:
		_fail("no RESERVE MY NAME row in Settings")
		return false
	# Headless + url_override: the panel asked once on build.
	if not await _until(func() -> bool: return str(sp.names_state) == "free"):
		_fail("status before reserving: '%s' %s" % [sp.names_state, lbl.text])
		return false
	_log.append("free")
	btn.pressed.emit()
	if not await _until(func() -> bool: return str(sp.names_state) == "reserved"):
		_fail("reserve: '%s' %s" % [sp.names_state, lbl.text])
		return false
	if btn.text.to_upper().find("RESERVED") < 0:
		_fail("button after reserving: %s" % btn.text)
		return false
	_log.append("reserved")
	# Another player, same name (other spelling) -> taken.
	_st.profile_id = id_b
	_st.player_name = "G4tekeeper"
	sp._names_refresh()
	if not await _until(func() -> bool: return str(sp.names_state) == "taken"):
		_fail("other profile check: '%s' %s" % [sp.names_state, lbl.text])
		return false
	sp.names_state = ""
	btn.pressed.emit()
	if not await _until(func() -> bool: return str(sp.names_state) == "taken"):
		_fail("other profile reserve: '%s' %s" % [sp.names_state, lbl.text])
		return false
	_log.append("taken")
	# Unreachable master -> offline.
	NA.url_override = "http://127.0.0.1:9"
	NA.timeout_override = 4.0
	sp.names_api.queue_free()
	sp.names_api = null
	await _frames(2)
	sp._names_refresh()
	if not await _until(func() -> bool: return str(sp.names_state) == "offline", 20000):
		_fail("offline: '%s' %s" % [sp.names_state, lbl.text])
		return false
	_log.append("offline")
	NA.url_override = ""
	NA.timeout_override = -1.0
	return true


func _catchup_units() -> bool:
	var C = load("res://scripts/catchup.gd")
	var cu: Node = C.new()
	cu.set("main", Node.new())
	root.add_child(cu)
	C.force_sp = true
	_st.catchup = true
	_st.game_mode = 0   # DM
	var newbie := _soldier("Newbie", false)
	var vet := _soldier("Vet", false)
	var bot := _soldier("Bot 1", true)
	var want := [0.0, 0.0, 0.0, 0.10, 0.15, 0.20, 0.20]
	for i in range(1, 7):
		cu.on_kill("Vet", "Newbie", 1, 2)
		if absf(cu.cut_for(newbie) - want[i]) > 0.001:
			_fail("cut after %d deaths: %.2f" % [i, cu.cut_for(newbie)])
			return false
	if absf(cu.scale(newbie, 50.0, "Vet") - 40.0) > 0.01 or cu.scale(newbie, 50.0, "Newbie") != 50.0 or cu.scale(vet, 50.0, "Newbie") != 50.0:
		_fail("scale: %.1f / self %.1f / vet %.1f" % [cu.scale(newbie, 50.0, "Vet"), cu.scale(newbie, 50.0, "Newbie"), cu.scale(vet, 50.0, "Newbie")])
		return false
	_st.catchup = false
	if cu.cut_for(newbie) != 0.0:
		_fail("still on with the setting off")
		return false
	_st.catchup = true
	_st.game_mode = 9   # Gun Game
	if cu.cut_for(newbie) != 0.0:
		_fail("on in Gun Game")
		return false
	_st.game_mode = 0
	for i in 4:
		cu.on_kill("Newbie", "Bot 1", 2, 3)
	if cu.cut_for(newbie) != 0.0:
		_fail("still on after a kill")
		return false
	if cu.cut_for(bot) != 0.0:
		_fail("bot got catch-up")
		return false
	C.bots_too = true
	var bot_cut: float = cu.cut_for(bot)
	C.bots_too = false
	if bot_cut <= 0.0:
		_fail("bots_too (measuring hook) didn't apply")
		return false
	# Team kill (team mode, same team) doesn't end it; a suicide adds a death.
	_st.game_mode = 1   # TDM
	for i in 3:
		cu.on_kill("Vet", "Newbie", 1, 2)
	cu.on_kill("Newbie", "Mate", 2, 2)
	if cu.cut_for(newbie) <= 0.0:
		_fail("team kill ended catch-up")
		return false
	cu.on_kill("Newbie", "Newbie", 2, 2)
	if absf(cu.cut_for(newbie) - 0.15) > 0.001:
		_fail("suicide count: %.2f" % cu.cut_for(newbie))
		return false
	C.force_sp = false
	if cu.cut_for(newbie) != 0.0:
		_fail("on in single player")
		return false
	cu.queue_free()
	_st.game_mode = 0
	_log.append("catchup rules ok")
	return true


func _catchup_match() -> bool:
	var C = load("res://scripts/catchup.gd")
	C.force_sp = true
	_st.catchup = true
	_st.game_mode = 0
	_st.map_index = 0
	_st.custom_map_path = ""
	_st.bot_count = 0
	root.get_node("Net").set_singleplayer()
	change_scene_to_file("res://scenes/main.tscn")
	if not await _until(func() -> bool:
			return current_scene != null and current_scene.get("_catchup") != null and current_scene.get("player") != null \
				and is_instance_valid(current_scene.get("player"))):
		_fail("match didn't start")
		return false
	await _frames(10)
	var m := current_scene
	var p: Node = m.player
	p.set("ceasefire_t", 0.0)
	var HH = load("res://scripts/host_hits.gd")
	HH.damage(p, 30.0, "Ghost", "AK-74", 3)
	var plain := 100.0 - float(p.health)
	m._catchup.streak[str(p.display_name)] = 5
	var h0 := float(p.health)
	HH.damage(p, 30.0, "Ghost", "AK-74", 3)
	var cut := h0 - float(p.health)
	C.force_sp = false
	if absf(plain - 30.0) > 0.01 or absf(cut - 24.0) > 0.01 or int(m._catchup.reduced_hits) != 1:
		_fail("match hit path: plain %.1f, with catch-up %.1f (want 30 / 24), cut hits %d" % [plain, cut, int(m._catchup.reduced_hits)])
		return false
	_log.append("match hit path 30 -> 24")
	return true
