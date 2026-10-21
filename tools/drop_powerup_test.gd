extends SceneTree
## Drop the power-up (#303) — gate stage F (DROP-POWERUP-TEST).
##   godot --headless --fixed-fps 60 -s tools/drop_powerup_test.gd
## Single player, no bots. The owner's rule: dropping just ENDS the power-up,
## nothing is left to pick up again. Checks, through the real input path
## (the drop_powerup action):
##   - drop with nothing active does nothing;
##   - every kind (predator / berserker / vest / cluster), collected from a real
##     box, ends the moment it is dropped (kind-specific state restored, the
##     HUD timer pill gone, "<KIND> dropped" toast);
##   - nothing spawns (no bonus box, no weapon pickup) and the box slot keeps
##     its normal respawn timer: it comes back BONUS_RESPAWN after the pickup,
##     never earlier because of the drop;
##   - the touch DROP button shows only while a power-up is active;
##   - the action is in the Controls list with a free key + pad button, and
##     the new strings translate (es / pt_BR / de / fr).

const KINDS := ["predator", "berserker", "vest", "cluster"]
const NEW_KEYS := ["Drop Power-up", "Drop power-up", "%s dropped", "DROP"]

var _t := 0.0
var _phase := 0
var _step := 0
var _step_t := 0.0
var _ki := 0
var _log: Array = []
var _press_frames := -1
var _box_slot := -1
var _pickup_t := -1.0
var _first_slot := -1
var _first_pickup_t := -1.0
var _first_back_t := -1.0
var _before: Dictionary = {}
var _counts: Array = []
var _touch: Control = null


func _fail(msg: String) -> bool:
	print("DROP-POWERUP-TEST FAIL %s | %s" % [msg, " ".join(_log)])
	Input.action_release("drop_powerup")
	quit()
	return true


func _bonus_boxes(m) -> Array:
	var out: Array = []
	for bid in m._bonus_boxes.keys():
		var b = m._bonus_boxes[bid]
		if is_instance_valid(b) and not b.is_queued_for_deletion() and not (str(b.get("bonus_kind")) in ["medkit", "grenades"]):
			out.append(b)
	return out


func _world_counts(m) -> Array:
	var boxes := 0
	for n in m.get_children():
		if n is Area2D and n.get("bonus_kind") != null and not n.is_queued_for_deletion():
			boxes += 1
	var wps := 0
	for w in m.get_tree().get_nodes_in_group("weapon_pickup"):
		if is_instance_valid(w) and not w.is_queued_for_deletion():
			wps += 1
	return [boxes, wps]


func _press_drop() -> void:
	Input.action_press("drop_powerup")
	_press_frames = 3


