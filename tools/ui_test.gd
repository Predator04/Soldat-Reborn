extends SceneTree
## Graphics Phase C (#272) UI test (gate F `ui`):
##   transitions: a screen change starts a slide + fade, finishes on the right
##     screen at its exact layout position; Reduce motion makes it instant;
##   buttons: hover → 1.03, press → 0.97, release + leave → 1.0 (none with
##     Reduce motion);
##   gamepad: D-pad focus moves through the main menu;
##   settings live preview: exists only while Settings is open, freed after;
##   leak check: opening / closing every menu screen 3× leaves the node count flat;
##   HUD: vitals show + ease after damage, team score strip, toast, death band,
##     UI scale applies live to the HUD root.
##   godot --headless --fixed-fps 60 -s tools/ui_test.gd
const UIFx = preload("res://scripts/ui_fx.gd")
const UITheme = preload("res://scripts/ui_theme.gd")

var _st := 0
var _n := 0
var _t := 0
var _m: Node = null
var _bad: Array = []
var _log: Array = []
var _base_menu_pos := Vector2.ZERO
var _btn: Button = null
var _prev: Control = null
var _seen: Dictionary = {}
var _pad_step := 0
var _cycle := 0
var _counts: Array = []
var _hp0 := 0.0


func _wait(frames: int) -> bool:
	_t += 1
	if _t < frames:
		return true
	_t = 0
	return false


func _end(ok: bool, why: String = "") -> bool:
	var st = root.get_node_or_null("Settings")
	if st != null:
		st.reduce_motion = false
		st.ui_scale = 1.0
	if ok and _bad.is_empty():
		print("UI-TEST ok  %s" % "  ".join(_log))
	else:
		print("UI-TEST fail: %s  %s  | %s" % [why, "; ".join(_bad), "  ".join(_log)])
	quit()
	return true


func _near(a: float, b: float, eps: float = 0.006) -> bool:
	return absf(a - b) <= eps


func _pad(button: int) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = down
		e.device = 0
		Input.parse_input_event(e)


func _nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


