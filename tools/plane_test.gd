extends SceneTree
## Plane check (gate stage F, #291).
##   godot --headless --fixed-fps 60 -s tools/plane_test.gd
## map_io keeps plane_spawns through a save / load round trip. On a flat range
## with a runway plane and an air-spawn plane: F seats the pilot (hidden in the
## cockpit); the nose gun hits a bot; the take-off run (nose can't lift below
## ROTATE_SPEED); level flight holds its height at speed; a loop at speed
## comes all the way round without stalling; slow + nose up = stall: the nose
## drops and it falls (it can't hover), and throttle recovers it; a bomb drops
## (cooldown) and hits a bot below; a gentle touchdown costs nothing, a hard
## one costs HP by impact speed, a nose-dive wrecks it and kills the pilot;
## respawn on its spot; shot down in the air ejects the pilot alive; F gets
## out; the air-spawn plane waits in the air, launches flying when boarded,
## falls when abandoned and comes back to its spot; a bot pilot takes off and
## flies; a plane a bot left parked down the runway goes home ~8 s after it
## stops (#294). Then a Maker map in CTF: a bot boards a plane on its own and flies it
## (distance flown in the air), without flying into the ground over and over.

const G := 1900.0

var _phase := 0
var _t := 0.0
var _st := 0
var _st_t := 0.0
var _log: Array = []
var _bad: Array = []
var _pg: Node = null     # runway plane
var _pa: Node = null     # air-spawn plane
var _ba: Node = null     # bot A: pilot
var _bb: Node = null     # bot B: target dummy
var _protect := true
var _x0 := 0.0
var _y0 := 0.0
var _v := 0.0
var _acc := 0.0
var _prev := 0.0
var _minsp := 0.0
var _hp0 := 0.0
var _flag := false
var _dead := false
var _spawn_g := Vector2.ZERO
var _spawn_a := Vector2.ZERO
var _maxalt := 0.0
var _lift_v := -1.0
var _maker_t := 0.0
var _maker_planes: Array = []


func _key(action: String, down: bool) -> void:
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_all() -> void:
	for a in ["jump", "crouch", "move_right", "move_left", "fire", "weapon_throw", "grenade"]:
		Input.action_release(a)


func _fail(msg: String) -> bool:
	_release_all()
	print("PLANE-TEST FAIL %s | %s" % [msg, " ".join(_log)])
	quit()
	return true


func _next(st: int) -> void:
	_st = st
	_st_t = 0.0


func _up_key(pl: Node) -> String:
	return "move_left" if float(pl.get("face")) > 0.0 else "move_right"


