extends Node2D
## Plays back a recorded match (replay_recorder.gd) on top of its map: every
## soldier, shot, flag, vehicle and kill, with play / pause, speed, seeking
## and a camera that follows any player (or roams freely).

const SoldierArt := preload("res://scripts/soldier_art.gd")
const Recorder := preload("res://scripts/replay_recorder.gd")

var main: Node
var data: Dictionary = {}
var frames: Array = []
var who: Dictionary = {}
var events: Array = []
var t := 0.0
var speed := 1.0
var playing := true
var follow_id := -1              # soldier id the camera follows; -1 = free cam
var _fi := 0                     # frame index at or before t
var _puppets: Dictionary = {}    # id -> Puppet
var _cam: Camera2D
var _ui: CanvasLayer
var _slider: HSlider
var _time_lbl: Label
var _info_lbl: Label
var _feed: VBoxContainer
var _speed_btn: Button
var _play_btn: Button
var _seeking := false
var duration := 0.0


class Puppet extends Node2D:
	var st: Array = []           # [id, x, y, aim, facing, vx, vy, bits, weapon, back, hp]
	var info: Dictionary = {}
	var label := ""

	func _draw() -> void:
		if st.is_empty():
			return
		var bits: int = int(st[7])
		var col := Color.html(str(info.get("color", "ffffff")))
		var aim := Vector2.RIGHT.rotated(float(st[3]))
		SoldierArt.draw_soldier(self, col, float(st[4]) if float(st[4]) != 0.0 else 1.0, aim, Vector2(float(st[5]), float(st[6])),
			bits & 1 != 0, bits & 2 != 0, Color(0.72, 0.72, 0.78), "bullet", 0.0, float(st[10]), 0.0, false, str(st[8]),
			bits & 4 != 0, bits & 32 != 0, bits & 8 != 0, bits & 16 != 0, false, "", false, false,
			info.get("cos", {}), str(st[9]), 0, false, false, true)
		if bits & 2 == 0:
			var f := ThemeDB.fallback_font
			var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string_outline(f, Vector2(-w * 0.5, -40), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(-w * 0.5, -40), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col.lightened(0.3))


func _ready() -> void:
	data = Recorder.load_file(Net.replay_path)
	frames = data.get("frames", [])
	who = data.get("who", {})
	events = data.get("events", [])
	duration = float(frames[-1][0]) if not frames.is_empty() else 0.0
	_cam = Camera2D.new()
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 7.0
	add_child(_cam)
	_cam.make_current()
	_build_ui()
	# Start on the player who recorded it, if they're in it.
	var me := str(data.get("header", {}).get("me", ""))
	for id in who.keys():
		if str(who[id].get("name", "")) == me and me != "":
			follow_id = int(id)
	if follow_id < 0 and not who.is_empty():
		follow_id = int(who.keys()[0])
	if not frames.is_empty() and frames[0][1].size() > 0:
		_cam.global_position = Vector2(frames[0][1][0][1], frames[0][1][0][2])
	print("REPLAY loaded frames=%d soldiers=%d duration=%.1f" % [frames.size(), who.size(), duration])


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.06, 0.07, 0.09, 0.85)))
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -64
	bar.offset_left = 12
	bar.offset_right = -12
	bar.offset_bottom = -10
	_ui.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	bar.add_child(hb)
	_play_btn = UITheme.make_small_button("PAUSE", 96, 36)
	_play_btn.pressed.connect(toggle_play)
	hb.add_child(_play_btn)
	_speed_btn = UITheme.make_small_button("1x", 64, 36)
	_speed_btn.pressed.connect(cycle_speed)
	hb.add_child(_speed_btn)
	var back10 := UITheme.make_small_button("-10s", 64, 36)
	back10.pressed.connect(func() -> void: seek(t - 10.0))
	hb.add_child(back10)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = maxf(duration, 0.1)
	_slider.step = 0.1
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.drag_started.connect(func() -> void: _seeking = true)
	_slider.drag_ended.connect(func(_c: bool) -> void:
		_seeking = false
		seek(_slider.value))
	hb.add_child(_slider)
	_time_lbl = Label.new()
	UITheme.style_body(_time_lbl, 14)
	hb.add_child(_time_lbl)
	var prev := UITheme.make_small_button("◀", 44, 36)
	prev.pressed.connect(func() -> void: cycle_follow(-1))
	hb.add_child(prev)
	var nxt := UITheme.make_small_button("▶", 44, 36)
	nxt.pressed.connect(func() -> void: cycle_follow(1))
	hb.add_child(nxt)
	var free := UITheme.make_small_button("FREE CAM", 110, 36)
	free.pressed.connect(func() -> void: follow_id = -1)
	hb.add_child(free)
	var exit := UITheme.make_small_button("EXIT", 80, 36)
	exit.pressed.connect(exit_replay)
	hb.add_child(exit)
	var h: Dictionary = data.get("header", {})
	_info_lbl = Label.new()
	_info_lbl.position = Vector2(16, 12)
	UITheme.style_body(_info_lbl, 15, UITheme.COL_ACCENT_HI)
	_info_lbl.text = "%s  ·  %s  ·  %s" % [tr("REPLAY"), str(h.get("map", "?")), Time.get_datetime_string_from_unix_time(int(h.get("when", 0))).replace("T", " ").left(16)]
	_ui.add_child(_info_lbl)
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -360
	_feed.offset_right = -14
	_feed.offset_top = 12
	_ui.add_child(_feed)
	var help := Label.new()
	help.text = tr("Space pause · ←/→ seek · ↑/↓ speed · Q/E player · F free cam · Esc exit")
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.offset_top = -84
	help.offset_left = -300
	help.offset_right = 300
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_body(help, 12, UITheme.COL_TEXT_MUTED)
	_ui.add_child(help)


