extends SceneTree
## Scripted single-player feature exercise (menu path, offline peer):
## gestures + /kill, every weapon slot, both grenade types, weapon throw,
## extreme gameplay mods, live bot-count changes, a vote, the GIF recorder.
## Any script / engine error in the log is a failure (the gate greps it).
##   godot --headless --fixed-fps 60 -s tools/feature_test.gd -- [--map=19] [--mode=1]

var _map := 19
var _mode := 1
var _t := 0.0
var _loaded := false
var _step := 0
var _log: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): _map = int(a.substr(6))
		elif a.begins_with("--mode="): _mode = int(a.substr(7))


func _tap(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_press(action)
		get_root().get_tree().create_timer(0.1).timeout.connect(func() -> void: Input.action_release(action))


func _process(delta: float) -> bool:
	var st := root.get_node_or_null("Settings")
	if st == null:
		return false
	if not _loaded:
		st.set("custom_map_path", "")
		st.set("map_index", _map)
		st.set("game_mode", _mode)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_loaded = true
		return false
	var m := current_scene
	if m == null or m.get("MAPS") == null:
		return false
	_t += delta
	var p = m.get("player")
	var at := [1.0, 3.0, 5.0, 8.0, 12.0, 16.0, 20.0, 24.0, 27.0, 30.0, 34.0, 38.0]
	if _step < at.size() and _t >= at[_step]:
		match _step:
			0:
				for c in ["victory", "smoke", "takeoff", "tabac"]:
					if p != null and is_instance_valid(p):
						p.apply_gesture("/" + c)
				_log.append("gestures")
			1:
				for i in range(1, 11):
					_tap("weapon_%d" % i)
				_tap("secondary_swap")
				_log.append("weapon slots")
			2:
				_tap("grenade")
				_tap("grenade_toggle")
				_log.append("grenade + toggle")
			3:
				_tap("grenade")
				_tap("weapon_throw")
				_tap("reload")
				_log.append("cluster + throw + reload")
			4:
				st.set("mod_gravity", 2.0); st.set("mod_jet", 0.3); st.set("mod_damage", 3.0); st.set("mod_speed", 1.8)
				_log.append("mods high")
			5:
				st.set("mod_gravity", 0.4); st.set("mod_jet", 2.5); st.set("mod_damage", 0.3); st.set("mod_speed", 0.6)
				_log.append("mods low")
			6:
				for k in ["mod_gravity", "mod_jet", "mod_damage", "mod_speed"]:
					st.set(k, 1.0)
				st.set("bot_count", 2)
				m._reconcile_bots()
				_log.append("bots -> 2")
			7:
				st.set("bot_count", 10)
				m._reconcile_bots()
				_log.append("bots -> 10")
			8:
				if m.has_method("request_vote"):
					m.request_vote("votemap", "3")
				root.get_node("GifRecorder").toggle()
				_log.append("vote + gif start")
			9:
				root.get_node("GifRecorder").toggle()
				if p != null and is_instance_valid(p):
					p.apply_gesture("/kill")
				_log.append("gif stop + /kill")
			10:
				if p != null and is_instance_valid(p):
					p.apply_gesture("/mercy")
				_log.append("mercy")
			11:
				st.set("bot_count", -1)
				m._reconcile_bots()
				var bots := 0
				for s in get_nodes_in_group("soldier"):
					if is_instance_valid(s) and s.get("loadout") != null:
						bots += 1
				print("FEATURE-TEST done steps=%s bots_now=%d player=%s" % [", ".join(_log), bots, str(m.get("player") != null and is_instance_valid(m.get("player")))])
				quit()
				return true
		_step += 1
	return false
