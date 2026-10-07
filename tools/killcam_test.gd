extends SceneTree
## Kill cam (gate stage F). When a bot kills you:
##  1. the rewind plays the last seconds from the recorder (live soldiers
##     hidden, its own camera, slow motion at the end), the respawn waits for it;
##  2. then the live kill cam follows the killer (name / HP / weapon on the HUD);
##  3. the next death, SPACE skips the rewind and you respawn on the normal
##     2 s timer, not the padded one.
##   godot --headless -s tools/killcam_test.gd

var _n := 0
var _st := 0
var _saved := []
var _bot: Node = null
var _t := 0
var _died_ms := 0
var _rewind_ms := 0
var _shot_n := 0
var _clock := 0.0   # game time (the gate runs --fixed-fps 60)


func _now() -> int:
	return int(_clock * 1000.0)


func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _process(d: float) -> bool:
	_n += 1
	_clock += d
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _st == 0:
		_saved = [st.bot_count, st.game_mode, st.map_index, st.custom_map_path, st.killcam_replay]
		st.bot_count = 1
		st.game_mode = 0
		st.map_index = 19
		st.custom_map_path = ""
		st.killcam_replay = true
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_st = 1
		return false
	var m = current_scene
	if m == null or m.get("spectator") == null and m.get("player") == null:
		return false
	match _st:
		1:
			if _n < 90 or m.player == null or not is_instance_valid(m.player) or m.recorder == null or float(m.recorder._t) < 3.5:
				return false
			for s in get_nodes_in_group("soldier"):
				if s.get("loadout") != null and not bool(s.get("dead")):
					_bot = s
			if _bot == null:
				return false
			_kill(m)
			_st = 2
		2:
			if _n - _t < 6:
				return false
			var kc = m.killcam
			if kc == null or not kc.is_active():
				return _end(false, "rewind not playing")
			if kc._puppets.size() < 1:
				return _end(false, "rewind has %d puppets, frame0 soldiers=%d who=%s killer=%d" % [kc._puppets.size(), kc.frames[0][1].size(), str(kc.who), kc.killer_id])
			if is_instance_valid(_bot) and _bot.visible:
				return _end(false, "live bot still visible during rewind")
			if root.get_viewport().get_camera_2d() != kc._cam:
				return _end(false, "rewind camera not current")
			_st = 3
		3:
			# Rewind runs to the end on its own; the respawn waits for it.
			if m.killcam.is_active():
				var shot := _arg("--shot=")
				if shot != "" and _shot_n < 2 and m.killcam.t >= m.killcam.t_end - (0.9 if _shot_n == 0 else 0.15):
					root.get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_%d.png" % _shot_n))
					_shot_n += 1
				if m.player != null and is_instance_valid(m.player) and not bool(m.player.dead):
					return _end(false, "respawned while the rewind was still playing")
				if _now() - _died_ms > 9000:
					return _end(false, "rewind never ended")
				return false
			_rewind_ms = _now() - _died_ms
			var kc = m.killcam
			if not kc.slowmo_seen:
				return _end(false, "no slow motion")
			if _rewind_ms < 3000:
				return _end(false, "rewind too short (%d ms)" % _rewind_ms)
			if is_instance_valid(_bot) and not _bot.visible:
				return _end(false, "bot left hidden after rewind")
			print("KILLCAM rewind %d ms (LENGTH %.2f s)" % [_rewind_ms, kc.LENGTH])
			_st = 4
		4:
			# Respawn right after the rewind (normal delay already over).
			if m.player != null and is_instance_valid(m.player) and not bool(m.player.dead):
				var ms := _now() - _died_ms
				if m.spectator.is_active():
					return _end(false, "spectator still on after respawn")
				if ms > _rewind_ms + 1200:
					return _end(false, "respawn %d ms after death, rewind ended at %d" % [ms, _rewind_ms])
				print("KILLCAM respawn %d ms after death" % ms)
				_t = _n
				_st = 5
			elif _now() - _died_ms > 9000:
				return _end(false, "no respawn after rewind")
		5:
			# Second death: live kill cam label while the rewind plays, then skip.
			if _n - _t < 30:
				return false
			if not is_instance_valid(_bot) or bool(_bot.dead):
				return _end(true, "rewind ok (bot gone before skip check)")
			_kill(m)
			_st = 6
		6:
			if _n - _t < 6:
				return false
			var sp = m.spectator
			var txt: String = m.hud.lbl_spectate.text
			if sp == null or not sp.is_killcam() or sp._target != _bot:
				return _end(false, "live kill cam not on the killer")
			if not (txt.contains("KILL CAM") and txt.contains(str(_bot.display_name)) and txt.contains("HP") and txt.contains("AK-74")):
				return _end(false, "hud: '%s'" % txt)
			if not m.killcam.is_active():
				return _end(false, "second rewind not playing")
			var ev := InputEventKey.new()
			ev.keycode = KEY_SPACE
			ev.pressed = true
			Input.parse_input_event(ev)
			_st = 7
		7:
			if m.killcam.is_active():
				if _now() - _died_ms > 1500:
					return _end(false, "SPACE didn't skip the rewind")
				return false
			if root.get_viewport().get_camera_2d() != m.spectator.cam:
				return _end(false, "view not handed back to the live kill cam")
			_st = 8
		8:
			if m.player != null and is_instance_valid(m.player) and not bool(m.player.dead):
				var ms := _now() - _died_ms
				if ms > 2900:
					return _end(false, "skipped but respawn took %d ms (normal is 2 s)" % ms)
				return _end(true, "rewind %d ms with slow-mo, live kill cam on %s, skip -> respawn in %d ms" % [_rewind_ms, str(_bot.display_name), ms])
			if _now() - _died_ms > 6000:
				return _end(false, "no respawn after skip")
	return false


func _kill(m) -> void:
	m.player.ceasefire_t = 0.0
	m.player.take_damage(999.0, str(_bot.display_name), "AK-74", int(_bot.team))
	_t = _n
	_died_ms = _now()


func _end(ok: bool, msg: String) -> bool:
	var st = root.get_node("Settings")
	st.bot_count = _saved[0]; st.game_mode = _saved[1]; st.map_index = _saved[2]; st.custom_map_path = _saved[3]; st.killcam_replay = _saved[4]
	print("KILLCAM-TEST %s %s" % ["ok" if ok else "FAIL", msg])
	quit(0 if ok else 1)
	return true
