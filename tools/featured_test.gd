extends SceneTree
## FEATURED levels (#295), gate F `ft` (FEATURED-TEST):
##   godot --headless --fixed-fps 60 -s tools/featured_test.gd [-- --only=slug,slug] [--secs=N]
## 1. Data: every level in featured_levels.gd loads, carries its maker block,
##    decompiles + recompiles to the same geometry, validates with no errors or
##    warnings for each listed mode, passes tools/map_audit.py, and its runtime
##    nav graph (nav_builder.gd, pads simulated) routes every objective leg of
##    its modes: CTF each team spawn <-> enemy flag + enemy flag -> home, DOM /
##    HTF / INF / Rambo each objective <-> every team spawn.
## 2. UI, offline (master pointed at a dead port): LEVELS opens on FEATURED with
##    every level carded (outline drawn) and no server request; the detail has
##    EDIT A COPY instead of code / like / bookmark and the level's modes; PLAY
##    sets a user:// copy + the first mode; HOST ONLINE reaches the Host screen;
##    EDIT A COPY opens the Maker with an unsaved, identical copy; the Maker's
##    New map sheet starts from Empty / Starter / a featured level; the editor's
##    LEVELS overlay edits a copy in place.
## 3. The new strings translate (es / pt_BR / de / fr).
## 4. Bots, per level, in its first mode (short): graph adopted, bots travel,
##    few hazard deaths, objective progress (CTF: each team pushes halfway to the
##    enemy flag; DOM: a point taken; HTF: flag grabbed or reached), pads used
##    where the level has them, a vehicle boarded where it has them.

const MODE_IDX := {"dm": 0, "tdm": 1, "ctf": 2, "inf": 3, "htf": 4, "rm": 5, "pm": 6, "dom": 7, "br": 8, "gg": 9}
const NEW_KEYS := ["FEATURED", "EDIT A COPY", "Hand-built", "NEW MAP", "Start from:", "Empty", "Starter", "START",
	"%s copy", "Editing a copy of %s.", "No featured levels found.",
	"Open this level in the Map Editor as a new map you can change and save.",
	"Just the world: build everything yourself.", "Some ground, two bases and two bridges to begin with."]

var FL = null
var B = null
var IO = null
var _log: Array = []
var _st: Node = null
var _saved := {}
var _done := false
var _only: Array = []
var _secs := 22.0
var _deadline := 400000


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = Array(a.substr(7).split(",", false))
		elif a.begins_with("--secs="):
			_secs = float(a.substr(7))
	_run()


func _process(_d: float) -> bool:
	if not _done and Time.get_ticks_msec() > _deadline:
		_finish(false, "timed out after: " + " | ".join(_log))
	return false


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _until(cond: Callable, frames: int = 600) -> bool:
	var n := 0
	while not cond.call():
		if n >= frames or _done:
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
	TranslationServer.set_locale("en")
	print("FEATURED-TEST %s %s | %.1f s" % ["ok" if ok else "FAIL", msg, Time.get_ticks_msec() / 1000.0])
	quit(0 if ok else 1)


func _slugs() -> Array:
	var out: Array = []
	for s in FL.slugs():
		if _only.is_empty() or _only.has(s):
			out.append(s)
	return out


func _run() -> void:
	await _frames(2)
	while root.get_node_or_null("Settings") == null:
		await process_frame
	_st = root.get_node("Settings")
	for k in ["master_url", "game_mode", "custom_map_path", "bot_count", "vehicles", "map_index", "level_bookmarks"]:
		_saved[k] = _st.get(k)
	FL = load("res://scripts/featured_levels.gd")
	B = load("res://scripts/maker/maker_build.gd")
	IO = load("res://scripts/map_io.gd")
	if FL.LEVELS.size() != 8:
		return _fail("expected 8 featured levels, catalog has %d" % FL.LEVELS.size())
	for s in _slugs():
		if not _check_data(s):
			return
	_log.append("data ok (%d levels)" % _slugs().size())
	if not _check_i18n():
		return
	if _only.is_empty():
		if not await _check_ui():
			return
	for s in _slugs():
		if not await _check_bots(s):
			return
	_finish(true, " | ".join(_log))