## Put a plane in flight (sim peer = this one, single player).
func _set_flight(pl: Node, pos: Vector2, vel: Vector2, heading: float, thr: float) -> void:
	(pl as Node2D).global_position = pos
	pl.set("velocity", vel)
	pl.set("_tilt", heading)
	pl.set("face", 1.0 if cos(heading) >= 0.0 else -1.0)
	pl.set("throttle", thr)
	pl.set("_grounded", false)
	pl.set("air_parked", false)


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		var MapIO = load("res://scripts/map_io.gd")
		var m := {"name": "qa_plane", "platforms": [], "player_spawn": Vector2(500, G - 20),
			"bot_spawns": [Vector2(2400, G - 20), Vector2(2600, G - 20)],
			"plane_spawns": [Vector2(700, G), Vector2(3600, G - 700)]}
		var back: Dictionary = MapIO.json_to_map(MapIO.map_to_json(m))
		var ps: Array = back.get("plane_spawns", [])
		_log.append("map_io plane_spawns=%d" % ps.size())
		if ps.size() != 2 or ps[0] != Vector2(700, G) or ps[1] != Vector2(3600, G - 700):
			_bad.append("map_io round trip lost plane_spawns (%s)" % str(ps))
		var n := 0
		for f in DirAccess.get_files_at("res://assets/maps"):
			if f.ends_with(".json") and FileAccess.get_file_as_string("res://assets/maps/" + f).contains("plane_spawns"):
				n += 1
		_log.append("maps_with_planes=%d" % n)
		# #294: Outpost's ridge runway had no route to it on foot and was
		# dropped (tools/place_vehicles.py --plane now requires one): Fortress
		# and Industrial.
		if n < 2:
			_bad.append("only %d classic maps have plane spawns" % n)
		st.set("custom_map_path", MapIO.save_to_file("qa_plane", m))
		st.set("game_mode", 0); st.set("bot_count", 2); st.set("vehicles", true)
		st.set("survival", false); st.set("realistic", false); st.set("advance", false)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	if _phase == 2:
		return _maker_phase(d)
	var m = current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += d
	_st_t += d
	if _t > 150.0:
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
	var gn := _pg as Node2D
	var gb := _pg as CharacterBody2D
	match _st:
		0:
			for v in get_nodes_in_group("vehicle"):
				if str(v.get("kind")) != "plane":
					continue
				if bool(v.get("air_spawn")):
					_pa = v
				else:
					_pg = v
			for s in get_nodes_in_group("soldier"):
				if s.get("bot_id") != null:
					if _ba == null:
						_ba = s
					else:
						_bb = s
			if _pg == null or _pa == null:
				return _fail("planes missing (ground=%s air=%s)" % [str(_pg), str(_pa)])
			if _ba == null or _bb == null:
				return _fail("bots missing")
			for v in [_pg, _pa]:
				if float(v.get("hp")) != 380.0:
					_bad.append("plane hp %d" % int(v.get("hp")))
				if not v.is_in_group("vehicle") or not v.has_method("seat_of"):
					_bad.append("not a seated vehicle")
			if float(_pg.get("face")) != 1.0:
				_bad.append("runway plane faces the short side")
			if not bool(_pa.get("air_parked")) or float(_pa.get("face")) != -1.0:
				_bad.append("air plane not parked facing the middle (parked=%s face=%d)" % [str(_pa.get("air_parked")), int(_pa.get("face"))])
			for b in [_ba, _bb]:
				b.set_physics_process(false)
				b.set_process(false)
				(b as Node2D).global_position = Vector2(4300, G - 20)
			gn = _pg as Node2D
			_spawn_g = gn.global_position
			_spawn_a = (_pa as Node2D).global_position
			_log.append("spawn ground=(%d,%d) air=(%d,%d)" % [int(_spawn_g.x), int(_spawn_g.y), int(_spawn_a.x), int(_spawn_a.y)])
			if G - _spawn_g.y < 6.0 or G - _spawn_g.y > 22.0:
				_bad.append("runway plane not resting on its wheels (%.0f above the ground)" % (G - _spawn_g.y))
			p.global_position = gn.global_position + Vector2(-20, 10)
			p.velocity = Vector2.ZERO
			_next(1)
		1:
			# F seats the pilot, hidden in the cockpit.
			if _st_t > 0.3 and _st_t < 0.45:
				_key("weapon_throw", true)
			if _st_t >= 0.45:
				_key("weapon_throw", false)
			if _pg.seat_of(p) == 0:
				_key("weapon_throw", false)
				_log.append("pilot")
				_next(2)
			elif _st_t > 1.5:
				return _fail("F did not seat the pilot")
		2:
			# Nose gun on the ground at a bot level with the nose.
			if _st_t > 0.2 and _st_t < 0.25:
				if (p as CanvasItem).visible:
					_bad.append("pilot body still drawn in the cockpit")
				if (p as Node2D).global_position.distance_to(gn.global_position) > 20.0:
					_bad.append("pilot not in the cockpit")
			if _st_t > 0.3 and _st_t < 0.35:
				_bb.set("health", 1000.0)
				_bb.global_position = Vector2(gn.global_position.x + 320.0, G - 1.0)
				_bb.set("velocity", Vector2.ZERO)
				_pg.set("heat", 0.0)
				_key("fire", true)
			if _st_t > 0.8:
				_key("fire", false)
				var bh := float(_bb.get("health"))
				_log.append("gun heat=%.2f bot_hp=%d" % [float(_pg.get("heat")), int(bh)])
				if float(_pg.get("heat")) <= 0.0:
					_bad.append("nose gun did not fire")
				if bh >= 1000.0:
					_bad.append("nose gun missed a bot dead ahead")
				if absf(gn.global_position.x - _spawn_g.x) > 4.0:
					_bad.append("parked plane crept while firing")
				_bb.global_position = Vector2(4300, G - 20)
				_x0 = gn.global_position.x
				_y0 = gn.global_position.y
				_lift_v = -1.0
				_key("jump", true)            # throttle up
				_key(_up_key(_pg), true)      # nose up the whole way
				_next(3)
		3:
			# Take-off run: wheels stay down below ROTATE_SPEED.
			var sp: float = gb.velocity.length()
			if _lift_v < 0.0 and _y0 - gn.global_position.y > 6.0:
				_lift_v = sp
				_log.append("liftoff v=%d run=%dpx t=%.2fs" % [int(sp), int(gn.global_position.x - _x0), _st_t])
				if sp < float(_pg.ROTATE_SPEED) - 10.0:
					_bad.append("lifted off below rotate speed (%d)" % int(sp))
			if _lift_v < 0.0 and sp < float(_pg.ROTATE_SPEED) - 20.0 and absf(angle_difference(float(_pg.get("_tilt")), 0.0)) > 0.02:
				_bad.append("nose up on the ground at %d px/s" % int(sp))
				_lift_v = 0.0001
			if _y0 - gn.global_position.y > 380.0:
				_key(_up_key(_pg), false)
				_log.append("climbed 380px at x+%d hp=%d" % [int(gn.global_position.x - _x0), int(_pg.get("hp"))])
				if float(_pg.get("hp")) < 380.0:
					_bad.append("take-off hurt it")
				_next(4)
			elif _st_t > 8.0:
				return _fail("never climbed out (v=%d y=%d)" % [int(sp), int(gn.global_position.y)])
		4:
			# Level flight at full throttle: speed builds, height holds.
			if _st_t < 0.05:
				_set_flight(_pg, Vector2(800, 1200), Vector2(600, 0), 0.0, 1.0)
				_y0 = 1200.0
			if _st_t > 4.0:
				var sp4: float = gb.velocity.length()
				var dy: float = gn.global_position.y - _y0
				_log.append("level v=%d dy=%d" % [int(sp4), int(dy)])
				if sp4 < 800.0:
					_bad.append("slow in level flight (%d)" % int(sp4))
				if absf(dy) > 120.0:
					_bad.append("level flight lost / gained %d px" % int(dy))
				_next(5)
		5:
			# A loop at speed: all the way round, never stalling.
			if _st_t < 0.05:
				_set_flight(_pg, Vector2(1200, 1150), Vector2(900, 0), 0.0, 1.0)
				_acc = 0.0
				_prev = 0.0
				_minsp = 9999.0
				_y0 = 1150.0
				_key("move_left", true)
			else:
				var a := float(_pg.get("_tilt"))
				_acc += absf(angle_difference(_prev, a))
				_minsp = minf(_minsp, gb.velocity.length())
			_prev = float(_pg.get("_tilt"))
			if _acc >= TAU or _st_t > 4.5:
				_key("move_left", false)
				_log.append("loop %.0fdeg in %.2fs min_v=%d end_dy=%d" % [rad_to_deg(_acc), _st_t, int(_minsp), int(gn.global_position.y - _y0)])
				if _acc < TAU - 0.2:
					_bad.append("couldn't loop (%.0f deg)" % rad_to_deg(_acc))
				if _minsp < float(_pg.STALL_SPEED):
					_bad.append("stalled in the loop (%d)" % int(_minsp))
				if float(_pg.get("hp")) < 380.0:
					_bad.append("the loop hit something")
				_next(6)
		6:
			# Slow + nose up + throttle closed: it stalls, the nose drops, it falls.
			if _st_t < 0.05:
				_set_flight(_pg, Vector2(1000, 700), Vector2(430, 0), -0.35, 0.0)
				_flag = false
				_acc = -1.0
				_key("crouch", true)
				_key("move_left", true)
				_y0 = 0.0
				_v = 0.0
			var sp6: float = gb.velocity.length()
			if not _flag and _pg.stalled() and sp6 < float(_pg.STALL_SPEED):
				_flag = true
				_y0 = gn.global_position.y
				_v = _st_t
			if _flag:
				_acc = maxf(_acc, Vector2.from_angle(float(_pg.get("_tilt"))).y)
			if _flag and _st_t - _v > 2.5:
				_key("crouch", false)
				_key("move_left", false)
				var fell: float = gn.global_position.y - _y0
				_log.append("stall at %.1fs: nose_down_max=%.2f fell=%dpx v=%d" % [_v, _acc, int(fell), int(sp6)])
				if _acc < 0.3:
					_bad.append("nose didn't drop in the stall (%.2f)" % _acc)
				if fell < 150.0:
					_bad.append("hung in the air in a stall (fell %d px)" % int(fell))
				_key("jump", true)
				_next(7)
			elif _st_t > 6.0:
				return _fail("never stalled (v=%d)" % int(sp6))
		7:
			# Throttle + speed: it flies again.
			if _st_t > 2.0:
				var sp7: float = gb.velocity.length()
				_log.append("recovered v=%d" % int(sp7))
				if sp7 < float(_pg.STALL_SPEED) + float(_pg.STALL_BAND) or _pg.stalled():
					_bad.append("no recovery from the stall (v=%d)" % int(sp7))
				_key("jump", false)
				_next(8)
		8:
			# Bomb run: level at 500 px, the bot where it should land.
			if _st_t < 0.05:
				_set_flight(_pg, Vector2(1400, G - 520), Vector2(600, 0), 0.0, 0.55)
				_pg.set("bomb_cd", 0.0)
				_flag = false
			if _st_t > 0.3 and not _flag:
				var pos: Vector2 = gn.global_position + Vector2(-2, 11)
				var vx: float = gb.velocity.x * 0.95 + 20.0
				var tt: float = sqrt(2.0 * (G - 8.0 - pos.y) / float(_pg.BOMB_GRAV))
				_bb.set("health", 1000.0)
				_bb.global_position = Vector2(pos.x + vx * tt, G - 1.0)
				_bb.set("velocity", Vector2.ZERO)
				_key("grenade", true)
				_flag = true
				_v = _st_t
			if _flag and _st_t - _v > 0.1 and _st_t - _v < 0.15:
				_key("grenade", false)
				var nb := 0
				for r in m.get_children():
					if str(r.name).begins_with("PlaneBomb_"):
						nb += 1
						if r.get("bomb_look") != true or r.get("local_only") != true or float(r.get("grav")) <= 0.0:
							_bad.append("bomb isn't a gravity rocket with the bomb look")
				_log.append("bombs=%d in_air=%d" % [int(_pg.get("bombs_dropped")), nb])
				if int(_pg.get("bombs_dropped")) != 1:
					_bad.append("grenade key didn't drop one bomb")
			if _flag and _st_t - _v > 0.2 and _st_t - _v < 0.25:
				_key("grenade", true)
			if _flag and _st_t - _v > 0.3 and _st_t - _v < 0.35:
				_key("grenade", false)
				if int(_pg.get("bombs_dropped")) != 1:
					_bad.append("bomb cooldown ignored")
			if _flag and float(_bb.get("health")) < 1000.0:
				_log.append("bomb hit bot hp=%d t=%.2fs" % [int(_bb.get("health")), _st_t - _v])
				if float(_pg.get("hp")) < 380.0:
					_bad.append("own bomb hurt the plane")
				_bb.global_position = Vector2(4300, G - 20)
				_next(9)
			elif _st_t > 4.0:
				return _fail("bomb never hit (bot hp %d)" % int(_bb.get("health")))
		9:
			# Gentle touchdown on the wheels: no damage, rolls to a stop.
			if _st_t < 0.05:
				_pg.apply_hp(380.0)
				_set_flight(_pg, Vector2(1600, G - 13.0 - 30.0), Vector2(380, 90), -0.05, 0.0)
			if _st_t > 3.0:
				_log.append("touchdown hp=%d v=%d grounded=%s" % [int(_pg.get("hp")), int(gb.velocity.length()), str(_pg.get("_grounded"))])
				if float(_pg.get("hp")) < 380.0:
					_bad.append("gentle touchdown hurt it")
				if not bool(_pg.get("_grounded")):
					_bad.append("didn't settle on its wheels")
				_next(10)
		10:
			# Hard touchdown: damage by impact speed, still flyable.
			if _st_t < 0.05:
				_pg.apply_hp(380.0)
				_set_flight(_pg, Vector2(2200, G - 60.0), Vector2(200, 440), 0.15, 0.0)
				_hp0 = 380.0
			if _st_t > 1.5:
				var lost: float = _hp0 - float(_pg.get("hp"))
				_log.append("hard landing -%dhp crashes=%d" % [int(lost), int(_pg.get("crashes"))])
				if lost < 150.0 or lost > 340.0 or not bool(_pg.get("alive")):
					_bad.append("hard landing damage off (%d)" % int(lost))
				_next(11)
		11:
			# Nose-dive into the ground: wreck, pilot dies.
			if _st_t < 0.05:
				_pg.apply_hp(380.0)
				_set_flight(_pg, Vector2(2600, 1300), Vector2.from_angle(1.15) * 900.0, 1.15, 1.0)
				_protect = false
				_dead = false
				var pname := str(p.display_name)
				m.kill.connect(func(_k, v, _w, _kt, _vt): if str(v) == pname: _dead = true)
			if _pg.get("alive") == false:
				_log.append("nose-dive wreck after %.2fs" % _st_t)
				_next(12)
			elif _st_t > 3.0:
				return _fail("nose-dive didn't wreck it (hp %d)" % int(_pg.get("hp")))
		12:
			if _st_t > 0.4:
				if not _dead:
					_bad.append("crash left the pilot alive")
				_protect = true
				_pg.set("_respawn_t", 0.05)
				_next(13)
		13:
			if _pg.get("alive") == true:
				var dd: float = gn.global_position.distance_to(_spawn_g)
				_log.append("respawned hp=%d dist=%d spawn_pos=%s" % [int(_pg.get("hp")), int(dd), str(_pg.get("spawn_pos"))])
				if float(_pg.get("hp")) != 380.0 or dd > 30.0 or float(_pg.get("face")) != 1.0:
					_bad.append("respawn wrong")
				_flag = false
				_next(14)
			elif _st_t > 2.0:
				return _fail("never respawned")
		14:
			# Shot down in the air: the pilot is thrown clear, alive.
			if p == null or not is_instance_valid(p) or p.get("dead") == true:
				if _st_t > 15.0:
					return _fail("player never respawned")
				return false
			if _st == 14 and not _flag:
				p.global_position = gn.global_position + Vector2(-20, 10)
				p.velocity = Vector2.ZERO
				_pg.request_enter(p)
				_flag = true
			if _pg.seat_of(p) == 0 and _st_t > 0.3:
				_set_flight(_pg, Vector2(2400, 900), Vector2(700, 0), 0.0, 0.8)
				_pg.take_damage(99999.0, "QA", "LAW", 77)
				_flag = false
				_next(15)
			elif _st_t > 3.0 and _pg.seat_of(p) != 0:
				return _fail("re-entry failed")
		15:
			if _st_t > 0.3 and not _flag:
				_flag = true
				var ok: bool = _pg.get("alive") == false and p.get("dead") != true and _pg.seat_of(p) < 0 and (p as CanvasItem).visible
				_log.append("shot down: pilot ejected alive=%s hp=%d" % [str(ok), int(p.get("health"))])
				if not ok:
					_bad.append("shot down in the air didn't eject the pilot alive")
			if _st_t > 3.0:
				if gn.global_position.y < G - 70.0:
					_bad.append("wreck floating at y=%d" % int(gn.global_position.y))
				_pg.set("_respawn_t", 0.05)
				_flag = false
				_next(16)
		16:
			# F gets out on the ground.
			if _pg.get("alive") != true:
				return false
			if not _flag and _st_t > 0.3:
				_flag = true
				p.global_position = gn.global_position + Vector2(-20, 10)
				p.velocity = Vector2.ZERO
				_pg.request_enter(p)
			if _flag and _st_t > 0.6 and _st_t < 0.75:
				_key("weapon_throw", true)
			if _flag and _st_t >= 0.75:
				_key("weapon_throw", false)
			if _st_t > 1.2:
				_log.append("exit seat=%d visible=%s" % [_pg.seat_of(p), str((p as CanvasItem).visible)])
				if _pg.seat_of(p) >= 0 or not (p as CanvasItem).visible:
					_bad.append("F didn't get the pilot out")
				_flag = false
				_next(17)
		17:
			# The air-spawn plane: waited where it was, launches flying.
			var an := _pa as Node2D
			if not _flag:
				_flag = true
				var moved: float = an.global_position.distance_to(_spawn_a)
				_log.append("air plane parked=%s moved=%d" % [str(_pa.get("air_parked")), int(moved)])
				if not bool(_pa.get("air_parked")) or moved > 2.0:
					_bad.append("air-spawn plane didn't wait in the air")
				p.global_position = an.global_position + Vector2(10, 20)
				p.velocity = Vector2.ZERO
				_pa.request_enter(p)
				_v = 0.0
			if _pa.seat_of(p) == 0 and _v == 0.0:
				_v = _st_t
				var sp17: float = (_pa as CharacterBody2D).velocity.length()
				_log.append("air launch v=%d" % int(sp17))
				if sp17 < 500.0 or bool(_pa.get("air_parked")):
					_bad.append("air plane didn't launch flying")
				_y0 = an.global_position.y
			if _v > 0.0 and _st_t - _v > 1.2:
				var dy17: float = an.global_position.y - _y0
				_log.append("air flight 1.2s dy=%d v=%d" % [int(dy17), int((_pa as CharacterBody2D).velocity.length())])
				if dy17 > 200.0 or _pa.stalled():
					_bad.append("air-launched plane fell out of the sky")
				_key("weapon_throw", true)
				_next(18)
			elif _st_t > 2.0 and _v == 0.0:
				return _fail("couldn't board the air plane")
		18:
			# Bail out: the empty plane can't stay up.
			if _st_t > 0.15:
				_key("weapon_throw", false)
			var an2 := _pa as Node2D
			if _st_t > 0.3 and _st_t < 0.35:
				if _pa.seat_of(p) >= 0:
					_bad.append("couldn't bail out in the air")
				_y0 = an2.global_position.y
			if _st_t > 8.0:
				var gone: bool = _pa.get("alive") == false or an2.global_position.y > _y0 + 300.0
				_log.append("abandoned: alive=%s dy=%d" % [str(_pa.get("alive")), int(an2.global_position.y - _y0)])
				if not gone:
					_bad.append("an empty plane stayed up")
				if _pa.get("alive") == false:
					_pa.set("_respawn_t", 0.05)
				else:
					m.vehicle_send("net_vehicle_respawn", [int(_pa.get("vehicle_id"))], true)
				_next(19)
		19:
			if _st_t > 0.5:
				var back_ok: bool = _pa.get("alive") == true and bool(_pa.get("air_parked")) and (_pa as Node2D).global_position.distance_to(_spawn_a) < 4.0
				_log.append("air respawn parked=%s" % str(back_ok))
				if not back_ok:
					_bad.append("air plane didn't come back to its spot")
				# Bot pilot on the runway plane.
				p.global_position = Vector2(300, G - 20)
				_ba.set_physics_process(true)
				_ba.set("health", 100.0)
				(_ba as Node2D).global_position = gn.global_position + Vector2(10, 10)
				m._vehicles_sys.vehicle_bot_board(_pg, _ba, 0)
				if _pg.driver() != _ba:
					return _fail("bot did not board as pilot")
				if (_ba as CanvasItem).visible:
					_bad.append("bot pilot drawn in the cockpit")
				(_bb as Node2D).global_position = Vector2(4300, G - 20)
				_y0 = gn.global_position.y
				_maxalt = 0.0
				_pg.set("bot_flown", 0.0)
				_hp0 = float(_pg.get("crashes"))
				_next(20)
		20:
			if not is_instance_valid(_ba) or not is_instance_valid(_bb):
				return _fail("bot pilot / target freed (crashed?) after %.1fs" % _st_t)
			_ba.set("target", _bb)
			_bb.set("health", 100.0)
			_maxalt = maxf(_maxalt, _y0 - gn.global_position.y)
			if _st_t > 12.0 or _pg.driver() != _ba:
				_log.append("bot pilot max_alt=%dpx flown=%d crashes=%d hp=%d seated=%s" % [int(_maxalt), int(_pg.get("bot_flown")),
					int(_pg.get("crashes")) - int(_hp0), int(_pg.get("hp")), str(_pg.driver() == _ba)])
				if _maxalt < 150.0:
					_bad.append("bot pilot never took off")
				if float(_pg.get("bot_flown")) < 1500.0:
					_bad.append("bot pilot barely flew")
				if int(_pg.get("crashes")) - int(_hp0) > 0:
					_bad.append("bot pilot hit the ground")
				_flag = false
				_next(21)
		21:
			# #294: a bot pilot leaves the plane parked far down the runway:
			# it goes home ABANDON_RETURN s after it comes to rest (not the
			# full #259 idle minute).
			if _pg.get("alive") != true:
				_pg.set("_respawn_t", 0.05)
				return false
			if not _flag:
				_flag = true
				if _pg.driver() != _ba:
					_ba.set("health", 100.0)
					(_ba as Node2D).global_position = gn.global_position + Vector2(10, 10)
					m._vehicles_sys.vehicle_bot_board(_pg, _ba, 0)
				_set_flight(_pg, Vector2(_spawn_g.x + 900.0, G - 60.0), Vector2.ZERO, 0.0, 0.0)
				_pg._bot_leave(_ba, 20.0)
				_ba.set_physics_process(false)
				(_ba as Node2D).global_position = Vector2(4300, G - 20)
				_v = 0.0
			if _v == 0.0 and gn.global_position.distance_to(_spawn_g) < 30.0:
				_v = _st_t
			if _v > 0.0 or _st_t > 20.0:
				_log.append("abandoned plane home after %.1fs" % _v)
				if _v <= 0.0 or _v < float(_pg.ABANDON_RETURN) or _v > float(_pg.ABANDON_RETURN) + 4.0:
					_bad.append("abandoned plane didn't go home ~%ds after it stopped (%.1f s)" % [int(_pg.ABANDON_RETURN), _v])
				if float(_pg.get("face")) != 1.0 or not bool(_pg.get("alive")):
					_bad.append("abandoned plane came home wrong")
				_release_all()
				_phase = 2
				_st = 0
				_st_t = 0.0
				_t = 0.0
	return false


