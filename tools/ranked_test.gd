extends SceneTree
## Ranked (gate stage C, with a local master server): round-end and leave
## reports reach /report, the leaderboard and /profile add them up, and a
## player's own profile hash finds them.
##   godot --headless -s tools/ranked_test.gd -- --master=http://127.0.0.1:PORT

var _st := 0
var _n := 0
var _r: Node
var _fm: Node
var _url := ""
var _http: HTTPRequest
var _got := {}
var _ida := "0123456789abcdef0123456789abcdef"
var _idb := "fedcba9876543210fedcba9876543210"


func _process(_d: float) -> bool:
	_n += 1
	var net = root.get_node_or_null("Net")
	if net == null:
		return false
	match _st:
		0:
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--master="):
					_url = a.substr(9)
			net.stats_url = _url
			_fm = load("res://tools/ranked_fake_main.gd").new()
			root.add_child(_fm)
			_r = load("res://scripts/ranked.gd").new()
			_r.main = _fm
			root.add_child(_r)
			_http = HTTPRequest.new()
			root.add_child(_http)
			# Ace (blue, 2) and Bee (red, 3) join; Bee already had 5 kills
			# from an earlier visit under that name (not re-counted).
			_fm._peer_names = {2: "Ace", 3: "Bee"}
			_fm._connected_peers = {2: true, 3: true}
			_fm._peer_team_by_id = {2: 1, 3: 2}
			_fm.player_stats = {"Bee": {"k": 5, "d": 1, "c": 0}}
			net.peer_profiles = {2: _ida.sha256_text(), 3: _idb.sha256_text()}
			_r.player_joined(2)
			_r.player_joined(3)
			_fm.player_stats = {"Ace": {"k": 7, "d": 2, "c": 1}, "Bee": {"k": 8, "d": 4, "c": 0}}
			_r.round_end(1)          # blue wins
			_fm.player_stats["Ace"] = {"k": 10, "d": 3, "c": 1}
			_r.player_left(2)        # leaves mid-round: +3 kills, +1 death
			_st = 1
		1:
			if _r.sent_reports >= 2:
				_http.request_completed.connect(func(_a, _c, _h, b): _got["board"] = JSON.parse_string(b.get_string_from_utf8()); _st = 3)
				_http.request(_url + "/leaderboard")
				_st = 2
			elif _n > 600:
				return _end(false, "reports not sent (%d)" % _r.sent_reports)
		3:
			var h2 := HTTPRequest.new()
			root.add_child(h2)
			h2.request_completed.connect(func(_a, _c, _h, b): _got["me"] = JSON.parse_string(b.get_string_from_utf8()); _st = 5)
			h2.request(_url + "/profile?id=" + _ida.sha256_text())
			_st = 4
		5:
			var ps: Array = _got.board.get("players", [])
			var ace: Dictionary = ps[0] if ps.size() > 0 else {}
			var bee: Dictionary = ps[1] if ps.size() > 1 else {}
			var bad: Array = []
			if str(ace.get("name")) != "Ace" or int(ace.k) != 10 or int(ace.d) != 3 or int(ace.c) != 1 or int(ace.w) != 1 or int(ace.m) != 1:
				bad.append("ace %s" % str(ace))
			if str(bee.get("name")) != "Bee" or int(bee.k) != 3 or int(bee.d) != 3 or int(bee.w) != 0 or int(bee.m) != 1:
				bad.append("bee %s" % str(bee))
			if not bool(_got.me.get("found")) or int(_got.me.get("rank")) != 1:
				bad.append("profile %s" % str(_got.me))
			return _end(bad.is_empty(), "ace k%d d%d c%d w%d xp%d | bee k%d xp%d | me rank %s %s" % [int(ace.get("k", -1)), int(ace.get("d", -1)), int(ace.get("c", -1)), int(ace.get("w", -1)), int(ace.get("xp", -1)), int(bee.get("k", -1)), int(bee.get("xp", -1)), str(_got.me.get("rank")), str(bad)])
	if _n > 900:
		return _end(false, "timeout at step %d" % _st)
	return false


func _end(ok: bool, msg: String) -> bool:
	print("RANKED-TEST %s %s" % ["ok" if ok else "FAIL", msg])
	quit(0 if ok else 1)
	return true
