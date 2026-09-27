extends SceneTree
## Plays the Training match by injecting input for whatever step is showing.
##   godot --headless --fixed-fps 60 -s tools/training_test.gd
## Prints TRAINING-TEST ok / FAIL (gate stage F).

var _t := 0.0
var _phase := 0
var _orig_mode := -1
var _step_t := 0.0
var _last_step := -1
var _tap := 0.0


func _release_all() -> void:
	for a in ["move_left", "move_right", "jump", "jet", "fire", "reload", "weapon_1", "grenade", "crouch", "secondary_swap"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		st.set("game_mode", 2)
		_orig_mode = 2
		load("res://scripts/training.gd").start_training()
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if _phase == 1:
		if m == null or m.get("hud") == null or m.hud.get_node_or_null("Training") == null:
			return false
		_t += d
		var tr = m.hud.get_node("Training")
		var step: int = int(tr.get("_step"))
		if step != _last_step:
			_last_step = step
			_step_t = 0.0
			_release_all()
		_step_t += d
		var p = m.get("player")
		if step >= 9:
			_release_all()
			print("TRAINING-TEST steps done in %.1fs" % _t)
			change_scene_to_file("res://scenes/menu.tscn")
			_phase = 2
			return false
		if p == null or not is_instance_valid(p) or bool(p.get("dead")):
			return false
		_tap -= d
		var name: String = str(tr.STEPS[step][0])
		match name:
			"MOVE":
				var right: bool = int(_step_t) % 2 == 0
				Input.action_press("move_right" if right else "move_left")
				Input.action_release("move_left" if right else "move_right")
			"JUMP":
				if p.is_on_floor():
					Input.action_press("jump")
				else:
					Input.action_release("jump")
			"JET BOOTS":
				if p.is_on_floor():
					Input.action_press("jump")
				else:
					Input.action_release("jump")
					Input.action_press("jet")
			"SHOOT", "RELOAD", "SWITCH WEAPON", "GRENADE":
				var a: String = {"SHOOT": "fire", "RELOAD": "reload", "SWITCH WEAPON": "weapon_1", "GRENADE": "grenade"}[name]
				if _tap <= 0.0:
					_tap = 0.25
					if Input.is_action_pressed(a):
						Input.action_release(a)
					else:
						Input.action_press(a)
			"CROUCH":
				Input.action_press("crouch")
			"FIGHT":
				for s in get_nodes_in_group("soldier"):
					if is_instance_valid(s) and s != p and s.get("loadout") != null and not bool(s.get("dead")) and _step_t > 1.0:
						s.take_damage(999.0, str(p.display_name), "AK-74", int(p.team))
		if _t > 120.0:
			print("TRAINING-TEST FAIL stuck on step %d (%s)" % [step, name])
			quit()
			return true
		return false
	if _phase == 2:
		_t += d
		if m != null and m.name != "Main" and _t > 0.5:
			var ok: bool = int(st.get("game_mode")) == _orig_mode and not bool(st.get("training")) and int(st.get("bot_count")) != 0
			print("TRAINING-TEST %s settings_restored=%s mode=%d bots=%d" % ["ok" if ok else "FAIL", str(ok), int(st.get("game_mode")), int(st.get("bot_count"))])
			quit()
			return true
	return false
