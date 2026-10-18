extends SceneTree
## Graphics Phase B (#271) — gate stage F "fxpool":
##  1. pools sized per quality (High / Medium / Low) and never exceeded;
##  2. heavy combat effects for several seconds after warm-up grow the node
##     count by zero (every effect is a pooled slot, none is a node);
##  3. decals are capped and the ring recycles the oldest;
##  4. Blood 0 spawns no blood, gibs or decals;
##  5. hit-stop / slow-mo obey Settings.hit_stop + Screen Shake 0, shake obeys
##     the slider, and the match keeps simulating during a hit-stop;
##  6. COSMETIC ONLY: the same scripted 7 s scenario (seeded, stick aim, real
##     input, real shots, scripted hits) run with every effect on and with
##     every effect off ends with bit-identical player position / velocity /
##     health / fuel / ammo and the same next value of the global random
##     stream (gameplay randomness untouched by FX).
##   godot --headless --fixed-fps 60 -s tools/fx_test.gd

const MAP := {"name": "qa_fx", "platforms": [{"p": Vector2(2600, 1700), "s": Vector2(60, 400)}],
	"player_spawn": Vector2(2200, 1880), "bot_spawns": [Vector2(600, 1880)]}

var _st := 0
var _n := 0
var _bad: Array = []
var _log: Array = []
var _saved := []
var _map_path := ""
var _w = null
var _nodes0 := 0
var _nodes_max := 0
var _phys0 := 0
var _run := 0
var _runs: Array = []
var _k := 0
var _G = null