func toggle_play() -> void:
	playing = not playing
	if t >= duration:
		seek(0.0)
		playing = true
	_play_btn.text = tr("PAUSE") if playing else tr("PLAY")


const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]


## Button: next speed (wraps). Keys: up / down without wrapping.
func cycle_speed(dir := 0) -> void:
	var i := SPEEDS.find(speed)
	if dir == 0:
		i = (i + 1) % SPEEDS.size()
	else:
		i = clampi(i + dir, 0, SPEEDS.size() - 1)
	speed = SPEEDS[i]
	_speed_btn.text = ("%sx" % str(speed)).replace(".0x", "x")


func seek(to: float) -> void:
	t = clampf(to, 0.0, duration)
	_fi = 0
	while _fi < frames.size() - 1 and float(frames[_fi + 1][0]) <= t:
		_fi += 1


func cycle_follow(dir: int) -> void:
	var ids: Array = who.keys()
	ids.sort()
	if ids.is_empty():
		return
	var i := ids.find(follow_id)
	follow_id = int(ids[posmod(i + dir, ids.size())])


func exit_replay() -> void:
	Net.replay_path = ""
	# Put back the map / mode the player had picked before watching.
	for k in Net.replay_restore.keys():
		Settings.set(k, Net.replay_restore[k])
	Net.replay_restore = {}
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE: toggle_play()
		KEY_LEFT: seek(t - 5.0)
		KEY_RIGHT: seek(t + 5.0)
		KEY_UP: cycle_speed(1)
		KEY_DOWN: cycle_speed(-1)
		KEY_Q: cycle_follow(-1)
		KEY_E: cycle_follow(1)
		KEY_F: follow_id = -1
		KEY_ESCAPE: exit_replay()
		_: return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if frames.is_empty():
		return
	if playing and not _seeking:
		t += delta * speed
		if t >= duration:
			t = duration
			playing = false
			_play_btn.text = tr("PLAY")
	while _fi < frames.size() - 1 and float(frames[_fi + 1][0]) <= t:
		_fi += 1
	var a: Array = frames[_fi]
	var b: Array = frames[mini(_fi + 1, frames.size() - 1)]
	var span := float(b[0]) - float(a[0])
	var k := clampf((t - float(a[0])) / span, 0.0, 1.0) if span > 0.0 else 0.0
	_apply_soldiers(a, b, k)
	if not _seeking:
		_slider.set_value_no_signal(t)
	_time_lbl.text = "%d:%02d / %d:%02d" % [int(t) / 60, int(t) % 60, int(duration) / 60, int(duration) % 60]
	_update_feed()
	# Free cam: arrow-free roaming with WASD.
	if follow_id < 0:
		var mv := Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		_cam.global_position += mv * 900.0 * delta
	queue_redraw()


