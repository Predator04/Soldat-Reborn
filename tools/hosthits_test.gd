extends SceneTree
## Host-decided hits (#266), gate stage F. Runs a real dedicated server, UDP
## latency proxies (tools/udp_lag_proxy.py) and scripted smoke clients
## (scripts/smoke_duel.gd), then reads their logs.
##   godot --headless -s tools/hosthits_test.gd -- --case=honest|cheats [--out=DIR]
##
## honest: a shooter at ~150 ms round trip fires its AK at a strafing, hopping
##   victim at ~100 ms (the server keeps the victim alive with medikits). The
##   host's decisions must match what the shooter's own screen showed, shot by
##   shot (>= 85 % of its predicted hits land, extra hits <= 30 %), every hit
##   must do exactly the AK's 22, the victim must have been told the same total,
##   and the server must log no TRUST line.
## cheats: modified clients against the same kind of server. Shooters: 3x fire
##   rate, 10x damage in their own copy, a magazine that never empties, rounds
##   spawned next to the target, silent aim, infinite jet fuel — each refused /
##   corrected with its counter and TRUST line, the damage numbers unchanged.
##   Victims (no medikits): taking half of / none of the host's hits — logged,
##   and the host still kills them.
## Prints HOSTHITS-TEST ok|FAIL.  (Several minutes: real-time multi-process.)

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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--case="):
			case = a.substr(7)
		elif a.begins_with("--out="):
			_out = a.substr(6)
	if _out == "":
		_out = OS.get_user_data_dir().path_join("hosthits_test")
	elif not _out.is_absolute_path():
		_out = _proj.path_join(_out)   # (the gate passes build/gate/...; it runs from the repo root)
	DirAccess.make_dir_recursive_absolute(_out)
	_err_re.compile(ERR_RE)
	_drop_re.compile(DROP_RE)
	if case == "cheats":
		_cheats()
	else:
		_honest()
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


func _game(args: String, secs: int, logname: String) -> int:
	return _spawn("exec timeout %d %s --path %s --headless -- %s > %s 2>&1" % [secs, _q(_godot), _q(_proj), args, _q(_out.path_join(logname))])


func _proxy(listen: int, to: int, delay: int, seed: int, logname: String) -> int:
	return _spawn("exec timeout 600 python3 %s --listen %d --to 127.0.0.1:%d --delay-ms %d --jitter-ms 6 --seed %d > %s 2>&1" % [
		_q(_proj.path_join("tools/udp_lag_proxy.py")), listen, to, delay, seed, _q(_out.path_join(logname))])


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
func _host(extra: String, logname: String) -> Array:
	for _try in 3:
		var port := 30000 + randi() % 9000
		var pid := _game("--dedicated --port %d --map Arena --mode dm --fill=1 --hosthits-log %s" % [port, extra], 600, logname)
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

