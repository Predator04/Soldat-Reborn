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
var _tries := 0              # #250: consecutive failures of the queue head
var sent_reports := 0        # for tests


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		_busy = false
		if code == 200:
			sent_reports += 1
			_queue.pop_front()
			_tries = 0
			_pump()
			return
		# #250: the line used to be popped before the request and dropped on
		# any failure — flaky networks silently lost ranked results. Retry a
		# few times, then give up on that line.
		_tries += 1
		if _tries >= 3 and not _queue.is_empty():
			print("RANKED report dropped after %d tries: http %d" % [_tries, code])
			_queue.pop_front()
			_tries = 0
		_retry_later())


## Re-attempt the queue head shortly (used by the failure path above).
func _retry_later() -> void:
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_inside_tree():
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
	# #250: send the queue HEAD without popping — only a 200 pops it.
	var err := _http.request(Net.stats_url.trim_suffix("/") + "/report", headers, HTTPClient.METHOD_POST, str(_queue[0]))
	if err != OK:
		_busy = false
		_retry_later()
