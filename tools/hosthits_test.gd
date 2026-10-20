extends SceneTree
## Host-decided hits (#266), gate stage F. Runs real dedicated servers, UDP
## latency proxies (tools/udp_lag_proxy.py: delay, jitter, loss, stalls) and
## scripted smoke clients (scripts/smoke_duel.gd), then reads their logs.
##   godot --headless -s tools/hosthits_test.gd -- --case=honest|cheats [--out=DIR]
##         [--scenarios=a,b,...] [--parallel=N]
##
## honest: the SCENARIOS below, each on its own server: one scripted shooter
##   attacks one scripted victim (kept alive with medikits) over lagging,
##   jittery, lossy links with stalls — AK, Spas pellets, knife, LAW, M79,
##   grenades, the buggy gun; victims strafing, jetting or driving; shooters
##   standing, strafing or jetting; 50-250 ms round trips; a second shooter
##   joining a match in progress after a round end + map change. Each must
##   show: no refusal at all (every refusal counter zero, no TRUST line), the
##   host's hits matching what the shooter's own screen showed (bullets shot by
##   shot, splash / melee / vehicle-gun hits in total), the weapon's damage per
##   hit, and the victim told exactly what the host applied. The first batch
##   also checks that a pre-#266 build is refused with a readable reason.
## cheats: modified clients against the same kind of server. Shooters: 3x fire
##   rate, 10x damage in their own copy, a magazine that never empties, rounds
##   spawned next to the target, silent aim, infinite jet fuel — each refused /
##   corrected with its counter and TRUST line, the damage numbers unchanged.
##   Victims (no medikits): taking half of / none of the host's hits — logged,
##   and the host still kills them.
## Prints HOSTHITS-SCENARIO lines and, last, HOSTHITS-TEST ok|FAIL.
## (Several minutes: real-time multi-process.)

const ERR_RE := "FEATURE-FAIL|No multiplayer peer is assigned|SCRIPT ERROR|Parse Error|Cannot load|Identifier not found|Invalid call|Cannot infer|Node not found|Invalid packet|Failed to get path|previously freed|Invalid access|Invalid get|Invalid set|Invalid assignment|Nonexistent function|out of bounds|Lambda capture|while flushing queries"
# Kicked / force-killed cheaters leave packets for bodies already gone (as in
# the gate's C trust cases); only allowed in the cheat sessions.
const DROP_RE := "Node not found: \"Main/Player_|Failed to get cached node from peer|Invalid packet received. Requested node was not found|Unable to send packet on channel|Failed to get path from RPC: Main/Player_"
const AK_DMG := 22.0

var _godot := ""
var _proj := ""
var _out := ""
var _pids: Array = []
var _bad: Array = []
var _log: Array = []
var _err_re := RegEx.new()
var _drop_re := RegEx.new()


func _initialize() -> void:
	_godot = OS.get_executable_path()
	_proj = ProjectSettings.globalize_path("res://").rstrip("/")
	var case := "honest"
	var names: Array = SCENARIOS.keys()
	var parallel := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--case="):
			case = a.substr(7)
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--scenarios="):
			names = Array(a.substr(12).split(",", false))
		elif a.begins_with("--parallel="):
			parallel = maxi(1, int(a.substr(11)))
	if _out == "":
		_out = OS.get_user_data_dir().path_join("hosthits_test")
	elif not _out.is_absolute_path():
		_out = _proj.path_join(_out)   # (the gate passes build/gate/...; it runs from the repo root)
	DirAccess.make_dir_recursive_absolute(_out)
	_err_re.compile(ERR_RE)
	_drop_re.compile(DROP_RE)
	if case == "cheats":
		_cheats()
		# A client a busy machine kept loading past ENet's timeout loses its
		# connection before it ever plays: that run says nothing about the
		# host's checks, so it gets one more go (in a subfolder).
		var lost := []
		for k in TAGS.keys():
			if _read("cheat_%s.log" % k).contains("Lost connection to the host"):
				lost.append(k)
		if not _bad.is_empty() and not lost.is_empty():
			print("HOSTHITS-CHEATS first run inconclusive (lost connection: %s): %s" % [",".join(lost), str(_bad)])
			_stop_all()
			_bad.clear()
			_log = ["retried (lost connection: %s)" % ",".join(lost)]
			_out = _out.path_join("retry")
			DirAccess.make_dir_recursive_absolute(_out)
			_cheats()
	else:
		_honest(names, parallel)
	_stop_all()
	var ok := _bad.is_empty()
	print("(host-hits test logs in %s)" % _out)
	# (Last line carrying the tag: the gate's ft reads the last one.)
	print("HOSTHITS-TEST %s case=%s %s | %s" % ["ok" if ok else "FAIL", case, str(_bad), " ".join(_log)])
	quit(0 if ok else 1)


