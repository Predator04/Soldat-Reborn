extends SceneTree
## Graphics Phase B (#271) FX benchmark (gate stage F "fxbench"). Worst case
## around the player: 8 simultaneous gibbings + 4 explosions, then a 3 s
## minigun spray (muzzle star, casing, ricochet or blood hit per round) with a
## fresh gibbing + explosion every second. Reports pool sizes, peak live
## counts, node counts before / during / after, and per-frame cost (FX update
## + draw, measured inside fx_world.gd, plus the engine's process time).
##   godot --headless --fixed-fps 60 -s tools/fx_bench.gd -- [--map=8] [--bots=0] [--quality=2]
## Works under a real renderer too (drop --headless) for on-GPU frame times.

var _map := 8
var _bots := 0
var _quality := 2
var _n := 0
var _st := 0
var _G = null
var _w = null
var _saved := []
var _nodes0 := 0
var _nodes_max := 0
var _nodes_end := 0
var _base: Array = []
var _upd: Array = []
var _drw: Array = []
var _fx: Array = []
var _frame: Array = []
var _peak := {}
var _peak_live := 0
var _last_us := 0
var _bad: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): _map = int(a.substr(6))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--quality="): _quality = int(a.substr(10))


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _n > 60 * 60:
		_bad.append("timeout")
		return _end(st)
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	match _st:
		0:
			_G = load("res://scripts/gfx.gd")
			_saved = [st.bot_count, st.game_mode, st.map_index, st.custom_map_path, st.gfx_quality, st.blood_intensity]
			st.bot_count = _bots
			st.game_mode = 0
			st.map_index = _map
			st.custom_map_path = ""
			st.set_gfx_quality(_quality)
			st.blood_intensity = 1.0
			root.get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 1
			_n = 0
		1:
			var m = current_scene
			if m == null or m.get("player") == null or not is_instance_valid(m.player) or m.get_node_or_null("FxWorld") == null:
				return false
			if _n < 90:
				return false
			_w = m.get_node("FxWorld")
			m.player.ceasefire_t = 9999.0
			_st = 2
			_n = 0
		2:
			# Baseline: 1 s with no FX.
			_base.append(frame_ms)
			if _n >= 60:
				_nodes0 = _nodes()
				_nodes_max = _nodes0
				_st = 3
				_n = 0
				_burst(current_scene, true)
		3:
			var m = current_scene
			var p: Vector2 = m.player.global_position
			# Minigun: ~20 rounds/s.
			if _n % 3 == 0:
				var dir := Vector2.RIGHT.rotated(sin(_n * 0.13) * 0.15)
				_G.muzzle(m, p + Vector2(12, -12), false, dir)
				_G.casing(m, p + Vector2(2, -10), 1.0)
				var FX = load("res://scripts/impact_fx.gd")
				if _n % 6 == 0:
					FX.spawn(m, p + Vector2(110, -12) + dir * 20.0, -dir, "blood")
				else:
					FX.spawn(m, p + Vector2(240, -8) + dir * 40.0, -dir, "wall")
			if _n % 60 == 0:
				_burst(m, false)
			_upd.append(float(_w.update_us) / 1000.0)
			_drw.append(float(_w.draw_us) / 1000.0)
			_fx.append(float(_w.update_us + _w.draw_us) / 1000.0)
			_frame.append(frame_ms)
			_nodes_max = maxi(_nodes_max, _nodes())
			var live: int = _w.live_total()
			if live > _peak_live:
				_peak_live = live
				_peak = _w.stats()
			if _n >= 180:
				_st = 4
				_n = 0
		4:
			# Let everything finish / settle for 2 s.
			if _n >= 120:
				_nodes_end = _nodes()
				return _end(st)
	return false


func _burst(m, big: bool) -> void:
	var p: Vector2 = m.player.global_position
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in (8 if big else 1):
		_w.gib(p + Vector2(60 + i * 18, -4), Vector2(r.randf_range(-80, 80), -60), Color(0.3, 0.45, 0.9), {}, i % 2 == 0, 1.0 if i % 2 == 0 else -1.0)
	for i in (4 if big else 1):
		_G.explosion(m, p + Vector2(80 + i * 60, -10), 100.0)


func _nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _stat(a: Array) -> String:
	if a.is_empty():
		return "-"
	var s := a.duplicate()
	s.sort()
	var avg := 0.0
	for v in s:
		avg += float(v)
	avg /= s.size()
	return "avg %.2f p95 %.2f max %.2f" % [avg, float(s[int(s.size() * 0.95)]), float(s[s.size() - 1])]


func _p95(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[int(s.size() * 0.95)])


func _end(st) -> bool:
	st.bot_count = _saved[0]; st.game_mode = _saved[1]; st.map_index = _saved[2]; st.custom_map_path = _saved[3]
	st.set_gfx_quality(_saved[4]); st.blood_intensity = _saved[5]
	if _nodes_max > _nodes0 or _nodes_end > _nodes0:
		_bad.append("node count grew: %d -> max %d, end %d" % [_nodes0, _nodes_max, _nodes_end])
	# Headless CPU budget for the whole FX system (shared 2-core CI box):
	# generous, it only catches a pathological regression.
	if _p95(_fx) > 8.0:
		_bad.append("FX cost p95 %.2f ms" % _p95(_fx))
	if _peak.is_empty() or int(_peak.get("gibs", 0)) < 8:
		_bad.append("burst didn't fill the pools: %s" % str(_peak))
	var ok := _bad.is_empty()
	print("FX-BENCH %s %s | q=%d map=%d bots=%d | nodes before %d, max during burst %d, after %d | pools %s | peak live %s | FX ms/frame: update %s, draw %s, total %s | whole frame ms: baseline %s, burst %s" % [
		"ok" if ok else "FAIL", str(_bad), _quality, _map, _bots, _nodes0, _nodes_max, _nodes_end,
		"parts %d gibs %d casings %d decals %d heat %d spurts %d sticky %d" % [_peak.get("parts_cap", 0), _peak.get("gibs_cap", 0), _peak.get("casings_cap", 0), _peak.get("decals_cap", 0), _peak.get("heat_cap", 0), _peak.get("spurts_cap", 0), _peak.get("sticky_cap", 0)],
		"parts %d gibs %d casings %d decals %d" % [_peak.get("parts", 0), _peak.get("gibs", 0), _peak.get("casings", 0), _peak.get("decals", 0)],
		_stat(_upd), _stat(_drw), _stat(_fx), _stat(_base), _stat(_frame)])
	quit(0 if ok else 1)
	return true