var _SF = null


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _G == null:
		# Loaded lazily: these scripts read autoloads, which don't exist yet
		# while this SceneTree script compiles.
		_G = load("res://scripts/gfx.gd")
		_SF = load("res://scripts/gfx/screen_feel.gd")
	if _n > 60 * 90:
		_bad.append("timeout at stage %d" % _st)
		return _end()
	match _st:
		0:
			_saved = [st.bot_count, st.game_mode, st.map_index, st.custom_map_path, st.gfx_quality, st.blood_intensity,
				st.screen_shake_intensity, st.hit_stop, st.vehicles, st.visual_style]
			var MapIO = load("res://scripts/map_io.gd")
			_map_path = MapIO.save_to_file("qa_fx", MAP)
			_setup(st, true)
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 1
			_n = 0
		1:
			var m = current_scene
			if m == null or m.get("player") == null or not is_instance_valid(m.player) or m.get_node_or_null("FxWorld") == null:
				return false
			if _n < 30:
				return false
			_w = m.get_node("FxWorld")
			var s: Dictionary = _w.stats()
			_log.append("high caps parts=%d gibs=%d casings=%d decals=%d" % [s.parts_cap, s.gibs_cap, s.casings_cap, s.decals_cap])
			if s.parts_cap != 1000 or s.gibs_cap != 72 or s.casings_cap != 64 or s.decals_cap != 256 or s.heat_cap != 6:
				_bad.append("High pool sizes %s" % str(s))
			_st = 2
			_n = 0
		2:
			# Warm-up: 2 s of heavy combat effects.
			var m = current_scene
			_combat(m, _n)
			_check_caps("warm-up")
			if _n >= 120:
				_nodes0 = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
				_nodes_max = _nodes0
				_st = 3
				_n = 0
		3:
			# 6 s more of the same: node count must stay flat.
			var m = current_scene
			_combat(m, _n)
			_check_caps("combat")
			_nodes_max = maxi(_nodes_max, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			if _n >= 360:
				var s: Dictionary = _w.stats()
				_log.append("nodes %d->max %d (live parts=%d gibs=%d decals=%d spawned=%d)" % [_nodes0, _nodes_max, s.parts, s.gibs, s.decals, s.spawned_total])
				if _nodes_max > _nodes0:
					_bad.append("node count grew during combat FX: %d -> %d" % [_nodes0, _nodes_max])
				if s.spawned_total < 3000:
					_bad.append("combat burst spawned only %d effects" % s.spawned_total)
				_st = 4
				_n = 0
		4:
			# Decal ring: overfill, stays capped, recycles.
			var cap: int = _w.stats().decals_cap
			var rec0: int = _w.decals_recycled
			for i in cap + 150:
				_w._splat(Vector2(2000 + i % 300, 1900), Vector2.UP, 14.0)
			var s: Dictionary = _w.stats()
			_log.append("decals %d/%d recycled +%d" % [s.decals, cap, s.decals_recycled - rec0])
			if s.decals != cap or s.decals_recycled - rec0 < 150:
				_bad.append("decal ring: %d live of %d, recycled %d" % [s.decals, cap, s.decals_recycled - rec0])
			# Medium.
			st.set_gfx_quality(1)
			current_scene.apply_gfx_quality()
			_st = 5
			_n = 0
		5:
			var m = current_scene
			if _n == 2:
				var s: Dictionary = _w.stats()
				_log.append("medium caps parts=%d gibs=%d casings=%d decals=%d" % [s.parts_cap, s.gibs_cap, s.casings_cap, s.decals_cap])
				if s.parts_cap != 420 or s.gibs_cap != 28 or s.casings_cap != 24 or s.decals_cap != 96 or s.heat_cap != 0:
					_bad.append("Medium pool sizes %s" % str(s))
			if _n > 2:
				_combat(m, _n)
				_check_caps("medium")
			if _n >= 90:
				# Blood 0: nothing bloody at all.
				st.blood_intensity = 0.0
				_w.configure()
				for i in 10:
					_w.gib(m.player.global_position + Vector2(40, 0), Vector2(0, -50), Color.RED, {}, true, 1.0)
					_w.blood_hit(m.player.global_position + Vector2(30, -10), Vector2.LEFT)
					load("res://scripts/impact_fx.gd").spawn(m, m.player.global_position + Vector2(30, -10), Vector2.LEFT, "blood")
					_w._splat(m.player.global_position, Vector2.UP, 12.0)
				m.player._spawn_gibs()
				var s: Dictionary = _w.stats()
				var kinds: PackedInt32Array = s.kinds
				if s.gibs != 0 or s.decals != 0 or kinds[_w.K_DROP] != 0 or kinds[_w.K_MIST] != 0:
					_bad.append("Blood 0 still spawned: gibs=%d decals=%d drops=%d mist=%d" % [s.gibs, s.decals, kinds[_w.K_DROP], kinds[_w.K_MIST]])
				st.blood_intensity = 1.0
				# Low: pools empty, nothing spawns, no nodes.
				st.set_gfx_quality(0)
				m.apply_gfx_quality()
				var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
				for i in 30:
					_combat(m, i)
				var s2: Dictionary = _w.stats()
				if s2.parts_cap != 0 or s2.parts != 0 or s2.gibs != 0 or s2.decals != 0:
					_bad.append("Low spawned FX: %s" % str(s2))
				if int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) > nodes:
					_bad.append("Low combat created nodes")
				st.set_gfx_quality(2)
				m.apply_gfx_quality()
				_st = 6
				_n = 0
		6:
			# Screen feel toggles.
			var m = current_scene
			var f = m.get_node_or_null("ScreenFeel")
			if f == null:
				_bad.append("no ScreenFeel")
				_st = 8
				return false
			if _n == 1:
				st.hit_stop = false
				st.screen_shake_intensity = 1.0
				var h0: int = f.hitstops
				_SF.local_kill("AK-74")
				_SF.local_hit(80.0)
				if f.hitstops != h0:
					_bad.append("hit-stop fired with the toggle off")
				st.hit_stop = true
				st.screen_shake_intensity = 0.0
				_SF.local_kill("AK-74")
				if f.hitstops != h0:
					_bad.append("hit-stop fired with Screen Shake 0")
				f.trauma = 0.0
				m.player._shake(7.0)
				_G.explosion(m, m.player.global_position, 120.0)
				if f.trauma > 0.0:
					_bad.append("shake with Screen Shake 0 (trauma %.2f)" % f.trauma)
				st.screen_shake_intensity = 1.0
				m.player._shake(7.0)
				if f.trauma <= 0.0:
					_bad.append("no shake at intensity 1")
				_SF.local_kill("AK-74")
				if f.hitstops != h0 + 1 or not f.holding():
					_bad.append("hit-stop didn't start (count %d, holding %s)" % [f.hitstops - h0, str(f.holding())])
				_SF.local_kill("LAW")
				if f.slowmos < 1:
					_bad.append("double kill didn't start the slow-mo look")
				_phys0 = Engine.get_physics_frames()
				_k = int(m.player.get("fuel") * 1000.0)
				if Engine.time_scale != 1.0:
					_bad.append("time_scale %.2f" % Engine.time_scale)
			elif _n == 3:
				# Mid hit-stop: the world keeps simulating.
				if not f.holding():
					_bad.append("hit-stop ended too early")
				if Engine.get_physics_frames() - _phys0 < 2:
					_bad.append("physics paused during hit-stop")
			elif _n == 20:
				if f.holding():
					_bad.append("hit-stop still holding after 20 frames")
				_log.append("hitstops=%d slowmos=%d" % [f.hitstops, f.slowmos])
				_st = 7
				_n = 0
				_run = 0
		7:
			return _determinism(st)
		8:
			return _end()
	return false