# ── processes ──

func _spawn(cmd: String) -> int:
	var pid := OS.create_process("bash", ["-c", cmd])
	if pid > 0:
		_pids.append(pid)
	return pid


func _q(s: String) -> String:
	return "'" + s.replace("'", "'\\''") + "'"


func _game(args: String, secs: int, logname: String, engine := "") -> int:
	return _spawn("exec timeout %d %s --path %s --headless %s -- %s > %s 2>&1" % [secs, _q(_godot), _q(_proj), engine, args, _q(_out.path_join(logname))])


func _proxy(listen: int, to: int, link: String, seed: int, logname: String) -> int:
	return _spawn("exec timeout 600 python3 %s --listen %d --to 127.0.0.1:%d %s --seed %d > %s 2>&1" % [
		_q(_proj.path_join("tools/udp_lag_proxy.py")), listen, to, link, seed, _q(_out.path_join(logname))])


func _stop(pid: int) -> void:
	if pid > 0:
		OS.execute("kill", ["-TERM", str(pid)])
		_pids.erase(pid)


func _stop_all() -> void:
	for pid in _pids.duplicate():
		_stop(pid)


func _alive(pid: int) -> bool:
	# (Also reaps it: a finished child stays in /proc as a zombie until then.)
	return pid > 0 and OS.is_process_running(pid)


func _read(logname: String) -> String:
	var p := _out.path_join(logname)
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""


func _wait_for(logname: String, needle: String, secs: float) -> bool:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		if _read(logname).contains(needle):
			return true
		OS.delay_msec(250)
	return false


func _wait_exit(pid: int, secs: float) -> void:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while _alive(pid) and Time.get_ticks_msec() < until:
		OS.delay_msec(250)


## Dedicated server on a free-looking port; returns [pid, port] or [] on failure.
func _host(extra: String, logname: String, map := "Arena") -> Array:
	for _try in 3:
		var port := 30000 + randi() % 9000
		var pid := _game("--dedicated --port %d --map %s --mode dm --fill=1 --hosthits-log %s" % [port, map, extra], 600, logname)
		if _wait_for(logname, "listening on port %d" % port, 90.0):
			OS.delay_msec(3000)
			return [pid, port]
		_stop(pid)
	_bad.append("server did not start (%s)" % logname)
	return []


func _errors(logname: String, allow_drops: bool) -> int:
	var n := 0
	for line in _read(logname).split("\n"):
		if _err_re.search(line) != null and not (allow_drops and _drop_re.search(line) != null):
			n += 1
	return n


func _lines(logname: String, prefix: String) -> Array:
	var out: Array = []
	for line in _read(logname).split("\n"):
		if line.begins_with(prefix):
			out.append(line)
	return out


func _kv(line: String, key: String) -> float:
	var at := line.find(" " + key + "=")
	if at < 0:
		return 0.0
	var rest := line.substr(at + key.length() + 2)
	return float(rest.split(" ")[0])


func _stats(logname: String) -> String:
	var l := _lines(logname, "HOSTHITS ")
	return l[-1] if not l.is_empty() else ""


func _duel_line(logname: String) -> String:
	for line in _lines(logname, "SMOKE-DUEL role="):
		return line
	return ""


# ── honest ──

