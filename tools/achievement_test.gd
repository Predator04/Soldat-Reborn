extends SceneTree
## Achievements (gate stage F): kills / headshots / multi-kills / streaks /
## captures / wins unlock the right achievements once, with a signal; the
## player's real stats are restored afterwards.
##   godot --headless -s tools/achievement_test.gd

var _n := 0


func _process(_d: float) -> bool:
	_n += 1
	if _n < 3:
		return false
	var S = root.get_node("Stats")
	var st = root.get_node("Settings")
	var keep := {"kills": S.kills, "deaths": S.deaths, "suicides": S.suicides, "wins": S.wins, "losses": S.losses,
		"matches_played": S.matches_played, "kbw": S.kills_by_weapon.duplicate(true), "c": S.counters.duplicate(true),
		"u": S.unlocked.duplicate(true), "gm": st.game_mode, "surv": st.survival}
	S.kills = 0; S.deaths = 0; S.wins = 0; S.matches_played = 0
	S.kills_by_weapon = {}; S.counters = {}; S.unlocked = {}
	var got: Array = []
	S.achievement_unlocked.connect(func(id, _t, _d2): got.append(id))
	var bad: Array = []
	S.record_kill("Barrett (headshot)")
	S.record_kill("Grenade")
	if not ("first_blood" in got and "double" in got):
		bad.append("first kill / double missing %s" % str(got))
	S.record_kill("Knife"); S.record_kill("Knife")
	if not ("massacre" in got):
		bad.append("4 quick kills no massacre")
	S.record_death()
	for i in 10:
		S.record_kill("Buggy")
	if not ("roadkill" in got and "unstoppable" in got):
		bad.append("roadkill/unstoppable missing")
	if int(S.counters.get("headshots", 0)) != 1 or int(S.counters.get("melee", 0)) != 2:
		bad.append("counters %s" % str(S.counters))
	S.record_event("capture")
	st.survival = true
	for m in [0, 1, 2, 3, 4]:
		st.game_mode = m
		S.record_match_end(true)
	if not ("winner" in got and "all_rounder" in got and "survivor" in got):
		bad.append("win achievements missing")
	var n_before := got.size()
	S.record_kill("Barrett")
	for id in got.slice(n_before):
		if got.count(id) > 1:
			bad.append("unlocked twice: " + str(id))
	print("ACH-TEST %s %s | unlocked=%d %s" % ["ok" if bad.is_empty() else "FAIL", str(bad), S.unlocked.size(), str(got)])
	S.kills = keep["kills"]; S.deaths = keep["deaths"]; S.suicides = keep["suicides"]; S.wins = keep["wins"]
	S.losses = keep["losses"]; S.matches_played = keep["matches_played"]; S.kills_by_weapon = keep["kbw"]
	S.counters = keep["c"]; S.unlocked = keep["u"]; st.game_mode = keep["gm"]; st.survival = keep["surv"]
	S.save()
	quit()
	return true