func _honest() -> void:
	var h := _host("--smoke-medic", "honest_host.log")
	if h.is_empty():
		return
	var port: int = h[1]
	var ps := port + 10   # (port + 1 is the server's query port)
	var pv := port + 11
	_proxy(ps, port, 75, 1, "honest_proxy_shooter.log")
	_proxy(pv, port, 50, 2, "honest_proxy_victim.log")
	if not _wait_for("honest_proxy_shooter.log", "LAGPROXY listening", 15.0) or not _wait_for("honest_proxy_victim.log", "LAGPROXY listening", 15.0):
		_bad.append("latency proxies did not start: %s %s" % [_read("honest_proxy_shooter.log").right(200), _read("honest_proxy_victim.log").right(200)])
		return
	var v := _game("--smoke-join --port %d --smoke-secs=44 --smoke-role=victim --clan=vic" % pv, 120, "honest_victim.log")
	_wait_for("honest_victim.log", "SMOKE-DUEL placed", 60.0)
	OS.delay_msec(2000)
	var s := _game("--smoke-join --port %d --smoke-secs=36 --smoke-role=shooter --hosthits-log --clan=sht" % ps, 120, "honest_shooter.log")
	_wait_exit(s, 110.0)
	_wait_exit(v, 30.0)
	# A pre-#266 build (same game version, online protocol 1) is turned away
	# with a readable reason instead of joining.
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	var old := _game("--smoke-join --port %d --smoke-secs=12 --smoke-net-version=%s" % [port, ver], 60, "honest_oldbuild.log")
	_wait_exit(old, 55.0)
	var left := ""
	for line in _lines("honest_oldbuild.log", "NET left the match: "):
		left = line
	_log.append("old build: '%s'" % left.substr(20))
	if not left.contains("Version mismatch: host %s (online protocol %d), you %s (online protocol 1)" % [ver, preload("res://scripts/game_info.gd").NET_PROTOCOL, ver]):
		_bad.append("an old-protocol client was not refused cleanly ('%s')" % left)
	OS.delay_msec(5500)   # one more HOSTHITS summary
	_stop(h[0])
	# Shot by shot: what the shooter's screen predicted vs what the host decided.
	var pred := {}
	for line in _lines("honest_shooter.log", "PREDHIT shot="):
		pred[int(line.split(" ")[1].substr(5))] = true
	var host := {}
	for line in _lines("honest_host.log", "HOSTSHOT shot="):
		host[int(line.split(" ")[1].substr(5))] = true
	var both := 0
	for k in pred.keys():
		if host.has(k):
			both += 1
	var extra := host.size() - both
	_log.append("predicted=%d host=%d matched=%d extra=%d" % [pred.size(), host.size(), both, extra])
	if pred.size() < 15:
		_bad.append("too few predicted hits to judge (%d)" % pred.size())
	elif float(both) < 0.85 * pred.size():
		_bad.append("host confirmed only %d of %d predicted hits" % [both, pred.size()])
	if pred.size() > 0 and float(extra) > 0.30 * pred.size():
		_bad.append("host added %d hits the shooter never saw (of %d)" % [extra, pred.size()])
	# Same damage numbers: every hit an AK hit, and the victim was told the total.
	var total := 0.0
	var wrong := 0
	for line in _lines("honest_host.log", "HOSTHIT "):
		var amt := float(line.split(" -> ")[1].split(" ")[1]) if line.contains(" -> ") else 0.0
		total += amt
		if line.begins_with("HOSTHIT «SHT»") and absf(amt - AK_DMG) > 0.01:
			wrong += 1
	if wrong > 0:
		_bad.append("%d hits not worth exactly %.0f" % [wrong, AK_DMG])
	var vd := _duel_line("honest_victim.log")
	var told := _kv(vd, "damage_taken")
	_log.append("host_damage=%.0f victim_told=%.0f" % [total, told])
	if vd == "" or absf(told - total) > 0.5:
		_bad.append("victim was told %.0f damage, host applied %.0f" % [told, total])
	var st := _stats("honest_host.log")
	_log.append("rewind_avg=%.0fms capped=%d" % [_kv(st, "rewind_ms") / maxf(1.0, _kv(st, "rewind_shots")), int(_kv(st, "rewind_capped"))])
	var trust := _lines("honest_host.log", "TRUST ")
	if not trust.is_empty():
		_bad.append("honest clients tripped the host: %s" % str(trust.slice(0, 3)))
	for f in ["honest_host.log", "honest_victim.log", "honest_shooter.log"]:
		var e := _errors(f, false)
		if e > 0:
			_bad.append("%d error lines in %s" % [e, f])


# ── cheats ──

const TAGS := {"dmg": "DMG", "rate": "RATE", "ammo": "AMMO", "origin": "ORIG", "silentaim": "SIL", "fuel": "FUEL"}


func _cheats() -> void:
	# A: an honest victim (tagged VIC, kept alive with medikits) under fire from
	# six modified shooters at once. (Each server stays well inside the 5 min
	# round, so its counters cover the whole run.)
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
		pids.append(_game("--smoke-join --port %d --smoke-secs=40 --smoke-role=shooter --smoke-target=VIC --smoke-start-ms=500 --smoke-cheat=%s --clan=%s" % [
			port, kind, TAGS[kind]], 120, "cheat_%s.log" % kind))
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
		if absf(float(line.split(" -> ")[1].split(" ")[2]) - AK_DMG) > 0.01:
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
