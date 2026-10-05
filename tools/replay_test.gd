extends SceneTree
## Replays (gate stage F): a bot match is recorded, saved when you leave, shows
## in REPLAYS, plays back on its map with every soldier where the recording
## had them, seeks, and EXIT puts your map / mode back.
##   godot --headless --fixed-fps 60 -s tools/replay_test.gd

var _n := 0
var _st := 0
var _t := 0
var _saved := []
var _bad: Array = []
var _log: Array = []
var _file := ""
var _shot := ""
var _rp: Node = null


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	var net = root.get_node_or_null("Net")
	if st == null or net == null:
		return false
	var R = load("res://scripts/replay_recorder.gd")
	match _st:
		0:
			_saved = [st.bot_count, st.game_mode, st.map_index, st.custom_map_path]
			for f in R.list_files():
				DirAccess.remove_absolute(f)
			st.bot_count = 4
			st.game_mode = 2
			st.map_index = 19
			st.custom_map_path = ""
			net.set_singleplayer()
			change_scene_to_file("res://scenes/main.tscn")
			_st = 1
			_t = _n
		1:
			# ~25 s of match time at a fixed 60 fps.
			if _n - _t < 1500:
				return false
			var rec = current_scene.recorder
			_log.append("frames=%d who=%d kills=%d" % [rec.frames.size(), rec.who.size(), rec.events.size()])
			change_scene_to_file("res://scenes/menu.tscn")   # leaving saves
			_st = 2
			_t = _n
		2:
			if _n - _t < 20:
				return false
			var files: Array = R.list_files()
			if files.is_empty():
				return _end(false, "no replay saved on leaving")
			_file = files[0]
			var d: Dictionary = R.load_file(_file)
			var frames: Array = d.get("frames", [])
			if frames.size() < 300 or (d.get("who", {}) as Dictionary).size() < 5:
				return _end(false, "thin replay: frames=%d who=%d" % [frames.size(), (d.get("who", {}) as Dictionary).size()])
			_log.append("file=%s %dKB" % [_file.get_file(), FileAccess.get_file_as_bytes(_file).size() / 1024])
			var m = current_scene
			m._open_replays()
			if m._replays_panel.rows_shown != 1:
				return _end(false, "REPLAYS lists %d" % m._replays_panel.rows_shown)
			st.map_index = 5            # what the player had picked
			if not m._replays_panel.watch_replay(_file):
				return _end(false, "watch failed")
			_st = 3
			_t = _n
		3:
			var m = current_scene
			if m == null or not m.get("replay_mode"):
				if _n - _t > 300:
					return _end(false, "replay scene never came up")
				return false
			if _n - _t < 30:
				return false
			var rp: Node = null
			for c in m.get_children():
				if c.get_script() == load("res://scripts/replay_player.gd"):
					rp = c
			if rp == null:
				return _end(false, "no replay player")
			if int(m.cur_map_index) != 19:
				_bad.append("played on map %d, recorded on 19" % int(m.cur_map_index))
			# Seek to the middle and compare puppets with the recorded frame.
			rp.playing = false
			var fi: int = rp.frames.size() / 2
			rp.seek(float(rp.frames[fi][0]))
			rp._process(0.0)
			var off := 0.0
			var cnt := 0
			for s in rp.frames[rp._fi][1]:
				var p = rp._puppets.get(int(s[0]))
				if p == null:
					_bad.append("no puppet for %d" % int(s[0]))
					continue
				off = maxf(off, p.position.distance_to(Vector2(s[1], s[2])))
				cnt += 1
			_log.append("puppets=%d max_off=%.1f" % [cnt, off])
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--shot=") and _shot == "":
					_shot = a.substr(7)
					rp.playing = true
					rp.follow_id = int(rp.frames[rp._fi][1][0][0])
					_rp = rp
					_st = 35
					_t = _n
					return false
			if cnt < 3 or off > 1.0:
				_bad.append("puppets %d off %.1f" % [cnt, off])
			rp.playing = true
			rp.cycle_speed()
			_log.append("speed=%s" % str(rp.speed))
			rp.exit_replay()
			_st = 4
			_t = _n
		35:
			if _n - _t < 50:
				return false
			root.get_texture().get_image().save_png(_shot)
			_rp.exit_replay()
			_st = 4
			_t = _n
		4:
			if _n - _t < 20:
				return false
			if st.map_index != 5:
				_bad.append("map choice not restored (%d)" % st.map_index)
			if net.replay_path != "":
				_bad.append("still in replay mode")
			return _end(_bad.is_empty(), " ".join(_log))
	return false


func _end(ok: bool, msg: String) -> bool:
	var st = root.get_node("Settings")
	st.bot_count = _saved[0]; st.game_mode = _saved[1]; st.map_index = _saved[2]; st.custom_map_path = _saved[3]
	print("REPLAY-TEST %s %s %s" % ["ok" if ok else "FAIL", str(_bad), msg])
	quit(0 if ok else 1)
	return true
