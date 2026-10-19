extends SceneTree
## BACK rule gate test (scripts/ui_back.gd): the Android system BACK
## (NOTIFICATION_WM_GO_BACK_REQUEST, propagated from the root like the engine
## does), Esc and the ui_cancel action close the TOP-MOST overlay first and
## never leave the screen (or quit the app) from under a dialog.
##   Main menu: every screen (Settings / Controls, Host, Join, server browser,
##   LEVELS, MAP FILES, stats, credits, leaderboard, customize, replays,
##   friends) -> main list; an open popup list closes before its screen; the
##   first-launch name prompt stays (no skip), CHANGE NAME cancels, WHAT'S NEW
##   and the rejoin prompt close.
##   Map editor: Maker FILE / MAP popups, context menu, problems sheet, open
##   sheet, armed piece, selection; ADVANCED: PUBLISH, LEVELS (stacked on
##   PUBLISH: LEVELS first), the load list, a popup list — all close with the
##   editor still up; with nothing open BACK leaves to the menu.
##   Play-test: pause list / Settings / quit confirm step back one at a time,
##   the chat line closes, then BACK returns to EDIT. A normal match: BACK
##   toggles the pause menu. Replay viewer: BACK leaves to the menu.
## Each case runs with the notification and with Esc / ui_cancel.
##   godot --headless --fixed-fps 60 -s tools/back_button_test.gd

const HOWS := ["notif", "esc", "cancel"]

var _log: Array = []
var _bad: Array = []
var _done := false
var _step := "boot"
var _st: Node = null
var _net: Node = null
var _saved := {}
var _replays_before: Array = []
var UIBack = null


func _initialize() -> void:
	_run()


func _process(_d: float) -> bool:
	if not _done and Time.get_ticks_msec() > 200000:
		_finish("timed out at step '%s'" % _step)
	return false


## A quit() from the game (the menu's root-list BACK) ends the run here.
func _finalize() -> void:
	if not _done:
		print("BACK-TEST FAIL the app quit at step '%s' | %s" % [_step, " | ".join(_bad)])


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _until(cond: Callable, frames: int = 600) -> bool:
	var n := 0
	while not cond.call():
		n += 1
		if n > frames:
			return false
		await process_frame
	return true


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_bad.append("%s: %s" % [_step, what])


func _finish(err: String = "") -> void:
	if _done:
		return
	if err != "":
		_bad.append(err)
	if _st != null:
		for k in _saved:
			_st.set(k, _saved[k])
		_st.save()
	if _net != null:
		_net.set("maker_return", {})
		_net.set("replay_path", "")
	_done = true
	if _bad.is_empty():
		print("BACK-TEST ok ", " ".join(_log), " | %.1f s" % (Time.get_ticks_msec() / 1000.0))
	else:
		print("BACK-TEST FAIL ", " | ".join(_bad), " :: ", " ".join(_log))
	quit(0 if _bad.is_empty() else 1)


## One BACK press: the Android notification (root.propagate_notification,
## as the engine's window event does), the Esc key, or a ui_cancel action.
## Focus is released first for the keys: a LineEdit being typed in takes the
## first Esc itself (ends editing), which is the expected desktop behaviour.
func _back(how: String) -> void:
	match how:
		"notif":
			root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		"esc":
			root.gui_release_focus()
			var k := InputEventKey.new()
			k.keycode = KEY_ESCAPE
			k.physical_keycode = KEY_ESCAPE
			k.pressed = true
			Input.parse_input_event(k)
			var r := k.duplicate() as InputEventKey
			r.pressed = false
			Input.parse_input_event(r)
		"cancel":
			root.gui_release_focus()
			var a := InputEventAction.new()
			a.action = "ui_cancel"
			a.pressed = true
			Input.parse_input_event(a)
			var ar := InputEventAction.new()
			ar.action = "ui_cancel"
			ar.pressed = false
			Input.parse_input_event(ar)
	await _frames(3)


func _vis(c: Variant) -> bool:
	return c != null and is_instance_valid(c) and (c as CanvasItem).is_visible_in_tree() and not (c as Node).is_queued_for_deletion()


