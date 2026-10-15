extends SceneTree
## #263 verification: uneven teams get rebalanced by moving BOTS at round
## reset; a human-heavy imbalance is left alone.
##   godot --headless -s tools/balance_test.gd

var _t := 0.0
var _phase := 0
var _bad: Array = []
var _log: Array = []
var _main = null
const TEAM_BLUE := 1
const TEAM_RED := 2


func _team_counts() -> Dictionary:
	var counts := {TEAM_BLUE: 0, TEAM_RED: 0, "bots_blue": 0, "bots_red": 0}
	for sld in get_nodes_in_group("soldier"):
		if not is_instance_valid(sld):
			continue
		var t: int = int(sld.get("team"))
		if counts.has(t):
			counts[t] += 1
			if sld.get("bot_id") != null:
				var key := "bots_blue" if t == TEAM_BLUE else "bots_red"
				counts[key] += 1
	return counts


func _process(delta: float) -> bool:
	_t += delta
	if _t > 50.0:
		return _end("timeout phase=%d" % _phase)
	match _phase:
		0:
			var MapIO = load("res://scripts/map_io.gd")
			# Team mode (TDM) with a 2-bot roster.
			var m := {"name": "qa_bal", "platforms": [], "player_spawn": Vector2(400, 1780),
				"bot_spawns": [Vector2(700, 1780), Vector2(900, 1780)]}
			var st := get_root().get_node("Settings")
			st.set("custom_map_path", MapIO.save_to_file("qa_bal", m))
			st.set("game_mode", 1)   # Teammatch
			st.set("bot_count", 2)
			st.set("vehicles", false)
			get_root().get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_phase = 1
			return false
		1:
			_main = current_scene
			if _main == null or _main.get("MAPS") == null:
				return false
			if _main.get("player") == null:
				return false
			_t = 0.0
			_phase = 2
			return false
		2:
			if _t < 2.0:
				return false
			var c0 := _team_counts()
			_log.append("start b=%d r=%d (bots b%d/r%d)" % [c0[TEAM_BLUE], c0[TEAM_RED], c0["bots_blue"], c0["bots_red"]])
			# Stack the living roster: move every live bot + the player to BLUE.
			for sld in get_nodes_in_group("soldier"):
				if not is_instance_valid(sld):
					continue
				sld.set("team", TEAM_BLUE)
				sld.set("color", Color(0.35, 0.55, 1.0))
			var c1 := _team_counts()
			_log.append("stacked b=%d r=%d" % [c1[TEAM_BLUE], c1[TEAM_RED]])
			# Fire the round reset exactly as the game does.
			_main.call("_reset_round")
			var c2 := _team_counts()
			_log.append("after reset b=%d r=%d" % [c2[TEAM_BLUE], c2[TEAM_RED]])
			var diff: int = absi(c2[TEAM_BLUE] - c2[TEAM_RED])
			# Player + 2 bots stacked blue = 3v0; balancing can only move bots,
			# so best case 2v1 → diff <= 1 is the pass bar.
			if diff > 1:
				_bad.append("teams not balanced after reset (b=%d r=%d)" % [c2[TEAM_BLUE], c2[TEAM_RED]])
			# The HUMAN must still be on their chosen team.
			if int(_main.get("player").get("team")) != TEAM_BLUE:
				_bad.append("a human was moved off their team")
			return _end("")
	return false


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	print("BALANCE-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
	quit()
	return true
