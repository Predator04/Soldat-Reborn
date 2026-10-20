extends SceneTree
## Script/physics cost per frame in a busy match (no rendering).
##   godot --headless --fixed-fps 60 -s tools/perf_test.gd -- --map=13 --mode=2 --bots=16 --secs=25 [--inject-ms=10]
## Prints avg / p95 / max of the main thread's frame cost after warmup, and
## the busiest node types by count. Phones have ~4x less CPU than a desktop, so
## keep avg well under 4 ms here.
##
## Load-robust verdict (#293). The gate box often runs several gates at once;
## a raw wall-clock frame gap then mostly measures how long the scheduler kept
## this process off the CPU (seen: avg 58 ms, single gaps of 4 s, while the
## frames themselves cost ~5 ms). So, on Linux:
##  - frame cost = the main thread's ON-CPU time per frame (/proc/self/schedstat
##    field 1, via tools/gate_load.gd; updated per scheduler tick, so one frame
##    is +-1 tick, the average is exact). Run-queue waits and lock waits behind
##    starved threads don't count; everything our scripts, physics and the
##    engine compute does. Seen: 4.9-5.4 ms whether the box is quiet or loaded
##    to 9 (vs. wall averages of 6-58 ms).
##  - the match is seeded (PERF_SEED), so every run plays the same fight: the
##    random action alone moved the cost ~+-10 %.
##  - calibration: a fixed synthetic GDScript workload (CAL_REF_MS on this box)
##    runs in the warm-up frames; on a slower machine the limits scale by
##    cal / CAL_REF_MS, clamped to [1, CAL_MAX_FACTOR] (a faster machine keeps
##    the limits; nothing loosens them more than 2x).
## Raw wall and "own" (wall minus run-queue wait) numbers are still printed.
## Without schedstat (non-Linux) it falls back to wall time.
## --inject-ms=N (or env PERF_INJECT_MS) burns N ms of main-thread CPU per
## measured frame: a deliberately slowed build, which must FAIL (the gate's
## own regression signal; see CLAUDE.md "Release gate").

const GL = preload("res://tools/gate_load.gd")
const AVG_LIMIT := 6.0       # ms, mean frame cost (scaled by the calibration factor)
const MAX_LIMIT := 80.0      # ms, worst single frame = a hitch (scaled likewise)
const PERF_SEED := 293
const CAL_REF_MS := 2.50     # ms, calibration workload on this box with nothing else running
const CAL_MAX_FACTOR := 2.0
const CAL_POOL := 32768      # entities in the calibration heap (power of two)
const CAL_ITERS := 1500      # entity updates per calibration run (~2 ms)

var _map := 13
var _mode := 2
var _bots := 16
var _secs := 25.0
var _inject_ms := 0.0
var _loaded := false
var _t := 0.0
var _started := false
var _frames := 0
var _sched_ok := false
# Per measured frame: wall gap, on-CPU, own (wall minus queue wait), all ms.
var _wall: Array = []
var _cpu: Array = []
var _own: Array = []
var _cal: Array = []
var _last := {}   # {us, run, wait} at the end of the previous measured frame
var _cal_sink := 0
var _pool: Array = []
var _order := PackedInt32Array()
var _cal_off := 0


func _initialize() -> void:
	var env := OS.get_environment("PERF_INJECT_MS")
	if env != "":
		_inject_ms = float(env)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): _map = int(a.substr(6))
		elif a.begins_with("--mode="): _mode = int(a.substr(7))
		elif a.begins_with("--bots="): _bots = int(a.substr(7))
		elif a.begins_with("--secs="): _secs = float(a.substr(7))
		elif a.begins_with("--inject-ms="): _inject_ms = float(a.substr(12))
	_sched_ok = GL.has_sched()
	_build_cal_pool()


