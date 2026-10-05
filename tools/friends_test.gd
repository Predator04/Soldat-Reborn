extends SceneTree
## Friends screen (gate stage F): recent players listed (online first, then
## starred, then newest), the online one shows where and JOIN asks the menu to
## join that server; starring persists; the list keeps 40 + favourites.
##   godot --headless -s tools/friends_test.gd

var _n := 0


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null or _n < 3:
		return false
	var saved: Array = st.recent_players.duplicate(true)
	var bad: Array = []
	var now := int(Time.get_unix_time_from_system())
	st.recent_players = [{"name": "Old Pal", "last": now - 86400 * 3, "fav": false},
		{"name": "«XYZ» Ace", "last": now - 600, "fav": false}, {"name": "Starred", "last": now - 86400 * 9, "fav": true}]
	var P = load("res://scripts/friends_panel.gd").new()
	root.add_child(P)
	P._servers = [{"name": "Soldat Reborn Official", "map": "Ascent", "ip": "1.2.3.4", "port": 7777, "names": ["«XYZ» Ace", "Someone"]}]
	P._render()
	if P.rows_shown != 3: bad.append("rows %d" % P.rows_shown)
	if P.online_shown != 1: bad.append("online %d" % P.online_shown)
	var first_lbl := ""
	for l in _labels(P._list.get_child(0)):
		first_lbl += l.text
	if not first_lbl.contains("«XYZ» Ace") or not first_lbl.contains("Soldat Reborn Official"):
		bad.append("online friend not first: %s" % first_lbl)
	var second := ""
	for l in _labels(P._list.get_child(1)):
		second += l.text
	if not second.contains("Starred"): bad.append("starred not second: %s" % second)
	var got := []
	P.join_requested.connect(func(ip, port): got.append("%s:%d" % [ip, port]))
	for b in _buttons(P._list.get_child(0)):
		if b.text == "JOIN":
			b.pressed.emit()
	if got != ["1.2.3.4:7777"]: bad.append("join %s" % str(got))
	# Remember: 50 strangers + 1 favourite -> 40 strangers kept, favourite kept.
	st.recent_players = [{"name": "Fav", "last": 1, "fav": true}]
	var names: Array = []
	for i in 50:
		names.append("P%d" % i)
	load("res://scripts/main.gd").remember_players(names, now)
	var favs: int = st.recent_players.filter(func(e): return e.fav).size()
	if st.recent_players.size() != 41 or favs != 1: bad.append("cap: %d entries, %d fav" % [st.recent_players.size(), favs])
	st.recent_players = saved
	print("FRIENDS-TEST %s %s" % ["ok" if bad.is_empty() else "FAIL", str(bad)])
	quit(0 if bad.is_empty() else 1)
	return true


func _labels(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Label: out.append(c)
		out.append_array(_labels(c))
	return out


func _buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button: out.append(c)
		out.append_array(_buttons(c))
	return out