## One pass over every main-menu screen: open, let it settle, close.
func _cycle_screens() -> void:
	var m := _m
	var openers := [
		func() -> void: m._open_settings(),
		func() -> void: m._open_host(),
		func() -> void:
			m._menu_root.visible = false
			m._join_root.visible = true,
		func() -> void:
			m._refresh_stats_labels()
			m._menu_root.visible = false
			m._stats_root.visible = true,
		func() -> void: m._open_credits(),
		func() -> void: m._open_leaderboard(),
		func() -> void: m._open_customize(),
		func() -> void: m._open_map_library(),
		func() -> void: m._open_replays(),
		func() -> void: m._open_friends(),
	]
	for o in openers:
		o.call()
		if m._menu_root.visible:
			_bad.append("a screen didn't hide the main list")
			continue
		m._go_back()
	# Settings → Controls → back → back, and the browser.
	m._open_settings()
	m._settings_panel.controls_pressed.emit()
	m._go_back()
	m._go_back()
	m._master_edit.text = "http://127.0.0.1:9"
	m._menu_root.visible = false
	m._browser._on_browse_pressed()
	m._browse_root.visible = false
	m._menu_root.visible = true


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _n > 60 * 90:
		return _end(false, "timeout in state %d" % _st)
	match _st:
		0:
			st.name_set = true
			st.player_name = "Tester"
			st.reduce_motion = false
			st.ui_scale = 1.0
			st.master_url = "http://127.0.0.1:9"   # nothing listens: online panels fail quietly
			st.game_mode = 2
			st.map_index = 19
			st.custom_map_path = ""
			st.bot_count = 4
			st.killcam_replay = false
			change_scene_to_file("res://scenes/menu.tscn")
			_st = 1
		1:
			_m = current_scene
			if _m == null or _m.get("_menu_root") == null or _n < 20:
				return false
			if _wait(10):
				return false
			_base_menu_pos = _m._menu_root.position
			# ── transition: main → settings
			_m._open_settings()
			var sp: Control = _m._settings_panel
			if not (sp.visible and UIFx.is_animating(sp) and sp.modulate.a < 0.5):
				_bad.append("settings didn't start a transition (anim=%s a=%.2f)" % [UIFx.is_animating(sp), sp.modulate.a])
			_st = 2
		2:
			if _wait(24):
				return false
			var sp: Control = _m._settings_panel
			if UIFx.is_animating(sp) or not _near(sp.modulate.a, 1.0) or sp.has_meta("uifx_shift"):
				_bad.append("settings transition didn't finish")
			if _m._menu_root.visible:
				_bad.append("main list still up under settings")
			# Live preview while open.
			_prev = sp.get("preview")
			if _prev == null or not _prev.is_inside_tree() or _prev.get("viewport") == null:
				_bad.append("no settings preview while open")
			else:
				_log.append("preview=%s" % str((_prev.get("viewport") as SubViewport).size))
			_m._go_back()
			if not (_m._menu_root.visible and UIFx.is_animating(_m._menu_root)):
				_bad.append("back to main didn't animate")
			_st = 3
		3:
			if _wait(24):
				return false
			if not _m._menu_root.visible or _m._settings_panel.visible:
				_bad.append("back didn't land on the main list")
			if _m._menu_root.position.distance_to(_base_menu_pos) > 0.5:
				_bad.append("main list landed off its layout (%s vs %s)" % [_m._menu_root.position, _base_menu_pos])
			if _m._settings_panel.get("preview") != null or (is_instance_valid(_prev) and _prev.is_inside_tree()):
				_bad.append("settings preview not freed after closing")
			_log.append("transitions")
			# ── Reduce motion: instant swap
			st.reduce_motion = true
			_m._open_host()
			var hr: Control = _m._host_root
			if UIFx.is_animating(hr) or not _near(hr.modulate.a, 1.0) or hr.has_meta("uifx_shift"):
				_bad.append("reduce motion: host screen still animated")
			# #304 / #314: the Host mode list has every mode, Zombie last (after Bomb Defusal).
			var hp: OptionButton = _m.get("_host_mode_pick")
			var names: Array = load("res://scripts/game_lists.gd").MODE_NAMES
			if hp == null or hp.item_count != names.size() or str(names[names.size() - 1]) != "Zombie" \
					or hp.get_item_text(hp.item_count - 1) != tr("Zombie") or hp.get_item_text(hp.item_count - 2) != tr("Bomb Defusal"):
				_bad.append("host mode list: %d items (want %d, Zombie last)" % [hp.item_count if hp != null else -1, names.size()])
			_m._go_back()
			if UIFx.is_animating(_m._menu_root) or _m._menu_root.position.distance_to(_base_menu_pos) > 0.5:
				_bad.append("reduce motion: main list animated back")
			_log.append("reduce-motion")
			# ── buttons
			for b in _m._menu_root.find_children("*", "Button", true, false):
				if (b as Button).text == "HOST GAME":
					_btn = b
			if _btn == null:
				return _end(false, "no HOST GAME button")
			_btn.mouse_entered.emit()
			if not _near(_btn.scale.x, 1.0):
				_bad.append("reduce motion: hover scaled the button")
			_btn.mouse_exited.emit()
			st.reduce_motion = false
			_btn.mouse_entered.emit()
			_st = 4
		4:
			if _wait(16):
				return false
			if not _near(_btn.scale.x, UIFx.HOVER_SCALE):
				_bad.append("hover scale %.3f" % _btn.scale.x)
			if not _near(_btn.pivot_offset.x, _btn.size.x * 0.5, 0.6):
				_bad.append("button pivot not centred")
			_btn.button_down.emit()
			_st = 5
		5:
			if _wait(12):
				return false
			if not _near(_btn.scale.x, UIFx.PRESS_SCALE):
				_bad.append("press scale %.3f" % _btn.scale.x)
			_btn.button_up.emit()
			_btn.mouse_exited.emit()
			_st = 6
		6:
			if _wait(16):
				return false
			if not _near(_btn.scale.x, 1.0):
				_bad.append("button didn't return to 1.0 (%.3f)" % _btn.scale.x)
			_log.append("button-scale")
			# ── gamepad focus through the main menu
			_m._menu_first_focus.grab_focus()
			_seen.clear()
			_pad_step = 0
			_st = 7
		7:
			if _wait(3):
				return false
			var f: Control = root.gui_get_focus_owner()
			if f != null and _m._menu_root.is_ancestor_of(f):
				_seen[f] = true
			var seq := [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT]
			if _pad_step < seq.size():
				_pad(seq[_pad_step])
				_pad_step += 1
				return false
			var fo: Control = root.gui_get_focus_owner()
			if _seen.size() < 4:
				_bad.append("D-pad focus visited only %d controls" % _seen.size())
			elif fo is Button and not _near(fo.scale.x, UIFx.HOVER_SCALE, 0.02) and not UIFx.reduce_motion():
				_bad.append("focused button not lifted (%.3f)" % fo.scale.x)
			_log.append("pad-focus=%d" % _seen.size())
			if fo != null:
				fo.release_focus()
			_cycle = 0
			_counts.clear()
			_st = 8
		8:
			# ── leak check: every screen open / closed, 3 passes.
			if _wait(20):
				return false
			_cycle_screens()
			_cycle += 1
			_st = 9
		9:
			if _wait(40):
				return false
			_counts.append(_nodes())
			if _cycle < 3:
				_st = 8
				return false
			_log.append("nodes=%s" % str(_counts))
			if _counts[2] > _counts[0]:
				_bad.append("node count grew over 3 passes: %s" % str(_counts))
			if not _m._menu_root.visible:
				_bad.append("menu list hidden after the passes")
			# ── HUD
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 10
		10:
			var mm = current_scene
			if mm == null or mm.get("hud") == null or not is_instance_valid(mm.get("player")):
				return false
			if _wait(90):
				return false
			_m = mm
			var hud = mm.hud
			var p = mm.player
			var ui: Control = hud.get("_ui")
			if ui == null or not ui.is_in_group("ui_scaled"):
				_bad.append("HUD has no UI-scaled root")
			if str(hud.lbl_health.text) != str(int(p.health)):
				_bad.append("health label '%s' vs %d" % [hud.lbl_health.text, int(p.health)])
			if not str(hud.lbl_ammo.text).contains("/") and not str(hud.lbl_ammo.text).contains("RELOAD"):
				_bad.append("ammo label '%s'" % hud.lbl_ammo.text)
			if hud.score_strip == null or not hud.score_strip.has_teams():
				_bad.append("CTF score strip has no team blocks")
			_hp0 = float(p.health)
			p.take_damage(35.0, str(p.display_name))   # self damage: passes spawn protection
			_st = 11
		11:
			if _wait(40):
				return false
			var hud = _m.hud
			var p = _m.player
			if int(p.health) >= int(_hp0):
				_bad.append("damage didn't land (%d)" % int(p.health))
			if not is_instance_valid(p) or bool(p.dead):
				return _end(false, "player died during the HUD check")
			var bars: Control = hud.get("_bars")
			var want: float = clampf(float(p.health) / 100.0, 0.0, 1.0)
			if str(hud.lbl_health.text) != str(int(p.health)):
				_bad.append("health label didn't update")
			if absf(float(bars.get("_hp")) - want) > 0.03:
				_bad.append("health bar not eased to %.2f (%.2f)" % [want, float(bars.get("_hp"))])
			_log.append("hp %d->%d" % [int(_hp0), int(p.health)])
			hud.toast("UI TEST", "toast line")
			if not (hud.lbl_toast.visible and str(hud.lbl_toast.text).contains("toast line")):
				_bad.append("toast not shown")
			hud.show_death("Red_Bot_1", "AK-74", 3.0)
			if not (hud.get("_death_band") as Control).visible or not hud.lbl_death.visible:
				_bad.append("death band not shown")
			hud._hide_death()
			if (hud.get("_death_band") as Control).visible:
				_bad.append("death band stuck")
			# UI scale, live.
			root.get_node("Settings").ui_scale = 1.15
			UITheme.refresh_ui_scale(self)
			var ui: Control = hud.get("_ui")
			var vp: Vector2 = ui.get_viewport_rect().size
			if not _near(ui.scale.x, 1.15) or absf(ui.size.x - vp.x / 1.15) > 1.0:
				_bad.append("UI scale not applied to the HUD (%s, %s)" % [ui.scale, ui.size])
			root.get_node("Settings").ui_scale = 1.0
			UITheme.refresh_ui_scale(self)
			if not _near(ui.scale.x, 1.0) or absf(ui.size.x - vp.x) > 1.0:
				_bad.append("UI scale didn't return to 100%")
			_log.append("hud")
			_st = 12
		12:
			if _wait(10):
				return false
			return _end(true)
	return false
