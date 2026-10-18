extends SceneTree
## Dev-only staged vehicle capture (#276 / #277, not part of the gate): parks
## the buggy, the tank and (when the build has one) the helicopter side by side
## on a flat stretch and saves real renders of a scripted sequence, so the same
## run makes before / after pairs on an older build.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 \
##     -s tools/vehicle_stage.gd -- --out=DIR --shot=parked|damage|wreck|drive|tank|heli [--style=classic] [--q=2] [--noheli] [--zoom=1.6]
## Uses only the vehicle API both builds share (seats, request_enter, take_damage,
## apply_hp, _host_destroy, _fire, _make_vehicle).
var _out := "."
var _shot := "parked"
var _style := "cinematic"
var _q := 2
var _zoom := 1.6
var _noheli := false
var _anchor_heli := false   # --anchor=heli: line up next to the map's own heli pad
var _map := 94
var _n := 0
var _t := -1
var _cam: Camera2D = null
var _veh: Array = []      # [buggy, tank, heli?]
var _x0 := 0.0
var _gy := 0.0
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--shot="): _shot = a.substr(7)
		elif a.begins_with("--style="): _style = a.substr(8)
		elif a.begins_with("--q="): _q = int(a.substr(4))
		elif a.begins_with("--zoom="): _zoom = float(a.substr(7))
		elif a.begins_with("--map="): _map = int(a.substr(6))
		elif a == "--noheli": _noheli = true
		elif a == "--anchor=heli": _anchor_heli = true


func _save(tag: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_out, _shot, tag])
	print("VSTAGE saved %s_%s" % [_shot, tag])


func _ground(main: Node, x: float, from_y: float) -> float:
	return float(main._geom_ground_y(x, from_y))


func _process(_d: float) -> bool:
	_n += 1
	var st = root.get_node_or_null("Settings")
	if st == null:
		return false
	if _n == 2:
		st.bot_count = 0
		st.game_mode = 0
		st.map_index = _map
		st.custom_map_path = ""
		st.name_set = true
		st.vehicles = true
		st.visual_style = _style
		st.set_gfx_quality(_q)
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		return false
	var m = current_scene
	if m == null or m.get("player") == null or not is_instance_valid(m.player):
		return false
	if _n < 160:
		return false
	var p = m.player
	p.set("ceasefire_t", 9999.0)
	if _cam == null:
		_setup(m)
		_t = 0
		return false
	_t += 1
	if _t % 50 == 0:
		print("VSTAGE t=%d ms=%d" % [_t, Time.get_ticks_msec()])
	_run(m, p)
	if _done:
		quit()
		return true
	if _t > 2400:
		print("VSTAGE timeout")
		quit()
		return true
	return false


func _setup(m: Node) -> void:
	var vs: Array = []
	for v in get_nodes_in_group("vehicle"):
		vs.append(v)
	var buggy = null
	var tank = null
	for v in vs:
		if str(v.get("kind")) == "buggy" and buggy == null:
			buggy = v
		elif str(v.get("kind")) == "tank" and tank == null:
			tank = v
	var sp: Vector2 = tank.global_position if tank != null else m.player.global_position
	_x0 = sp.x - 260.0
	for v in vs:
		if _anchor_heli and str(v.get("kind")) == "heli":
			sp = (v as Node2D).global_position
			_x0 = sp.x - 470.0
	_gy = _ground(m, sp.x, sp.y - 80.0)
	var sys = m.get("_vehicles_sys")
	var want := [["buggy", _x0], ["tank", _x0 + 200.0]]
	if not _noheli:
		want.append(["heli", _x0 + (800.0 if _shot in ["drive", "tank"] else 470.0)])
	var id := 90
	for w in want:
		var gx: float = w[1]
		var gy := _ground(m, gx, _gy - 160.0)
		var v = sys._make_vehicle(id, Vector2(gx, gy - 4.0), Vector2(gx, gy - 4.0), -1.0, true, w[0])
		_veh.append(v)
		id += 1
	# Park the map's own vehicles far away so they don't wander into view.
	for v in vs:
		(v as Node2D).global_position = Vector2(60.0, -4000.0)
		v.set_physics_process(false)
		(v as Node2D).visible = false
	m.player.global_position = Vector2(_x0 - 160.0, _gy - 30.0)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(_zoom, _zoom)
	m.add_child(_cam)
	_cam.global_position = Vector2(_x0 + 230.0, _gy - 90.0)
	_cam.make_current()
	var hud = m.get("hud")
	if hud != null:
		hud.visible = false