func _process(d: float) -> bool:
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _phase == 0:
		st.set("custom_map_path", ""); st.set("map_index", 5); st.set("game_mode", 0)
		st.set("bot_count", 0)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = 1
		return false
	var m = current_scene
	if m == null or m.get("MAPS") == null or m.get("hud") == null:
		return false
	if _press_frames >= 0:
		_press_frames -= 1
		if _press_frames < 0:
			Input.action_release("drop_powerup")
	_t += d
	_step_t += d
	if _t > 75.0:
		return _fail("timeout step=%d kind=%d" % [_step, _ki])
	var p = m.get("player")
	if _t < 1.5 or p == null or not is_instance_valid(p):
		return false
	p.set("ceasefire_t", 0.0)
	p.set("health", 100.0)
	var bon = m.get("_bonuses")
	# When does the first collected box's slot come back?
	if _first_slot >= 0 and _first_back_t < 0.0 and int(bon._bonus_slot_active[_first_slot]) != 0:
		_first_back_t = _t
	match _step:
		0:
			if _log.is_empty() and not _static_checks():
				return true
			# Nothing active: pressing drop must do nothing.
			if str(p.bonus_kind) != "":
				# Spawned on a box (bonus slots sit on spawn points): start clean.
				_log.append("spawn-pickup=%s" % str(p.bonus_kind))
				p._clear_bonus_local()
				_step_t = 0.0
				return false
			if _step_t < 0.3:
				return false
			_counts = _world_counts(m)
			_press_drop()
			_step = 1
			_step_t = 0.0
		1:
			if _step_t > 0.4:
				if int(bon.drops_done) != 0 or str(p.bonus_kind) != "" or _world_counts(m) != _counts:
					return _fail("drop with nothing active changed something")
				if bon.host_drop_powerup(1):
					return _fail("host_drop_powerup accepted with nothing active")
				_log.append("noop-ok")
				# The touch DROP button (hidden without a power-up).
				_touch = load("res://scripts/touch_controls.gd").new()
				m.add_child(_touch)
				if _touch._btn_shown(6) or str(_touch._buttons[6]["action"]) != "drop_powerup":
					return _fail("touch DROP shown without a power-up")
				_step = 2
				_step_t = 0.0
		2:
			# Collect the next kind from a real box.
			var boxes: Array = []
			for b in _bonus_boxes(m):
				# Leave the first slot alone until its comeback is timed.
				if _first_back_t >= 0.0 or int(b.get_meta("slot", -1)) != _first_slot:
					boxes.append(b)
			if boxes.is_empty():
				if _step_t > 30.0:
					return _fail("no bonus box available for %s" % KINDS[_ki])
				return false
			var box = boxes[0]
			var kind: String = KINDS[_ki]
			box.bonus_kind = kind
			_box_slot = int(box.get_meta("slot", -1))
			_before = {"sec": p.using_secondary, "idx": p.secondary_index, "col": p.color, "cl": p.use_cluster}
			p.global_position = box.global_position
			p.velocity = Vector2.ZERO
			_step = 3
			_step_t = 0.0
		3:
			var kind: String = KINDS[_ki]
			if str(p.bonus_kind) == kind:
				_pickup_t = _t
				if _first_slot < 0:
					_first_slot = _box_slot
					_first_pickup_t = _t
				var cd: float = float(bon._bonus_slot_cd[_box_slot])
				if absf(cd - bon.BONUS_RESPAWN) > 0.2 or int(bon._bonus_slot_active[_box_slot]) != 0:
					return _fail("%s: slot not counting down after pickup (cd=%.2f)" % [kind, cd])
				_step = 4
				_step_t = 0.0
				return false
			if _step_t > 0.5:
				# body_entered missed (spawned overlapping): touch it the host way.
				var bs := _bonus_boxes(m)
				for b in bs:
					if int(b.get_meta("slot", -1)) == _box_slot:
						m._on_bonus_touched(p, int(b.bonus_id), _box_slot)
						break
			if _step_t > 3.0:
				return _fail("%s never picked up" % kind)
		4:
			# Active: HUD pill + touch DROP visible; kind state applied.
			if _step_t < 0.3:
				return false
			var kind: String = KINDS[_ki]
			if not m.hud.lbl_bonus.visible:
				return _fail("%s: HUD pill not shown while active" % kind)
			if not _touch._btn_shown(6):
				return _fail("%s: touch DROP hidden while active" % kind)
			if kind == "berserker" and not (p.using_secondary and int(p.secondary_index) == 1):
				return _fail("berserker did not lock the knife")
			if kind == "cluster" and not p.use_cluster:
				return _fail("cluster did not turn cluster grenades on")
			_counts = _world_counts(m)
			_step_t = 0.0
			_press_drop()
			_step = 5
		5:
			var kind: String = KINDS[_ki]
			if str(p.bonus_kind) != "":
				if _step_t > 0.2:
					return _fail("%s still active after drop (done=%d ignored=%d b_prev=%s pressed=%s)" % [kind,
						int(bon.drops_done), int(bon.drops_ignored), str(p.b_prev), str(Input.is_action_pressed("drop_powerup"))])
				return false
			# Ended within a few frames of the press.
			var ended_after := _step_t
			match kind:
				"predator":
					if not is_equal_approx(p.modulate.a, 1.0):
						return _fail("predator alpha not restored")
				"berserker":
					if p.using_secondary != _before["sec"] or int(p.secondary_index) != int(_before["idx"]) or p.color != _before["col"]:
						return _fail("berserker loadout / colour not restored")
				"cluster":
					if p.use_cluster != _before["cl"]:
						return _fail("cluster: grenade type not back to %s" % str(_before["cl"]))
				"vest":
					var h0: float = float(p.health)
					p.take_damage(10.0, "Someone", "AK-74", 2)
					if absf((h0 - float(p.health)) - 10.0) > 0.01:
						return _fail("vest still halves damage after drop (%.1f)" % (h0 - float(p.health)))
					p.set("health", 100.0)
			if _world_counts(m) != _counts:
				return _fail("%s: drop spawned something %s -> %s" % [kind, str(_counts), str(_world_counts(m))])
			if int(bon._bonus_slot_active[_box_slot]) != 0:
				return _fail("%s: box came back at the drop" % kind)
			var cd: float = float(bon._bonus_slot_cd[_box_slot])
			var want: float = bon.BONUS_RESPAWN - (_t - _pickup_t)
			if absf(cd - want) > 0.25:
				return _fail("%s: slot timer changed by the drop (cd=%.2f want %.2f)" % [kind, cd, want])
			var toast: String = str(m.hud.lbl_toast.text)
			if toast.find("dropped") < 0 or not m.hud.lbl_toast.visible:
				return _fail("%s: no 'dropped' toast (got '%s')" % [kind, toast])
			_log.append("%s-dropped(%.2fs)" % [kind, ended_after])
			_step = 6
			_step_t = 0.0
		6:
			if _step_t < 0.2:
				return false
			if m.hud.lbl_bonus.visible:
				return _fail("%s: HUD pill still shown after drop" % KINDS[_ki])
			if _touch._btn_shown(6):
				return _fail("%s: touch DROP still shown after drop" % KINDS[_ki])
			# A second press with nothing active is a no-op.
			_counts = _world_counts(m)
			var done: int = int(bon.drops_done)
			_press_drop()
			_before = {"done": done}
			_step = 7
			_step_t = 0.0
		7:
			if _step_t < 0.4:
				return false
			if int(bon.drops_done) != int(_before["done"]) or _world_counts(m) != _counts:
				return _fail("second drop press did something")
			_ki += 1
			if _ki >= KINDS.size():
				_step = 8
			else:
				_step = 2
			_step_t = 0.0
		8:
			# The first box's slot comes back on its normal timer, not earlier.
			var since: float = _t - _first_pickup_t
			if _first_back_t >= 0.0:
				since = _first_back_t - _first_pickup_t
				if since < bon.BONUS_RESPAWN - 0.3:
					return _fail("first box back early (%.1fs after pickup)" % since)
				_log.append("box-back-after=%.1fs" % since)
				print("DROP-POWERUP-TEST ok drops=%d %s" % [int(bon.drops_done), " ".join(_log)])
				Input.action_release("drop_powerup")
				quit()
				return true
			elif since > bon.BONUS_RESPAWN + 3.0:
				return _fail("first box never came back (%.1fs) slot=%d active=%s cd=%s kind='%s'" % [since, _first_slot,
					str(bon._bonus_slot_active), str(bon._bonus_slot_cd), str(p.bonus_kind)])
	return false


