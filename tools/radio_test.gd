extends SceneTree
## Team radio check (gate stage F).
##   godot --headless --fixed-fps 60 -s tools/radio_test.gd
## Presses V, 2, 3 (friendly flag carrier — down) as the player and checks the
## call lands in the chat feed with its voice line and without switching
## weapons; then waits for a bot to call out an enemy flag carrier.
## A call-out needs a flag grab, and in a random bot match the first grab can
## take 15 s or well over 100 s (an attacker dies, or drops the flag before the
## robbed team's 0.7 s call). So after NATURAL_S of game time without one the
## test stages the grab (#293): an enemy bot is put on our flag, and the
## same path (grab -> _bot_radio_efc -> net_radio) must produce the call.

var _t := 0.0
var _phase := 0
var _step := 0
var _w0 := -1
var _log: Array = []
var _t4 := 0.0
var _staged := false
const NATURAL_S := 60.0


func _key(kc: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = kc
		e.keycode = kc
		e.pressed = down
		Input.parse_input_event(e)


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		st.set("custom_map_path", ""); st.set("map_index", 0); st.set("game_mode", 2)
		st.set("bot_count", 6); st.set("bot_skill", 3); st.set("sfx_volume", 0.8)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null or m.get("hud") == null:
		return false
	_t += d
	var p = m.get("player")
	if _t > 150.0:
		print("RADIO-TEST FAIL timeout step=%d %s" % [_step, " ".join(_log)])
		quit()
		return true
	if _t < 2.0 or p == null or not is_instance_valid(p):
		return false
	match _step:
		0:
			_w0 = int(p.get("weapon_index"))
			_key(KEY_V)
			_step = 1
		1:
			if p.get("radio_open") == true:
				_log.append("menu")
				_key(KEY_2)
				_step = 2
		2:
			_key(KEY_3)
			_step = 3
		3:
			var feed = m.hud.get("chat_feed")
			var said := false
			for c in feed.get_children():
				if c is Label and str(c.text).contains("(RADIO)") and str(c.text).contains("Friendly flag carrier — down"):
					said = true
			var voiced: int = int(root.get_node("Sfx").play_counts.get("radio/ffcdown", 0))
			if said and voiced > 0:
				_log.append("player-call")
				if int(p.get("weapon_index")) != _w0 or p.get("radio_open") == true:
					print("RADIO-TEST FAIL weapon switched or menu stuck")
					quit()
					return true
				_step = 4
				_t4 = _t
				m.set("radio_count", 0)
			elif _t > 10.0:
				print("RADIO-TEST FAIL no player call said=%s voiced=%d" % [said, voiced])
				quit()
				return true
		4:
			if int(m.get("radio_count")) > 0:
				_log.append("bot-call@%.0fs%s" % [_t, " (staged grab)" if _staged else ""])
				print("RADIO-TEST ok %s" % " ".join(_log))
				quit()
				return true
			if _t - _t4 > NATURAL_S:
				_stage_grab(m, p)
	return false


## Puts a living bot onto an untaken enemy flag every frame until it grabs
## it, while a bot of the robbed team is alive to make the call.
func _stage_grab(m: Node, _p: Node) -> void:
	for f in m.flags:
		if f.has_meta("carrier") and f.get_meta("carrier") != null:
			continue
		var team := int(f.get_meta("team"))
		var robbed := false
		var thief: Node2D = null
		for b in get_nodes_in_group("soldier"):
			if not is_instance_valid(b) or b.get("bot_id") == null or bool(b.get("dead")):
				continue
			if int(b.get("team")) == team:
				robbed = true
			elif thief == null:
				thief = b
		if not robbed or thief == null:
			continue
		if not _staged:
			_log.append("no natural grab in %.0fs" % NATURAL_S)
		_staged = true
		thief.global_position = (f as Node2D).global_position
		(thief as CharacterBody2D).velocity = Vector2.ZERO
		return
