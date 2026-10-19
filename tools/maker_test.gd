extends SceneTree
## Maker mode (#286) gate test. Drives the real editor + match:
##   place pieces from the palette API -> touching solid pieces merge into one
##   outline (separate ones don't), collision + drawn polys generated; select /
##   duplicate / rotate / flip / resize / delete; undo / redo; spikes, lava and
##   pads compile to hazards / jump_pads; validation catches a buried spawn and
##   missing CTF flags; save -> load round trip gives the identical map JSON;
##   PLAY loads the match with that map and the player spawned under the camera;
##   a jump pad launches the soldier, spikes kill him, bots see the zones;
##   EDIT returns to the same view with the map unchanged; node count flat over
##   three edit / play cycles. Any script error in the log fails the gate.
##   godot --headless --fixed-fps 60 -s tools/maker_test.gd

const CYCLES := 3

var _n := 0
var _phase := 0
var _t := 0.0
var _bad: Array = []
var _log: Array = []
var _mk = null
var _ref_json := ""
var _cam := Vector2.ZERO
var _spawn := Vector2.ZERO
var _cycle := 0
var _nodes: Array = []
var _pad_y0 := 0.0
var _launched := false
var _wait := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_bad.append(what)


func _end() -> bool:
	var st := root.get_node_or_null("Settings")
	if st != null:
		st.set("custom_map_path", "")
		st.call("save")
	if _bad.is_empty():
		print("MAKER-TEST ok ", " ".join(_log))
	else:
		print("MAKER-TEST FAIL ", " | ".join(_bad), " :: ", " ".join(_log))
	quit()
	return true


func _outline_spanning(x0: float, x1: float, y: float) -> int:
	var n := 0
	for o in _mk.preview().get("_mk_outlines", []):
		var pts: PackedVector2Array = o["pts"]
		var r := Rect2(pts[0], Vector2.ZERO)
		for v in pts:
			r = r.expand(v)
		if r.position.x <= x0 + 16.0 and r.end.x >= x1 - 16.0 and r.position.y <= y and r.end.y >= y:
			n += 1
	return n


