extends SceneTree
## Trigger check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/fire_test.gd
## Every primary must fire from a plain click. The Barrett (semi-auto with a
## wind-up) used to spin up and never shoot; a tap must fire it once after the
## wind-up, and holding the trigger must not fire a second round.

const FRAMES_HELD := 3

var _t := 0.0
var _phase := 0
var _slot := 0
var _stage := 0
var _stage_t := 0.0
var _mag0 := 0
var _log: Array = []
var _bad: Array = []


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		st.set("custom_map_path", ""); st.set("map_index", 19); st.set("game_mode", 0); st.set("bot_count", 0)
		st.set("advance", false)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += d
	var p = m.get("player")
	if _t < 1.5 or p == null or not is_instance_valid(p) or p.get("dead") == true:
		return false
	if _t > 60.0:
		print("FIRE-TEST FAIL timeout slot=%d" % _slot)
		quit()
		return true
	_stage_t += d
	match _stage:
		0:
			p.call("_switch_weapon", _slot)
			p.set("reloading", false)
			p.call("_set_active_mag", int(p.weapons[_slot]["mag"]))
			p.set("fire_cd", 0.0)
			_mag0 = int(p.call("_active_mag"))
			_stage = 1
			_stage_t = 0.0
		1:
			if _stage_t > 0.3:   # weapon switch cooldown
				Input.action_press("fire")
				_stage = 2
				_stage_t = 0.0
		2:
			# Wind-up guns (Barrett, Minigun): hold the trigger for the whole
			# window; everything else: a short tap.
			var hold: bool = float(p.weapons[_slot].get("startup", 0.0)) > 0.0
			var semi: bool = not bool(p.weapons[_slot].get("auto", false))
			if not hold and _stage_t > FRAMES_HELD / 60.0:
				Input.action_release("fire")
			if _stage_t > 1.2:
				Input.action_release("fire")
				var used: int = _mag0 - int(p.call("_active_mag"))
				var wn: String = str(p.weapons[_slot]["name"])
				_log.append("%s=%d" % [wn, used])
				var ok: bool = used >= 1 and (not (hold and semi) or used == 1)
				if not ok:
					_bad.append(wn)
				_slot += 1
				_stage = 0
				if _slot >= p.weapons.size():
					if _bad.is_empty():
						print("FIRE-TEST ok %s" % " ".join(_log))
					else:
						print("FIRE-TEST FAIL %s | %s" % [str(_bad), " ".join(_log)])
					quit()
					return true
	return false