## The calibration heap, built once before the match (own RNG: the global
## stream belongs to gameplay).
func _build_cal_pool() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in CAL_POOL:
		_pool.append({"p": Vector2(i, i * 0.5), "v": Vector2(rng.randf(), rng.randf()), "hp": i & 255, "tag": "e%d" % i})
	_order.resize(CAL_POOL)
	for i in CAL_POOL:
		_order[i] = i
	for i in range(CAL_POOL - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t := _order[i]; _order[i] = _order[j]; _order[j] = t


## Burns ms of this thread's CPU time (not wall time: under load a wall-clock
## busy-wait would be mostly preempted and inject far less work).
func _busy_wait(ms: float) -> void:
	var a := GL.stamp()
	var x := 0
	while true:
		for _i in 200:
			x += 1
		if GL.own_ms(a, GL.stamp()) >= ms:
			break
	_cal_sink += x & 1


## Fixed synthetic workload: vector maths plus dictionary traffic scattered
## over a ~6 MB heap of small entities (like a frame of bot / bullet / node
## scripts), so cache and memory-bandwidth contention slow it like the game.
func _cal_work() -> void:
	var acc := 0.0
	var mask := CAL_POOL - 1
	for i in CAL_ITERS:
		var e: Dictionary = _pool[_order[(i * 7919 + _cal_off) & mask]]
		var p: Vector2 = e.p + (e.v as Vector2).rotated(i * 0.001) * 0.016
		e.p = p
		e.hp = (int(e.hp) + 1) & 255
		acc += p.length_squared() * 0.0001 + float((e.tag as String).length())
	_cal_off = (_cal_off + CAL_ITERS) & mask
	_cal_sink += int(acc) & 1


func _calibrate() -> void:
	var a := GL.stamp()
	_cal_work()
	# Pure computation: its own time (wall minus queue wait) is its CPU time,
	# without the tick granularity of the run counter.
	_cal.append(GL.own_ms(a, GL.stamp()))


static func _pct(sorted: Array, q: float) -> float:
	return sorted[clampi(int(sorted.size() * q), 0, sorted.size() - 1)]


func _process(d: float) -> bool:
	var st := root.get_node_or_null("Settings")
	if st == null:
		return false
	if not _loaded:
		st.set("custom_map_path", ""); st.set("map_index", _map); st.set("game_mode", _mode)
		st.set("bot_count", _bots); st.set("vehicles", true); st.set("survival", false); st.set("advance", false)
		root.get_node("Net").set_singleplayer()
		# Same fight every run (#293): the match is random and its cost varies
		# ~+-10 % with the action, which alone could cross the limit.
		seed(PERF_SEED)
		var sfx := root.get_node_or_null("Sfx")
		if sfx != null and sfx.get("_rng") != null:
			(sfx.get("_rng") as RandomNumberGenerator).seed = PERF_SEED
		var gfx = load("res://scripts/gfx.gd")
		if gfx != null and gfx.get("rng") != null:
			(gfx.rng as RandomNumberGenerator).seed = PERF_SEED
		change_scene_to_file("res://scenes/main.tscn")
		_loaded = true
		return false
	if current_scene == null or current_scene.get("MAPS") == null:
		return false
	_t += d
	if _t <= 3.0:
		# Calibration in the warm-up frames, in the match's own conditions,
		# so it never pollutes the caches of a measured frame.
		if _t > 1.0:
			_calibrate()
		return false
	if _inject_ms > 0.0:
		_busy_wait(_inject_ms)
	var now := GL.stamp()
	if _started:
		var fm := GL.wall_ms(_last, now)
		var cpu := GL.cpu_ms(_last, now)
		var own := GL.own_ms(_last, now)
		_wall.append(fm); _cpu.append(cpu); _own.append(own)
		if cpu > 15.0:
			print("SPIKE t=%.2f cpu=%.1fms own=%.1fms wall=%.1fms bullets=%d nodes=%d" % [_t, cpu, own, fm, get_nodes_in_group("bullet").size(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	_started = true
	_frames += 1
	_last = now
	if _t > _secs:
		_report()
		quit()
		return true
	return false


func _report() -> void:
	var counts := {}
	for node in current_scene.get_children():
		var k := node.get_class() + ("/" + (node.get_script() as Script).resource_path.get_file() if node.get_script() != null else "")
		counts[k] = int(counts.get(k, 0)) + 1
	var top: Array = counts.keys()
	top.sort_custom(func(a, b) -> bool: return counts[a] > counts[b])
	var tops := []
	for k in top.slice(0, 6): tops.append("%s=%d" % [k, counts[k]])
	var n := maxf(1.0, _wall.size())
	var sums := [0.0, 0.0, 0.0]
	for i in _wall.size():
		sums[0] += _wall[i]; sums[1] += _cpu[i]; sums[2] += _own[i]
	var wall := _wall.duplicate(); wall.sort()
	var cpu := _cpu.duplicate(); cpu.sort()
	var own := _own.duplicate(); own.sort()
	var cal := _cal.duplicate(); cal.sort()
	print("WALL frames=%d avg=%.2fms median=%.2fms p95=%.2fms max=%.2fms (raw wall-clock gaps, incl. time other processes held the CPU)" % [_wall.size(), sums[0] / n, _pct(wall, 0.5), _pct(wall, 0.95), wall[-1]])
	if _sched_ok:
		print("OWN  avg=%.2fms median=%.2fms p95=%.2fms max=%.2fms (wall minus run-queue wait; queued %.0f%% of wall)" % [sums[2] / n, _pct(own, 0.5), _pct(own, 0.95), own[-1], 100.0 * (sums[0] - sums[2]) / maxf(1.0, sums[0])])
		print("CPU  avg=%.2fms median=%.2fms p95=%.2fms max=%.2fms (main thread on-CPU, +-1 tick per frame)" % [sums[1] / n, _pct(cpu, 0.5), _pct(cpu, 0.95), cpu[-1]])
	var cal_ms: float = _pct(cal, 0.5) if cal.size() > 0 else CAL_REF_MS
	var factor := clampf(cal_ms / CAL_REF_MS, 1.0, CAL_MAX_FACTOR)
	var avg: float = sums[1] / n
	var mx: float = cpu[-1]
	var ok := avg < AVG_LIMIT * factor and mx < MAX_LIMIT * factor
	print("CAL  runs=%d median=%.2fms min=%.2fms ref=%.2fms factor=%.2f -> limits avg<%.2fms max<%.1fms" % [cal.size(), cal_ms, cal[0] if cal.size() > 0 else 0.0, CAL_REF_MS, factor, AVG_LIMIT * factor, MAX_LIMIT * factor])
	# Gate verdict: smooth on this machine (phones are ~4x slower).
	print("PERF-TEST %s avg=%.2fms max=%.1fms (%s, calibrated x%.2f; quiet-box equivalent avg=%.2fms) wall_avg=%.2fms wall_max=%.0fms%s" % [
		"ok" if ok else "FAIL", avg, mx, "main-thread CPU" if _sched_ok else "wall", factor, avg / factor,
		sums[0] / n, wall[-1], (" injected=%.1fms" % _inject_ms) if _inject_ms > 0.0 else ""])
	print("PERF map=%d mode=%d bots=%d nodes=%d objects=%d | %s" % [_map, _mode, _bots, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), ", ".join(tops)])