func _editor_steps() -> void:
	var e = current_scene
	var Build = load("res://scripts/maker/maker_build.gd")
	var MapIO = load("res://scripts/map_io.gd")
	_check(bool(_mk.active), "editor did not open in Maker mode")
	_check(Build.is_maker(e._map), "starter map has no maker block")
	_mk.new_map()
	var p0: int = _mk._pieces().size()
	# Two touching blocks merge; a third one apart stays separate.
	var a: Dictionary = _mk.place("block", Vector2(600, 800))
	var b: Dictionary = _mk.place("block", Vector2(1000, 800))
	_mk.place("block", Vector2(2000, 700))
	_check(_mk._pieces().size() == p0 + 3, "place() did not add 3 pieces")
	var merged: int = _outline_spanning(400, 1200, 800)
	_check(merged == 1, "touching blocks did not merge into one outline (%d)" % merged)
	var apart: int = _outline_spanning(1800, 2200, 700)
	_check(apart == 1, "separate block missing (%d)" % apart)
	var c: Dictionary = _mk.compiled()
	_check((c.get("collision", []) as Array).size() > 0 and (c.get("polys", []) as Array).size() > 0, "no collision / polys compiled")
	var vc_ok := true
	for poly in c.get("polys", []):
		if (poly.get("vc", PackedColorArray()) as PackedColorArray).size() != (poly.get("points", PackedVector2Array()) as PackedVector2Array).size():
			vc_ok = false
	_check(vc_ok, "drawn polys without per-vertex colours")
	_log.append("outlines=%d polys=%d coll=%d" % [(_mk.preview().get("_mk_outlines", []) as Array).size(), (c["polys"] as Array).size(), (c["collision"] as Array).size()])
	# Undo / redo.
	var n1: int = _mk._pieces().size()
	_mk.undo()
	_check(_mk._pieces().size() == n1 - 1, "undo did not remove the last piece")
	_mk.redo()
	_check(_mk._pieces().size() == n1, "redo did not bring it back")
	# Selection ops: duplicate, rotate, flip, resize, delete.
	_mk.sel = [{"k": "pc", "i": int(b["i"])}]
	_mk.duplicate_selection()
	_check(_mk._pieces().size() == n1 + 1, "duplicate failed")
	var dup: Dictionary = _mk.sel[0]
	var pd: Dictionary = _mk._pieces()[int(dup["i"])]
	_mk.rotate_selection()
	_check(int(pd.get("r", 0)) == 1, "rotate failed")
	_mk.flip_selection()
	_check(int(pd.get("f", 0)) == 1, "flip failed")
	var rr: Rect2 = _mk.ref_rect(dup)
	_mk.resize_ref(dup, 4, rr.end + Vector2(80, 40), rr)
	_mk.commit()
	_check(_mk.ref_rect(dup).size.x > rr.size.x + 40.0, "resize failed")
	_mk.delete_selection()
	_check(_mk._pieces().size() == n1, "delete failed")
	# Box select picks both merged blocks.
	_mk._box_a = Vector2(380, 680)
	_mk._box_b = Vector2(1220, 920)
	var got := 0
	for r in _mk.all_refs():
		if str(r["k"]) == "pc" and Rect2(_mk._box_a, Vector2.ZERO).expand(_mk._box_b).intersects(_mk.ref_rect(r)):
			got += 1
	_check(got >= 2, "box select found %d pieces" % got)
	# Hazards + helpers on the starter ground (top at y 1510, x 200..1400).
	_mk.place("spikes", Vector2(1100, 1490))
	_mk.place("pad", Vector2(400, 1500))
	_mk.place("lava", Vector2(1600, 1600))
	c = _mk.compiled()
	var hz: Array = c.get("hazards", [])
	_check(hz.size() == 2, "hazards not compiled (%d)" % hz.size())
	_check((c.get("jump_pads", []) as Array).size() == 1, "jump pad not compiled")
	var sp_rect := Rect2()
	for h in hz:
		if str(h["kind"]) == "spikes":
			sp_rect = h["rect"]
	_check(absf(sp_rect.end.y - 1510.0) < 3.0, "spikes did not settle on the ground (%s)" % str(sp_rect))
	# Validation: a buried spawn, then missing CTF flags.
	var buried: Dictionary = _mk.place("spawn_blue", Vector2(800, 1650))
	var probs: Array = Build.validate(_mk.compiled(), 2)
	var found := false
	for pr in probs:
		if str(pr["lvl"]) == "error" and str(pr["msg"]).contains("buried"):
			found = true
	_check(found, "buried spawn not reported")
	_mk.sel = [buried]
	_mk.delete_selection()
	_check(not Build.has_errors(Build.validate(_mk.compiled(), 2)), "starter map + pieces not valid for CTF: %s" % str(Build.validate(_mk.compiled(), 2)))
	var flags = e._map["ctf_flags"]
	e._map.erase("ctf_flags")
	_check(Build.has_errors(Build.validate(_mk.compiled(), 2)), "missing CTF flags not reported")
	e._map["ctf_flags"] = flags
	_mk.commit()
	_touch_steps(e)
	# Save -> load round trip.
	_mk._name.text = "qa_maker_roundtrip"
	var path: String = _mk.save()
	_check(path != "", "save failed")
	var before: String = MapIO.map_to_json(_mk.compiled())
	var loaded: Dictionary = MapIO.load_from_file(path)
	var again: Dictionary = Build.compile(Build.decompile(loaded))
	again["name"] = _mk.map_name()
	again.erase("_mk_outlines")
	_check(MapIO.map_to_json(again) == before, "save -> load round trip changed the map")
	_mk.load_path(path)
	_check(MapIO.map_to_json(_mk.compiled()) == before, "load_path() changed the map")
	_ref_json = before
	_log.append("json=%dB" % before.length())


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.position = pos
	t.pressed = pressed
	_mk.handle_input(t)