# Per link (s_ = the shooter's, v_ = the victim's): one-way delay ms; both get
# `jitter` (0..N ms extra), `loss` (% dropped each way) and stalls (every
# ~spike_every s everything is held spike_ms). damage: one hit (0 = splash,
# any amount; a Vest halves it). match: "shot" (bullets, shot by shot) or
# "total" (splash / melee / vehicle gun: hit counts).
const SCENARIOS := {
	"ak150": {"weapon": "ak", "s_ms": 75, "v_ms": 50, "jitter": 6, "damage": 22.0, "match": "shot"},
	"ak250": {"weapon": "ak", "s_ms": 125, "v_ms": 100, "jitter": 40, "loss": 3.0, "spike_every": 6.0, "spike_ms": 250,
		"v_move": "jet", "damage": 22.0, "match": "shot"},
	"move250": {"weapon": "ak", "s_ms": 125, "v_ms": 90, "jitter": 40, "loss": 3.0, "spike_every": 5.0, "spike_ms": 300,
		"s_move": "jet", "damage": 22.0, "match": "shot"},
	"spas250": {"weapon": "spas", "s_ms": 120, "v_ms": 100, "jitter": 40, "loss": 3.0, "spike_every": 5.0, "spike_ms": 300,
		"s_move": "strafe", "v_move": "jet", "damage": 9.0, "match": "shot"},
	"knife250": {"weapon": "knife", "s_ms": 125, "v_ms": 100, "jitter": 40, "loss": 3.0, "spike_every": 5.0, "spike_ms": 300,
		"damage": 55.0, "match": "total"},
	# A slow PC: the shooter's game stalls 45 ms every frame (Godot --frame-delay:
	# ~20 fps, physics catching up several steps at a time, packets in bursts).
	"slowpc": {"weapon": "ak", "s_ms": 60, "v_ms": 50, "jitter": 15, "s_move": "strafe", "damage": 22.0, "match": "shot",
		"s_engine": "--frame-delay 45"},
	"slowspas": {"weapon": "spas", "s_ms": 60, "v_ms": 50, "jitter": 15, "damage": 9.0, "match": "shot",
		"s_engine": "--frame-delay 45"},
	"lowping": {"weapon": "ak", "s_ms": 25, "v_ms": 25, "jitter": 4, "s_move": "jet", "damage": 22.0, "match": "shot"},
	"spas": {"weapon": "spas", "s_ms": 90, "v_ms": 60, "jitter": 30, "loss": 2.0, "s_move": "strafe", "damage": 9.0, "match": "shot"},
	"knife": {"weapon": "knife", "s_ms": 100, "v_ms": 60, "jitter": 20, "loss": 1.0, "damage": 55.0, "match": "total"},
	# (Lagrange: flat open ground by its first buggy, no other vehicle near.)
	"law": {"secs": 52, "need": 4, "weapon": "law", "s_ms": 90, "v_ms": 75, "jitter": 20, "damage": 0.0, "match": "total",
		"map": "Lagrange", "args": "--smoke-near-vehicle --smoke-offsets=-480,-180"},
	"m79": {"secs": 52, "need": 4, "weapon": "m79", "s_ms": 60, "v_ms": 60, "jitter": 15, "loss": 1.0, "damage": 0.0, "match": "total",
		"map": "Lagrange", "args": "--smoke-near-vehicle --smoke-offsets=-350,-180"},
	"grenade": {"secs": 52, "need": 4, "weapon": "grenade", "s_ms": 70, "v_ms": 50, "jitter": 15, "damage": 0.0, "match": "total",
		"map": "Lagrange", "args": "--smoke-near-vehicle --smoke-offsets=-440,-180"},
	"buggy": {"weapon": "buggy", "s_ms": 75, "v_ms": 50, "jitter": 20, "loss": 1.0, "damage": 14.0, "match": "total",
		"map": "Lagrange", "args": "--smoke-near-vehicle --smoke-offsets=-350,0"},
	"drive": {"weapon": "ak", "s_ms": 80, "v_ms": 60, "jitter": 20, "v_move": "drive", "damage": 22.0, "match": "shot",
		"map": "Lagrange", "args": "--smoke-near-vehicle --smoke-offsets=0,-450"},
	"jip": {"weapon": "ak", "s_ms": 100, "v_ms": 50, "jitter": 25, "loss": 1.0, "damage": 22.0, "match": "shot", "jip": true},
}

const WEAPON_NAMES := {"ak": ["AK-74"], "spas": ["Spas-12"], "knife": ["Knife"], "law": ["LAW"], "m79": ["M79"], "grenade": ["Grenade", "Cluster"], "buggy": ["Buggy MG"]}

# Counters that mean the host refused / overrode something a client said.
const REFUSALS := ["refused_", "aim_refused", "hp_ignored"]