func _apply_soldiers(a: Array, b: Array, k: float) -> void:
	var nxt: Dictionary = {}
	for st in b[1]:
		nxt[int(st[0])] = st
	var alive: Dictionary = {}
	for st in a[1]:
		var id := int(st[0])
		alive[id] = true
		var p: Puppet = _puppets.get(id)
		if p == null:
			p = Puppet.new()
			_puppets[id] = p
			add_child(p)
		p.info = who.get(id, who.get(str(id), {}))
		p.label = str(p.info.get("name", ""))
		var s: Array = st.duplicate()
		if nxt.has(id) and (int(st[7]) & 2) == (int(nxt[id][7]) & 2):
			var n: Array = nxt[id]
			if Vector2(n[1], n[2]).distance_to(Vector2(st[1], st[2])) < 300.0:   # not a respawn jump
				s[1] = lerpf(float(st[1]), float(n[1]), k)
				s[2] = lerpf(float(st[2]), float(n[2]), k)
				s[3] = lerp_angle(float(st[3]), float(n[3]), k)
		p.st = s
		p.position = Vector2(float(s[1]), float(s[2]))
		p.visible = true
		p.queue_redraw()
		if id == follow_id:
			_cam.global_position = p.position + Vector2(0, -20)
	for id in _puppets.keys():
		if not alive.has(id):
			_puppets[id].visible = false


func _update_feed() -> void:
	for c in _feed.get_children():
		c.queue_free()
	var shown := 0
	for i in range(events.size() - 1, -1, -1):
		var e: Array = events[i]
		var et := float(e[0])
		if et > t or t - et > 6.0:
			continue
		var l := Label.new()
		l.text = "%s  [%s]  %s" % [str(e[2]), str(e[4]), str(e[3])] if str(e[2]) != str(e[3]) else "%s  ✝" % str(e[3])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UITheme.style_body(l, 13)
		_feed.add_child(l)
		shown += 1
		if shown >= 5:
			break


func _draw() -> void:
	if frames.is_empty():
		return
	var a: Array = frames[_fi]
	# Shots: tracers / rockets / grenades.
	for s in a[2]:
		var p := Vector2(float(s[1]), float(s[2]))
		match str(s[0]):
			"b":
				var d := Vector2.RIGHT.rotated(float(s[3]))
				draw_line(p - d * 14.0, p, Color(1.0, 0.9, 0.5, 0.9), 1.6)
			"r":
				draw_circle(p, 4.0, Color(1.0, 0.55, 0.2))
			"g":
				draw_circle(p, 3.0, Color(0.4, 0.6, 0.35))
	# Flags.
	for f in a[3]:
		var fp := Vector2(float(f[1]), float(f[2]))
		var fc := Color(0.35, 0.55, 1.0) if int(f[0]) == 1 else Color(0.95, 0.3, 0.25)
		draw_line(fp, fp + Vector2(0, -26), Color(0.85, 0.85, 0.85), 2.0)
		draw_colored_polygon(PackedVector2Array([fp + Vector2(1, -26), fp + Vector2(16, -21), fp + Vector2(1, -16)]), fc)
	# Vehicles (simple silhouettes).
	for v in a[4]:
		var vp := Vector2(float(v[1]), float(v[2]))
		var tank := str(v[0]) == "tank"
		var vc := Color(0.45, 0.48, 0.4) if bool(v[4]) else Color(0.2, 0.2, 0.2)
		draw_set_transform(vp, float(v[3]), Vector2.ONE)
		draw_rect(Rect2(-30 if tank else -24, -14, 60 if tank else 48, 14), vc)
		draw_circle(Vector2(-16, 2), 7.0, Color(0.12, 0.12, 0.12))
		draw_circle(Vector2(16, 2), 7.0, Color(0.12, 0.12, 0.12))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
