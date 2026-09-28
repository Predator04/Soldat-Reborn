extends SceneTree
## Weapon range test (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/weapon_test.gd
## On a flat test range, the player uses every primary and secondary against a
## frozen target: each must damage it, spend ammo, and reload back to a full
## mag. Then a bot armed with each bot weapon must hurt a (1000 HP) player.
## Prints WEAPON-TEST ok / FAIL with per-weapon numbers.

const RANGE_Y := 1900.0

var _phase := 0
var _t := 0.0
var _slots: Array = []      # [secondary?, index, name]
var _i := 0
var _st := 0
var _st_t := 0.0
var _mag0 := 0
var _hp0 := 0.0
var _dmg := 0.0
var _log: Array = []
var _bad: Array = []
var _target: Node = null
var _bot_list: Array = []
var _bi := 0
var _p_hp_min := 100.0


func _init_map() -> void:
	var MapIO = load("res://scripts/map_io.gd")
	var m := {"name": "qa_range", "platforms": [], "player_spawn": Vector2(1000, RANGE_Y - 20),
		"bot_spawns": [Vector2(1300, RANGE_Y - 20)]}
	var path: String = MapIO.save_to_file("qa_range", m)
	var st = root.get_node("Settings")
	st.set("custom_map_path", path)
	st.set("game_mode", 0); st.set("bot_count", 1); st.set("bot_skill", 3)
	st.set("realistic", false); st.set("advance", false); st.set("survival", false)


func _aim(v: Vector2) -> void:
	for a in ["aim_left", "aim_right", "aim_up", "aim_down"]:
		Input.action_release(a)
	v = v.normalized()
	if v.x > 0: Input.action_press("aim_right", v.x)
	if v.x < 0: Input.action_press("aim_left", -v.x)
	if v.y < 0: Input.action_press("aim_up", -v.y)
	if v.y > 0: Input.action_press("aim_down", v.y)


func _w(p) -> Dictionary:
	var s: Array = _slots[_i]
	return (p.secondary if s[0] else p.weapons)[s[1]]


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		_init_map()
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += d
	if _t > 170.0:
		print("WEAPON-TEST FAIL timeout phase=%d i=%d %s" % [_phase, _i, " ".join(_log)])
		quit()
		return true
	var p = m.get("player")
	if _t < 1.0 or p == null or not is_instance_valid(p):
		return false
	if _phase == 1:
		for i in p.weapons.size():
			_slots.append([false, i, str(p.weapons[i]["name"])])
		for i in p.secondary.size():
			_slots.append([true, i, str(p.secondary[i]["name"])])
		for s in get_nodes_in_group("soldier"):
			if s.get("bot_id") != null:
				_target = s
		if _target == null:
			print("WEAPON-TEST FAIL no target bot")
			quit()
			return true
		_target.set_physics_process(false)
		_target.set_process(false)
		_phase = 2
		_st = 0
	if _phase == 2:
		return _player_step(m, p, d)
	if _phase == 3:
		return _bot_step(m, p, d)
	return false


