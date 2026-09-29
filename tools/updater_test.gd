extends SceneTree
## Auto-updater (gate stage F). Needs a local server (the gate starts one):
##   python3 -m http.server <port> --directory <dir with latest.json + SoldatReborn.exe>
##   godot --headless -s tools/updater_test.gd -- --update-url=http://127.0.0.1:<port>/latest.json
## Checks version compare, the release check, the download + size check, and
## the Windows swap script.

var _u: Node
var _t := 0.0
var _t0 := 0
var _st := 0
var _bad: Array = []
var _log: Array = []


func _initialize() -> void:
	var U = load("res://scripts/updater.gd")
	for c in [["1.21.2", "1.21.1", true], ["v1.22.0", "1.21.9", true], ["1.21.1", "1.21.1", false], ["1.9.0", "1.21.0", false], ["2.0", "1.99.99", true]]:
		if U.is_newer(c[0], c[1]) != c[2]:
			_bad.append("is_newer%s" % str(c))
	var sc: String = U.swap_script("C:/Games/SR/SoldatReborn.exe", "C:/Games/SR/SoldatReborn.update.exe", 4242)
	for need in ["PID eq 4242", "move /y \"C:\\Games\\SR\\SoldatReborn.update.exe\" \"C:\\Games\\SR\\SoldatReborn.exe\"", "start \"\" \"C:\\Games\\SR\\SoldatReborn.exe\"", "SoldatReborn.previous.exe"]:
		if not sc.contains(need):
			_bad.append("swap script lacks %s" % need)
	_u = U.new()
	root.add_child(_u)
	# The gate runs with --fixed-fps (fast frames), and HTTPRequest's timeout
	# counts frame time: turn it off and time out on the wall clock instead.
	_t0 = Time.get_ticks_msec()


func _process(d: float) -> bool:
	_t = (Time.get_ticks_msec() - _t0) / 1000.0
	if _t > 30.0:
		return _end("timeout st=%d state=%s err=%s" % [_st, _u.state, _u.error])
	match _st:
		0:
			_u._http.timeout = 0
			_u.check()
			_st = 1
		1:
			if _u.state == "available" or _u.state == "none" or _u.state == "failed":
				_log.append("check=%s latest=%s err=%s" % [_u.state, _u.latest, _u.error])
				if _u.state != "available":
					return _end("expected an update")
				_u.download_to(OS.get_user_data_dir().path_join("updater_test.bin"))
				_st = 2
		2:
			if _u.state == "ready" or _u.state == "failed":
				_log.append("download=%s %s" % [_u.state, _u.error])
				if _u.state != "ready":
					return _end("download failed")
				return _end("")
	return false


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	DirAccess.remove_absolute(OS.get_user_data_dir().path_join("updater_test.bin"))
	print("UPDATER-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
	quit()
	return true
