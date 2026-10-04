extends Node
## Ranked results reporter (dedicated host only). Sends each player's kills,
## deaths, caps and wins to the master server's /report at every round end,
## and a partial line when someone leaves. Players are identified by the hash
## of their profile id (Net.peer_profiles); bots never count.

var main: Node
var _base: Dictionary = {}   # peer id -> {"k","d","c"} already reported
var _queue: Array = []
var _http: HTTPRequest
var _busy := false
var sent_reports := 0        # for tests


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		_busy = false
		if code == 200:
			sent_reports += 1
		else:
			print("RANKED report failed: http %d" % code)
		_pump())


func _stats_for(pid: int) -> Dictionary:
	var nm := str(main._peer_names.get(pid, ""))
	var st: Dictionary = main.player_stats.get(nm, {})
	return {"k": maxi(0, int(st.get("k", 0))), "d": int(st.get("d", 0)), "c": int(st.get("c", 0))}


# Start counting from what the player already has (a rejoin keeps its stats
# under the same name; those were reported when they left).
func player_joined(pid: int) -> void:
	_base[pid] = _stats_for(pid)


func _line(pid: int, played: bool, win: bool) -> Dictionary:
	var cur := _stats_for(pid)
	var b: Dictionary = _base.get(pid, {"k": 0, "d": 0, "c": 0})
	_base[pid] = cur
	return {"id": str(Net.peer_profiles.get(pid, "")), "name": str(main._peer_names.get(pid, "")),
		"k": maxi(0, cur.k - b.k), "d": maxi(0, cur.d - b.d), "c": maxi(0, cur.c - b.c),
		"played": played, "win": win}


func round_end(winner: int) -> void:
	var lines: Array = []
	for pid in main._connected_peers.keys():
		if not Net.peer_profiles.has(pid):
			continue
		var t: int = int(main._peer_team_by_id.get(pid, pid))
		lines.append(_line(pid, true, winner >= 0 and t == winner))
	_send(lines)


func player_left(pid: int) -> void:
	if Net.peer_profiles.has(pid):
		var ln := _line(pid, false, false)
		if ln.k + ln.d + ln.c > 0:
			_send([ln])
	_base.erase(pid)
	Net.peer_profiles.erase(pid)


func _send(lines: Array) -> void:
	if lines.is_empty() or Net.stats_url == "":
		return
	_queue.append(JSON.stringify({"players": lines}))
	print("RANKED queued %d line(s): %s" % [lines.size(), JSON.stringify(lines).left(300)])
	_pump()


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var headers := PackedStringArray(["Content-Type: application/json"])
	var key := OS.get_environment("SOLDAT_STATS_KEY")
	if key != "":
		headers.append("X-Soldat-Key: " + key)
	var err := _http.request(Net.stats_url.trim_suffix("/") + "/report", headers, HTTPClient.METHOD_POST, str(_queue.pop_front()))
	if err != OK:
		_busy = false