func _enter(p: Node, v: Node) -> void:
	(p as Node2D).global_position = (v as Node2D).global_position + Vector2(-8, -12)
	p.set("velocity", Vector2.ZERO)
	v.request_enter(p)


func _run(m: Node, p: Node) -> void:
	match _shot:
		"parked":
			if _t == 90:
				_save("a")
				_done = true
		"damage":
			if _t == 10:
				var fr := [0.42, 0.18, 0.4]
				for i in _veh.size():
					var v = _veh[i]
					v.apply_hp(float(v.get("MAX_HP")) * fr[i])
			if _t == 150:
				_save("a")
			if _t == 175:
				_save("b")
				_done = true
		"wreck":
			if _t == 10:
				for v in _veh:
					v._host_destroy("", -1)
			if _t == 26:
				_save("a_blast")
			if _t == 150:
				_save("b_burning")
			if _t == 760:
				_save("c_husk")
				_done = true
		"drive":
			var b = _veh[0]
			if _t == 5:
				_enter(p, b)
			if _t == 30:
				Input.action_press("move_right")
			if _t > 30:
				_cam.global_position = (b as Node2D).global_position + Vector2(40, -60)
			if _t == 70:
				_save("a")
			if _t >= 60 and _t <= 120 and b.has_method("_fire"):
				b.set("aim_dir", Vector2(1, -0.45).normalized())
				if float(b.get("fire_cd")) <= 0.0:
					b._fire(p)
			if _t == 96:
				_save("b_firing")
			if _t == 118:
				Input.action_release("move_right")
				_done = true
		"tank":
			var tk = _veh[1]
			if _t == 5:
				_enter(p, tk)
			if _t == 40:
				Input.action_press("move_right")
			if _t > 40:
				_cam.global_position = (tk as Node2D).global_position + Vector2(60, -60)
			if _t == 100:
				_save("a_moving")
				Input.action_release("move_right")
			if _t == 120:
				tk.set("aim_dir", Vector2(1, -0.25).normalized())
				tk._fire(p)
			if _t == 123:
				_save("b_fire")
			if _t == 132:
				_save("c_recoil")
				_done = true
		"heli":
			_run_heli(m, p)
		_:
			_done = true


func _run_heli(m: Node, p: Node) -> void:
	if _veh.size() < 3:
		_done = true
		return
	var h = _veh[2]
	var hp0: Vector2 = (h as Node2D).global_position
	if _t == 5:
		_enter(p, h)
	if _t == 20:
		_save("a_spinup")
	if _t == 75:
		Input.action_press("jump")
	if _t > 75:
		_cam.global_position = (h as Node2D).global_position + Vector2(20, 40)
	if _t == 100:
		_save("b_liftoff_wash")
	if _t == 150:
		Input.action_release("jump")
		Input.action_press("move_right")
	if _t == 190:
		_save("c_flying")
	if _t == 205:
		Input.action_release("move_right")
		if h.has_method("_fire_rockets"):
			h._fire_rockets(p)
	if _t == 210:
		_save("d_rockets")
	if _t == 222:
		_save("d2_rockets")
	if _t == 240:
		h.apply_hp(float(h.get("MAX_HP")) * 0.2)
	if _t == 330:
		_save("e_damaged")
	if _t == 340:
		h.take_damage(99999.0, "QA", "LAW", 77)
	if _t > 340 and _t < 700:
		_cam.global_position = (h as Node2D).global_position + Vector2(0, -40)
	if _t == 370:
		_save("f_spinout")
	if bool(h.get("alive")) == false and get_meta("dead_t", -1) == -1:
		set_meta("dead_t", _t)
	if get_meta("dead_t", -1) != -1 and _t == int(get_meta("dead_t")) + 8:
		_save("g_wreck")
	if get_meta("dead_t", -1) != -1 and _t == int(get_meta("dead_t")) + 200:
		_save("h_husk")
		_done = true
