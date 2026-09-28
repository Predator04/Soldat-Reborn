extends SceneTree
## Grenade cooking check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/grenade_test.gd
## tap -> thrown, soft; 0.9 s hold -> thrown hard with a shorter fuse;
## hold past the fuse -> goes off in hand and kills the thrower.

var _t := 0.0
var _phase := 0
var _stage := 0
var _stage_t := 0.0
var _log: Array = []
var _grenades_before := 0
var _spawned: Array = []   # [speed, fuse] of each grenade as it enters the tree
var _hooked := false
var _wait := 3.5
var _holder: Node = null
var _inhand_dead := false
var _holding := false


func _on_child(n: Node) -> void:
	if n is RigidBody2D and n.get("fuse") != null:
		_spawned.append([(n as RigidBody2D).linear_velocity.length(), float(n.get("fuse"))])


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		st.set("custom_map_path", ""); st.set("map_index", 19); st.set("game_mode", 0); st.set("bot_count", 0)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null:
		return false
	if not _hooked:
		_hooked = true
		m.child_entered_tree.connect(_on_child)
	_t += d
	var p = m.get("player")
	if _t < 1.5:
		return false
	if _t > 40.0:
		print("GRENADE-TEST FAIL timeout stage=%d log=%s" % [_stage, " | ".join(_log)])
		quit()
		return true
	_stage_t += d
	# Our own grenades land close; wait out any death / respawn between stages.
	if _holding:
		# Holding: the body we pressed with must die before 2.6 s.
		if not is_instance_valid(_holder) or bool(_holder.get("dead")):
			_inhand_dead = true
	elif p == null or not is_instance_valid(p) or bool(p.get("dead")):
		_stage_t = 0.0
		Input.action_release("grenade")
		return false
	if _stage >= 1 and _wait > 0.0:
		_wait -= d
		_stage_t = 0.0
		return false
	match _stage:
		0:  # tap
			if _stage_t < 0.05:
				_spawned.clear()
				Input.action_press("grenade")
			elif _stage_t < 0.2:
				Input.action_release("grenade")
			elif _stage_t > 0.3:
				_log.append(_check("tap", 250.0, 360.0, 2.0, 2.25))
				_next()
		1:  # full wind-up
			if _stage_t < 0.05:
				_spawned.clear()
				Input.action_press("grenade")
			elif _stage_t > 0.95 and Input.is_action_pressed("grenade"):
				Input.action_release("grenade")
			elif _stage_t > 1.1:
				_log.append(_check("windup", 600.0, 700.0, 1.1, 1.4))
				_next()
				_wait = 3.5
		2:  # hold too long
			if not _holding:
				_holding = true
				_holder = p
				Input.action_press("grenade")
			if _stage_t > 2.6:
				Input.action_release("grenade")
				var dead: bool = _inhand_dead
				_log.append("inhand dead=%s" % str(dead))
				var ok: bool = true
				for l in _log:
					if "FAIL" in str(l) or ("inhand" in str(l) and not "dead=true" in str(l)):
						ok = false
				print("GRENADE-TEST %s %s" % ["ok" if ok else "FAIL", " | ".join(_log)])
				quit()
				return true
	return false


func _next() -> void:
	_stage += 1
	_stage_t = 0.0


func _check(label: String, vmin: float, vmax: float, fmin: float, fmax: float) -> String:
	if _spawned.size() != 1:
		return "%s FAIL spawned=%d" % [label, _spawned.size()]
	var sp: float = _spawned[0][0]
	var fu: float = _spawned[0][1]
	_spawned.clear()
	var ok: bool = sp >= vmin and sp <= vmax and fu >= fmin and fu <= fmax
	return "%s %s speed=%.0f fuse=%.2f" % [label, "ok" if ok else "FAIL", sp, fu]
