extends SceneTree
## Unlocks in play (gate stage F): a level-1 player one kill short of level 2
## gets the kill, the "UNLOCKED: Weapon skin: Desert" toast fires once (after
## the RANK UP), the item becomes pickable in CUSTOMIZE, and after equipping it
## the next respawn wears it.
##   godot --headless -s tools/unlock_test.gd

var _n := 0
var _st := 0
var _t := 0
var _saved := {}
var _bad: Array = []
var _log: Array = []


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	var stats = root.get_node_or_null("Stats")
	if st == null or stats == null:
		return false
	if _st == 0:
		_saved = {"xp": stats.counters.get("xp", 0), "unl": stats.unlocked.duplicate(), "wskin": st.cos_wskin,
			"bots": st.bot_count, "mode": st.game_mode, "map": st.map_index}
		stats.counters["xp"] = 95       # level 1, 5 XP short of level 2
		stats.unlocked = {"first_blood": 1}
		st.cos_wskin = ""
		st.bot_count = 1
		st.game_mode = 0
		st.map_index = 19
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_st = 1
		return false
	var m = current_scene
	if m == null or m.get("hud") == null or m.hud == null or m.get("player") == null:
		return false
	match _st:
		1:
			if _n < 40 or not is_instance_valid(m.player):
				return false
			var C = load("res://scripts/customization.gd")
			if C.is_unlocked("wskin", "desert"):
				return _end(false, "desert skin unlocked at level 1")
			stats._add_xp(10)                 # the kill
			_t = _n
			_st = 2
		2:
			if _n - _t < 400:
				return false
			var C = load("res://scripts/customization.gd")
			_log.append("toasts=%d" % m.hud.unlock_toasts)
			if not C.is_unlocked("wskin", "desert"):
				_bad.append("desert not unlocked at level 2")
			if m.hud.unlock_toasts != 1:
				_bad.append("unlock toasts %d (want 1)" % m.hud.unlock_toasts)
			# Equip it the way the CUSTOMIZE screen does, then respawn.
			load("res://scripts/customize_panel.gd").cos_set("wskin", "desert")
			var live: String = str(m.player.cosmetics.get("wskin", ""))
			_log.append("live=%s" % live)
			if live != "desert":
				_bad.append("equipping mid-match didn't apply live")
			m.player.ceasefire_t = 0.0
			m.player.take_damage(999.0, "", "", -1)
			_t = _n
			_st = 3
		3:
			if is_instance_valid(m.player) and not bool(m.player.dead) and _n - _t > 30:
				var w: String = str(m.player.cosmetics.get("wskin", ""))
				_log.append("respawned wskin=%s" % w)
				if w != "desert":
					_bad.append("respawn lost the skin")
				# Tracer + jet colors reach the bullets / jet particles.
				m.player.cosmetics["tracer"] = "gold"
				m.player.cosmetics["jet"] = "blue"
				m.player.call("_switch_weapon", 2)
				m.player.set("fire_cd", 0.0)
				Input.action_press("jet")
				_t = _n
				_st = 4
				return false
			if _n - _t > 900:
				return _end(false, "no respawn")
		4:
			if _n - _t == 40:
				Input.action_press("fire")
			if _n - _t < 52:
				return false
			Input.action_release("fire")
			Input.action_release("jet")
			var tinted := 0
			for b in get_nodes_in_group("bullet"):
				if str(b.get("killer_name")) == str(m.player.display_name) and (b.get("tint") as Color).is_equal_approx(load("res://scripts/customization.gd").TRACERS["gold"]):
					tinted += 1
			var jc: Color = m.player.jet_particles.color
			_log.append("gold_tracers=%d jet=%s" % [tinted, jc.to_html(false)])
			if tinted == 0:
				_bad.append("no gold tracer on own bullets")
			if not (jc.b > jc.r):
				_bad.append("jet particles not blue")
			return _end(_bad.is_empty(), " ".join(_log))
	return false


func _end(ok: bool, msg: String) -> bool:
	var st = root.get_node("Settings")
	var stats = root.get_node("Stats")
	stats.counters["xp"] = _saved.xp
	stats.unlocked = _saved.unl
	st.cos_wskin = _saved.wskin
	st.bot_count = _saved.bots; st.game_mode = _saved.mode; st.map_index = _saved.map
	st.save()
	print("UNLOCK-TEST %s %s %s" % ["ok" if ok else "FAIL", str(_bad), msg])
	quit(0 if ok else 1)
	return true
