extends SceneTree
## Vehicle art draw-path smoke test (gate stage F, #276).
##   godot --headless --fixed-fps 60 -s tools/vehicle_art_test.gd
## Buggy, tank, helicopter and plane (#291) parked on a flat range. For every quality (Low /
## Medium / High) in both looks (cinematic / classic) each vehicle is drawn
## pristine, crewed + running + firing, at four damage levels and as a burning
## wreck, then respawned. Checks: every vehicle's _draw ran in every state, the
## pooled effects fired on Medium / High (and nothing on Low), no node-count
## growth between passes (pools, never a node per effect), parked vehicles
## didn't move (cosmetics never touch the simulation), zero script errors
## (the gate greps the log).

const G := 1900.0
const STATES := ["pristine", "running", "dmg60", "dmg40", "dmg20", "dmg8", "wreck", "respawn"]

var _phase := 0
var _t := 0.0
var _log: Array = []
var _bad: Array = []
var _veh: Array = []
var _pass := 0               # index into _passes
var _passes: Array = []
var _si := 0                 # state index
var _vi := 0                 # vehicle index
var _frames := 0
var _draw0 := 0
var _nodes: Array = []       # node count at the end of each full sweep
var _hists: Array = []       # node kinds at the end of each full sweep (growth report)
var _home: Array = []
var _fx0 := 0
var _fx_by_q := {}


func _fail(msg: String) -> bool:
	print("VART-TEST FAIL %s | %s" % [msg, " ".join(_log)])
	quit()
	return true


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		var MapIO = load("res://scripts/map_io.gd")
		var m := {"name": "qa_vart", "platforms": [], "player_spawn": Vector2(400, G - 20),
			"bot_spawns": [Vector2(3600, G - 20)], "vehicle_spawns": [Vector2(900, G)],
			"tank_spawns": [Vector2(1300, G)], "heli_spawns": [Vector2(1800, G)], "plane_spawns": [Vector2(2400, G)]}
		st.set("custom_map_path", MapIO.save_to_file("qa_vart", m))
		st.set("game_mode", 0); st.set("bot_count", 1); st.set("vehicles", true)
		st.set("survival", false); st.set("realistic", false); st.set("advance", false)
		for rep in 2:
			for q in [0, 1, 2]:
				for style in ["cinematic", "classic"]:
					_passes.append([q, style])
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += d
	if _t > 160.0:
		return _fail("timeout pass=%d state=%d veh=%d" % [_pass, _si, _vi])
	var p = m.get("player")
	if _t < 1.5 or p == null or not is_instance_valid(p):
		return false
	p.set("ceasefire_t", 999.0)
	p.set("health", 100.0)
	if _phase == 1:
		for v in get_nodes_in_group("vehicle"):
			_veh.append(v)
		if _veh.size() != 4:
			return _fail("expected 4 vehicles, got %d" % _veh.size())
		for s in get_nodes_in_group("soldier"):
			if s.get("bot_id") != null:
				s.set_physics_process(false)
				s.set_process(false)
				(s as Node2D).global_position = Vector2(3600, G - 20)
		_phase = 2
		_frames = 0
		return false
	if _phase == 2:
		# Let everything settle on the ground, remember where it rests.
		_frames += 1
		if _frames > 90:
			for v in _veh:
				_home.append((v as Node2D).global_position)
			_begin_pass(st)
			_phase = 3
		return false
	return _step(m, p, st)


func _begin_pass(st) -> void:
	var q: int = _passes[_pass][0]
	st.set("visual_style", _passes[_pass][1])
	st.set_gfx_quality(q)
	var FxW = load("res://scripts/gfx/fx_world.gd")
	FxW.reconfigure()
	var Atm = load("res://scripts/gfx/atmosphere.gd")
	Atm.restyle(self)
	_si = 0
	_vi = 0
	_frames = 0
	var w = FxW.current
	_fx0 = int(w.spawned_total) if w != null else 0


func _step(m: Node, p: Node, st) -> bool:
	var v = _veh[_vi]
	var state: String = STATES[_si]
	if _frames == 0:
		_draw0 = int(v.get("draws"))
		# #293: the other vehicles start each state at rest on their spot —
		# the test's own rockets / shells / wreck blasts legitimately shove
		# a parked plane, which then rolled on through later states (seen:
		# "tank moved 333px", the plane 1100 px). Cosmetics are judged below.
		for i in _veh.size():
			if _veh[i] != v and _veh[i].get("alive") == true:
				(_veh[i] as Node2D).global_position = _home[i]
				(_veh[i] as CharacterBody2D).velocity = Vector2.ZERO
		_enter_state(m, p, v, state)
	# Keep the camera (it follows the player) on this vehicle: off-screen
	# vehicles skip their redraw.
	if state != "running" and p.get("mounted_m2") == null:
		p.global_position = Vector2((v as Node2D).global_position.x - 120.0, G - 30)
		p.set("velocity", Vector2.ZERO)
	_frames += 1
	if state == "running" and _frames % 20 == 5:
		if v.get("kind") == "heli":
			v.set("rocket_cd", 0.0)
			v._fire_rockets(p)
		else:
			v.set("fire_cd", 0.0)
			v.set("aim_dir", Vector2(0.3, -0.95).normalized())
			v._fire(p)
	var hold := 40 if state in ["running", "wreck"] else 12
	if _frames < hold:
		return false
	if int(v.get("draws")) <= _draw0:
		_bad.append("%s %s q%d %s: never drawn" % [v.get("kind"), state, _passes[_pass][0], _passes[_pass][1]])
	# Nothing but cosmetics ran in a non-firing state: no parked body may
	# have been nudged in it (the vehicle under test: end of pass, as before).
	if state in ["pristine", "dmg60", "dmg40", "dmg20", "dmg8"]:
		for i in _veh.size():
			if _veh[i] == v:
				continue
			var dd: float = (_veh[i] as Node2D).global_position.distance_to(_home[i])
			if dd > 24.0:
				_bad.append("%s moved %dpx while the %s was %s (pass %d)" % [_veh[i].get("kind"), int(dd), v.get("kind"), state, _pass])
	_leave_state(m, p, v, state)
	_frames = 0
	_si += 1
	if _si >= STATES.size():
		_si = 0
		_vi += 1
		if _vi >= _veh.size():
			return _end_pass(m, st)
	return false