func _player_step(m, p, d: float) -> bool:
	_st_t += d
	p.set("ceasefire_t", 0.0)
	p.set("health", 100.0)
	var w: Dictionary = _w(p)
	var wn: String = str(w["name"])
	var kind: String = str(w.get("kind", "bullet"))
	match _st:
		0:
			Input.action_release("fire")
			var s: Array = _slots[_i]
			if s[0]:
				p.set("using_secondary", true)
				p.set("secondary_index", s[1])
			else:
				p.set("using_secondary", false)
				p.set("weapon_index", s[1])
			p.set("reloading", false)
			p.set("fire_cd", 0.0)
			p.set("spin_up_t", 0.0)
			p.call("_set_active_mag", int(w["mag"]))
			var dist := 300.0
			var aim := Vector2.RIGHT
			if kind == "melee" or kind == "melee_cont":
				dist = 22.0
			elif kind == "flame":
				dist = 80.0
			elif wn == "M79":
				dist = 200.0
				aim = Vector2(cos(deg_to_rad(-31.0)), sin(deg_to_rad(-31.0)))
			elif kind == "rocket":
				dist = 380.0
			elif kind == "arrow":
				aim = Vector2(cos(deg_to_rad(-3.0)), sin(deg_to_rad(-3.0)))   # arrows sag
			p.global_position = Vector2(1000, RANGE_Y - 20)
			p.velocity = Vector2.ZERO
			_target.set("dead", false)
			_target.set("health", 1000.0)
			_target.set("ceasefire_t", 0.0)
			_target.global_position = Vector2(1000 + dist, RANGE_Y - 20)
			_aim(aim)
			_mag0 = int(w["mag"])
			_hp0 = 1000.0
			_dmg = 0.0
			_st = 1
			_st_t = 0.0
		1:
			if _st_t > 0.4:   # settle + switch cooldown
				_st = 2
				_st_t = 0.0
		2:
			# The frozen target doesn't fall: keep it level with the (settled) shooter.
			_target.global_position.y = p.global_position.y
			# Auto weapons: hold. Semi: click every 0.25 s.
			var auto: bool = bool(w.get("auto", false))
			if auto:
				Input.action_press("fire")
			else:
				if fmod(_st_t, 0.3) < 0.15:
					Input.action_press("fire")
				else:
					Input.action_release("fire")
			var hp: float = float(_target.get("health"))
			if _target.get("dead") == true:
				hp = -1.0
			_dmg = maxf(_dmg, 1000.0 - hp)
			if _dmg > 0.0 and _st_t > 0.5 or _st_t > 3.0:
				Input.action_release("fire")
				var used: int = _mag0 - int(p.call("_active_mag"))
				_log.append("%s dmg=%.0f used=%d" % [wn, _dmg, used])
				if _dmg <= 0.0:
					_bad.append(wn + " no damage")
				if used <= 0 and kind != "melee":
					_bad.append(wn + " used no ammo")
				_st = 3
				_st_t = 0.0
		3:
			# Reload from empty (melee knife has nothing to reload).
			if kind == "melee":
				_next()
				return false
			p.call("_set_active_mag", 0)
			p.set("fire_cd", 0.0)
			Input.action_press("reload")
			_st = 4
			_st_t = 0.0
		4:
			if _st_t > 0.1:
				Input.action_release("reload")
			if int(p.call("_active_mag")) == int(w["mag"]):
				_next()
			elif _st_t > float(w.get("reload", 2.0)) + 1.5:
				_bad.append(wn + " did not reload (mag=%d)" % int(p.call("_active_mag")))
				_next()
	return false


func _next() -> void:
	_i += 1
	_st = 0
	if _i >= _slots.size():
		_phase = 3
		_st = 0


# Bots: every bot weapon must be able to hurt a player standing in the open.
func _bot_step(m, p, d: float) -> bool:
	_st_t += d
	var B: Dictionary = (load("res://scripts/bot.gd") as GDScript).get_script_constant_map()
	if _bot_list.is_empty():
		for k in B.WEAPON_STATS:
			_bot_list.append(str(k))
		_target.set_physics_process(true)
		_target.set_process(true)
	p.set("ceasefire_t", 0.0)
	if p.get("dead") == true:
		_st_t = 0.0
		return false
	var wn: String = _bot_list[_bi]
	match _st:
		0:
			_target.set("loadout", wn)
			_target.set("using_secondary", false)
			_target.set("ammo", 999)
			_target.set("health", 100.0)
			_target.set("ceasefire_t", 0.0)
			var near: bool = wn in ["Knife", "Chainsaw", "Flamethrower"]
			_target.global_position = Vector2(1000 + (40.0 if near else 320.0), RANGE_Y - 20)
			p.global_position = Vector2(1000, RANGE_Y - 20)
			p.set("health", 1000.0)
			_p_hp_min = 1000.0
			_st = 1
			_st_t = 0.0
		1:
			p.set("ceasefire_t", 0.0)
			_target.set("ammo", 999)
			_target.set("_retreat_t", 0.0)   # left over from being shot in phase 2
			_p_hp_min = minf(_p_hp_min, float(p.get("health")))
			if float(p.get("health")) < 400.0:
				p.set("health", 1000.0)
			if _p_hp_min < 1000.0 or _st_t > 10.0:
				_log.append("bot:%s hurt=%s" % [wn, str(_p_hp_min < 1000.0)])
				if _p_hp_min >= 1000.0:
					_bad.append("bot " + wn + " never hurt the player")
				_bi += 1
				_st = 0
				if _bi >= _bot_list.size():
					print("WEAPON-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
					quit()
					return true
	return false