func _honest(names: Array, parallel: int) -> void:
	var retry: Array = []
	for n in names:
		if not SCENARIOS.has(n):
			_bad.append("unknown scenario '%s'" % n)
	var todo: Array = names.filter(func(n) -> bool: return SCENARIOS.has(n))
	_batches(todo, parallel, true, retry)
	# A scenario that missed only on agreement (no refusal, no wrong number)
	# gets one more go on its own: on a busy machine a starved client falls
	# seconds behind and its screen no longer shows what the host rewinds to.
	if not retry.is_empty():
		_log.append("retried=%s" % ",".join(retry))
		_batches(retry, 1, false, [])


func _batches(names: Array, parallel: int, first_run: bool, retry: Array) -> void:
	var first := first_run
	var i := 0
	while i < names.size():
		var runs: Array = []
		for n in names.slice(i, i + parallel):
			runs.append(_sc_start(n, n if first_run else "%s_retry" % n))
		i += parallel
		for r in runs:
			_sc_join(r)
		for r in runs:
			_sc_play(r)
		for r in runs:
			_sc_wait(r)
		if first and not runs.is_empty() and not (runs[0]["host"] as Array).is_empty():
			first = false
			_old_build(int(runs[0]["host"][1]))
		OS.delay_msec(5500)   # one more HOSTHITS summary
		for r in runs:
			if not (r["host"] as Array).is_empty():
				_stop(int(r["host"][0]))
			for pid in r["proxies"]:
				_stop(int(pid))
		OS.delay_msec(500)
		for r in runs:
			var bad: Array = _sc_judge(r)
			var agreement_only := not bad.is_empty()
			for b in bad:
				var soft := false
				for k in ["confirmed only", "landed only", "added", "too few predicted", "its screen showed"]:
					if str(b).contains(k):
						soft = true
				agreement_only = agreement_only and soft
			if first_run and agreement_only:
				retry.append(r["base"])
				continue
			for b in bad:
				_bad.append("%s: %s" % [r["name"], b])


func _sc_start(base: String, n: String) -> Dictionary:
	var sc: Dictionary = SCENARIOS[base]
	var r := {"name": n, "base": base, "sc": sc, "host": [], "proxies": [], "shooters": [], "victim": 0, "ps": 0}
	var extra := "--smoke-medic=VIC"
	if bool(sc.get("jip", false)):
		extra += " --smoke-round-secs=34"
	r["host"] = _host(extra, "%s_host.log" % n, str(sc.get("map", "Arena")))
	return r


func _link(sc: Dictionary, pre: String) -> String:
	return "--delay-ms %d --jitter-ms %d --loss-pct %.1f --spike-every %.1f --spike-ms %d" % [
		int(sc.get(pre + "ms", 50)), int(sc.get("jitter", 0)), float(sc.get("loss", 0.0)), float(sc.get("spike_every", 0.0)), int(sc.get("spike_ms", 0))]


func _sc_join(r: Dictionary) -> void:
	if (r["host"] as Array).is_empty():
		return
	var n: String = r["name"]
	var sc: Dictionary = r["sc"]
	var port: int = r["host"][1]
	r["ps"] = port + 10   # (port + 1 is the server's query port)
	var pv: int = port + 11
	r["proxies"].append(_proxy(int(r["ps"]), port, _link(sc, "s_"), 1, "%s_proxy_shooter.log" % n))
	r["proxies"].append(_proxy(pv, port, _link(sc, "v_"), 2, "%s_proxy_victim.log" % n))
	if not _wait_for("%s_proxy_shooter.log" % n, "LAGPROXY listening", 15.0) or not _wait_for("%s_proxy_victim.log" % n, "LAGPROXY listening", 15.0):
		_bad.append("%s: latency proxies did not start" % n)
		r["host"] = []
		return
	var jip := bool(sc.get("jip", false))
	# (The victim stays until the test says every shooter has left — a busy
	# machine can take a while to load a shooter — at most vsecs.)
	var vsecs := 240
	var done := _out.path_join("%s_done" % n)
	DirAccess.remove_absolute(done)
	r["done"] = done
	r["victim"] = _game("--smoke-join --port %d --smoke-secs=%d --smoke-role=victim --smoke-move=%s%s --clan=vic --smoke-done-file=%s %s" % [
		pv, vsecs, str(sc.get("v_move", "strafe")), " --smoke-vote" if jip else "", _q(done), str(sc.get("args", ""))], vsecs + 30, "%s_victim.log" % n)


