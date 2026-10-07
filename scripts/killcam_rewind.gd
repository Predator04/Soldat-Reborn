extends Node2D
## Kill cam rewind: the moment you die, the last few seconds play back from
## the match recorder (replay_recorder.gd) — real speed, then slow motion over
## the killing shot — framed on you and your killer. Live soldiers and shots
## are hidden while it plays so only the replay is on screen. Space / click /
## tap / pad A skips. When it ends (or is skipped) Main is told you're ready
## to respawn; the live kill cam (spectator.gd) takes over if you're still
## waiting (long respawns).

const RP := preload("res://scripts/replay_player.gd")

const SECS := 3.0            # how far back it rewinds
const SLOW_LAST := 0.8       # the last N seconds play in slow motion…
const SLOW_SPEED := 0.5      # …at this speed
const HOLD := 0.45           # freeze on the kill before handing back
## Wall-clock length of a full rewind (Main pads the respawn wait by this).
const LENGTH := (SECS - SLOW_LAST) + SLOW_LAST / SLOW_SPEED + HOLD

signal finished(skipped: bool)

var main: Node
var frames: Array = []
var who: Dictionary = {}
var t := 0.0
var t0 := 0.0
var t_end := 0.0
var killer_id := -1
var victim_id := -1
var killer_name := ""
var weapon := ""
var _fi := 0
var _hold := 0.0
var _active := false
var _puppets: Dictionary = {}
var _hidden: Array = []
var _cam: Camera2D
var _ui: CanvasLayer
var _title: Label
var _sub: Label
var _slow: Label
var _bar: ColorRect
var _flash: ColorRect
var _marker: Node2D
var _flashed := false
var played_secs := 0.0       # tests
var slowmo_seen := false     # tests


class Marker extends Node2D:
	var target: Vector2
	var on := false
	var pulse := 0.0
	var col := Color(1.0, 0.3, 0.25)

	func _draw() -> void:
		if not on:
			return
		var a := 0.55 + 0.35 * sin(pulse * 7.0)
		var p := target + Vector2(0, -62)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-9, -12), p + Vector2(9, -12), p + Vector2(0, 0)]), Color(col, a))
		draw_arc(target + Vector2(0, -14), 30.0, 0.0, TAU, 32, Color(col, a * 0.6), 2.0)


func is_active() -> bool:
	return _active


## Start a rewind of the last SECS seconds. Returns false (and does nothing)
## when there's nothing to show: no recorder, killer not in the recording…
func start(rec: Node, killer: String, victim: String, wpn: String) -> bool:
	if _active or rec == null or not is_instance_valid(rec) or not rec.has_method("last_seconds"):
		return false
	if killer == "" or killer == victim:
		return false
	frames = rec.last_seconds(SECS)
	if frames.size() < 6:
		print("KILLCAM-REWIND skip: only %d frames recorded" % frames.size())
		return false
	who = (rec.get("who") as Dictionary).duplicate(true)
	killer_id = -1
	victim_id = -1
	for id in who.keys():
		var n := str(who[id].get("name", ""))
		if n == killer:
			killer_id = int(id)
		elif n == victim:
			victim_id = int(id)
	if killer_id < 0:
		var names: Array = []
		for id in who.keys():
			names.append(str(who[id].get("name", "")))
		print("KILLCAM-REWIND skip: killer '%s' not in recording %s" % [killer, str(names)])
		return false
	killer_name = killer
	weapon = wpn
	t0 = float(frames[0][0])
	t_end = float(frames[-1][0])
	t = t0
	_fi = 0
	_hold = 0.0
	_flashed = false
	played_secs = 0.0
	slowmo_seen = false
	_build()
	_active = true
	set_process(true)
	set_process_input(true)
	_tick(0.0)
	_cam.reset_smoothing()
	print("KILLCAM-REWIND start frames=%d span=%.2f killer=%s" % [frames.size(), t_end - t0, killer])
	return true


