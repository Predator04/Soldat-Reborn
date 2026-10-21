extends RefCounted
## Load-robust timing helpers for gate tests (#293). The gate box often runs
## several gates at once, so wall-clock time mostly measures how long other
## processes held the CPU. No class_name: tests run with -s before autoloads,
## so they `preload("res://tools/gate_load.gd")`.
##
##   factor()      GATE_LOAD from the environment (release_gate.sh measures the
##                 machine's load at start: 1 = quiet), clamped to [1, MAX]:
##                 multiply WAIT-style wall-clock deadlines by it (time allowed
##                 for something to happen), never a measured limit.
##   stamp()       {us, run, wait}: wall clock + this (main) thread's on-CPU and
##                 run-queue wait nanoseconds from /proc/self/schedstat (Linux;
##                 run / wait are 0 elsewhere — callers fall back to wall time).
##   own_ms(a, b)  wall ms between two stamps minus the time the thread sat in
##                 the run queue = what the thread spent working or blocked by
##                 itself (not preempted by other processes).
##   cpu_ms(a, b)  on-CPU ms between two stamps (updated per scheduler tick, so
##                 one frame is +-1 tick; sums over many frames are exact).

const MAX_FACTOR := 4.0


static func factor() -> float:
	var v := OS.get_environment("GATE_LOAD")
	if v == "" or not v.is_valid_float():
		return 1.0
	return clampf(float(v), 1.0, MAX_FACTOR)


## Wall-clock deadline scaled by factor().
static func wait_ms(base_ms: float) -> int:
	return int(base_ms * factor())


static func has_sched() -> bool:
	return _read().size() == 2


static func _read() -> Array:
	var f := FileAccess.open("/proc/self/schedstat", FileAccess.READ)
	if f == null:
		return []
	var parts := f.get_line().split(" ", false)
	if parts.size() < 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return []
	return [int(parts[0]), int(parts[1])]


## Clock + scheduler counters read back to back. A preemption between the two
## reads would charge its queue wait to the wrong interval, so retry until the
## pair is tight.
static func stamp() -> Dictionary:
	var us := Time.get_ticks_usec()
	var sc: Array = []
	for _try in 4:
		sc = _read()
		var after := Time.get_ticks_usec()
		if after - us < 500:
			break
		us = after
	if sc.size() != 2:
		return {"us": us, "run": 0, "wait": 0, "ok": false}
	return {"us": us, "run": sc[0], "wait": sc[1], "ok": true}


static func wall_ms(a: Dictionary, b: Dictionary) -> float:
	return (int(b["us"]) - int(a["us"])) / 1000.0


static func own_ms(a: Dictionary, b: Dictionary) -> float:
	var w := wall_ms(a, b)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return w
	return maxf(0.0, w - (int(b["wait"]) - int(a["wait"])) / 1000000.0)


static func cpu_ms(a: Dictionary, b: Dictionary) -> float:
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return wall_ms(a, b)
	return (int(b["run"]) - int(a["run"])) / 1000000.0
