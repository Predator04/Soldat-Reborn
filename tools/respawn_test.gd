extends SceneTree
## Respawn / death-screen regression test (gate stage R).
##   godot --headless --fixed-fps 60 -s tools/respawn_test.gd -- --mode=2 [--survival]
## Kills the player a few seconds in, waits for the next life (timed respawn,
## or the Survival round reset), and checks the death screen is gone once the
## new body is alive. Prints RESPAWN-TEST ok / FAIL.

var _t := 0.0
var _loaded := false
var _killed := false
var _mode := 2
var _survival := false
var _died_at := -1.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			_mode = int(a.substr(7))
		elif a == "--survival":
			_survival = true


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if not _loaded:
		st.set("custom_map_path", "")
		st.set("map_index", 19)
		st.set("game_mode", _mode)
		st.set("survival", _survival)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_loaded = true
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null or m.get("hud") == null:
		return false
	_t += d
	var p = m.get("player")
	var alive: bool = p != null and is_instance_valid(p) and not bool(p.get("dead"))
	if not _killed:
		if _t > 3.0 and alive:
			_killed = true
			p.apply_gesture("/kill")
		return false
	if _died_at < 0.0:
		if not alive:
			_died_at = _t
		return false
	if alive and _t - _died_at > 0.5:
		# Give the HUD a frame to settle, then check.
		var dead_ui: bool = bool(m.hud.get("_dead"))
		var overlay: bool = m.hud.get("desat_overlay") != null and bool(m.hud.desat_overlay.visible)
		if dead_ui or overlay:
			print("RESPAWN-TEST FAIL mode=%d survival=%s respawned after %.1fs but death_ui=%s overlay=%s" % [_mode, str(_survival), _t - _died_at, str(dead_ui), str(overlay)])
		else:
			print("RESPAWN-TEST ok mode=%d survival=%s respawned after %.1fs" % [_mode, str(_survival), _t - _died_at])
		quit()
		return true
	if _t > 400.0:
		print("RESPAWN-TEST FAIL mode=%d survival=%s never respawned" % [_mode, str(_survival)])
		quit()
		return true
	return false
