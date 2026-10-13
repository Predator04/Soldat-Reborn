extends SceneTree
## #256/#257 verification: host weapon bans remove a weapon from the whole
## match (menus, spawns, bots, pickups), and the classic host chat commands
## (addbot/kick/bots/say/ff) work from Main.
##   godot --headless -s tools/community_test.gd

var _t := 0.0
var _phase := 0
var _bad: Array = []
var _log: Array = []
var _main = null
var _player = null


var _mc = null


func _process(delta: float) -> bool:
	if _mc == null:
		_mc = get_root().get_node_or_null("MatchConfig")
		if _mc == null:
			return false
	_t += delta
	if _t > 40.0:
		return _end("timeout phase=%d" % _phase)
	match _phase:
		0:
			var MapIO = load("res://scripts/map_io.gd")
			var m := {"name": "qa_bans", "platforms": [], "player_spawn": Vector2(400, 1780),
				"bot_spawns": [Vector2(700, 1780), Vector2(900, 1780), Vector2(1100, 1780)],
				# One banned + one allowed map pickup.
				"weapon_pickups": [{"pos": Vector2(500, 1780), "weapon": "Barrett"},
					{"pos": Vector2(560, 1780), "weapon": "Spas-12"}]}
			var st := get_root().get_node("Settings")
			st.set("custom_map_path", MapIO.save_to_file("qa_bans", m))
			st.set("game_mode", 0)
			st.set("bot_count", 3)
			st.set("vehicles", false)
			# #256: ban Barrett (a map pickup + the top sniper) and the Knife.
			st.set("weapon_bans", ["Barrett", "Knife"])
			st.set("spawn_primary", 7)   # Barrett index — must fall back
			st.set("spawn_secondary", 1) # Knife — must fall back
			get_root().get_node("Net").set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_phase = 1
			return false
		1:
			_main = current_scene
			if _main == null or _main.get("MAPS") == null:
				return false
			_player = _main.get("player")
			if _player == null or not is_instance_valid(_player):
				return false
			# Bans active everywhere they matter:
			var pi: int = int(_player.get("weapon_index"))
			var si: int = int(_player.get("secondary_index"))
			var pname := str((_player.get("weapons") as Array)[pi]["name"])
			var sname := str((_player.get("secondary") as Array)[si]["name"])
			if _mc.weapon_banned(pname):
				_bad.append("spawn primary is banned: %s" % pname)
			if _mc.weapon_banned(sname):
				_bad.append("spawn secondary is banned: %s" % sname)
			_log.append("spawn=%s/%s" % [pname, sname])
			# Map pickups: banned one absent, allowed one present.
			var names: Array = []
			for wp in get_nodes_in_group("weapon_pickup"):
				names.append(str(wp.get("weapon_name")))
			if names.has("Barrett"):
				_bad.append("banned map pickup spawned")
			if not names.has("Spas-12"):
				_bad.append("allowed map pickup missing")
			_log.append("pickups=%s" % str(names))
			# Bots never hold banned loadouts.
			for b in _main._live_bots():
				var ln := str(b.get("loadout"))
				if _mc.weapon_banned(ln):
					_bad.append("bot holds banned loadout %s" % ln)
			_log.append("bots=%d" % _main._live_bots().size())
			_phase = 2
			_t = 0.0
			return false
		2:
			# Pickup + switch guards.
			if _player.call("try_pickup_weapon", "Barrett", -1):
				_bad.append("try_pickup_weapon accepted a banned weapon")
			var bidx := 7  # Barrett
			_player.set("weapon_index", 2)
			_player.call("_switch_weapon", bidx)
			if int(_player.get("weapon_index")) == bidx:
				_bad.append("_switch_weapon switched into a banned weapon")
			_log.append("guards ok")
			_phase = 3
			_t = 0.0
			return false
		3:
			# Host commands (#257): addbot, bots, kick, say, ff.
			var n0: int = _main._live_bots().size()
			_main.host_addbot(3, "Scrappy")
			var n1: int = _main._live_bots().size()
			if n1 != n0 + 1:
				_bad.append("host_addbot: %d -> %d" % [n0, n1])
			var named := false
			for b in _main._live_bots():
				if str(b.get("display_name")) == "Scrappy":
					named = true
			if not named:
				_bad.append("host_addbot name not applied")
			if not _main.host_kick("scrappy"):
				_bad.append("host_kick(prefix) missed Scrappy")
			if _main.host_kick("no-such-bot"):
				_bad.append("host_kick matched a nonexistent name")
			_main.host_set_bots(2)
			_main.host_say("hello from the host")
			var ff0: bool = _mc.host_friendly_fire
			_main.host_toggle_ff()
			if _mc.host_friendly_fire == ff0:
				_bad.append("host_toggle_ff did not flip")
			_main.host_toggle_ff()
			_log.append("bots %d->%d" % [n0, n1])
			_phase = 4
			_t = 0.0
			return false
		4:
			# Counts settle a frame later (despawn queue_frees flush at idle).
			if _t < 0.6:
				return false
			var n2: int = _main._live_bots().size()
			if n2 != 2:
				_bad.append("after kick+set_bots(2) -> %d bots (want 2)" % n2)
			_log.append("settled=%d" % n2)
			return _end("")
	return false


func _end(fail: String) -> bool:
	if fail != "":
		_bad.append(fail)
	get_root().get_node("Settings").set("weapon_bans", [])
	print("COMMUNITY-TEST %s %s | %s" % ["ok" if _bad.is_empty() else "FAIL", str(_bad), " ".join(_log)])
	quit()
	return true