func _static_checks() -> bool:
	var CM = load("res://scripts/controls_map.gd")
	var defs: Array = CM.defaults_for("drop_powerup")
	if defs.is_empty() or not InputMap.has_action("drop_powerup"):
		_fail("drop_powerup not in ControlsMap / InputMap")
		return false
	# Its defaults must not collide with any other action's defaults.
	for row in CM.ACTIONS:
		if str(row[0]) == "drop_powerup":
			continue
		for e in (row[2] as Array):
			for dd in defs:
				if str(e.get("type")) == str(dd.get("type")) and int(e.get("physical_keycode", -1)) == int(dd.get("physical_keycode", -1)) \
						and int(e.get("button_index", -1)) == int(dd.get("button_index", -1)) and str(dd.get("type")) != "joy_motion":
					_fail("drop_powerup default collides with %s" % str(row[0]))
					return false
	var has_pad := false
	for dd in defs:
		has_pad = has_pad or str(dd.get("type")) == "joy_button"
	if not has_pad:
		_fail("drop_powerup has no gamepad default")
		return false
	var hint := FileAccess.get_file_as_string("res://scripts/controls_hint.gd")
	if hint.find("\"drop_powerup\"") < 0:
		_fail("controls hint has no drop row")
		return false
	for loc in ["es", "pt_BR", "de", "fr"]:
		TranslationServer.set_locale(loc)
		for k in NEW_KEYS:
			if TranslationServer.translate(k) == k:
				TranslationServer.set_locale("en")
				_fail("'%s' has no %s translation" % [k, loc])
				return false
	TranslationServer.set_locale("en")
	_log.append("controls=%s+%s strings-ok" % [CM.primary_label("drop_powerup"), CM.event_display(CM.event_from_dict(defs[1]))])
	return true
