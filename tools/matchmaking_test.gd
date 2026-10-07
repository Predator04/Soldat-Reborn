extends SceneTree
## Skill matchmaking (#33, gate C): against a local master server, rated
## players get a skill (avg XP per match, 3+ matches), /list shows each
## server's average, and Quick Play scores the server at your level ahead of
## one far from it (same ping, both with people). Unrated players match
## anywhere.  godot --headless -s tools/matchmaking_test.gd -- --master=URL

var _st := 0
var _n := 0
var _t := 0
var _url := ""
var _saved_url := ""
var _saved_pid := ""
var _m: Node
var _http: HTTPRequest
var _queue: Array = []
var _busy := false
var _bad: Array = []
var _log: Array = []
const PID := "fedcba9876543210fedcba9876543210"


func _post(path: String, body: Dictionary) -> void:
	_queue.append([path, JSON.stringify(body)])


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	var it: Array = _queue.pop_front()
	_busy = true
	_http.request(_url + str(it[0]), ["Content-Type: application/json"], HTTPClient.METHOD_POST, str(it[1]))


func _line(id: String, name: String, k: int, c: int, win: bool) -> Dictionary:
	return {"id": id, "name": name, "k": k, "d": 3, "c": c, "win": win, "played": true}


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	match _st:
		0:
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--master="):
					_url = a.substr(9)
			_saved_url = st.master_url
			_saved_pid = st.profile_id
			st.profile_id = PID
			st.master_url = _url
			# Pure scoring rules first.
			var M = load("res://scripts/menu.gd")
			if M.skill_penalty(-1, 300) != 0.0 or M.skill_penalty(300, null) != 0.0:
				_bad.append("unrated should match anywhere")
			if not (M.skill_penalty(300, 310) < M.skill_penalty(300, 600)):
				_bad.append("closer skill not preferred")
			if M.skill_penalty(300, 99999) > 180.0:
				_bad.append("penalty not capped")
			_http = HTTPRequest.new()
			root.add_child(_http)
			_http.request_completed.connect(func(_r, _c, _h, _b) -> void: _busy = false)
			var me: String = st.profile_hash()
			var pro := "a".repeat(64)
			var rook := "b".repeat(64)
			for i in 4:
				_post("/report", {"players": [_line(me, "MM Me", 18, 1, true), _line(pro, "MM Pro", 20, 1, true), _line(rook, "MM Rook", 1, 0, false)]})
			_post("/register", {"name": "MM Pro Server", "port": 7911, "map": "A", "mode": "CTF", "players": 1, "max": 8, "version": str(ProjectSettings.get_setting("application/config/version")), "names": ["MM Pro"]})
			_post("/register", {"name": "MM Rookie Server", "port": 7912, "map": "A", "mode": "CTF", "players": 1, "max": 8, "version": str(ProjectSettings.get_setting("application/config/version")), "names": ["MM Rook"]})
			_st = 1
		1:
			_pump()
			if _busy or not _queue.is_empty():
				return false
			change_scene_to_file("res://scenes/menu.tscn")
			_st = 2
			_t = _n
		2:
			_m = current_scene
			if _m == null or _m.get("_menu_root") == null or _n - _t < 10:
				return false
			_m._menu_root.visible = false
			_m._browse_root.visible = true
			_m._refresh_browse()
			_m._fetch_my_skill()
			_t = _n
			_st = 3
		3:
			var rows: Array = _m._master_rows
			if (_m.my_skill < 0 or rows.size() < 2) and _n - _t < 300:
				return false
			_log.append("my_skill=%d" % _m.my_skill)
			if _m.my_skill < 0:
				_bad.append("no skill fetched for me")
			var pro_s := INF
			var rook_s := INF
			for r in rows:
				_log.append("%s skill=%s score=%.0f" % [r.get("name"), str(r.get("skill")), _m.qp_score(r)])
				if str(r.get("name")) == "MM Pro Server":
					pro_s = _m.qp_score(r)
				elif str(r.get("name")) == "MM Rookie Server":
					rook_s = _m.qp_score(r)
			if pro_s == INF or rook_s == INF:
				_bad.append("servers not listed (%d rows)" % rows.size())
			elif not (pro_s < rook_s):
				_bad.append("quick play prefers the rookie server (%.0f vs %.0f)" % [pro_s, rook_s])
			return _end()
	return false


func _end() -> bool:
	var st = root.get_node("Settings")
	st.master_url = _saved_url
	st.profile_id = _saved_pid
	var ok := _bad.is_empty()
	print("MATCHMAKING-TEST %s %s %s" % ["ok" if ok else "FAIL", str(_bad), " | ".join(_log)])
	quit(0 if ok else 1)
	return true