func _shooter_cmd(r: Dictionary, secs: int, clan: String) -> String:
	var sc: Dictionary = r["sc"]
	return "--smoke-join --port %d --smoke-secs=%d --smoke-role=shooter --smoke-target=VIC --smoke-weapon=%s --smoke-move=%s --hosthits-log --clan=%s %s" % [
		int(r["ps"]), secs, str(sc.get("weapon", "ak")), str(sc.get("s_move", "stand")), clan, str(sc.get("args", ""))]


func _sc_play(r: Dictionary) -> void:
	if (r["host"] as Array).is_empty():
		return
	var n: String = r["name"]
	if not _wait_for("%s_victim.log" % n, "SMOKE-DUEL placed", 60.0):
		_bad.append("%s: the victim never got placed" % n)
	OS.delay_msec(1000)
	# jip: this shooter plays most of a short round; the round ends, the victim
	# votes, the map changes, then a second shooter joins the new map.
	var secs := 24 if bool(r["sc"].get("jip", false)) else int(r["sc"].get("secs", 36))
	r["shooters"] = [["SHT", _game(_shooter_cmd(r, secs, "sht"), secs + 80, "%s_shooter.log" % n, str(r["sc"].get("s_engine", ""))), "%s_shooter.log" % n]]


func _sc_wait(r: Dictionary) -> void:
	if (r["host"] as Array).is_empty():
		return
	var n: String = r["name"]
	for sh in r["shooters"]:
		_wait_exit(int(sh[1]), 115.0)
	if bool(r["sc"].get("jip", false)):
		# A second map line = the map changed (34 s round + winner screen + vote).
		var until := Time.get_ticks_msec() + 60000
		while Time.get_ticks_msec() < until and _lines("%s_host.log" % n, "HOSTHITS-MAP ").size() < 2:
			OS.delay_msec(250)
		OS.delay_msec(1500)
		var p2 := _game(_shooter_cmd(r, 32, "shb"), 115, "%s_shooter2.log" % n)
		r["shooters"].append(["SHB", p2, "%s_shooter2.log" % n])
		_wait_exit(p2, 115.0)
	OS.delay_msec(1000)   # (the last hits reach the victim)
	var f := FileAccess.open(str(r["done"]), FileAccess.WRITE)
	if f != null:
		f.store_string("done")
		f.close()
	_wait_exit(int(r["victim"]), 45.0)


## A pre-#266 build (same game version, online protocol 1) is turned away with
## a readable reason instead of joining.
func _old_build(port: int) -> void:
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	var old := _game("--smoke-join --port %d --smoke-secs=12 --smoke-net-version=%s" % [port, ver], 60, "oldbuild.log")
	_wait_exit(old, 55.0)
	var left := ""
	for line in _lines("oldbuild.log", "NET left the match: "):
		left = line
	_log.append("old build: '%s'" % left.substr(20))
	if not left.contains("Version mismatch: host %s (online protocol %d), you %s (online protocol 1)" % [ver, preload("res://scripts/game_info.gd").NET_PROTOCOL, ver]):
		_bad.append("an old-protocol client was not refused cleanly ('%s')" % left)