# ── 1. data ──────────────────────────────────────────────────────────────────

func _ok_path(nav, a: Vector2, b: Vector2) -> bool:
	var p: PackedVector2Array = nav.path(a, b)
	return p.size() > 0 and p[p.size() - 1].distance_to(b) < 260.0


func _check_data(slug: String) -> bool:
	var meta: Dictionary = FL.meta(slug)
	var path: String = FL.path(slug)
	if not FileAccess.file_exists(path):
		return _fail("%s: %s missing" % [slug, path])
	var m: Dictionary = FL.load_map(slug)
	if m.is_empty() or str(m.get("name", "")) != str(meta["title"]) or not B.is_maker(m):
		return _fail("%s: bad map (name %s, maker %s)" % [slug, str(m.get("name", "")), str(B.is_maker(m))])
	if str(m["maker"].get("theme", "")) != str(meta["theme"]):
		return _fail("%s: theme %s, catalog says %s" % [slug, str(m["maker"].get("theme")), str(meta["theme"])])
	# Decompile (EDIT A COPY) -> compile again: the same geometry.
	var src: Dictionary = FL.source(slug)
	var c2: Dictionary = B.compile(src)
	for k in ["polys", "collision", "hazards", "jump_pads"]:
		if (c2.get(k, []) as Array).size() != (m.get(k, []) as Array).size():
			return _fail("%s: %s %d after a decompile + compile, file has %d" % [slug, k, (c2.get(k, []) as Array).size(), (m.get(k, []) as Array).size()])
	for k in str(meta["modes"]).split(" ", false):
		if not MODE_IDX.has(k):
			return _fail("%s: unknown mode %s" % [slug, k])
		var probs: Array = B.validate(m, int(MODE_IDX[k]))
		if not probs.is_empty():
			return _fail("%s %s: validate: %s" % [slug, k, str(probs[0]["msg"])])
	var out: Array = []
	var code := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/map_audit.py"), ProjectSettings.globalize_path(path)], out, true)
	var txt := "".join(out)
	if code != 0 or not txt.contains("0 / 1 maps have problems"):
		return _fail("%s: map_audit: %s" % [slug, txt.strip_edges().replace("\n", " ; ").left(300)])
	# Runtime nav: every objective leg of the listed modes.
	var nb = load("res://scripts/nav_builder.gd").new()
	var data: Dictionary = nb._build(IO.load_from_file(path))
	var nav = load("res://scripts/nav_graph.gd").new()
	nav.adopt(data)
	if nav.is_empty():
		return _fail("%s: no runtime nav graph" % slug)
	var ts: Dictionary = m.get("team_spawns", {})
	var modes: PackedStringArray = str(meta["modes"]).split(" ", false)
	var legs := 0
	var bad: Array = []
	if "ctf" in modes:
		var fl: Array = m["ctf_flags"]
		for t in [1, 2]:
			var home: Vector2 = fl[t - 1]
			var enemy: Vector2 = fl[2 - t]
			for sp in ts.get(t, []):
				legs += 2
				if not _ok_path(nav, sp, enemy):
					bad.append("T%d spawn%s->flag" % [t, str(Vector2i(sp))])
				if not _ok_path(nav, enemy, sp):
					bad.append("T%d flag->spawn%s" % [t, str(Vector2i(sp))])
			legs += 1
			if not _ok_path(nav, enemy, home):
				bad.append("T%d enemy flag->home" % t)
	var objs: Array = []
	if "dom" in modes:
		for d in m.get("dom_points", []):
			objs.append(["dom", (d as Vector2) + Vector2(0, 28)])
	for pair in [["htf", "htf_flag"], ["inf", "inf_flag"], ["rm", "rambo_pos"]]:
		if pair[0] in modes:
			objs.append([pair[0], m[pair[1]]])
	var all_spawns: Array = (ts.get(1, []) as Array) + (ts.get(2, []) as Array)
	if all_spawns.is_empty():
		all_spawns = m.get("bot_spawns", [])
	for o in objs:
		for sp in all_spawns:
			legs += 2
			if not _ok_path(nav, sp, o[1]):
				bad.append("spawn%s->%s%s" % [str(Vector2i(sp)), o[0], str(Vector2i(o[1]))])
			if not _ok_path(nav, o[1], sp):
				bad.append("%s%s->spawn%s" % [o[0], str(Vector2i(o[1])), str(Vector2i(sp))])
	if not bad.is_empty():
		return _fail("%s: nav legs broken (%d / %d): %s" % [slug, bad.size(), legs, ", ".join(bad.slice(0, 4))])
	print("FEATURED-DATA %s polys=%d nav=%d legs=%d pads=%d" % [slug, (m["polys"] as Array).size(), int(data["stats"]["nodes"]), legs,
		int(data["stats"].get("pads", 0))])
	return true


