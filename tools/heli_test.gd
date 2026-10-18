extends SceneTree
## Helicopter check (gate stage F, #277).
##   godot --headless --fixed-fps 60 -s tools/heli_test.gd
## On a flat range: F seats you as the pilot; the rotor has to spin up before
## it lifts; W climbs to altitude, it hovers / settles gently, A/D flies it
## sideways, S lands it softly (no damage); a salvo of two rockets hits a bot;
## bullets do half damage and explosives full (1.5x through splash); the door
## gunner seat fires the MG (human and bot); 0 HP at altitude = spin-out ->
## crash -> wreck that kills the pilot, then a respawn on its pad; an idle,
## displaced helicopter goes home (#259); a gentle wreck on the ground ejects
## the crew alive; a bot pilot takes off. Also: the big open classic maps carry
## heli_spawns.

const G := 1900.0

var _phase := 0
var _t := 0.0
var _st := 0
var _st_t := 0.0
var _log: Array = []
var _bad: Array = []
var _h: Node = null
var _ba: Node = null     # bot A: gunner / pilot
var _bb: Node = null     # bot B: target dummy
var _y0 := 0.0
var _x0 := 0.0
var _lift_t := -1.0
var _hp0 := 0.0
var _php0 := 0.0
var _drv_dead := false
var _protect := true
var _spawn := Vector2.ZERO
var _maxalt := 0.0


func _key(action: String, down: bool) -> void:
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _fail(msg: String) -> bool:
	for a in ["jump", "crouch", "move_right", "move_left", "fire", "weapon_throw"]:
		Input.action_release(a)
	print("HELI-TEST FAIL %s | %s" % [msg, " ".join(_log)])
	quit()
	return true


