extends SceneTree
## Kill cam (gate stage F): when a bot kills you, the camera follows that bot
## and the HUD shows its name, health and weapon; respawn ends it.
##   godot --headless -s tools/killcam_test.gd

var _n := 0
var _st := 0
var _saved := []
var _bot: Node = null
var _t := 0


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _st == 0:
		_saved = [st.bot_count, st.game_mode, st.map_index, st.custom_map_path]
		st.bot_count = 1
		st.game_mode = 0
		st.map_index = 19
		st.custom_map_path = ""
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_st = 1
		return false
	var m = current_scene
	if m == null or m.get("spectator") == null and m.get("player") == null:
		return false
	match _st:
		1:
			if _n < 60 or m.player == null or not is_instance_valid(m.player):
				return false
			for s in get_nodes_in_group("soldier"):
				if s.get("loadout") != null and not bool(s.get("dead")):
					_bot = s
			if _bot == null:
				return false
			m.player.ceasefire_t = 0.0
			m.player.take_damage(999.0, str(_bot.display_name), "AK-74", int(_bot.team))
			_t = _n
			_st = 2
		2:
			if _n - _t < 10:
				return false
			var sp = m.spectator
			var txt: String = m.hud.lbl_spectate.text
			if sp == null or not sp.is_killcam():
				return _end(false, "kill cam not active")
			if sp._target != _bot:
				return _end(false, "following %s, not the killer" % str(sp._target))
			if not (txt.contains("KILL CAM") and txt.contains(str(_bot.display_name)) and txt.contains("HP") and txt.contains("AK-74")):
				return _end(false, "hud: '%s'" % txt)
			_st = 3
			_t = _n
			print("KILLCAM hud: %s" % txt)
		3:
			# Respawn ends the kill cam.
			if m.player != null and is_instance_valid(m.player) and not bool(m.player.dead):
				if m.spectator.is_active():
					return _end(false, "spectator still on after respawn")
				return _end(true, "followed %s; respawn ended it" % str(_bot.display_name))
			if _n - _t > 900:
				return _end(false, "no respawn")
	return false


func _end(ok: bool, msg: String) -> bool:
	var st = root.get_node("Settings")
	st.bot_count = _saved[0]; st.game_mode = _saved[1]; st.map_index = _saved[2]; st.custom_map_path = _saved[3]
	print("KILLCAM-TEST %s %s" % ["ok" if ok else "FAIL", msg])
	quit(0 if ok else 1)
	return true
