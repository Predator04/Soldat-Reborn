extends SceneTree
## Medikit / grenade kit check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/kit_test.gd
## On Aftermath: counts the kits the map spawns, then hurts the player and
## drops him on a medikit (health back to 100), empties his grenades and drops
## him on a grenade kit (back to 3), and checks a full-health soldier leaves a
## medikit alone.

var _t := 0.0
var _phase := 0
var _step := 0
var _step_t := 0.0
var _log: Array = []


func _boxes(m, kind: String) -> Array:
	var out: Array = []
	for n in m.get_children():
		if n is Area2D and str(n.get("bonus_kind")) == kind:
			out.append(n)
	return out


func _fail(msg: String) -> bool:
	print("KIT-TEST FAIL %s | %s" % [msg, " ".join(_log)])
	quit()
	return true


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		st.set("custom_map_path", ""); st.set("map_index", 5); st.set("game_mode", 0)
		st.set("bot_count", 0)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null or m.get("hud") == null:
		return false
	_t += d
	_step_t += d
	if _t > 40.0:
		return _fail("timeout step=%d" % _step)
	var p = m.get("player")
	if _t < 1.5 or p == null or not is_instance_valid(p):
		return false
	p.set("ceasefire_t", 0.0)
	match _step:
		0:
			var med := _boxes(m, "medkit")
			var gk := _boxes(m, "grenades")
			_log.append("medkits=%d grenade_kits=%d" % [med.size(), gk.size()])
			if med.is_empty() or gk.is_empty():
				return _fail("map spawned no kits")
			# Full health: standing on a medikit must not use it up.
			p.global_position = med[0].global_position
			p.velocity = Vector2.ZERO
			_step = 1
			_step_t = 0.0
		1:
			if _step_t > 1.0:
				if int(m.get("kits_taken")) != 0:
					return _fail("full-health soldier took a medikit")
				_log.append("full-hp-ignored")
				p.set("health", 35.0)
				_step = 2
				_step_t = 0.0
		2:
			var med2 := _boxes(m, "medkit")
			if float(p.get("health")) >= 100.0:
				_log.append("healed")
				p.set("grenades", 0)
				var gk := _boxes(m, "grenades")
				p.global_position = gk[0].global_position
				p.velocity = Vector2.ZERO
				_step = 3
				_step_t = 0.0
			elif _step_t > 0.4 and not med2.is_empty():
				# Keep him on a live medikit (the poll picks up a soldier already on it).
				p.global_position = med2[0].global_position
				p.velocity = Vector2.ZERO
			if _step_t > 6.0:
				return _fail("medikit did not heal (hp=%.0f)" % float(p.get("health")))
		3:
			if int(p.get("grenades")) == 3:
				_log.append("grenades-refilled kits_taken=%d" % int(m.get("kits_taken")))
				print("KIT-TEST ok %s" % " ".join(_log))
				quit()
				return true
			if _step_t > 6.0:
				return _fail("grenade kit did not refill (g=%d)" % int(p.get("grenades")))
	return false