# ── 3. strings ───────────────────────────────────────────────────────────────

func _check_i18n() -> bool:
	var keys: Array = NEW_KEYS.duplicate()
	for e in FL.LEVELS:
		keys.append(str(e["blurb"]))
	for loc in ["es", "pt_BR", "de", "fr"]:
		TranslationServer.set_locale(loc)
		for k in keys:
			var t := TranslationServer.translate(k)
			if t == k:
				TranslationServer.set_locale("en")
				return _fail("'%s' has no %s translation" % [k, loc])
	TranslationServer.set_locale("en")
	_log.append("strings translate (%d keys x 4)" % keys.size())
	return true


# ── 2. UI ────────────────────────────────────────────────────────────────────

func _check_ui() -> bool:
	_st.master_url = "http://127.0.0.1:9"   # offline: FEATURED needs no server
	_st.game_mode = 0
	change_scene_to_file("res://scenes/menu.tscn")
	if not await _until(func() -> bool: return current_scene != null and current_scene.get("_menu_root") != null, 300):
		return _fail("menu never loaded")
	await _frames(10)
	var menu: Node = current_scene
	(menu.find_child("LevelsButton", true, false) as Button).pressed.emit()
	var pn: Node = menu.get("_levels_panel")
	if pn == null or not pn.visible:
		return _fail("LEVELS didn't open")
	if str(pn.tab) != "featured" or pn._tab_btns.keys()[0] != "featured":
		return _fail("LEVELS opened on '%s' (first tab %s), want FEATURED first" % [str(pn.tab), str(pn._tab_btns.keys()[0])])
	await _frames(3)
	if int(pn.loaded) != 8 or pn._cards.size() != 8 or int(pn.api.requests) != 0 or bool(pn.offline):
		return _fail("FEATURED: loaded=%d cards=%d requests=%d offline=%s" % [int(pn.loaded), pn._cards.size(), int(pn.api.requests), str(pn.offline)])
	for id in pn._cards:
		var th: Array = (pn._cards[id] as Node).find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n.get("tris") != null)
		if th.is_empty() or int(th[0].tris) < 2:
			return _fail("card %s: no outline" % id)
	# Other tabs still talk to the server; FEATURED again is instant.
	pn.set_tab("hot")
	pn.set_tab("featured")
	if int(pn.loaded) != 8:
		return _fail("FEATURED after HOT: loaded=%d" % int(pn.loaded))
	_log.append("tab offline: 8 cards, 0 requests")
	# Detail of each level.
	for e in FL.LEVELS:
		var id: String = FL.ID_PREFIX + str(e["slug"])
		pn.select(id)
		var modes: PackedStringArray = str(e["modes"]).split(" ", false)
		if not pn._d_edit.visible or pn._d_like.get_parent().visible or pn._d_code.get_parent().visible:
			return _fail("%s detail: edit=%s like=%s code=%s" % [id, str(pn._d_edit.visible), str(pn._d_like.get_parent().visible), str(pn._d_code.get_parent().visible)])
		if pn._d_mode.item_count != modes.size() or pn.selected_mode() != int(MODE_IDX[modes[0]]):
			return _fail("%s detail: %d modes (want %d), picks %d (want %d)" % [id, pn._d_mode.item_count, modes.size(), pn.selected_mode(), int(MODE_IDX[modes[0]])])
	# PLAY (hooked: the bot matches run in part 4).
	var played := [false]
	pn.play_hook = func() -> void: played[0] = true
	pn.select(FL.ID_PREFIX + "magma_crown")
	(pn.find_child("Play", true, false) as Button).pressed.emit()
	await _frames(2)
	var cp := str(_st.custom_map_path)
	if not played[0] or not cp.begins_with(FL.CACHE_DIR) or str(IO.load_from_file(cp).get("name", "")) != "Magma Crown" or int(_st.game_mode) != 7:
		return _fail("PLAY: hook=%s path=%s mode=%d" % [str(played[0]), cp, int(_st.game_mode)])
	_log.append("PLAY -> %s DOM" % cp.get_file())
	# HOST ONLINE: the menu's Host screen with the level picked.
	pn.gate = Callable()
	pn.select(FL.ID_PREFIX + "iron_valley")
	pn.host_selected()
	await _frames(3)
	var hp: Array = menu.get("_host_custom_paths")
	var mp: OptionButton = menu.get("_map_pick")
	if hp.is_empty() or not str(hp[hp.size() - 1]).begins_with(FL.CACHE_DIR) or mp == null or mp.get_item_text(mp.selected) != "Level: Iron Valley":
		return _fail("HOST ONLINE: paths=%s pick=%s" % [str(hp), mp.get_item_text(mp.selected) if mp != null else "none"])
	_log.append("HOST ONLINE -> Host screen")
	# EDIT A COPY from the menu: the Maker with an unsaved copy.
	menu._open_levels("featured")
	pn = menu.get("_levels_panel")
	await _frames(2)
	pn.select(FL.ID_PREFIX + "twin_forts")
	(pn.find_child("EditCopy", true, false) as Button).pressed.emit()
	if not await _until(func() -> bool: return current_scene != null and current_scene.scene_file_path == "res://scenes/map_editor.tscn" and current_scene.get("_maker") != null, 300):
		return _fail("EDIT A COPY never opened the editor")
	await _frames(5)
	var ed: Node = current_scene
	var mk: Node = ed.get("_maker")
	var want_n: int = (FL.source("twin_forts")["maker"]["pieces"] as Array).size()
	var em: Dictionary = ed.get("_map")
	if not bool(mk.active) or (em["maker"]["pieces"] as Array).size() != want_n or str(mk.map_name()) != "Twin Forts copy":
		return _fail("EDIT A COPY: active=%s pieces=%d (want %d) name=%s" % [str(mk.active), (em["maker"]["pieces"] as Array).size(), want_n, str(mk.map_name())])
	if (mk.compiled()["polys"] as Array).size() != (FL.load_map("twin_forts")["polys"] as Array).size():
		return _fail("EDIT A COPY: the copy compiles differently")
	if FileAccess.file_exists(IO.MAPS_DIR + IO.safe_filename("Twin Forts copy") + ".json"):
		DirAccess.remove_absolute(IO.MAPS_DIR + IO.safe_filename("Twin Forts copy") + ".json")
		return _fail("EDIT A COPY saved a file (should stay unsaved)")
	_log.append("EDIT A COPY -> Maker (%d pieces)" % want_n)
	# FILE > New map: Start from Empty / Starter / featured.
	mk.open_new()
	await _frames(2)
	var rows: int = mk._new_list.get_child_count()
	if not mk._new.visible or rows != 10:
		return _fail("New map sheet: visible=%s rows=%d (want 10)" % [str(mk._new.visible), rows])
	(mk._new_list.find_child("Start_magma_crown", true, false) as Button).pressed.emit()
	await _frames(2)
	em = ed.get("_map")
	if mk._new.visible or (em["maker"]["pieces"] as Array).size() != (FL.source("magma_crown")["maker"]["pieces"] as Array).size() or int(mk.test_mode) != 7:
		return _fail("Start from Magma Crown: pieces=%d test_mode=%d" % [(em["maker"]["pieces"] as Array).size(), int(mk.test_mode)])
	mk.open_new()
	await _frames(2)
	(mk._new_list.find_child("Start_empty", true, false) as Button).pressed.emit()
	await _frames(2)
	if (ed.get("_map")["maker"]["pieces"] as Array).size() != 0:
		return _fail("Start from Empty left pieces")
	mk.open_new()
	await _frames(2)
	(mk._new_list.find_child("Start_starter", true, false) as Button).pressed.emit()
	await _frames(2)
	if (ed.get("_map")["maker"]["pieces"] as Array).size() != (B.starter_map()["maker"]["pieces"] as Array).size():
		return _fail("Start from Starter: wrong pieces")
	mk.undo()
	if (ed.get("_map")["maker"]["pieces"] as Array).size() != 0:
		return _fail("undo after Start from didn't go back to the previous map")
	_log.append("New map: Empty / Starter / featured")
	# The editor's LEVELS overlay: EDIT A COPY in place.
	var ov: Node = load("res://scripts/level_publish.gd").open_levels(ed.get_node("UI"), ed)
	await _frames(3)
	if int(ov.loaded) != 8:
		return _fail("editor LEVELS overlay: loaded=%d" % int(ov.loaded))
	ov.select(FL.ID_PREFIX + "hollow_deep")
	(ov.find_child("EditCopy", true, false) as Button).pressed.emit()
	await _frames(3)
	if current_scene != ed or ov.visible or str(mk.map_name()) != "Hollow Deep copy" or not bool(mk.active):
		return _fail("overlay EDIT A COPY: same scene=%s overlay=%s name=%s" % [str(current_scene == ed), str(ov.visible), str(mk.map_name())])
	_log.append("editor overlay EDIT A COPY in place")
	_st.master_url = _saved["master_url"]
	return true