func _sc_judge(r: Dictionary) -> Array:
	var n: String = r["name"]
	var sc: Dictionary = r["sc"]
	var bad: Array = []
	var info: Array = []
	if (r["host"] as Array).is_empty():
		bad.append("no server")
	var hlog := "%s_host.log" % n
	var st := _stats(hlog)
	# 1. Nothing an honest client did was refused or overridden.
	var refused: Array = []
	for part in st.split(" "):
		var kv := part.split("=")
		if kv.size() == 2:
			for pre in REFUSALS:
				if kv[0].begins_with(pre) and float(kv[1]) > 0.0:
					refused.append(part)
	if not refused.is_empty():
		bad.append("refused: %s" % " ".join(refused))
	var trust := _lines(hlog, "TRUST ")
	if not trust.is_empty():
		bad.append("TRUST lines: %s" % str(trust.slice(0, 3)))
	# 2. Per shooter: the host's hits vs the shooter's own screen.
	var dmg: float = float(sc.get("damage", 0.0))
	for sh in r["shooters"]:
		var tag: String = sh[0]
		var slog: String = sh[2]
		# (This run's weapon only: a run-over or a wreck's blast is a hit too,
		# but not one this scenario measures.)
		var wn: Array = WEAPON_NAMES.get(str(sc.get("weapon", "ak")), [])
		var hits := _lines(hlog, "HOSTHIT «%s»" % tag).filter(func(l: String) -> bool:
			if not l.contains("-> «VIC»"):
				return false
			for w in wn:
				if l.contains("(%s)" % w):
					return true
			return wn.is_empty())
		var wrong := 0
		for line in hits:
			var amt := _amount(line)
			if dmg > 0.0 and absf(amt - dmg) > 0.01 and absf(amt - dmg * 0.5) > 0.01:
				wrong += 1
		if wrong > 0:
			bad.append("%s: %d hits worth neither %.0f nor %.0f (vest)" % [tag, wrong, dmg, dmg * 0.5])
		var duel := _duel_line(slog)
		if duel == "":
			bad.append("%s never reported (SMOKE-DUEL)" % tag)
		var need: int = int(sc.get("need", 8 if bool(sc.get("jip", false)) else 12))
		if str(sc.get("match", "shot")) == "shot":
			var pred := {}
			for line in _lines(slog, "PREDHIT shot="):
				var k := int(line.split(" ")[1].substr(5))
				pred[k] = int(pred.get(k, 0)) + 1
			var host := {}
			for line in _lines(hlog, "HOSTSHOT shot="):
				if line.ends_with("by=«%s» Player" % tag) or line.contains("by=«%s»" % tag):
					var k2 := int(line.split(" ")[1].substr(5))
					host[k2] = int(host.get(k2, 0)) + 1
			var np := 0
			var nh := 0
			var both := 0
			for k in pred.keys():
				np += int(pred[k])
				both += mini(int(pred[k]), int(host.get(k, 0)))
			for k in host.keys():
				nh += int(host[k])
			var extra := nh - both
			info.append("%s pred=%d host=%d matched=%d extra=%d" % [tag, np, nh, both, extra])
			if np < need:
				bad.append("%s: too few predicted hits to judge (%d)" % [tag, np])
			elif float(both) < 0.85 * np:
				bad.append("%s: host confirmed only %d of %d predicted hits" % [tag, both, np])
			if np > 0 and float(extra) > 0.30 * np:
				bad.append("%s: host added %d hits the shooter never saw (of %d)" % [tag, extra, np])
		else:
			# Splash / melee / vehicle gun: hit counts (splash damage depends on
			# the distance, which differs a little between the two views).
			var np2 := int(_kv(duel, "predicted_other_hits")) + int(_kv(duel, "predicted_hits"))
			var nh2 := hits.size()
			info.append("%s pred=%d host=%d" % [tag, np2, nh2])
			if np2 < (need if sc.has("need") else need / 2):
				bad.append("%s: too few predicted hits to judge (%d)" % [tag, np2])
			elif float(nh2) < 0.75 * np2:
				bad.append("%s: host landed only %d of %d predicted hits" % [tag, nh2, np2])
			if float(nh2) > 1.4 * np2 + 2.0:
				bad.append("%s: host landed %d hits, its screen showed %d" % [tag, nh2, np2])
	# 3. The victim was told exactly what the host applied.
	var total := 0.0
	for line in _lines(hlog, "HOSTHIT "):
		if line.contains("-> «VIC»"):
			total += _amount(line)
	var told := _kv(_duel_line("%s_victim.log" % n), "damage_taken")
	info.append("host_damage=%.0f victim_told=%.0f" % [total, told])
	# (A crew killed with its vehicle is dead on its own screen before the
	# host's killing hit arrives: only a killing hit may go untold.)
	var lethal := 0.0
	for line in _lines(hlog, "HOSTHIT "):
		if line.contains("-> «VIC»") and line.ends_with("hp 0.0"):
			lethal += _amount(line)
	if absf(told - total) > 0.5 and not (told <= total + 0.5 and total - told <= lethal + 0.5):
		bad.append("victim was told %.0f damage, host applied %.0f" % [told, total])
	info.append("rewind_avg=%.0fms" % (_kv(st, "rewind_ms") / maxf(1.0, _kv(st, "rewind_shots"))))
	# How far behind the shooters' screens ran beyond their round trip (a
	# starved client on a busy machine shows up here, in seconds).
	var lag := 0.0
	var nl := 0
	for line in _lines(hlog, "HOSTRECV "):
		var va := _kv(line, "view_age")
		if va >= 0.0:
			lag += va - _kv(line, "rtt")
			nl += 1
	info.append("view_lag=%.0fms" % (lag / maxf(1.0, float(nl))))
	if bool(sc.get("jip", false)):
		var maps := _lines(hlog, "HOSTHITS-MAP ")
		info.append("maps=%s" % ",".join(maps.map(func(l: String) -> String: return l.substr(13))))
		if maps.size() < 2:
			bad.append("no map change")
	var logs := [hlog, "%s_victim.log" % n]
	for sh in r["shooters"]:
		logs.append(sh[2])
	for f in logs:
		# (A map change: state packets already on their way to the old map's
		# bodies arrive at the new map and are dropped with an engine error —
		# as before #266; counted, not failed.)
		var drops: bool = bool(sc.get("jip", false)) and str(f) == hlog
		var e := _errors(f, drops)
		if drops:
			info.append("map-change drops=%d" % (_errors(f, false) - e))
		if e > 0:
			bad.append("%d error lines in %s" % [e, f])
	print("HOSTHITS-SCENARIO %s %s %s | %s" % [n, "ok" if bad.is_empty() else "FAIL", str(bad), " ".join(info)])
	_log.append("%s:%s" % [n, "ok" if bad.is_empty() else "FAIL"])
	return bad