## Stop early. `skipped` = the player asked; false = cut off (respawned, round reset).
func stop(skipped := false, notify := true) -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	set_process_input(false)
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	for p in _puppets.values():
		p.queue_free()
	_puppets.clear()
	if _marker != null:
		_marker.queue_free()
		_marker = null
	if _ui != null:
		_ui.queue_free()
		_ui = null
	if main != null and main.get("hud") != null and is_instance_valid(main.hud) and main.hud.has_method("set_rewind"):
		main.hud.set_rewind(false)
	if _cam != null:
		_cam.enabled = false
		_cam.queue_free()
		_cam = null
	# Hand the view back to the live kill cam if it's running.
	var sp = main.get("spectator") if main != null else null
	if sp != null and is_instance_valid(sp) and sp.is_active() and sp.get("cam") != null:
		sp.cam.enabled = true
		sp.cam.make_current()
	queue_redraw()
	print("KILLCAM-REWIND end skipped=%s played=%.2f" % [str(skipped), played_secs])
	if notify:
		finished.emit(skipped)


func _ready() -> void:
	set_process(false)
	set_process_input(false)
	z_index = 50


func _build() -> void:
	_cam = Camera2D.new()
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 6.0
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = int(main.get("MAP_W")) if main != null and main.get("MAP_W") != null else 4800
	_cam.limit_bottom = int(main.get("MAP_H")) if main != null and main.get("MAP_H") != null else 2000
	add_child(_cam)
	_cam.enabled = true
	_cam.make_current()
	_marker = Marker.new()
	_marker.z_index = 5
	add_child(_marker)
	_ui = CanvasLayer.new()
	_ui.layer = 11
	add_child(_ui)
	# Letterbox bars: reads instantly as "this is a replay". Everything we
	# print sits in the bottom bar (the top one is under the HUD's score box).
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.82)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.offset_bottom = 40
		else:
			bar.offset_top = -52
		_ui.add_child(bar)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.15, 0.1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_flash)
	_title = Label.new()
	_title.text = "◀◀  " + tr("KILL CAM")
	_title.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_title.offset_left = 18
	_title.offset_top = -46
	_title.offset_right = 400
	UITheme.style_title(_title, 26)
	_title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_ui.add_child(_title)
	_sub = Label.new()
	var w := ("  ·  " + tr(weapon)) if weapon != "" else ""
	_sub.text = (tr("Killed by %s") % killer_name) + w
	_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub.offset_left = -300
	_sub.offset_right = 300
	_sub.offset_top = -40
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_body(_sub, 18)
	_ui.add_child(_sub)
	var skip := Label.new()
	skip.text = tr("Tap to skip") if UITheme.is_touch() else tr("SPACE / click to skip")
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.offset_left = -320
	skip.offset_right = -18
	skip.offset_top = -38
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.style_body(skip, 14, UITheme.COL_TEXT_MUTED)
	_ui.add_child(skip)
	_slow = Label.new()
	_slow.text = tr("SLOW-MO")
	_slow.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_slow.offset_left = -100
	_slow.offset_right = 100
	_slow.offset_top = -86
	_slow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_body(_slow, 18, UITheme.COL_ACCENT_HI)
	_slow.visible = false
	_ui.add_child(_slow)
	_bar = ColorRect.new()
	_bar.color = Color(1.0, 0.35, 0.3, 0.9)
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bar.offset_top = -52
	_bar.offset_bottom = -49
	_bar.offset_right = 0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_bar)
	if main != null and main.get("hud") != null and main.hud.has_method("set_rewind"):
		main.hud.set_rewind(true)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	var skip := false
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = (event as InputEventKey).keycode
		skip = kc == KEY_SPACE or kc == KEY_ENTER or kc == KEY_KP_ENTER
	elif event is InputEventMouseButton and event.pressed:
		skip = (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch and event.pressed:
		skip = true
	elif event is InputEventJoypadButton and event.pressed:
		var jb: int = (event as InputEventJoypadButton).button_index
		skip = jb == JOY_BUTTON_A or jb == JOY_BUTTON_START
	if skip:
		get_viewport().set_input_as_handled()
		stop(true)


func _process(delta: float) -> void:
	if not _active:
		return
	_tick(delta)


func _tick(delta: float) -> void:
	played_secs += delta
	var slow := t >= t_end - SLOW_LAST
	if slow:
		slowmo_seen = true
	if t < t_end:
		t = minf(t_end, t + delta * (SLOW_SPEED if slow else 1.0))
	else:
		_hold += delta
		if not _flashed:
			_flashed = true
			_flash.color.a = 0.45
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 1.2)
	_slow.visible = slow and int(played_secs * 3.0) % 2 == 0
	var vw := get_viewport().get_visible_rect().size.x
	_bar.offset_right = vw * clampf((t - t0) / maxf(t_end - t0, 0.01), 0.0, 1.0)
	_hide_live()
	while _fi < frames.size() - 1 and float(frames[_fi + 1][0]) <= t:
		_fi += 1
	var a: Array = frames[_fi]
	var b: Array = frames[mini(_fi + 1, frames.size() - 1)]
	var span := float(b[0]) - float(a[0])
	var k := clampf((t - float(a[0])) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var kp := Vector2.INF
	var vp := Vector2.INF
	var nxt: Dictionary = {}
	for st in b[1]:
		nxt[int(st[0])] = st
	var seen: Dictionary = {}
	for st in a[1]:
		var id := int(st[0])
		seen[id] = true
		var p = _puppets.get(id)
		if p == null:
			p = RP.Puppet.new()
			_puppets[id] = p
			add_child(p)
		p.info = who.get(id, {})
		p.label = tr("YOU") if id == victim_id else str(p.info.get("name", ""))
		var s: Array = st.duplicate()
		if nxt.has(id) and (int(st[7]) & 2) == (int(nxt[id][7]) & 2):
			var n: Array = nxt[id]
			if Vector2(n[1], n[2]).distance_to(Vector2(st[1], st[2])) < 300.0:
				s[1] = lerpf(float(st[1]), float(n[1]), k)
				s[2] = lerpf(float(st[2]), float(n[2]), k)
				s[3] = lerp_angle(float(st[3]), float(n[3]), k)
		p.st = s
		p.position = Vector2(float(s[1]), float(s[2]))
		p.visible = true
		p.queue_redraw()
		if id == killer_id:
			kp = p.position
		elif id == victim_id:
			vp = p.position
	for id in _puppets.keys():
		if not seen.has(id):
			_puppets[id].visible = false
	# Frame killer + victim together (zoom out to fit, within reason).
	var focus := kp if kp != Vector2.INF else vp
	if focus != Vector2.INF:
		var zoom := 1.0
		if kp != Vector2.INF and vp != Vector2.INF:
			focus = (kp + vp) * 0.5
			var view := get_viewport().get_visible_rect().size
			var need := (kp - vp).abs() + Vector2(260, 220)
			zoom = clampf(minf(view.x / need.x, (view.y - 112.0) / need.y), 0.55, 1.15)
		if slow and kp != Vector2.INF:
			zoom = minf(zoom * 1.12, 1.25)
		_cam.global_position = focus + Vector2(0, -20)
		_cam.zoom = _cam.zoom.lerp(Vector2(zoom, zoom), clampf(delta * 4.0, 0.0, 1.0)) if delta > 0.0 else Vector2(zoom, zoom)
	_marker.on = kp != Vector2.INF
	_marker.target = kp if kp != Vector2.INF else Vector2.ZERO
	_marker.pulse += delta
	_marker.queue_redraw()
	queue_redraw()
	if _hold >= HOLD:
		stop(false)


## Keep the live world's soldiers and shots out of the shot while replaying.
func _hide_live() -> void:
	for g in ["soldier", "bullet", "grenade"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is CanvasItem and (n as CanvasItem).visible:
				(n as CanvasItem).visible = false
				_hidden.append(n)


func _draw() -> void:
	if not _active or frames.is_empty():
		return
	var a: Array = frames[_fi]
	for s in a[2]:
		var p := Vector2(float(s[1]), float(s[2]))
		match str(s[0]):
			"b":
				var d := Vector2.RIGHT.rotated(float(s[3]))
				draw_line(p - d * 22.0, p, Color(1.0, 0.92, 0.55, 0.95), 2.0)
			"r":
				draw_circle(p, 5.0, Color(1.0, 0.55, 0.2))
			"g":
				draw_circle(p, 3.5, Color(0.45, 0.65, 0.35))