# ── 4. bots ──────────────────────────────────────────────────────────────────

func _check_bots(slug: String) -> bool:
	var meta: Dictionary = FL.meta(slug)
	var mode := str(meta["modes"]).get_slice(" ", 0)
	var src: Dictionary = FL.load_map(slug)
	_st.custom_map_path = FL.local_copy(slug)
	_st.game_mode = int(MODE_IDX[mode])
	_st.bot_count = 8
	_st.vehicles = true
	root.get_node("Net").set_singleplayer()
	change_scene_to_file("res://scenes/main.tscn")
	if not await _until(func() -> bool: return current_scene != null and current_scene.get("nav") != null and current_scene.scene_file_path == "res://scenes/main.tscn", 600):
		return _fail("%s: match never started" % slug)
	var m: Node = current_scene
	if not await _until(func() -> bool: return not m.nav.is_empty(), 1500):
		return _fail("%s: runtime nav graph never adopted" % slug)
	if str((m.get("_map") as Dictionary).get("name", "")) != str(meta["title"]):
		return _fail("%s: match loaded %s" % [slug, str((m.get("_map") as Dictionary).get("name", ""))])
	var hz = m.get("_hazards")
	var hz0: int = int(hz.kills) if hz != null else 0
	var l0: int = int(hz.bot_launches) if hz != null else 0
	var events := {}
	var kills := [0]
	m.objective.connect(func(kind: String, _t: int, _w: String) -> void: events[kind] = int(events.get(kind, 0)) + 1)
	m.kill.connect(func(_a, _b, _c, _d, _e) -> void: kills[0] += 1)
	var dist := {}
	var last := {}
	var best := {1: INF, 2: INF}
	var start_d := {}
	var flags: Array = src.get("ctf_flags", [])
	var htf: Vector2 = src.get("htf_flag", Vector2.INF)
	var htf_near := false
	var boarded := 0
	var drv := {}
	var frames := int(_secs * 60.0)
	for _i in frames:
		await process_frame
		if _done:
			return false
		for b in get_nodes_in_group("soldier"):
			if not is_instance_valid(b) or b == m.player:
				continue
			var id: int = b.get_instance_id()
			var gp: Vector2 = b.global_position
			var stp: float = gp.distance_to(last.get(id, gp))
			if stp < 60.0:
				dist[id] = float(dist.get(id, 0.0)) + stp
			last[id] = gp
			var t := int(b.get("team"))
			if mode == "ctf" and flags.size() == 2 and (t == 1 or t == 2) and not bool(b.get("dead")):
				var enemy: Vector2 = flags[2 - t]
				if not start_d.has(t):
					start_d[t] = (flags[t - 1] as Vector2).distance_to(enemy)
				best[t] = minf(float(best[t]), gp.distance_to(enemy))
			if htf != Vector2.INF and gp.distance_to(htf) < 140.0:
				htf_near = true
		for v in get_nodes_in_group("vehicle"):
			if is_instance_valid(v) and v.has_method("driver"):
				var d = v.driver()
				if d != null and d != m.player and drv.get(v.get_instance_id()) != d:
					boarded += 1
				drv[v.get_instance_id()] = d
	var moved := 0
	for id in dist:
		if float(dist[id]) > 600.0:
			moved += 1
	var hk: int = (int(hz.kills) - hz0) if hz != null else 0
	var launches: int = (int(hz.bot_launches) - l0) if hz != null else 0
	var probs: Array = []
	if dist.size() == 0 or moved * 2 < dist.size():
		probs.append("bots didn't travel (%d / %d over 600 px)" % [moved, dist.size()])
	if hk > 1:
		probs.append("%d hazard deaths (%s)" % [hk, ", ".join(hz.kill_log)])
	match mode:
		"ctf":
			for t in [1, 2]:
				if float(best[t]) > float(start_d.get(t, 0.0)) * 0.5 and int(events.get("grab", 0)) == 0:
					probs.append("team %d got no closer than %d px to the enemy flag (%d apart)" % [t, int(best[t]), int(start_d.get(t, 0.0))])
		"dom":
			if int(events.get("dom", 0)) == 0:
				probs.append("no point captured")
		"htf":
			if int(events.get("grab", 0)) == 0 and not htf_near:
				probs.append("nobody reached the flag")
		"dm", "tdm", "gg":
			if kills[0] == 0:
				probs.append("no kills")
	if not (src.get("jump_pads", []) as Array).is_empty() and launches == 0:
		probs.append("nobody used a jump pad")
	var nveh: int = (src.get("vehicle_spawns", []) as Array).size() + (src.get("tank_spawns", []) as Array).size() \
		+ (src.get("heli_spawns", []) as Array).size() + (src.get("plane_spawns", []) as Array).size()
	if nveh > 0 and boarded == 0:
		probs.append("no bot boarded a vehicle")
	var line := "%s %s: moved %d/%d, kills %d, events %s, hazard deaths %d, pads %d, boarded %d" % [slug, mode, moved, dist.size(),
		kills[0], str(events), hk, launches, boarded]
	print("FEATURED-BOTS " + line)
	if not probs.is_empty():
		return _fail("%s %s: %s" % [slug, mode, "; ".join(probs)])
	_log.append("%s %s ok" % [slug, mode])
	return true