func _setup(st, fx_on: bool) -> void:
	st.bot_count = 0
	st.game_mode = 0
	st.custom_map_path = _map_path
	st.vehicles = false
	st.set_gfx_quality(2 if fx_on else 0)
	st.blood_intensity = 1.5 if fx_on else 0.0
	st.screen_shake_intensity = 2.0 if fx_on else 0.0
	st.hit_stop = fx_on
	st.visual_style = "cinematic" if fx_on else "classic"


## A worst-case-ish combat frame of pure cosmetics around the player.
func _combat(m, i: int) -> void:
	var p: Vector2 = m.player.global_position
	for s in 3:
		_G.muzzle(m, p + Vector2(10, -12), false, Vector2.RIGHT)
		_G.casing(m, p + Vector2(2, -10), 1.0, s == 0)
		load("res://scripts/impact_fx.gd").spawn(m, p + Vector2(160 + s * 7, -10), Vector2.LEFT, "wall")
		load("res://scripts/impact_fx.gd").spawn(m, p + Vector2(90, -14 + s), Vector2.LEFT, "blood")
	if i % 15 == 0:
		_G.explosion(m, p + Vector2(120, 0), 90.0)
	if i % 12 == 0:
		var w = m.get_node("FxWorld")
		w.gib(p + Vector2(70 + (i % 5) * 10, 0), Vector2(30, -40), Color(0.8, 0.2, 0.2), {}, i % 24 == 0, 1.0)
	if i % 20 == 0:
		_G.dust(m, p + Vector2(-40, 0), 1.0)


func _check_caps(tag: String) -> void:
	var s: Dictionary = _w.stats()
	if s.parts > s.parts_cap or s.gibs > s.gibs_cap or s.casings > s.casings_cap or s.decals > s.decals_cap or s.sticky > s.sticky_cap:
		_bad.append("%s: pool over cap %s" % [tag, str(s)])
	var kinds: PackedInt32Array = s.kinds
	var caps: PackedInt32Array = s.kind_caps
	for k in kinds.size():
		if kinds[k] > caps[k]:
			_bad.append("%s: kind %d over cap %d > %d" % [tag, k, kinds[k], caps[k]])
			break


# ── 6. simulation unaffected ─────────────────────────────────────────────