func _enter_state(m: Node, p: Node, v: Node, state: String) -> void:
	match state:
		"running":
			v.set_seat(0, p)
		"dmg60":
			v.apply_hp(float(v.get("MAX_HP")) * 0.6)
		"dmg40":
			v.apply_hp(float(v.get("MAX_HP")) * 0.4)
		"dmg20":
			v.apply_hp(float(v.get("MAX_HP")) * 0.2)
		"dmg8":
			v.apply_hp(float(v.get("MAX_HP")) * 0.08)
		"wreck":
			v._host_destroy("", -1)
		"respawn":
			v.set("_respawn_t", 0.02)


func _leave_state(m: Node, p: Node, v: Node, state: String) -> void:
	match state:
		"running":
			v.clear_seat_of(p)
			p.global_position = Vector2((v as Node2D).global_position.x - 120.0, G - 30)
			p.set("velocity", Vector2.ZERO)
			# Back on its spot (driving / lifting moved it) before the
			# damage states, which are drawn parked.
			var i := _veh.find(v)
			(v as Node2D).global_position = _home[i]
			(v as CharacterBody2D).velocity = Vector2.ZERO
			# ...with the engine off: a plane left with its lever open
			# taxied on through the damage states (#293, "plane moved 63px").
			if v.get("throttle") != null:
				v.set("throttle", 0.0)
		"respawn":
			if v.get("alive") != true:
				_bad.append("%s did not respawn" % v.get("kind"))


func _end_pass(m: Node, st) -> bool:
	var FxW = load("res://scripts/gfx/fx_world.gd")
	var w = FxW.current
	var q: int = _passes[_pass][0]
	var fx: int = (int(w.spawned_total) - _fx0) if w != null else 0
	_fx_by_q[q] = int(_fx_by_q.get(q, 0)) + fx
	# Parked vehicles must be back where they rested (respawn puts them on
	# their pad; cosmetics must never nudge a body).
	for i in _veh.size():
		var dd: float = (_veh[i] as Node2D).global_position.distance_to(_home[i])
		if dd > 24.0:
			_bad.append("%s moved %dpx in pass %d" % [_veh[i].get("kind"), int(dd), _pass])
	if _pass == 5 or _pass == _passes.size() - 1:
		# Shells / bombs / bullets still in flight are transient, not growth
		# (#293: two tank shells in the air at the second sweep = +6 nodes).
		_nodes.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - _in_flight(root))
		_hists.append(_kinds(root))
	_pass += 1
	if _pass >= _passes.size():
		_log.append("fx_spawned low=%d med=%d high=%d" % [int(_fx_by_q.get(0, 0)), int(_fx_by_q.get(1, 0)), int(_fx_by_q.get(2, 0))])
		_log.append("nodes sweep1=%d sweep2=%d" % [_nodes[0], _nodes[1]])
		if int(_fx_by_q.get(0, 0)) != 0:
			_bad.append("Low spawned pooled effects")
		if int(_fx_by_q.get(1, 0)) < 50 or int(_fx_by_q.get(2, 0)) < 100:
			_bad.append("vehicle effects missing on Medium / High")
		if _nodes[1] > _nodes[0] + 4:
			_bad.append("node count grew %d -> %d (%s)" % [_nodes[0], _nodes[1], _kinds_diff(_hists[0], _hists[1])])
		var draws := []
		for v in _veh:
			draws.append("%s=%d" % [v.get("kind"), int(v.get("draws"))])
		_log.append("draws " + " ".join(draws))
		print("VART-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
		quit()
		return true
	_begin_pass(st)
	return false


# Transient at a sweep's end: projectiles in flight, and the bot's body (the
# test's live fire can kill it: dying husk + respawned body = +1 bot subtree).
const _PROJECTILES := ["grenade.gd", "bullet.gd", "rocket.gd", "bot.gd"]


## Nodes in projectile subtrees (in flight, freed on impact / timeout).
func _in_flight(n: Node) -> int:
	if n.get_script() != null and _PROJECTILES.has((n.get_script() as Script).resource_path.get_file()):
		return _subtree(n)
	var t := 0
	for c in n.get_children():
		t += _in_flight(c)
	return t


func _subtree(n: Node) -> int:
	var t := 1
	for c in n.get_children():
		t += _subtree(c)
	return t


func _kinds(n: Node, out: Dictionary = {}) -> Dictionary:
	if n.get_script() != null and _PROJECTILES.has((n.get_script() as Script).resource_path.get_file()):
		return out
	var k := n.get_class() + ("/" + (n.get_script() as Script).resource_path.get_file() if n.get_script() != null else "")
	out[k] = int(out.get(k, 0)) + 1
	for c in n.get_children():
		_kinds(c, out)
	return out


func _kinds_diff(a: Dictionary, b: Dictionary) -> String:
	var out := []
	for k in b:
		var d := int(b[k]) - int(a.get(k, 0))
		if d != 0:
			out.append("%s%+d" % [k, d])
	for k in a:
		if not b.has(k):
			out.append("%s-%d" % [k, int(a[k])])
	return ", ".join(out)