## Phase 2: a Maker map (starter + a plane per team), CTF with bots: one of
## them boards a plane on its own and flies it.
func _maker_phase(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if _st == 0:
		var B = load("res://scripts/maker/maker_build.gd")
		var MapIO = load("res://scripts/map_io.gd")
		var src: Dictionary = B.starter_map("grassland")
		src["plane_spawns"] = [Vector2(330, 1510), Vector2(4470, 1510)]
		var cm: Dictionary = B.compile(src)
		cm["name"] = "QA Plane Maker"
		var probs: Array = B.validate(cm, 2)
		if B.has_errors(probs):
			return _fail("maker map invalid: %s" % str(probs))
		st.set("custom_map_path", MapIO.save_to_file("QA Plane Maker", cm))
		st.set("game_mode", 2); st.set("bot_count", 4)
		change_scene_to_file("res://scenes/main.tscn")
		_st = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null or m.get("_maker_spawn_override") == null and false:
		return false
	_t += d
	if _t < 1.0:
		return false
	var p = m.get("player")
	if p != null and is_instance_valid(p):
		p.set_physics_process(false)
		p.global_position = Vector2(2400, 1300)
		p.set("health", 100.0)
	if _maker_planes.is_empty():
		for v in get_nodes_in_group("vehicle"):
			if str(v.get("kind")) == "plane":
				_maker_planes.append(v)
		if _maker_planes.size() != 2:
			return _fail("maker map: %d planes" % _maker_planes.size())
	var best := 0.0
	var crashes := 0
	var boarded := 0
	for v in _maker_planes:
		if not is_instance_valid(v):
			continue
		best = maxf(best, float(v.get("bot_flown")))
		crashes += int(v.get("crashes"))
		if v.driver() != null:
			boarded += 1
	if best >= 2500.0 or _t > 45.0:
		_log.append("maker: best bot flight=%dpx crashes=%d t=%.0fs" % [int(best), crashes, _t])
		if best < 1500.0:
			_bad.append("maker map: no bot flew a plane (best %d px)" % int(best))
		if crashes > 2:
			_bad.append("maker map: bot pilots hit the ground %d times" % crashes)
		print("PLANE-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
		quit()
		return true
	return false