func _determinism(st) -> bool:
	match _run:
		0, 2:
			# Fresh match, seeded global stream, effects on (run A) / off (run B).
			_setup(st, _run == 0)
			_release_all()
			seed(271271)
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_run += 1
			_k = -1
			return false
		1, 3:
			var m = current_scene
			if _k < 0:
				if m == null or m.get("player") == null or not is_instance_valid(m.player) or m.get_node_or_null("FxWorld") == null:
					return false
				_k = 0
			_script_frame(m, _k)
			_k += 1
			if _k > 430:
				_release_all()
				var p = m.player
				var w: Dictionary = p.call("_active_weapon")
				_runs.append({"pos": p.global_position, "vel": p.velocity, "hp": p.health, "fuel": p.fuel,
					"ammo": int(p.call("_active_mag")), "rng": randi(), "bullets": get_nodes_in_group("bullet").size(), "weapon": str(w.get("name", ""))})
				if _run == 3:
					return _compare()
				_run += 1
			return false
	return false


func _script_frame(m, k: int) -> void:
	var p = m.player
	if k == 1:
		if not InputMap.has_action("aim_right"):
			_bad.append("no aim_right action")
		Input.action_press("aim_right", 1.0)
		p.ceasefire_t = 0.0
	if k == 60:
		Input.action_press("move_right")
	if k == 80:
		Input.action_press("jump")
	if k == 100:
		Input.action_release("jump")
	if k == 120:
		Input.action_press("jet")
	if k == 170:
		Input.action_release("jet")
		Input.action_release("move_right")
		Input.action_press("move_left")
	if k == 200:
		Input.action_release("move_left")
		Input.action_press("fire")
	if k == 330:
		Input.action_release("fire")
	if k >= 100 and k % 40 == 0 and k <= 380:
		p.take_damage(9.0, "QA", "AK-74", 1)
	# Cosmetic noise (only does anything in the effects-on run).
	if k % 25 == 0:
		_G.explosion(m, p.global_position + Vector2(80, -20), 100.0)
		m.get_node("FxWorld").gib(p.global_position + Vector2(60, 0), Vector2(0, -60), Color.RED, {}, true, 1.0)
		_SF.local_kill("LAW")
		_SF.local_hit(60.0)
		p._shake(7.0)
	load("res://scripts/impact_fx.gd").spawn(m, p.global_position + Vector2(50, -10), Vector2.LEFT, "blood")
	_G.casing(m, p.global_position, 1.0)


func _release_all() -> void:
	for a in ["aim_right", "move_right", "move_left", "jump", "jet", "fire"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func _compare() -> bool:
	var a: Dictionary = _runs[0]
	var b: Dictionary = _runs[1]
	_log.append("sim on: pos=%s vel=%s hp=%.1f fuel=%.3f ammo=%d rng=%d | off: pos=%s vel=%s hp=%.1f fuel=%.3f ammo=%d rng=%d" % [
		str(a.pos), str(a.vel), a.hp, a.fuel, a.ammo, a.rng, str(b.pos), str(b.vel), b.hp, b.fuel, b.ammo, b.rng])
	for key in ["pos", "vel", "hp", "fuel", "ammo", "rng", "weapon"]:
		if a[key] != b[key]:
			_bad.append("simulation differs with effects on vs off: %s %s vs %s" % [key, str(a[key]), str(b[key])])
	if a.hp >= 100.0 or a.ammo >= 30:
		_bad.append("scenario didn't exercise hits / shooting (hp %.1f ammo %d)" % [a.hp, a.ammo])
	_st = 8
	return false


func _end() -> bool:
	_release_all()
	var st = root.get_node("Settings")
	st.bot_count = _saved[0]; st.game_mode = _saved[1]; st.map_index = _saved[2]; st.custom_map_path = _saved[3]
	st.set_gfx_quality(_saved[4]); st.blood_intensity = _saved[5]; st.screen_shake_intensity = _saved[6]
	st.hit_stop = _saved[7]; st.vehicles = _saved[8]; st.visual_style = _saved[9]
	var ok := _bad.is_empty()
	print("FXPOOL-TEST %s %s %s" % ["ok" if ok else "FAIL", str(_bad), " | ".join(_log)])
	quit(0 if ok else 1)
	return true