func _next(st: int) -> void:
	_st = st
	_st_t = 0.0


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		var n := 0
		for f in DirAccess.get_files_at("res://assets/maps"):
			if f.ends_with(".json") and FileAccess.get_file_as_string("res://assets/maps/" + f).contains("heli_spawns"):
				n += 1
		_log.append("maps_with_helis=%d" % n)
		if n < 8:
			_bad.append("only %d classic maps have heli spawns" % n)
		var MapIO = load("res://scripts/map_io.gd")
		var m := {"name": "qa_heli", "platforms": [], "player_spawn": Vector2(600, G - 20),
			"bot_spawns": [Vector2(2400, G - 20), Vector2(2600, G - 20)], "heli_spawns": [Vector2(900, G)]}
		st.set("custom_map_path", MapIO.save_to_file("qa_heli", m))
		st.set("game_mode", 0); st.set("bot_count", 2); st.set("vehicles", true)
		st.set("survival", false); st.set("realistic", false); st.set("advance", false)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += d
	_st_t += d
	if _t > 110.0:
		return _fail("timeout st=%d" % _st)
	var p = m.get("player")
	if _st == 0 and (_t < 1.0 or p == null or not is_instance_valid(p)):
		return false
	if p != null and is_instance_valid(p):
		if _protect and p.get("dead") != true:
			p.set("health", 100.0)
			p.set("ceasefire_t", 999.0)
		else:
			p.set("ceasefire_t", 0.0)
	if _bb != null and is_instance_valid(_bb):
		_bb.set("ceasefire_t", 0.0)
	var hn := _h as Node2D
	var hb := _h as CharacterBody2D
	match _st:
		0:
			for v in get_nodes_in_group("vehicle"):
				_h = v
			for s in get_nodes_in_group("soldier"):
				if s.get("bot_id") != null:
					if _ba == null:
						_ba = s
					else:
						_bb = s
			if _h == null or _h.get("kind") != "heli":
				return _fail("no helicopter spawned")
			if _ba == null or _bb == null:
				return _fail("bots missing")
			if float(_h.get("hp")) != 420.0:
				_bad.append("heli hp %d" % int(_h.get("hp")))
			if not _h.is_in_group("vehicle") or not _h.has_method("seat_of"):
				_bad.append("not a seated vehicle (trust riding exemption)")
			for b in [_ba, _bb]:
				b.set_physics_process(false)
				b.set_process(false)
				(b as Node2D).global_position = Vector2(3000, G - 20)
			_spawn = (_h as Node2D).global_position
			p.global_position = (_h as Node2D).global_position + Vector2(-20, -10)
			p.velocity = Vector2.ZERO
			_next(1)
		1:
			# F seats the pilot.
			if _st_t > 0.3 and _st_t < 0.45:
				_key("weapon_throw", true)
			if _st_t >= 0.45:
				_key("weapon_throw", false)
			if _h.seat_of(p) == 0:
				_key("weapon_throw", false)
				_log.append("pilot")
				_y0 = hn.global_position.y
				_key("jump", true)
				_next(2)
			elif _st_t > 1.5:
				return _fail("F did not seat the pilot")
		2:
			# Spin-up gate, then lift-off.
			var up: float = _y0 - hn.global_position.y
			if up > 8.0 and _lift_t < 0.0:
				_lift_t = _st_t
			if _st_t > 0.7 and _st_t < 0.75 and up > 4.0:
				_bad.append("lifted before the rotor spun up (%.0fpx at %.2fs)" % [up, _st_t])
			if up > 320.0:
				_key("jump", false)
				_log.append("liftoff=%.2fs climb320=%.2fs" % [_lift_t, _st_t])
				if _lift_t < 0.8:
					_bad.append("lift-off too early %.2f" % _lift_t)
				_y0 = hn.global_position.y
				_next(3)
			elif _st_t > 5.0:
				return _fail("never climbed (up=%.0f rpm=%.2f)" % [up, float(_h.get("rpm"))])
		3:
			# Hands off: settles gently, doesn't drop.
			if _st_t < 0.8:
				_y0 = hn.global_position.y
			if _st_t > 1.8:
				var sank: float = hn.global_position.y - _y0
				_log.append("hover_sink=%.0fpx/s" % sank)
				if sank > 120.0 or sank < -20.0:
					_bad.append("hover not gentle (%.0f)" % sank)
				_x0 = hn.global_position.x
				_key("move_right", true)
				_next(4)
		4:
			if _st_t > 2.0:
				_key("move_right", false)
				var dx: float = hn.global_position.x - _x0
				_log.append("flew=%dpx vmax~%d" % [dx, int(hb.velocity.x)])
				if dx < 400.0:
					_bad.append("barely flew sideways")
				if p.global_position.distance_to(hn.global_position) > 60.0:
					_bad.append("pilot not riding along")
				_hp0 = float(_h.get("hp"))
				_key("crouch", true)
				_next(5)
		5:
			if hb.is_on_floor() and absf(hb.velocity.y) < 5.0 and _st_t > 0.3:
				_key("crouch", false)
				_log.append("landed hp=%d" % int(_h.get("hp")))
				if float(_h.get("hp")) < _hp0:
					_bad.append("soft landing hurt it")
				_next(6)
			elif _st_t > 6.0:
				return _fail("never landed")
		6:
			# Rockets at a bot 420 px ahead, level with the pod.
			if _st_t > 0.5:
				_bb.set("health", 1000.0)
				_bb.global_position = hn.global_position + Vector2(float(_h.get("face")) * 420.0, -1.0)
				_bb.set("velocity", Vector2.ZERO)
				var to: Vector2 = _bb.global_position + Vector2(0, -10) - _h._rocket_muzzle()
				_h.set("_rocket_aim", _h._clamp_to_nose(to.normalized()))
				_hp0 = float(_h.get("hp"))
				_h._fire_rockets(p)
				if int(_h.get("rockets_fired")) != 2:
					_bad.append("salvo != 2 rockets (%d)" % int(_h.get("rockets_fired")))
				var n := 0
				for r in m.get_children():
					if str(r.name).begins_with("HeliRocket_"):
						n += 1
				_log.append("rockets_in_air=%d" % n)
				_h._fire_rockets(p)
				if int(_h.get("rockets_fired")) != 2:
					_bad.append("cooldown ignored")
				_next(7)
		7:
			if float(_bb.get("health")) < 1000.0:
				_log.append("rockets hit bot hp=%d t=%.2fs" % [int(_bb.get("health")), _st_t])
				if float(_h.get("hp")) < _hp0:
					_bad.append("own rockets hurt the heli")
				var h0: float = float(_h.get("hp"))
				_h.take_damage(100.0, "QA", "AK-74", 77)
				var h1: float = float(_h.get("hp"))
				_h.take_damage(100.0, "QA", "LAW", 77)
				var h2: float = float(_h.get("hp"))
				_h.apply_hp(420.0)
				var Buggy = load("res://scripts/buggy.gd")
				Buggy.splash(self, hn.global_position, 120.0, 100.0, "QA", "LAW", 77)
				var h3: float = float(_h.get("hp"))
				_log.append("dmg bullet=%d explosive=%d splash=%d" % [h0 - h1, h1 - h2, 420.0 - h3])
				if absf((h0 - h1) - 50.0) > 0.5 or absf((h1 - h2) - 100.0) > 0.5 or (420.0 - h3) < 100.0:
					_bad.append("damage ratios wrong")
				_h.apply_hp(420.0)
				_bb.global_position = Vector2(3000, G - 20)
				# Human door gunner: out, back in on seat 1.
				_h.clear_seat_of(p)
				_next(8)
			elif _st_t > 3.0:
				return _fail("rockets never hit (bot hp %d)" % int(_bb.get("health")))
		8:
			if _st_t > 0.3 and _st_t < 0.35:
				_h.set_seat(1, p)
				_h.set("heat", 0.0)
				_h.set("fire_cd", 0.0)
			if _st_t > 0.4:
				_key("fire", true)
			if _st_t > 0.9:
				_key("fire", false)
				_log.append("gunner heat=%.2f seat=%d cd=%.2f oh=%s il=%s" % [float(_h.get("heat")), _h.seat_of(p), float(_h.get("fire_cd")), str(_h.get("overheated")), str(p.get("input_locked"))])
				if float(_h.get("heat")) <= 0.0:
					_bad.append("door gunner seat did not fire")
				_h.clear_seat_of(p)
				_next(9)
		9:
			# Bot gunner shoots at a target while the human pilots.
			if _st_t > 0.3 and _st_t < 0.35:
				p.global_position = hn.global_position + Vector2(-16, -10)
				_h.request_enter(p)
			if _st_t > 0.5 and _st_t < 0.55:
				if _h.seat_of(p) != 0:
					return _fail("re-entry as pilot failed")
				_ba.global_position = hn.global_position + Vector2(10, -10)
				m._vehicles_sys.vehicle_bot_board(_h, _ba, 1)
				_h.set("heat", 0.0)
				if _h.gunner() != _ba:
					return _fail("bot did not board as gunner")
			if _st_t > 0.6:
				_bb.global_position = hn.global_position + Vector2(-500, -260)
				_bb.set("velocity", Vector2.ZERO)
				_ba.set("target", _bb)
				_ba.set("_target_visible", true)
			if _st_t > 0.6 and float(_h.get("heat")) > 0.0:
				_log.append("bot gunner fired t=%.1fs" % _st_t)
				_h.clear_seat_of(_ba)
				_ba.global_position = Vector2(3000, G - 20)
				_bb.global_position = Vector2(3200, G - 20)
				_y0 = hn.global_position.y
				_key("jump", true)
				_next(10)
			elif _st_t > 4.0:
				return _fail("bot gunner never fired")
		10:
			# Climb, then 0 HP: spin out, crash, wreck kills the pilot.
			if _y0 - hn.global_position.y > 260.0 or _st_t > 3.5:
				_key("jump", false)
				_protect = false
				_drv_dead = false
				m.kill.connect(func(_k, v, _w, _kt, _vt): if str(v) == str(p.display_name): _drv_dead = true)
				_h.take_damage(99999.0, "QA", "LAW", 77)
				if not _h.spinning_out():
					return _fail("no spin-out at 0 HP")
				_next(11)
		11:
			if _h.get("alive") == false:
				_log.append("crashed after %.2fs crew_dead=%s" % [_st_t, str(_drv_dead)])
				_next(12)
			elif _st_t > 4.0:
				return _fail("spin-out never crashed")
		12:
			if _st_t > 0.3:
				if not _drv_dead:
					_bad.append("violent crash left the pilot alive")
				if hb.global_position.y < G - 60.0 and _st_t > 2.5:
					_bad.append("wreck floating at y=%d" % int(hb.global_position.y))
			if _st_t > 2.6:
				_protect = true
				_h.set("_respawn_t", 0.05)
				_next(13)
		13:
			if _h.get("alive") == true:
				var dpad: float = hn.global_position.distance_to(_spawn)
				_log.append("respawned hp=%d pad_dist=%d" % [int(_h.get("hp")), int(dpad)])
				if float(_h.get("hp")) != 420.0 or dpad > 30.0:
					_bad.append("respawn wrong")
				# #259 idle return: shove it off its pad, shorten the clock.
				_h.set("idle_respawn_time", 1.0)
				hn.global_position += Vector2(300, -40)
				_next(14)
			elif _st_t > 2.0:
				return _fail("never respawned")
		14:
			if _st_t > 3.0:
				var dpad2: float = hn.global_position.distance_to(_spawn)
				_log.append("idle_return pad_dist=%d" % int(dpad2))
				if dpad2 > 30.0:
					_bad.append("idle helicopter didn't go home")
				_h.set("idle_respawn_time", 60.0)
				# Gentle wreck on the ground ejects the crew alive.
				_ba.set("health", 100.0)
				_ba.set("dead", false)
				_ba.global_position = hn.global_position + Vector2(10, -10)
				m._vehicles_sys.vehicle_bot_board(_h, _ba, 1)
				if _h.gunner() != _ba:
					return _fail("bot gunner boarding (eject test) failed")
				_h.take_damage(99999.0, "QA", "LAW", 77)
				_next(15)
		15:
			if _st_t > 0.3:
				var ok: bool = _h.get("alive") == false and _ba.get("dead") != true and _h.seat_of(_ba) < 0
				_log.append("gentle wreck: crew ejected alive=%s hp=%d" % [str(ok), int(_ba.get("health"))])
				if not ok:
					_bad.append("gentle wreck didn't eject the crew alive")
				_h.set("_respawn_t", 0.05)
				_next(16)
		16:
			if _h.get("alive") == true and _st_t > 0.5:
				# Bot pilot: boards, waits for the rotor, takes off.
				_ba.set_physics_process(true)
				_ba.set("health", 100.0)
				_ba.global_position = hn.global_position + Vector2(10, -10)
				m._vehicles_sys.vehicle_bot_board(_h, _ba, 0)
				if _h.driver() != _ba:
					return _fail("bot did not board as pilot")
				_y0 = hn.global_position.y
				_bb.global_position = Vector2(2600, G - 20)
				_maxalt = 0.0
				_next(17)
		17:
			_ba.set("target", _bb)
			_maxalt = maxf(_maxalt, _y0 - hn.global_position.y)
			if _st_t > 8.0:
				_log.append("bot pilot max_alt=%dpx hp=%d x=%d seated=%s" % [int(_maxalt), int(_h.get("hp")), int(hn.global_position.x), str(_h.driver() == _ba)])
				if _maxalt < 150.0:
					_bad.append("bot pilot never took off")
				if float(_h.get("hp")) < 300.0:
					_bad.append("bot pilot crashed into things")
				print("HELI-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
				quit()
				return true
	return false