func _finger(idx: int, pos: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = idx
	d.position = pos
	d.relative = rel
	_mk.handle_input(d)


## Phone controls: finger-drag a piece, one-finger pan on empty space, pinch
## zoom, long press opens the context menu.
func _touch_steps(e) -> void:
	e._cam.position = Vector2(900, 1300)
	e._cam.zoom = Vector2(0.6, 0.6)
	e._cam.force_update_scroll()
	var r: Dictionary = _mk.place("block", Vector2(900, 1000))
	var p: Dictionary = _mk._pieces()[int(r["i"])]
	var x0 := float(p["x"])
	var at: Vector2 = _mk.to_screen(Vector2(x0, float(p["y"])))
	_touch(0, at, true)
	_finger(0, at + Vector2(30, 0), Vector2(30, 0))
	_finger(0, at + Vector2(60, 0), Vector2(30, 0))
	_touch(0, at + Vector2(60, 0), false)
	_check(absf(float(p["x"]) - (x0 + 100.0)) < 0.5, "finger drag moved the piece to x=%d (want %d)" % [int(p["x"]), int(x0 + 100.0)])
	# One finger on empty sky pans the view.
	var sky: Vector2 = _mk.to_screen(Vector2(300, 1000))
	var c0: Vector2 = e._cam.position
	_touch(0, sky, true)
	_finger(0, sky + Vector2(-60, 0), Vector2(-60, 0))
	_touch(0, sky + Vector2(-60, 0), false)
	_check(e._cam.position.x - c0.x > 60.0, "one-finger pan did not move the view")
	# Pinch zoom.
	e._cam.force_update_scroll()
	var z0: float = e._cam.zoom.x
	var mid: Vector2 = _mk.to_screen(Vector2(300, 1000))
	_touch(0, mid - Vector2(40, 0), true)
	_touch(1, mid + Vector2(40, 0), true)
	_finger(1, mid + Vector2(120, 0), Vector2(80, 0))
	_touch(1, mid + Vector2(120, 0), false)
	_touch(0, mid - Vector2(40, 0), false)
	_check(e._cam.zoom.x > z0 * 1.3, "pinch did not zoom in (%.2f -> %.2f)" % [z0, e._cam.zoom.x])
	# Long press on empty space opens the context menu.
	e._cam.zoom = Vector2(0.6, 0.6)
	e._cam.force_update_scroll()
	var lp: Vector2 = _mk.to_screen(Vector2(300, 1000))
	_touch(0, lp, true)
	_mk._process(0.6)
	_check(_mk._ctx.visible, "long press did not open the context menu")
	_touch(0, lp, false)
	_mk._close_popups()
	_mk.sel = [r]
	_mk.delete_selection()
	_log.append("touch=ok")


func _process(delta: float) -> bool:
	_n += 1
	_t += delta
	if _t > 110.0:
		_bad.append("timeout in phase %d (cycle %d)" % [_phase, _cycle])
		return _end()
	var st := root.get_node_or_null("Settings")
	match _phase:
		0:
			if st == null:
				return false
			st.set("bot_count", 0)
			st.set("game_mode", 0)
			st.set("custom_map_path", "")
			change_scene_to_file("res://scenes/map_editor.tscn")
			_phase = 1
		1:
			var e = current_scene
			if e == null or e.get("_maker") == null or _n < 8:
				return false
			_mk = e.get("_maker")
			_editor_steps()
			_phase = 2
		2:
			# PLAY from a known view over the west ground.
			var e = current_scene
			e._cam.position = Vector2(900, 1300)
			e._cam.zoom = Vector2(0.6, 0.6)
			e._cam.force_update_scroll()
			_cam = e._cam.position
			_mk.test_mode = 0
			_nodes.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			var ok: bool = _mk.play(true)
			_check(ok, "play() refused (cycle %d)" % _cycle)
			_spawn = root.get_node("Net").get("maker_return").get("spawn", Vector2.INF)
			_wait = 0
			_phase = 3
		3:
			var m = current_scene
			if m == null or m.get("MAPS") == null or m.get("player") == null or not is_instance_valid(m.get("player")):
				return false
			_wait += 1
			if _wait < 20:
				return false
			var pl = m.get("player")
			var mp: Dictionary = m.get("_map")
			if _cycle == 0:
				_check(str(mp.get("name", "")) == "qa_maker_roundtrip", "match loaded map '%s'" % str(mp.get("name", "")))
				_check((mp.get("hazards", []) as Array).size() == 2 and (mp.get("jump_pads", []) as Array).size() == 1, "match is missing hazards / pads")
				var px: float = (pl as Node2D).global_position.x
				_check(absf(px - _spawn.x) < 140.0, "player spawned at x=%d, camera spot x=%d" % [int(px), int(_spawn.x)])
				_log.append("spawn=(%d,%d)" % [int((pl as Node2D).global_position.x), int((pl as Node2D).global_position.y)])
				# Bots see the zones.
				var hzs = m.get("_hazards")
				var z: Rect2 = hzs.zones[0]["rect"]
				_check(m.hazard_at(z.get_center()), "hazard_at() misses a zone")
				_check(not z.grow(20.0).has_point(m.hazard_safe_goal(z.get_center())), "safe goal still inside the zone")
				# Jump pad: stand the soldier on it.
				var pad: Vector2 = hzs.pads[0]["pos"]
				(pl as Node2D).global_position = pad + Vector2(0, -2)
				pl.set("velocity", Vector2.ZERO)
				pl.set("ceasefire_t", 0.0)
				_pad_y0 = pad.y
				_wait = 0
				_phase = 4
				return false
			_wait = 0
			_phase = 6
		4:
			var m = current_scene
			var pl = m.get("player")
			_wait += 1
			if is_instance_valid(pl) and float((pl.get("velocity") as Vector2).y) < -600.0:
				_launched = true
			if _wait < 50:
				return false
			var hzs = m.get("_hazards")
			_check(int(hzs.launches) >= 1 and _launched, "jump pad did not launch (launches=%d)" % int(hzs.launches))
			_check(_pad_y0 - (pl as Node2D).global_position.y > 120.0 or _launched, "soldier did not rise off the pad")
			_log.append("pad_launches=%d" % int(hzs.launches))
			# Spikes: drop him into them.
			var sp: Rect2 = Rect2()
			for z in hzs.zones:
				if str(z["kind"]) == "spikes":
					sp = z["rect"]
			(pl as Node2D).global_position = Vector2(sp.get_center().x, sp.end.y - 1.0)
			pl.set("velocity", Vector2.ZERO)
			_wait = 0
			_phase = 5
		5:
			var m = current_scene
			var pl = m.get("player")
			_wait += 1
			if _wait < 12:
				return false
			_check(not is_instance_valid(pl) or bool(pl.get("dead")) or int(m.get("_hazards").kills) >= 1, "spikes did not kill the soldier")
			_log.append("spike_kills=%d" % int(m.get("_hazards").kills))
			_wait = 0
			_phase = 6
		6:
			# EDIT: back to the editor.
			var m = current_scene
			m.call("maker_edit")
			_wait = 0
			_phase = 7
		7:
			var e = current_scene
			if e == null or e.get("_maker") == null:
				return false
			_wait += 1
			if _wait < 30:
				return false
			_mk = e.get("_maker")
			var MapIO = load("res://scripts/map_io.gd")
			_check(bool(_mk.active), "EDIT did not come back to Maker mode")
			_check(MapIO.map_to_json(_mk.compiled()) == _ref_json, "map changed across PLAY / EDIT (cycle %d)" % _cycle)
			_check((e._cam.position as Vector2).distance_to(_cam) < 1.0, "camera moved across PLAY / EDIT")
			_cycle += 1
			if _cycle < CYCLES:
				_phase = 2
				return false
			_nodes.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			_log.append("nodes=%s" % str(_nodes))
			# The first sample is the fresh editor; every return must match it.
			for i in range(1, _nodes.size()):
				_check(absf(float(_nodes[i]) - float(_nodes[1])) <= 2.0, "node count grows across edit / play cycles: %s" % str(_nodes))
			_check(int(root.get_node("Settings").get("game_mode")) == 0, "PLAY left the test mode in the settings")
			return _end()
	return false