func _scene_is(path: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == path


func _run() -> void:
	await _frames(2)
	while root.get_node_or_null("Settings") == null or root.get_node_or_null("Net") == null:
		await process_frame
	_st = root.get_node("Settings")
	_net = root.get_node("Net")
	UIBack = load("res://scripts/ui_back.gd")
	for k in ["player_name", "name_set", "master_url", "last_seen_version", "bot_count", "game_mode",
			"map_index", "custom_map_path", "training"]:
		_saved[k] = _st.get(k)
	_st.player_name = "BackTester"
	_st.name_set = true
	_st.master_url = "http://127.0.0.1:9"   # online panels go offline at once
	_st.training = false
	_st.save()
	var R = load("res://scripts/replay_recorder.gd")
	_replays_before = R.list_files()
	for part in [_menu_cases, _editor_cases, _playtest_cases, _match_and_replay_cases]:
		# A script error inside a part makes its await return null: fail loudly.
		var ok = await (part as Callable).call()
		if not (ok is bool and ok):
			if _bad.is_empty():
				_bad.append("%s: aborted (script error / freed scene?)" % _step)
			return _finish()
	for f in R.list_files():
		if not _replays_before.has(f):
			DirAccess.remove_absolute(f)
	_finish()


# ── Main menu ───────────────────────────────────────────────────────────────

func _to_menu() -> Node:
	if not _scene_is("res://scenes/menu.tscn"):
		change_scene_to_file("res://scenes/menu.tscn")
	if not await _until(func() -> bool: return _scene_is("res://scenes/menu.tscn") and current_scene.get("_menu_root") != null, 600):
		_bad.append("%s: menu never loaded" % _step)
		return null
	await _frames(8)
	return current_scene


func _menu_cases() -> bool:
	_step = "menu"
	var m: Node = await _to_menu()
	if m == null:
		return false
	var screens := {
		"settings": [func() -> void: m._open_settings(), func() -> Variant: return m._settings_panel],
		"host": [func() -> void: m._open_host(), func() -> Variant: return m._host_root],
		"join": [func() -> void:
			m._menu_root.visible = false
			m._join_root.visible = true, func() -> Variant: return m._join_root],
		"stats": [func() -> void:
			m._refresh_stats_labels()
			m._menu_root.visible = false
			m._stats_root.visible = true, func() -> Variant: return m._stats_root],
		"credits": [func() -> void: m._open_credits(), func() -> Variant: return m._credits_root],
		"levels": [func() -> void: m._open_levels(), func() -> Variant: return m._levels_panel],
		"mapfiles": [func() -> void: m._open_map_library(), func() -> Variant: return m._lib_panel],
		"leaderboard": [func() -> void: m._open_leaderboard(), func() -> Variant: return m._lb_panel],
		"customize": [func() -> void: m._open_customize(), func() -> Variant: return m._cust_panel],
		"replays": [func() -> void: m._open_replays(), func() -> Variant: return m._replays_panel],
		"friends": [func() -> void: m._open_friends(), func() -> Variant: return m._friends_panel],
	}
	var n := 0
	for how in HOWS:
		for key in screens:
			_step = "menu %s %s" % [key, how]
			(screens[key][0] as Callable).call()
			await _frames(3)
			var pn: Variant = (screens[key][1] as Callable).call()
			_expect(_vis(pn) and not m._menu_root.visible, "screen didn't open")
			await _back(how)
			_expect(current_scene == m, "left the menu scene")
			_expect(not _vis(pn), "BACK didn't close it")
			_expect(m._menu_root.visible, "BACK didn't land on the main list")
			n += 1
		# Settings -> Controls: one step at a time.
		_step = "menu controls %s" % how
		m._open_settings()
		m._settings_panel.controls_pressed.emit()
		await _frames(3)
		await _back(how)
		_expect(m._settings_panel.visible and not m._controls_panel.visible, "Controls didn't step back to Settings")
		await _back(how)
		_expect(m._menu_root.visible and not m._settings_panel.visible, "Settings didn't step back to the list")
		# An open popup list closes before its screen — on the main list it
		# must not quit the app (the map picker).
		for spec in [["main list", func() -> void: pass, func() -> Variant: return m._menu_root],
				["host", func() -> void: m._open_host(), func() -> Variant: return m._host_root]]:
			_step = "menu %s popup %s" % [spec[0], how]
			(spec[1] as Callable).call()
			await _frames(3)
			var screen: Control = (spec[2] as Callable).call()
			var obs := screen.find_children("*", "OptionButton", true, false)
			if obs.is_empty():
				_bad.append("%s: no OptionButton" % _step)
				continue
			var ob := obs[0] as OptionButton
			ob.show_popup()
			await _frames(2)
			_expect(ob.get_popup().visible, "popup didn't open")
			await _back(how)
			_expect(not ob.get_popup().visible, "BACK didn't close the popup")
			_expect(_vis(screen), "BACK closed the screen under the popup")
			if screen != m._menu_root:
				await _back(how)
				_expect(not _vis(screen) and m._menu_root.visible, "second BACK didn't close the screen")
		# Server browser -> Join -> list (BACK used to quit from the browser).
		_step = "menu browser %s" % how
		m._master_edit.text = "http://127.0.0.1:9"
		m._menu_root.visible = false
		m._browser._on_browse_pressed()
		await _frames(3)
		await _back(how)
		_expect(not m._browse_root.visible and m._join_root.visible, "browser didn't step back to Join")
		await _back(how)
		_expect(m._menu_root.visible and not m._join_root.visible, "Join didn't step back to the list")
		# First-launch name prompt: no skip, BACK must not leave or quit.
		_step = "menu first name prompt %s" % how
		m._build_name_prompt()
		await _frames(3)
		var np: Control = m._name_prompt_root
		await _back(how)
		_expect(_vis(np) and not m._menu_root.visible, "first-launch name prompt closed / left")
		np.queue_free()
		m._menu_root.visible = true
		await _frames(2)
		# CHANGE NAME: BACK = cancel.
		_step = "menu change name %s" % how
		m._build_name_prompt(Callable(), true)
		await _frames(3)
		np = m._name_prompt_root
		await _back(how)
		_expect(not _vis(np) and m._menu_root.visible, "CHANGE NAME didn't cancel")
		await _frames(2)
		# WHAT'S NEW.
		_step = "menu whats new %s" % how
		_st.last_seen_version = "1.0.0"
		m._maybe_whats_new()
		await _frames(3)
		var wn: CanvasItem = UIBack.top(self)
		_expect(_vis(wn) and not m._menu_root.visible, "WHAT'S NEW didn't open")
		await _back(how)
		_expect(not _vis(wn) and m._menu_root.visible, "WHAT'S NEW didn't close")
		await _frames(2)
		# Connection lost -> rejoin prompt.
		_step = "menu rejoin %s" % how
		_net.last_server_ip = "127.0.0.1"
		_net.last_server_port = 9
		m._build_rejoin()
		await _frames(3)
		var rj: Control = m._rejoin_root
		_expect(_vis(rj), "rejoin prompt didn't open")
		await _back(how)
		_expect(not _vis(rj) and m._menu_root.visible and float(m._rejoin_t) <= 0.0, "rejoin prompt didn't close")
		if rj != null:
			rj.queue_free()
		m._rejoin_root = null
		await _frames(2)
	_expect(current_scene == m, "left the menu")
	_log.append("menu=%d" % n)
	return true


# ── Map editor ──────────────────────────────────────────────────────────────

func _to_editor() -> Node:
	change_scene_to_file("res://scenes/map_editor.tscn")
	if not await _until(func() -> bool: return _scene_is("res://scenes/map_editor.tscn") and current_scene.get("_maker") != null and current_scene.get_node_or_null("UI") != null, 600):
		_bad.append("%s: editor never loaded" % _step)
		return null
	await _frames(8)
	return current_scene


func _editor_cases() -> bool:
	_step = "editor"
	_st.bot_count = 0
	_st.game_mode = 0
	_st.custom_map_path = ""
	var e: Node = await _to_editor()
	if e == null:
		return false
	var mk: Node = e.get("_maker")
	var ui: CanvasLayer = e.get_node("UI")
	var n := 0
	for how in HOWS:
		var still := func() -> void:
			_expect(current_scene == e, "the editor was left")
		# Maker overlays.
		for mb_name in ["_file_menu", "_map_menu"]:
			_step = "maker %s %s" % [mb_name, how]
			var mb: MenuButton = mk.get(mb_name)
			mb.show_popup()
			await _frames(2)
			_expect(mb.get_popup().visible, "popup didn't open")
			await _back(how)
			_expect(not mb.get_popup().visible, "popup not closed")
			still.call()
			n += 1
		var sheets := {
			"context": [func() -> void:
				mk.sel = []
				mk._open_context(Vector2(400, 300)), "_ctx"],
			"problems": [func() -> void: mk._show_problems([{"lvl": "warn", "msg": "back test", "at": Vector2(100, 100)}], "play"), "_probs"],
			"open": [func() -> void: mk._open_load(), "_load"],
		}
		for key in sheets:
			_step = "maker %s %s" % [key, how]
			(sheets[key][0] as Callable).call()
			await _frames(2)
			var sh: Control = mk.get(sheets[key][1])
			_expect(_vis(sh), "sheet didn't open")
			await _back(how)
			_expect(not _vis(sh), "sheet not closed")
			still.call()
			n += 1
		_step = "maker armed %s" % how
		mk.arm("block")
		await _back(how)
		_expect(str(mk.armed) == "", "piece still armed")
		still.call()
		_step = "maker selection %s" % how
		mk.select_all()
		_expect(not (mk.sel as Array).is_empty(), "nothing to select")
		await _back(how)
		_expect((mk.sel as Array).is_empty(), "selection not cleared")
		still.call()
		# ADVANCED: PUBLISH, LEVELS, both stacked, the load list, a popup.
		e._set_maker(false)
		await _frames(2)
		_step = "advanced publish %s" % how
		(e.find_child("PublishButton", true, false) as Button).pressed.emit()
		await _frames(3)
		var dlg: Control = ui.get_node_or_null("PublishDialog")
		_expect(_vis(dlg), "PUBLISH didn't open")
		await _back(how)
		_expect(not _vis(dlg), "PUBLISH not closed")
		_expect(not bool(mk.active), "BACK switched out of ADVANCED")
		still.call()
		_step = "advanced levels %s" % how
		(e.find_child("LevelsButton", true, false) as Button).pressed.emit()
		await _frames(3)
		var lv: Control = ui.get_node_or_null("LevelsBrowser")
		_expect(_vis(lv), "LEVELS didn't open")
		await _back(how)
		_expect(not _vis(lv), "LEVELS not closed")
		still.call()
		_step = "advanced publish+levels %s" % how
		(e.find_child("PublishButton", true, false) as Button).pressed.emit()
		await _frames(2)
		(e.find_child("LevelsButton", true, false) as Button).pressed.emit()
		await _frames(3)
		await _back(how)
		_expect(not _vis(lv) and _vis(dlg), "LEVELS (on top) didn't close first")
		await _back(how)
		_expect(not _vis(dlg), "PUBLISH not closed second")
		still.call()
		_step = "advanced load %s" % how
		e._open_load()
		await _frames(2)
		var lp: Control = e.get("_load_panel")
		_expect(_vis(lp), "load list didn't open")
		await _back(how)
		_expect(not _vis(lp), "load list not closed")
		still.call()
		_step = "advanced popup %s" % how
		var obs := ui.find_children("*", "OptionButton", true, false)
		if obs.is_empty():
			_bad.append("%s: no OptionButton" % _step)
		else:
			var ob := obs[0] as OptionButton
			ob.show_popup()
			await _frames(2)
			await _back(how)
			_expect(not ob.get_popup().visible, "popup not closed")
		still.call()
		n += 6
		e._set_maker(true)
		await _frames(2)
	# Nothing open: BACK takes the editor's own exit (to the menu).
	_step = "editor leave"
	await _back("notif")
	if not await _until(func() -> bool: return _scene_is("res://scenes/menu.tscn"), 120):
		_bad.append("%s: BACK with nothing open didn't leave to the menu" % _step)
	_log.append("editor=%d" % n)
	return true


# ── Maker play-test ─────────────────────────────────────────────────────────

func _play() -> Node:
	var e: Node = await _to_editor()
	if e == null:
		return null
	var mk: Node = e.get("_maker")
	mk.test_mode = 0
	if not mk.play(true):
		_bad.append("%s: play() refused" % _step)
		return null
	if not await _until(func() -> bool: return _scene_is("res://scenes/main.tscn") and current_scene.get("player") != null \
			and is_instance_valid(current_scene.get("player")) and current_scene.get_node_or_null("PauseMenu") != null, 900):
		_bad.append("%s: play-test never started" % _step)
		return null
	await _frames(20)
	return current_scene


func _pause_cases(m: Node, how: String) -> void:
	var pm: Node = m.get_node("PauseMenu")
	_step = "pause list %s" % how
	pm.open()
	await _frames(2)
	await _back(how)
	_expect(not bool(pm._open), "pause list not closed")
	_expect(current_scene == m, "left the match")
	_step = "pause settings %s" % how
	pm.open()
	pm._open_settings()
	await _frames(2)
	await _back(how)
	_expect(bool(pm._open) and not pm._settings_panel.visible and pm._menu_wrapper.visible, "Settings didn't step back to the pause list")
	await _back(how)
	_expect(not bool(pm._open), "pause not closed after Settings")
	_step = "pause quit confirm %s" % how
	pm.open()
	pm._open_quit_confirm()
	await _frames(2)
	await _back(how)
	_expect(bool(pm._open) and not pm._quit_confirm_wrapper.visible, "quit confirm didn't step back")
	await _back(how)
	_expect(not bool(pm._open), "pause not closed after the confirm")
	_expect(current_scene == m, "left the match")
	paused = false


func _playtest_cases() -> bool:
	for how in HOWS:
		_step = "playtest %s" % how
		var m: Node = await _play()
		if m == null:
			return false
		await _pause_cases(m, how)
		_step = "playtest chat %s" % how
		var hud: Node = m.get("hud")
		hud.open_chat("global")
		await _frames(2)
		var cl: Node = hud.get("command_line")
		_expect(bool(cl.is_open), "chat line didn't open")
		await _back("notif")
		_expect(not bool(cl.is_open), "chat line not closed")
		_expect(not bool(m.get_node("PauseMenu")._open), "pause opened over the chat line")
		_expect(current_scene == m, "left the match")
		_step = "playtest touch layout %s" % how
		var TC = load("res://scripts/touch_controls.gd")
		TC.edit_mode = true
		await _back(how)
		_expect(not bool(TC.edit_mode), "touch layout editor not closed")
		_expect(not bool(m.get_node("PauseMenu")._open) and current_scene == m, "BACK left / paused instead of closing the layout editor")
		_step = "playtest edit %s" % how
		await _back(how)
		if not await _until(func() -> bool: return _scene_is("res://scenes/map_editor.tscn") and current_scene.get("_maker") != null, 300):
			_bad.append("%s: BACK with nothing open didn't return to EDIT (scene %s)" % [_step, current_scene.scene_file_path if current_scene != null else "?"])
			return false
		await _frames(10)
		_expect(bool(current_scene.get("_maker").active), "EDIT didn't come back to Maker mode")
	_step = "editor leave esc"
	await _back("esc")
	if not await _until(func() -> bool: return _scene_is("res://scenes/menu.tscn"), 120):
		_bad.append("%s: Esc with nothing open didn't leave the editor" % _step)
	_log.append("playtest=%d" % HOWS.size())
	return true


# ── Normal match + replay viewer ────────────────────────────────────────────

func _match_and_replay_cases() -> bool:
	_step = "match"
	_net.set("maker_return", {})
	_st.custom_map_path = ""
	_st.map_index = 0
	_st.game_mode = 0
	_st.bot_count = 2
	_net.set_singleplayer()
	change_scene_to_file("res://scenes/main.tscn")
	if not await _until(func() -> bool: return _scene_is("res://scenes/main.tscn") and current_scene.get_node_or_null("PauseMenu") != null \
			and current_scene.get("player") != null, 900):
		_bad.append("match never started")
		return false
	var m: Node = current_scene
	var pm: Node = m.get_node("PauseMenu")
	await _frames(20)
	for how in HOWS:
		_step = "match %s" % how
		await _back(how)
		_expect(bool(pm._open), "BACK didn't open the pause menu")
		_expect(current_scene == m, "left the match")
		await _back(how)
		_expect(not bool(pm._open), "second BACK didn't resume")
		await _pause_cases(m, how)
	# The recorder keeps matches of >= 15 s: play on, then leave (saves one).
	_step = "match record"
	await _frames(1000)
	pm._exit_to_menu()
	var menu: Node = await _to_menu()
	if menu == null:
		return false
	var R = load("res://scripts/replay_recorder.gd")
	var fresh := ""
	for f in R.list_files():
		if not _replays_before.has(f):
			fresh = f
	if fresh == "":
		_bad.append("no replay saved to watch")
		return false
	for how in HOWS:
		_step = "replay %s" % how
		menu = await _to_menu()
		if menu == null:
			return false
		menu._open_replays()
		if not menu._replays_panel.watch_replay(fresh):
			_bad.append("%s: watch failed" % _step)
			return false
		if not await _until(func() -> bool: return _scene_is("res://scenes/main.tscn") and bool(current_scene.get("replay_mode")), 600):
			_bad.append("%s: replay never came up" % _step)
			return false
		await _frames(20)
		await _back(how)
		if not await _until(func() -> bool: return _scene_is("res://scenes/menu.tscn"), 120):
			_bad.append("%s: BACK didn't leave the replay" % _step)
		_expect(str(_net.get("replay_path")) == "", "still in replay mode")
	_log.append("match+replay")
	return true