# ── cheats ──

const TAGS := {"dmg": "DMG", "rate": "RATE", "ammo": "AMMO", "origin": "ORIG", "silentaim": "SIL", "fuel": "FUEL"}


func _cheats() -> void:
	# A: an honest victim (tagged VIC, kept alive with medikits) under fire from
	# six modified shooters at once.
	var h := _host("--smoke-medic=VIC", "cheat_host.log")
	if h.is_empty():
		return
	var port: int = h[1]
	var v := _game("--smoke-join --port %d --smoke-secs=260 --smoke-role=victim --clan=vic" % port, 320, "cheat_victim.log")
	if not _wait_for("cheat_victim.log", "SMOKE-DUEL placed", 90.0):
		_bad.append("the victim never joined")
		return
	var pids: Array = []
	for kind in TAGS.keys():
		pids.append(_game("--smoke-join --port %d --smoke-secs=46 --smoke-role=shooter --smoke-target=VIC --smoke-start-ms=500 --smoke-cheat=%s --clan=%s" % [
			port, kind, TAGS[kind]], 130, "cheat_%s.log" % kind))
		OS.delay_msec(1500)   # (staggered: six clients loading at once can starve a small machine)
	for pid in pids:
		_wait_exit(pid, 115.0)
	OS.delay_msec(5500)   # one more HOSTHITS summary
	_stop(v)
	_stop(h[0])
	# B: two modified victims (no medikits) under honest shooters' short bursts.
	var h2 := _host("", "cheat2_host.log")
	if h2.is_empty():
		return
	var port2: int = h2[1]
	var vps: Array = []
	for pr in [["partial", "VP"], ["godmode", "VG"]]:
		vps.append(_game("--smoke-join --port %d --smoke-secs=56 --smoke-role=victim --smoke-cheat=%s --clan=%s" % [port2, pr[0], pr[1]], 150, "cheat_%s.log" % pr[0]))
	_wait_for("cheat_partial.log", "SMOKE-DUEL placed", 90.0)
	_wait_for("cheat_godmode.log", "SMOKE-DUEL placed", 30.0)
	var shs: Array = []
	for pr in [["VP", "S1"], ["VG", "S2"]]:
		shs.append(_game("--smoke-join --port %d --smoke-secs=36 --smoke-role=shooter --smoke-target=%s --smoke-start-ms=500 --smoke-burst --clan=%s" % [port2, pr[0], pr[1]], 120, "cheat_shooter_%s.log" % pr[0].to_lower()))
	for pid in shs + vps:
		_wait_exit(pid, 115.0)
	OS.delay_msec(5500)
	_stop(h2[0])
	var hl := _read("cheat_host.log")
	var st := _stats("cheat_host.log")
	_log.append("[%s]" % st.substr(9, 400))
	# Damage numbers: the 10x client's own copy said 220 a hit; the host applied
	# the AK's 22, every time.
	var dmg := _duel_line("cheat_dmg.log")
	var hits := _lines("cheat_host.log", "HOSTHIT «DMG»")
	var wrong := 0
	for line in hits:
		if absf(_amount(line) - AK_DMG) > 0.01 and absf(_amount(line) - AK_DMG * 0.5) > 0.01:
			wrong += 1
	_log.append("dmg: its screen %.0f over %d hits, host %d hits all %.0f=%s" % [_kv(dmg, "predicted_damage"), int(_kv(dmg, "predicted_hits")), hits.size(), AK_DMG, str(wrong == 0)])
	if _kv(dmg, "predicted_hits") < 3 or _kv(dmg, "predicted_damage") < 200.0 * _kv(dmg, "predicted_hits"):
		_bad.append("the damage cheat never hit on its own screen ('%s')" % dmg)
	if hits.size() < 3 or wrong > 0:
		_bad.append("damage cheat: %d host hits, %d not exactly %.0f" % [hits.size(), wrong, AK_DMG])
	_expect(hl, st, "rate", "refused_rate", "TRUST rate: ")
	_expect(hl, st, "ammo", "refused_ammo", "TRUST ammo: ")
	_expect(hl, st, "origin", "refused_origin", "TRUST origin: ")
	_expect(hl, st, "silentaim", "refused_aim", "TRUST aim: ")
	_expect(hl, st, "fuel", "refused_fuel", "TRUST fuel: ")
	if not hl.contains("fuel (jetting with an empty tank)"):
		_bad.append("no forced death for infinite fuel")
	# Spawned / silent-aim rounds never hurt anyone.
	var sneaky := _shooter_hits(st, "ORIG") + _shooter_hits(st, "SIL")
	_log.append("hits by spawned / silent-aim rounds: %d" % int(sneaky))
	if sneaky > 0.5:
		_bad.append("%d hits landed from spawned / silent-aim rounds" % int(sneaky))
	# Modified victims: logged, and the host's ledger still kills them.
	var h2l := _read("cheat2_host.log")
	for t in ["VP", "VG"]:
		var logged := false
		for line in _lines("cheat2_host.log", "TRUST hp: "):
			if line.contains("«%s»" % t):
				logged = true
		var deaths := 0
		for line in _lines("cheat2_host.log", "HOSTHIT "):
			if line.contains("-> «%s»" % t) and line.ends_with("hp 0.0"):
				deaths += 1
		_log.append("%s: logged=%s host kills=%d" % [t, str(logged), deaths])
		if not logged:
			_bad.append("«%s» (%s) ignoring the host's hits was not logged" % [t, "half damage" if t == "VP" else "godmode"])
		if deaths < 1:
			_bad.append("the host never killed «%s»" % t)
		if h2l.contains("TRUST forced death: «%s»" % t):
			_bad.append("«%s» was force-killed instead of simply dying" % t)
	for f in ["cheat_host.log", "cheat2_host.log", "cheat_victim.log", "cheat_dmg.log", "cheat_rate.log", "cheat_ammo.log", "cheat_origin.log",
			"cheat_silentaim.log", "cheat_fuel.log", "cheat_partial.log", "cheat_godmode.log", "cheat_shooter_vp.log", "cheat_shooter_vg.log"]:
		var e := _errors(f, true)
		if e > 0:
			_bad.append("%d error lines in %s" % [e, f])


## The damage of one "HOSTHIT <killer> -> <victim> <amount> (<weapon>) hp <n>" line.
func _amount(line: String) -> float:
	var re := RegEx.new()
	re.compile(" -> .* ([0-9.]+) \\(.*\\) hp ")
	var m := re.search(line)
	return float(m.get_string(1)) if m != null else 0.0


## Hits landed so far by the soldier tagged `tag` (HOSTHITS shooters=[...]).
func _shooter_hits(st: String, tag: String) -> float:
	var at := st.find("shooters=[")
	if at < 0:
		return 0.0
	var n := 0.0
	for e in st.substr(at + 10).split("]")[0].split(","):
		if e.begins_with("«%s»" % tag) and e.contains(":"):
			n += float(e.split(":")[1].split("/")[0])
	return n


func _expect(host_log: String, st: String, kind: String, counter: String, trust: String) -> void:
	var n := _kv(st, counter)
	_log.append("%s: %s=%d" % [kind, counter, int(n)])
	if n < 1.0:
		_bad.append("%s cheat not refused (%s=0)" % [kind, counter])
	if not host_log.contains(trust):
		_bad.append("no '%s' line for the %s cheat" % [trust.strip_edges(), kind])
