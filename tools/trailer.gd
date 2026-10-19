extends SceneTree
## Gameplay trailer director (#263; dev tool, never loaded by the game).
## One run = one BEAT of the trailer: a staged bot match (or the Maker /
## LEVELS / menu screens) on a fixed map, mode and seed, filmed by a director
## camera with the HUD hidden. Run it under Godot's Movie Maker mode so every
## frame is rendered at a fixed 60 fps however slow the machine is:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
##       --resolution 1920x1080 --fixed-fps 60 --write-movie OUT/<beat>.avi \
##       -s tools/trailer.gd -- --beat=<beat> --out=OUT --no-perf-guard
## tools/make_trailer.sh runs every beat, renders the title cards, then
## tools/trailer_edit.py picks the best window of each beat from the event
## log and cuts + mixes the MP4s with ffmpeg.
##
## Gameplay beats warm up with the render loop OFF (the match simulates, the
## movie gets cheap copies of a stale frame), watch for the beat's kind of
## highlight (a fight, a jet chase, a rocket in flight, a flag carrier near
## home, a crewed vehicle on the move), then switch rendering on and follow
## the subject for `secs` seconds with a damped spring camera. Every kill,
## explosion, flag event and wreck is logged with its frame number (and
## whether it was on screen) to OUT/<beat>.json; a few full-quality stills
## are saved on the biggest moments (key art).
##
## Other modes:
##   --cards --out=DIR [--url=...]  render the title cards as transparent PNG
##                                  sequences (UI fonts / palette, 60 fps)
##   --list                         print the beat names
##   --smoke                        headless self-test (gate F TRAILER-TEST):
##                                  run two beats briefly without rendering and
##                                  check highlights are picked and logged
##
## Repeatability: every beat sets the global and the cosmetic RNG seeds, fixed
## settings and a fresh user:// (make_trailer.sh), and the soldier animation
## state is reset when rendering starts. The game also reads the wall clock in
## a few AI timers (bot nav penalties), so a beat's exact bot moves can drift
## between machines of very different speed; the edit (beats, cut lengths,
## cards, music) is fixed and the highlight picker re-chooses each window.

const GameLists = preload("res://scripts/game_lists.gd")

const FPS := 60
const DEFAULT_URL := "github.com/Predator04/Tracerfall"

## map: GameLists name · mode: Settings MODE_* index · bots · seed ·
## warm: [min, max] seconds of unrendered warm-up · secs: rendered length ·
## pick: highlight kind · zoom: camera zoom (1 = the game's view) ·
## loadouts: weapon -> share of the bots · vehicle: kind to crew.
const BEATS := {
	"open": {"map": "Vortex", "mode": 2, "bots": 12, "seed": 2631, "warm": [7.0, 30.0], "secs": 8.0,
		"pick": "fight", "zoom": 1.05, "push": 0.08, "loadouts": {"Minigun": 0.2, "LAW": 0.2}},
	"jets": {"map": "Airpirates", "mode": 0, "bots": 10, "seed": 77, "warm": [6.0, 30.0], "secs": 7.0,
		"pick": "jet", "zoom": 1.2, "loadouts": {"Minimi": 0.3, "Steyr AUG": 0.3}},
	"boom": {"map": "Kampf", "mode": 0, "bots": 12, "seed": 4242, "warm": [5.0, 25.0], "secs": 8.0,
		"pick": "boom", "zoom": 1.35, "loadouts": {"LAW": 0.5, "M79": 0.35}},
	"multi": {"map": "Desert", "mode": 1, "bots": 14, "seed": 9001, "warm": [6.0, 25.0], "secs": 8.0,
		"pick": "boom", "zoom": 1.3, "loadouts": {"LAW": 0.3, "M79": 0.2, "Minigun": 0.25}},
	"hd": {"map": "Industrial", "mode": 2, "bots": 10, "seed": 314, "warm": [8.0, 30.0], "secs": 7.0,
		"pick": "fight", "vehicles": false, "zoom": 2.7, "omega": 4.0, "lead": 0.08, "aim_bias": 0.0, "push": 0.06,
		"loadouts": {"Minigun": 0.3, "Spas-12": 0.2, "LAW": 0.2}},
	"night": {"map": "Ruins", "mode": 2, "bots": 12, "seed": 5150, "warm": [7.0, 30.0], "secs": 7.0,
		"pick": "fight", "zoom": 1.4, "loadouts": {"LAW": 0.25, "Flamethrower": 0.2, "Minigun": 0.2}},
	"buggy": {"map": "Moonshine", "mode": 2, "bots": 10, "seed": 808, "warm": [3.0, 25.0], "secs": 6.0,
		"pick": "vehicle", "vehicle": "buggy", "zoom": 1.2},
	"tank": {"map": "Mayapan", "mode": 2, "bots": 10, "seed": 1944, "warm": [3.0, 25.0], "secs": 6.0,
		"pick": "vehicle", "vehicle": "tank", "zoom": 1.15},
	"heli": {"map": "Outpost", "mode": 2, "bots": 10, "seed": 1977, "warm": [4.0, 30.0], "secs": 7.0,
		"pick": "vehicle", "vehicle": "heli", "zoom": 1.0},
	"ctf": {"map": "Niall", "mode": 2, "bots": 12, "seed": 1212, "warm": [4.0, 150.0], "secs": 9.0,
		"pick": "carrier", "zoom": 1.15, "after_capture": 1.6},
	"maker": {"kind": "maker", "seed": 286, "bots": 6, "secs": 11.0},
	"levels": {"kind": "levels", "seed": 288, "secs": 5.0},
	"end": {"kind": "menu", "seed": 1, "secs": 7.0},
}
const ORDER := ["open", "jets", "boom", "multi", "hd", "night", "buggy", "tank", "heli", "ctf", "maker", "levels", "end"]

var _beat := "open"
var _b: Dictionary = {}
var _out := "user://trailer"
var _smoke := false
var _smoke_queue: Array = []
var _smoke_res: Array = []
var _cards := false
var _url := DEFAULT_URL
var _pace_ms := 260          # minimum wall time per RENDERED frame (see _pace)
var _secs_override := -1.0

var _f := 0                  # director frame counter (= movie frame index)
var _phase := "boot"
var _m: Node = null          # main / editor / menu scene
var _cam: Camera2D = null
var _cam_vel := Vector2.ZERO
var _subject: Node2D = null
var _subject_lost_f := -1
var _glide_until := -1
var _trigger := ""
var _warm_f0 := 0
var _render_f0 := -1
var _render_frames := 0
var _events: Array = []
var _stills: Array = []
var _still_due: Array = []   # [frame, tag]
var _last_still_f := -100000
var _proj: Dictionary = {}   # instance id -> [kind, pos, killer]
var _veh_alive: Dictionary = {}
var _track: Array = []       # [frame, screen x 0..1, screen y 0..1] of the subject
var _staged_vehicle: Node2D = null
var _capture_f := -1
var _last_pace_us := 0
var _timeline: Array = []    # scripted beats: [frame, name] marks for the editor
var _gostek = null
var _gfx = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--beat="): _beat = a.substr(7)
		elif a.begins_with("--out="): _out = a.substr(6)
		elif a == "--smoke": _smoke = true
		elif a == "--cards": _cards = true
		elif a.begins_with("--url="): _url = a.substr(6)
		elif a.begins_with("--pace-ms="): _pace_ms = int(a.substr(10))
		elif a.begins_with("--secs="): _secs_override = float(a.substr(7))
		elif a == "--list":
			print("TRAILER beats: ", " ".join(ORDER))
			quit()
			return
	DirAccess.make_dir_recursive_absolute(_out)
	if _smoke:
		_smoke_queue = ["boom", "heli"]
		_pace_ms = 0
		_next_smoke()
	elif not _cards:
		if not BEATS.has(_beat):
			push_error("TRAILER unknown beat %s" % _beat)
			quit(2)
			return
		_b = (BEATS[_beat] as Dictionary).duplicate(true)
		if _secs_override > 0.0:
			_b["secs"] = _secs_override
	print("TRAILER start beat=%s out=%s smoke=%s cards=%s" % [_beat, _out, str(_smoke), str(_cards)])


func _next_smoke() -> void:
	_beat = str(_smoke_queue.pop_front())
	_b = (BEATS[_beat] as Dictionary).duplicate(true)
	_b["secs"] = 3.0
	_b["warm"] = [3.0, 16.0]
	_f = 0
	_phase = "boot"
	_m = null
	_cam = null
	_subject = null
	_trigger = ""
	_render_f0 = -1
	_render_frames = 0
	_events = []
	_proj = {}
	_veh_alive = {}
	_staged_vehicle = null
	_capture_f = -1


# ── Main loop ────────────────────────────────────────────────────────────────

func _process(_d: float) -> bool:
	_f += 1
	var st := root.get_node_or_null("Settings")
	if st == null:
		return false
	if _cards:
		return _cards_tick()
	if _phase == "boot":
		if _f < 2:
			return false
		_boot(st)
		return false
	var kind := str(_b.get("kind", "match"))
	if kind == "maker":
		return _maker_tick()
	if kind == "levels":
		return _levels_tick()
	if kind == "menu":
		return _menu_tick()
	return _match_tick()


func _boot(st: Node) -> void:
	var sd := int(_b.get("seed", 1))
	seed(sd)
	_gfx = load("res://scripts/gfx.gd")
	_gfx.rng.seed = sd
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null and sfx.get("_rng") != null:
		(sfx.get("_rng") as RandomNumberGenerator).seed = sd
	_gostek = load("res://scripts/gostek.gd")
	st.name_set = true
	st.player_name = "Director"
	st.last_seen_version = str(ProjectSettings.get_setting("application/config/version", ""))
	st.visual_style = "cinematic"
	st.soldier_look = "operator"
	st.set_gfx_quality(2)
	st.music_muted = true          # the edit lays the soundtrack under the whole cut
	st.sfx_volume = 0.9
	st.hit_stop = false
	st.screen_shake = false
	st.bot_chatter = false
	st.damage_numbers = false
	st.killcam_replay = false
	st.vehicles = bool(_b.get("vehicles", true))
	st.reduce_motion = false
	st.help_seen = 99
	st.custom_map_path = ""
	st.bot_skill = 4
	var music := root.get_node_or_null("Music")
	if music != null:
		music.apply_volume()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var kind := str(_b.get("kind", "match"))
	if kind == "match":
		st.bot_count = int(_b["bots"])
		st.game_mode = int(_b["mode"])
		st.map_index = maxi(0, GameLists.MAP_NAMES.find(str(_b["map"])))
		root.get_node("Net").set_singleplayer()
		change_scene_to_file("res://scenes/main.tscn")
		_phase = "load"
	elif kind == "maker":
		st.bot_count = int(_b["bots"])
		st.game_mode = 2
		change_scene_to_file("res://scenes/map_editor.tscn")
		_phase = "load"
	elif kind == "levels":
		_levels_boot(st)
	else:
		change_scene_to_file("res://scenes/menu.tscn")
		_phase = "load"
	print("TRAILER boot beat=%s seed=%d" % [_beat, sd])


# ── Gameplay beats ───────────────────────────────────────────────────────────

func _match_tick() -> bool:
	if _phase == "load":
		var m := current_scene
		if m == null or m.get("MAPS") == null or not m.is_node_ready():
			return false
		_m = m
		_setup_match()
		_phase = "warm"
		_warm_f0 = _f
		_set_render(false)
		return false
	if _m == null or not is_instance_valid(_m):
		return _finish("scene lost")
	_hide_clutter()
	_watch_events()
	if _phase == "warm":
		var t := float(_f - _warm_f0) / FPS
		var warm: Array = _b.get("warm", [5.0, 25.0])
		if _staged_vehicle == null and str(_b.get("pick", "")) == "vehicle" and t > 0.5:
			_stage_vehicle()
		if t >= float(warm[0]) and _f % 3 == 0:
			var s := _pick(str(_b.get("pick", "fight")))
			if s != null:
				_trigger = str(_b.get("pick"))
				_start_render(s)
		if _phase == "warm" and t >= float(warm[1]):
			var s2 := _pick("fight")
			if s2 == null:
				s2 = _any_soldier()
			_trigger = "fallback"
			_start_render(s2)
		return false
	# render
	_pace()
	_render_frames += 1
	_update_camera()
	_take_due_stills()
	if _render_frames % 6 == 0 and _subject != null and is_instance_valid(_subject):
		var sp := _screen_of(_subject.global_position)
		_track.append([_f, snappedf(sp.x, 0.001), snappedf(sp.y, 0.001)])
	var n := int(float(_b["secs"]) * FPS)
	_periodic_still(_render_frames, n)
	if _capture_f > 0 and _f - _capture_f >= int(float(_b.get("after_capture", 99.0)) * FPS) and _render_frames >= 5 * FPS:
		return _finish("done")
	if _render_frames >= n:
		return _finish("done")
	return false


## Two extra key-art stills per beat (40 % and 70 % in) besides the event ones.
func _periodic_still(i: int, n: int) -> void:
	if i == int(n * 0.4) or i == int(n * 0.7):
		_still_due.append([_f + 1, "periodic"])
	_take_due_stills()


func _setup_match() -> void:
	var m := _m
	# The director films; nobody plays. The local soldier leaves the match.
	var p = m.get("player")
	if p != null and is_instance_valid(p):
		p.remove_from_group("soldier")
		p.visible = false
		p.process_mode = Node.PROCESS_MODE_DISABLED
		p.queue_free()
		m.set("player", null)
		if m.get("hud") != null and is_instance_valid(m.hud):
			m.hud.set("player", null)
	_cam = Camera2D.new()
	_cam.name = "TrailerCam"
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = int(m.get("MAP_W"))
	_cam.limit_bottom = int(m.get("MAP_H"))
	_cam.zoom = Vector2.ONE * float(_b.get("zoom", 1.0))
	m.add_child(_cam)
	_cam.make_current()
	m.kill.connect(_on_kill)
	m.objective.connect(_on_objective)
	_apply_loadouts()
	_hide_clutter()


func _apply_loadouts() -> void:
	var lo: Dictionary = _b.get("loadouts", {})
	if lo.is_empty():
		return
	var bots: Array = []
	for s in get_nodes_in_group("soldier"):
		if is_instance_valid(s) and s.get("loadout") != null:
			bots.append(s)
	bots.sort_custom(func(a, b) -> bool: return str(a.display_name) < str(b.display_name))
	var i := 0
	for w in lo.keys():
		var n := int(round(float(lo[w]) * bots.size()))
		for _k in n:
			if i >= bots.size():
				break
			_set_loadout(bots[i], str(w))
			i += 1


func _set_loadout(b: Node, w: String) -> void:
	b.set("loadout", w)
	var stats: Dictionary = (b.get_script() as Script).get_script_constant_map().get("AMMO_STATS", {})
	if stats.has(w):
		b.set("ammo", int(stats[w]["mag"]))


## Bots respawn with their roster loadout; keep the beat's mix by re-arming
## new bodies as they appear (same names, so the same shares).
func _rearm_respawns() -> void:
	var lo: Dictionary = _b.get("loadouts", {})
	if lo.is_empty():
		return
	for s in get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or s.get("loadout") == null or s.has_meta("trailer_armed"):
			continue
		s.set_meta("trailer_armed", true)
		var h := absi(hash(str(s.display_name) + _beat)) % 1000
		var acc := 0.0
		for w in lo.keys():
			acc += float(lo[w]) * 1000.0
			if h < acc:
				_set_loadout(s, str(w))
				break


func _hide_clutter() -> void:
	var m := _m
	if m == null:
		return
	var hud = m.get("hud")
	if hud != null and is_instance_valid(hud):
		var ui = hud.get_node_or_null("UIRoot")
		if ui != null:
			ui.visible = false
	if _f % 10 == 0 or _f < 5:
		for l in get_nodes_in_group("item_label"):
			if is_instance_valid(l):
				(l as CanvasItem).visible = false
		_rearm_respawns()
	for n in ["MakerBar", "TouchControls"]:
		var c = m.get_node_or_null(n)
		if c != null:
			c.visible = false


func _stage_vehicle() -> void:
	var kind := str(_b.get("vehicle", "buggy"))
	var v: Node2D = null
	for c in get_nodes_in_group("vehicle"):
		if is_instance_valid(c) and str(c.get("kind")) == kind and bool(c.get("alive")):
			v = c
			break
	if v == null:
		return
	_staged_vehicle = v
	# The two blue bots nearest the vehicle climb in (driver, then gunner).
	var cand: Array = []
	for s in get_nodes_in_group("soldier"):
		if is_instance_valid(s) and s.get("bot_id") != null and not bool(s.get("dead")) and int(s.get("team")) == 1:
			cand.append(s)
	cand.sort_custom(func(a, b) -> bool:
		return (a as Node2D).global_position.distance_to(v.global_position) < (b as Node2D).global_position.distance_to(v.global_position))
	var seats: int = (v.get("seats") as Array).size()
	for i in mini(seats, cand.size()):
		var s: Node2D = cand[i]
		s.global_position = v.global_position + Vector2(0, -20)
		if s is CharacterBody2D:
			(s as CharacterBody2D).velocity = Vector2.ZERO
		_m.vehicle_bot_board(v, s, i)
	print("TRAILER staged %s driver=%s" % [kind, str(v.driver() != null)])


func _start_render(s: Node2D) -> void:
	_subject = s
	_phase = "render"
	_render_f0 = _f
	_set_render(true)
	if _gostek != null:
		(_gostek.get("_states") as Dictionary).clear()   # same animation phase every run
	_cam.global_position = _cam_target()
	_cam_vel = Vector2.ZERO
	_cam.reset_smoothing()
	print("TRAILER render beat=%s trigger=%s subject=%s at_frame=%d warm=%.1fs" % [_beat, _trigger,
		str(s.get("display_name")) if s.get("display_name") != null else str(s.name), _f, float(_f - _warm_f0) / FPS])


func _set_render(on: bool) -> void:
	if not _smoke:
		RenderingServer.render_loop_enabled = on


## Rendered frames take at least _pace_ms of wall time: the soldier animation
## (gostek.gd) steps by real time unless a frame is slower than 250 ms, so
## pacing keeps every rendered frame on its fixed 1/60 s step.
func _pace() -> void:
	if _pace_ms <= 0:
		return
	var now := Time.get_ticks_usec()
	var want := _last_pace_us + _pace_ms * 1000
	if _last_pace_us > 0 and now < want:
		OS.delay_usec(want - now)
	_last_pace_us = Time.get_ticks_usec()


# ── Highlight pickers ────────────────────────────────────────────────────────

func _alive_soldiers() -> Array:
	var out: Array = []
	for s in get_nodes_in_group("soldier"):
		if is_instance_valid(s) and not bool(s.get("dead")) and s.get("team") != null:
			out.append(s)
	return out


func _enemies_near(s: Node2D, r: float) -> int:
	var n := 0
	var team := int(s.get("team"))
	for o in _alive_soldiers():
		if o == s:
			continue
		if team != 0 and int(o.get("team")) == team:
			continue
		if (o as Node2D).global_position.distance_to(s.global_position) < r:
			n += 1
	return n


func _any_soldier() -> Node2D:
	var a := _alive_soldiers()
	return a[0] if not a.is_empty() else null


func _pick(kind: String) -> Node2D:
	match kind:
		"fight":
			var best: Node2D = null
			var bs := 1.5
			for s in _alive_soldiers():
				var t = s.get("target")
				if t == null or not is_instance_valid(t) or _seated(s):
					continue
				var sc := float(_enemies_near(s, 650.0)) + (1.0 if s.get("_target_visible") == true else 0.0)
				if s.has_method("is_on_floor") and s.is_on_floor():
					sc += 0.25
				if sc > bs:
					bs = sc
					best = s
			return best
		"jet":
			for s in _alive_soldiers():
				if not bool(s.get("jet_on")) or not (s is CharacterBody2D):
					continue
				var v := (s as CharacterBody2D).velocity
				if v.length() < 230.0:
					continue
				for o in _alive_soldiers():
					if o == s or int(o.get("team")) == int(s.get("team")) and int(s.get("team")) != 0:
						continue
					var d := (o as Node2D).global_position.distance_to(s.global_position)
					if d < 750.0 and o is CharacterBody2D and not (o as CharacterBody2D).is_on_floor():
						return s
			return null
		"boom":
			for b in get_nodes_in_group("bullet"):
				if not is_instance_valid(b) or not b.has_method("_explode"):
					continue
				var shooter := _soldier_named(str(b.get("killer_name")))
				if shooter == null:
					continue
				var near := 0
				for o in _alive_soldiers():
					if (o as Node2D).global_position.distance_to((b as Node2D).global_position) < 520.0:
						near += 1
				if near >= 3:
					return shooter
			return null
		"carrier":
			for fl in _m.get("flags"):
				if not is_instance_valid(fl):
					continue
				var c = fl.get_meta("carrier", null)
				if c == null or not is_instance_valid(c) or bool(c.get("dead")):
					continue
				# Near the carrier's own base: a capture is coming.
				for home in _m.get("flags"):
					if not is_instance_valid(home) or int(home.get_meta("team", 0)) != int(c.get("team")):
						continue
					var base: Vector2 = home.get_meta("home", (home as Node2D).global_position)
					if (c as Node2D).global_position.distance_to(base) < 1500.0:
						return c
			return null
		"vehicle":
			var v := _staged_vehicle
			if v == null or not is_instance_valid(v) or v.driver() == null:
				return null
			var vel: Vector2 = v.get("velocity") if v.get("velocity") != null else Vector2.ZERO
			if str(v.get("kind")) == "heli":
				# Airborne and on its way (the take-off itself is slow).
				if not (v as CharacterBody2D).is_on_floor() and vel.length() > 140.0:
					return v
				return null
			if vel.length() > 90.0:
				return v
			return null
	return null


func _soldier_named(n: String) -> Node2D:
	if n == "":
		return null
	for s in get_nodes_in_group("soldier"):
		if is_instance_valid(s) and str(s.get("display_name")) == n:
			return s
	return null


# ── Camera ───────────────────────────────────────────────────────────────────

func _cam_target() -> Vector2:
	if _subject == null or not is_instance_valid(_subject):
		return _cam.global_position
	var p := _subject.global_position + Vector2(0, -40 if _subject.get("bot_id") != null else -60)
	var vel := Vector2.ZERO
	if _subject is CharacterBody2D:
		vel = (_subject as CharacterBody2D).velocity
	p += (vel * float(_b.get("lead", 0.22))).limit_length(170.0)
	var t = _subject.get("target")
	var bias := float(_b.get("aim_bias", 0.28))
	if bias > 0.0 and t != null and is_instance_valid(t) and (t as Node2D).global_position.distance_to(_subject.global_position) < 700.0:
		p = p.lerp((t as Node2D).global_position, bias)
	return p


func _subject_gone() -> bool:
	if _subject == null or not is_instance_valid(_subject) or not _subject.is_inside_tree():
		return true
	if _subject.get("dead") == true:
		return true
	if _subject.get("alive") != null and not bool(_subject.get("alive")):
		return true
	# Soldier beats film soldiers: one climbing into a vehicle hands over.
	if str(_b.get("pick", "")) != "vehicle" and _seated(_subject):
		return true
	return false


func _seated(s: Node) -> bool:
	if s.get("bot_id") == null:
		return false
	for v in get_nodes_in_group("vehicle"):
		if is_instance_valid(v) and v.has_method("seat_of") and int(v.seat_of(s)) >= 0:
			return true
	return false


func _update_camera() -> void:
	if _cam == null:
		return
	var dt := 1.0 / FPS
	if _subject_gone():
		if _subject_lost_f < 0:
			_subject_lost_f = _f
		# Hold on the spot for a beat, then glide to the killer / next fight.
		if _f - _subject_lost_f > 40:
			var nxt: Node2D = null
			if _subject != null and is_instance_valid(_subject) and _subject.get("last_killer") != null:
				nxt = _soldier_named(str(_subject.get("last_killer")))
			if nxt == null or bool(nxt.get("dead")) or nxt.global_position.distance_to(_cam.global_position) > 1100.0:
				nxt = _nearest_fight(_cam.global_position)
			if nxt != null:
				_subject = nxt
				_subject_lost_f = -1
				_glide_until = _f + 70
	else:
		_subject_lost_f = -1
	var target := _cam_target()
	# Keep the target where the camera limits let the view centre go, so the
	# spring never winds up past a map edge (that reads as lag coming back).
	var half := root.get_visible_rect().size / _cam.zoom * 0.5
	var lim := Rect2(Vector2(_cam.limit_left, _cam.limit_top) + half,
		Vector2(_cam.limit_right - _cam.limit_left, _cam.limit_bottom - _cam.limit_top) - half * 2.0)
	if lim.size.x > 0.0 and lim.size.y > 0.0:
		target = target.clamp(lim.position, lim.end)
	var w := float(_b.get("omega", 4.2))
	if _f < _glide_until:
		w *= 0.6
	# Critically damped spring: no overshoot, no jitter.
	var acc := (target - _cam.global_position) * w * w - _cam_vel * 2.0 * w
	_cam_vel += acc * dt
	_cam.global_position += _cam_vel * dt
	var k := float(_render_frames) / maxf(1.0, float(_b["secs"]) * FPS)
	var z := float(_b.get("zoom", 1.0)) * (1.0 + float(_b.get("push", 0.04)) * k)
	_cam.zoom = Vector2(z, z)


func _nearest_fight(at: Vector2) -> Node2D:
	var best: Node2D = null
	var bd := INF
	for s in _alive_soldiers():
		if _seated(s):
			continue
		var t = s.get("target")
		var d := (s as Node2D).global_position.distance_to(at)
		if t != null and is_instance_valid(t):
			d *= 0.6
		if d < bd:
			bd = d
			best = s
	return best


func _view_rect() -> Rect2:
	var vs := root.get_visible_rect().size / _cam.zoom
	var c := _cam.get_screen_center_position()
	return Rect2(c - vs * 0.5, vs)


func _screen_of(p: Vector2) -> Vector2:
	var r := _view_rect()
	return (p - r.position) / r.size


func _on_screen(p: Vector2) -> bool:
	return _phase == "render" and _view_rect().grow(-30.0).has_point(p)


# ── Event log ────────────────────────────────────────────────────────────────

func _log_event(kind: String, pos: Vector2, extra: Dictionary = {}) -> void:
	var e := {"f": _f, "kind": kind, "x": roundi(pos.x), "y": roundi(pos.y), "on": _on_screen(pos), "rendering": _phase == "render"}
	e.merge(extra)
	_events.append(e)
	if bool(e["on"]) and _f - _last_still_f > 50 and _stills.size() + _still_due.size() < 8:
		_still_due.append([_f + (5 if kind == "explosion" else 3), kind])
		_last_still_f = _f


func _on_kill(k: String, v: String, w: String, _kt: int, _vt: int) -> void:
	var vn := _soldier_named(v)
	var pos: Vector2 = vn.global_position if vn != null else Vector2.ZERO
	_log_event("kill", pos, {"killer": k, "victim": v, "weapon": w})


func _on_objective(kind: String, team: int, who: String) -> void:
	var s := _soldier_named(who)
	if kind == "capture" and _phase == "render" and _capture_f < 0:
		_capture_f = _f
	_log_event("flag_" + kind, s.global_position if s != null else Vector2.ZERO, {"team": team, "who": who})


func _watch_events() -> void:
	var seen: Dictionary = {}
	for b in get_nodes_in_group("bullet"):
		if is_instance_valid(b) and b.has_method("_explode"):
			seen[b.get_instance_id()] = ["rocket", (b as Node2D).global_position]
	for g in get_nodes_in_group("grenade"):
		if is_instance_valid(g):
			seen[g.get_instance_id()] = ["grenade", (g as Node2D).global_position]
	for id in _proj.keys():
		if not seen.has(id):
			_log_event("explosion", _proj[id][1], {"src": _proj[id][0]})
	_proj = seen
	for v in get_nodes_in_group("vehicle"):
		if not is_instance_valid(v):
			continue
		var id := v.get_instance_id()
		var alive := bool(v.get("alive"))
		if _veh_alive.get(id, alive) and not alive:
			_log_event("wreck", (v as Node2D).global_position, {"vehicle": str(v.get("kind"))})
		_veh_alive[id] = alive


func _take_due_stills() -> void:
	if _smoke:
		_still_due.clear()
		return
	for d in _still_due.duplicate():
		if _f < int(d[0]):
			continue
		_still_due.erase(d)
		_save_still(str(d[1]))


func _save_still(tag: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		return
	var p := _out.path_join("%s_still_%05d_%s.png" % [_beat, _f, tag])
	img.save_png(p)
	_stills.append({"f": _f, "tag": tag, "path": p.get_file()})


func _finish(why: String) -> bool:
	var kills := 0
	var booms := 0
	for e in _events:
		if bool(e.get("rendering")):
			if e["kind"] == "kill":
				kills += 1
			elif e["kind"] == "explosion":
				booms += 1
	var info := {"beat": _beat, "map": str(_b.get("map", "")), "mode": int(_b.get("mode", -1)), "seed": int(_b.get("seed", 0)),
		"fps": FPS, "trigger": _trigger, "render_start": _render_f0, "render_end": _f, "frames": _f,
		"secs": float(_b.get("secs", 0.0)), "events": _events, "stills": _stills, "track": _track, "timeline": _timeline,
		"why": why}
	if not _smoke:
		var f := FileAccess.open(_out.path_join(_beat + ".json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(info, "\t"))
			f.close()
	print("TRAILER done beat=%s why=%s trigger=%s render=%d..%d kills=%d explosions=%d events=%d stills=%d" % [
		_beat, why, _trigger, _render_f0, _f, kills, booms, _events.size(), _stills.size()])
	if _smoke:
		_smoke_res.append({"beat": _beat, "trigger": _trigger, "events": _events.size(), "why": why,
			"staged": _staged_vehicle != null and is_instance_valid(_staged_vehicle) and _staged_vehicle.driver() != null,
			"render_kills": kills, "render_booms": booms})
		if not _smoke_queue.is_empty():
			_next_smoke()   # boots the next beat's match two frames later
			return false
		return _smoke_verdict()
	_set_render(true)
	quit()
	return true


func _smoke_verdict() -> bool:
	var bad: Array = []
	for r in _smoke_res:
		if str(r["why"]) != "done":
			bad.append("%s ended: %s" % [r["beat"], r["why"]])
		if str(r["trigger"]) == "":
			bad.append("%s picked nothing" % r["beat"])
	var boom: Dictionary = _smoke_res[0]
	if str(boom["trigger"]) != "boom":
		bad.append("boom beat fell back (%s)" % boom["trigger"])
	if int(boom["render_booms"]) < 1:
		bad.append("boom beat: no explosion logged while filming")
	var heli: Dictionary = _smoke_res[1]
	if not bool(heli["staged"]) or str(heli["trigger"]) != "vehicle":
		bad.append("heli not crewed / not picked (staged=%s trigger=%s)" % [str(heli["staged"]), heli["trigger"]])
	var summary := " ".join(_smoke_res.map(func(r) -> String: return "%s:%s/ev=%d" % [r["beat"], r["trigger"], r["events"]]))
	if bad.is_empty():
		print("TRAILER-TEST ok ", summary)
	else:
		print("TRAILER-TEST FAIL ", " | ".join(bad), " :: ", summary)
	quit()
	return true


# ── Maker beat: build a level from the palette, press PLAY ──────────────────

## [tab, piece id, world target] — dragged from the palette card one by one.
const MAKER_STEPS := [
	["terrain", "hill", Vector2(2400, 1450)],
	["terrain", "float", Vector2(1640, 1250)],
	["terrain", "float", Vector2(3160, 1250)],
	["terrain", "bridge", Vector2(1600, 1528)],
	["terrain", "bridge", Vector2(3200, 1528)],
	["hazards", "lava", Vector2(1600, 1660)],
	["hazards", "pad_big", Vector2(1240, 1500)],
	["hazards", "crate", Vector2(1080, 1480)],
	["vehicles", "buggy", Vector2(900, 1490)],
]
var _mk = null
var _mstep := 0
var _mt := 0
var _cursor: Control = null
var _cur_pos := Vector2(640, 600)
var _drag_from := Vector2.ZERO
var _drag_to := Vector2.ZERO
var _play_f := -1


class TrailerCursor extends Control:
	var down := false

	func _draw() -> void:
		# Plain arrow pointer, white with a dark rim (the OS cursor isn't captured).
		var s := 1.25
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(0, 22), Vector2(6, 17), Vector2(10, 26),
			Vector2(14, 24), Vector2(10, 15), Vector2(17, 15)])
		for i in pts.size():
			pts[i] *= s
		draw_colored_polygon(pts, Color(0.05, 0.06, 0.08, 0.9))
		var inner := PackedVector2Array()
		var c := Vector2(6, 15) * s
		for p in pts:
			inner.append(c + (p - c) * 0.78)
		draw_colored_polygon(inner, Color(1, 1, 1) if not down else Color(1.0, 0.75, 0.45))
		if down:
			draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 28, Color(1.0, 0.6, 0.3, 0.8), 2.0)


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _card_center(id: String) -> Vector2:
	var cards = _mk.get("_cards")
	if cards == null:
		return Vector2(640, 660)
	for c in cards.get_children():
		if str(c.get("piece")) == id:
			return (c as Control).get_global_rect().get_center()
	return Vector2(640, 660)


func _maker_tick() -> bool:
	if _phase == "load":
		var e := current_scene
		if e == null or e.get("_maker") == null or not e.is_node_ready():
			return false
		_m = e
		_mt += 1
		if _mt < 20:
			return false
		_mk = e.get("_maker")
		_mk.new_map()   # starter map, Grassland theme
		# Strip the starter map back to its three ground strips: we build the rest.
		var pcs: Array = _mk._pieces()
		while pcs.size() > 3:
			pcs.pop_back()
		_mk.commit("")
		_mk.fit_view()
		var c: Camera2D = e.get("_cam")
		c.zoom = Vector2(0.36, 0.36)
		c.position = Vector2(2400, 1390)
		_mk.set_tab("terrain")
		e.queue_redraw()
		var layer := CanvasLayer.new()
		layer.layer = 120
		e.add_child(layer)
		_cursor = TrailerCursor.new()
		_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_cursor)
		_phase = "build"
		_mt = 0
		_mstep = 0
		_render_f0 = _f
		_timeline.append([_f, "build"])
		return false
	if _phase == "build":
		_pace()
		_mt += 1
		var step: Array = MAKER_STEPS[_mstep]
		# 1..10 glide to the card · 11 press · 12..40 drag · 41 release · ..46 rest
		if _mt == 1:
			if _mk.get("tab") != step[0]:
				_mk.set_tab(str(step[0]))
			_drag_from = _cur_pos
		if _mt <= 10:
			var to := _card_center(str(step[1]))
			_cur_pos = _drag_from.lerp(to, _ease(_mt / 10.0))
		elif _mt == 11:
			_cur_pos = _card_center(str(step[1]))
			_drag_from = _cur_pos
			_drag_to = _mk.to_screen(step[2])
			_mk.palette_press(str(step[1]), _cur_pos)
			(_cursor as TrailerCursor).down = true
		elif _mt <= 40:
			var np := _drag_from.lerp(_drag_to, _ease((_mt - 11) / 29.0))
			_mk.palette_motion(np, np - _cur_pos)
			_cur_pos = np
		elif _mt == 41:
			_mk.palette_release(_drag_to)
			(_cursor as TrailerCursor).down = false
			_timeline.append([_f, "placed_" + str(step[1])])
		elif _mt == 44 and _mstep in [5, MAKER_STEPS.size() - 1]:
			_save_still("maker_build")
		elif _mt >= 46:
			_mt = 0
			_mstep += 1
			if _mstep >= MAKER_STEPS.size():
				_phase = "to_play"
				_drag_from = _cur_pos
		_cursor.position = _cur_pos
		_cursor.queue_redraw()
		return false
	if _phase == "to_play":
		_pace()
		_mt += 1
		var btn := _find_play_button()
		var to := btn.get_global_rect().get_center() if btn != null else Vector2(1180, 30)
		_cur_pos = _drag_from.lerp(to, _ease(_mt / 30.0))
		(_cursor as TrailerCursor).down = _mt > 34
		_cursor.position = _cur_pos
		_cursor.queue_redraw()
		if _mt == 34 and btn != null:
			btn.button_pressed = true
		if _mt >= 42:
			_timeline.append([_f, "play"])
			_mk.set("test_mode", 2)
			var ok: bool = _mk.play(true)
			print("TRAILER maker play -> ", ok)
			_phase = "load_match"
			_play_f = _f
		return false
	if _phase == "load_match":
		var m := current_scene
		if m == null or m.get("MAPS") == null or not m.is_node_ready():
			return false
		# Runtime bot nav for the new level: let the worker finish before the
		# match's first tick so it is adopted on the same frame every run
		# (main waits on and adopts the task itself).
		var task := int(m.get("_nav_task"))
		if task >= 0:
			while not WorkerThreadPool.is_task_completed(task):
				OS.delay_msec(2)
		_m = m
		_b["zoom"] = 0.82
		_b["push"] = 0.1
		_setup_match()
		# Stage the fight on the new level's centre: blue on the left bridge /
		# hill, red on the right (this is the first frame of the match).
		var i := 0
		for s in get_nodes_in_group("soldier"):
			if not is_instance_valid(s) or s.get("bot_id") == null:
				continue
			var team := int(s.get("team"))
			var x := (1700.0 + 130.0 * (i % 4)) if team == 1 else (3100.0 - 130.0 * (i % 4))
			var gy: float = m._geom_ground_y(x, 1000.0)
			if gy != INF:
				(s as Node2D).global_position = Vector2(x, gy - 24.0)
			i += 1
		_timeline.append([_f, "match"])
		_phase = "maker_match"
		_render_frames = 0
		_subject = null
		_cam.global_position = Vector2(2400, 1360)
		return false
	# maker_match
	_pace()
	_hide_clutter()
	_watch_events()
	_render_frames += 1
	# A slow push-in on the middle of the level; the fight comes to us.
	var mid := Vector2.ZERO
	var n := 0
	for s in _alive_soldiers():
		if (s as Node2D).global_position.distance_to(Vector2(2400, 1400)) < 1100.0:
			mid += (s as Node2D).global_position
			n += 1
	var want := Vector2(2400, 1360) if n == 0 else Vector2(2400, 1360).lerp(mid / n + Vector2(0, -60), 0.5)
	var w := 2.2
	_cam_vel += ((want - _cam.global_position) * w * w - _cam_vel * 2.0 * w) / FPS
	_cam.global_position += _cam_vel / FPS
	var z := 0.82 * (1.0 + 0.1 * float(_render_frames) / 240.0)
	_cam.zoom = Vector2(z, z)
	if _render_frames == 100:
		_save_still("maker_match")
	if _f - _render_f0 >= int(float(_b["secs"]) * FPS):
		return _finish("done")
	return false


func _find_play_button() -> Button:
	var ui = _mk.get("root")
	if ui == null:
		return null
	for n in (ui as Node).find_children("*", "Button", true, false):
		if (n as Button).text == tr("Play").to_upper():
			return n
	return null


# ── LEVELS beat: the level browser with a populated (fake) server ───────────

var _fake: Node = null
var _lv_ids: Array = []
var _lv_wait := 0


func _levels_boot(st: Node) -> void:
	st.reduce_motion = false
	st.level_bookmarks = []
	st.game_mode = 2
	_fake = load("res://tools/levels_fake_master.gd").new()
	root.add_child(_fake)
	_fake.start()
	st.master_url = _fake.url()
	_phase = "seed"
	_levels_seed.call_deferred(st)


func _levels_seed(st: Node) -> void:
	var api: Node = load("res://scripts/levels_api.gd").new()
	root.add_child(api)
	var mapio = load("res://scripts/map_io.gd")
	var gen = load("res://scripts/map_gen.gd")
	var classic := func(stem: String) -> Dictionary:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/%s.json" % stem))
		return d if d is Dictionary else {}
	var editor_map := func(sd: int) -> Dictionary:
		var d = JSON.parse_string(mapio.map_to_json(gen.generate(sd)))
		return d if d is Dictionary else {}
	var samples := [
		["Frostbite Fortress", "Nyx", classic.call("icebeam"), "snow", 1840, 312, 30],
		["Rooftop Rumble", "Kestrel", editor_map.call(41), "urban", 960, 205, 50],
		["Sandstorm Siege", "Dune", classic.call("desert"), "desert", 2210, 188, 140],
		["Jungle Gym", "Moss", classic.call("jungle"), "jungle", 530, 141, 12],
		["Tower of Pain", "Ace", editor_map.call(7), "rock", 120, 37, 3],
		["Voland Heights", "Rook", classic.call("voland"), "rock", 3120, 402, 300],
		["Ruins of Ash", "Ember", classic.call("ash"), "ruins", 760, 96, 70],
		["Bunker Busters", "Tank", classic.call("bunker"), "urban", 410, 58, 20],
		["Sky Bridges", "Wren", editor_map.call(1234), "", 44, 9, 1],
		["Lava Lamp", "Cinder", editor_map.call(2026), "", 690, 120, 8],
	]
	for s in samples:
		var res := []
		api.upload(s[0], s[1], s[2], s[3], func(ok: bool, d: Dictionary, _e: String) -> void: res.append(d if ok else {}))
		while res.is_empty():
			await process_frame
		var id := str(res[0].get("id", ""))
		_lv_ids.append(id)
		if _fake.levels.has(id):
			var e: Dictionary = _fake.levels[id]
			e["plays"] = int(s[4])
			for i in int(s[5]):
				e["likers"]["p%d" % i] = true
			e["likes"] = int(s[5])
			# Fixed "uploaded N hours ago" against a fixed clock: same cards every run.
			e["up"] = int(Time.get_unix_time_from_system() * 1000.0) - int(s[6]) * 3600000
	change_scene_to_file("res://scenes/menu.tscn")
	_phase = "menu_load"


func _levels_tick() -> bool:
	if _phase == "seed":
		return false
	if _phase == "menu_load":
		var m := current_scene
		if m == null or not m.has_method("_open_levels") or not m.is_node_ready():
			return false
		_m = m
		_lv_wait += 1
		if _lv_wait < 30:
			return false
		m._open_levels("hot")
		_phase = "levels_load"
		return false
	var pn: Node = _m.get("_levels_panel")
	if _phase == "levels_load":
		if pn == null or int(pn.get("loaded")) < 0:
			return false
		_phase = "levels"
		_render_f0 = _f
		_timeline.append([_f, "levels"])
		var layer := CanvasLayer.new()
		layer.layer = 120
		_m.add_child(layer)
		_cursor = TrailerCursor.new()
		_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_cursor)
		_cur_pos = Vector2(980, 640)
		_drag_from = _cur_pos
		return false
	_pace()
	var t := _f - _render_f0
	# Glide to the first card, click it (detail panel opens), drift to PLAY.
	var card := _level_card(_lv_ids[5] if _lv_ids.size() > 5 else "")
	var card_pos := card.get_global_rect().get_center() if card != null else Vector2(400, 300)
	if t <= 50:
		_cur_pos = _drag_from.lerp(card_pos, _ease(t / 50.0))
	elif t == 56:
		pn.select(_lv_ids[5])
		_timeline.append([_f, "select"])
		_drag_from = _cur_pos
	elif t > 80 and t <= 140:
		var play := _find_button_text(pn, tr("PLAY"))
		var to := play.get_global_rect().get_center() if play != null else _cur_pos
		_cur_pos = _drag_from.lerp(to, _ease((t - 80) / 60.0))
	(_cursor as TrailerCursor).down = t >= 50 and t < 60
	_cursor.position = _cur_pos
	_cursor.queue_redraw()
	if t == 110:
		_save_still("levels")
	if t >= int(float(_b["secs"]) * FPS):
		return _finish("done")
	return false


func _level_card(id: String) -> Control:
	var pn: Node = _m.get("_levels_panel")
	if pn == null:
		return null
	var cards = pn.get("_cards")
	if cards is Dictionary and (cards as Dictionary).has(id) and is_instance_valid(cards[id]):
		return cards[id]
	return null


func _find_button_text(from: Node, text: String) -> Button:
	for n in from.find_children("*", "Button", true, false):
		if (n as Button).text.strip_edges().to_upper() == text.to_upper() and (n as Control).is_visible_in_tree():
			return n
	return null


# ── End card backdrop: the menu's animated sky, everything else hidden ──────

func _menu_tick() -> bool:
	if _phase == "load":
		var m := current_scene
		if m == null or not m.is_node_ready():
			return false
		_m = m
		_mt += 1
		if _mt < 3:
			return false
		for c in m.get_children():
			if c.name == "MenuBackdrop":
				continue
			if c is CanvasItem:
				(c as CanvasItem).visible = false
			elif c is CanvasLayer:
				(c as CanvasLayer).visible = false
		var bd = m.get_node_or_null("MenuBackdrop")
		if bd != null and bd.get("_rng") != null:
			(bd.get("_rng") as RandomNumberGenerator).seed = int(_b.get("seed", 1))
		_phase = "show"
		_render_f0 = _f
		return false
	_pace()
	if _f - _render_f0 >= int(float(_b["secs"]) * FPS):
		return _finish("done")
	return false


# ── Title cards: transparent PNG sequences in the game's UI type ────────────

## Each card: name, size, seconds (still = one frame), logo + lines
## ([text, font kind, px size, colour, y as a share of the height, delay s]).
## Rendered on a transparent SubViewport; trailer_edit.py overlays them.
var _card_list: Array = []
var _card_i := 0
var _card_frame := 0
var _card_vp: SubViewport = null
var _card_node: Control = null
var _card_pending := -1


class TitleCard extends Control:
	var lines: Array = []
	var logo := false
	var logo_y := 0.42
	var logo_px := 0
	var dur := 3.0
	var t := 0.0
	var band := 0.0          # opacity of the soft dark band behind the type
	var band_y := 0.5
	var band_h := 0.36
	var fade_out := true

	func _env(delay: float) -> float:
		var a := clampf((t - delay) / 0.35, 0.0, 1.0)
		var b := clampf((dur - t) / 0.4, 0.0, 1.0) if fade_out else 1.0
		return a * a * (3.0 - 2.0 * a) * b

	func _draw() -> void:
		var UT = load("res://scripts/ui_theme.gd")
		var k := _env(0.0)
		if band > 0.0:
			# Soft dark band behind the type so it reads over any footage.
			# One vertex-coloured strip (no per-row rects: they band).
			var h := size.y * band_h
			var y0 := size.y * band_y - h * 0.5
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			var rows := 12
			for i in rows + 1:
				var f := float(i) / rows
				var a := sqrt(1.0 - absf(f - 0.5) * 2.0) * band * k
				pts.append(Vector2(0, y0 + h * f))
				pts.append(Vector2(size.x, y0 + h * f))
				cols.append(Color(0.015, 0.02, 0.035, a))
				cols.append(Color(0.015, 0.02, 0.035, a))
			for i in rows:
				var q := PackedVector2Array([pts[i * 2], pts[i * 2 + 1], pts[i * 2 + 3], pts[i * 2 + 2]])
				var qc := PackedColorArray([cols[i * 2], cols[i * 2 + 1], cols[i * 2 + 3], cols[i * 2 + 2]])
				draw_polygon(q, qc)
		if logo:
			_draw_logo(UT, size.y * logo_y)
		for l in lines:
			var font: Font = UT.font(str(l[1]))
			var fs := int(l[2])
			var col: Color = l[3]
			var delay := float(l[5]) if l.size() > 5 else 0.0
			var kk := _env(delay)
			var sp := _spaced(str(l[0]), font, fs)
			var w: float = sp[1]
			var rise := (1.0 - _ease(clampf((t - delay) / 0.45, 0.0, 1.0))) * fs * 0.25
			var at := Vector2((size.x - w) * 0.5, size.y * float(l[4]) + rise)
			_draw_spaced(sp[0], font, fs, at, Color(0, 0, 0, 0.8 * kk), maxi(3, fs / 14))
			_draw_spaced(sp[0], font, fs, at, Color(col, col.a * kk), 0)

	func _ease(x: float) -> float:
		return 1.0 - pow(1.0 - x, 3.0)

	func _spaced(txt: String, font: Font, fs: int) -> Array:
		var track := fs * 0.06
		var xs: Array = []
		var x := 0.0
		for ch in txt:
			xs.append([ch, x])
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + track
		return [xs, maxf(0.0, x - track)]

	func _draw_spaced(xs: Array, font: Font, fs: int, at: Vector2, col: Color, outline: int) -> void:
		for c in xs:
			var p := at + Vector2(float(c[1]), 0)
			if outline > 0:
				draw_string_outline(font, p, str(c[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, col)
			else:
				draw_string(font, p, str(c[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _draw_logo(UT, cy: float) -> void:
		# The menu wordmark (menu_logo.gd) at trailer scale: TRACER off-white,
		# FALL ember, neon edge, a tracer round streaking under it that leaves
		# an ember underline.
		var font: Font = UT.font("logo")
		var fs := logo_px
		var a := "TRACER"
		var b := "FALL"
		var wa := font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var wb := font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var total := wa + wb
		var x0 := (size.x - total) * 0.5
		var base := cy + fs * 0.34
		var k := _env(0.0)
		var rise := (1.0 - _ease(clampf(t / 0.5, 0.0, 1.0))) * fs * 0.12
		var pa := Vector2(x0, base + rise)
		var pb := Vector2(x0 + wa, base + rise)
		var s := fs / 78.0
		for o in [[16.0, 0.06], [7.0, 0.14]]:
			draw_string_outline(font, pa, a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(float(o[0]) * s), Color(UT.COL_NEON, float(o[1]) * k))
			draw_string_outline(font, pb, b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(float(o[0]) * s), Color(UT.COL_ACCENT, float(o[1]) * k))
		draw_string_outline(font, pa, a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * s), Color(0, 0, 0, 0.75 * k))
		draw_string_outline(font, pb, b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * s), Color(0, 0, 0, 0.75 * k))
		draw_string(font, pa, a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UT.COL_TEXT, k))
		draw_string(font, pb, b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UT.COL_ACCENT, k))
		var ly := base + 14.0 * s
		var lx0 := x0 - 30.0 * s
		var lx1 := x0 + total + 30.0 * s
		var p := _ease(clampf((t - 0.15) / 0.75, 0.0, 1.0))
		var head := lerpf(lx0, lx1, p)
		if p <= 0.0:
			return
		var segs := 40
		for i in segs:
			var u0 := float(i) / segs
			var u1 := float(i + 1) / segs
			var xa := lerpf(lx0, lx1, u0)
			var xb := lerpf(lx0, lx1, u1)
			if xa > head:
				break
			var al := clampf(minf(u0, 1.0 - u1) * 6.0, 0.0, 1.0) * 0.85 * k
			draw_line(Vector2(xa, ly), Vector2(minf(xb, head), ly), Color(UT.COL_ACCENT, al), 2.0 * s)
		if p < 1.0:
			for j in 10:
				var tl := float(j) * 7.0 * s
				draw_line(Vector2(head - tl - 7.0 * s, ly), Vector2(head - tl, ly),
					Color(1.0, 0.92, 0.7, (1.0 - j / 10.0) * k), (3.0 - j * 0.2) * s)
			draw_circle(Vector2(head, ly), 3.5 * s, Color(1, 1, 0.9, k))


func _card_defs() -> Array:
	var UT = load("res://scripts/ui_theme.gd")
	var txt: Color = UT.COL_TEXT
	var acc: Color = UT.COL_ACCENT
	var dim: Color = UT.COL_TEXT_DIM
	var neon: Color = UT.COL_NEON
	var modes := GameLists.MODE_NAMES.size()
	var maps := GameLists.MAP_NAMES.size()
	var credit := "MUSIC: \"NECROMANCIDE\" BY MARSHALL ANDERSON  (CC BY 4.0)"
	return [
		# 16:9 trailer
		{"name": "title", "w": 1920, "h": 1080, "dur": 3.8, "logo": true, "logo_y": 0.45, "logo_px": 190,
			"band": 0.55, "band_y": 0.5, "lines": [["2D JETPACK SHOOTER", "caps", 40, Color(txt, 0.9), 0.64, 0.7]]},
		{"name": "ultrahd", "w": 1920, "h": 1080, "dur": 2.9, "band": 0.5, "band_y": 0.8, "band_h": 0.3, "lines": [
			["ULTRA HD", "display", 120, txt, 0.82, 0.0],
			["SOLDIERS  ·  WEAPONS  ·  TERRAIN  ·  DYNAMIC LIGHTING", "caps", 32, acc, 0.9, 0.25]]},
		{"name": "maker", "w": 1920, "h": 1080, "dur": 3.0, "band": 0.5, "band_y": 0.8, "band_h": 0.3, "lines": [
			["BUILD YOUR OWN LEVELS", "display", 104, txt, 0.82, 0.0],
			["MAKER MODE  ·  SHARE AND PLAY THEM IN LEVELS", "caps", 32, acc, 0.9, 0.25]]},
		{"name": "online", "w": 1920, "h": 1080, "dur": 2.6, "band": 0.5, "band_y": 0.83, "band_h": 0.24, "lines": [
			["ONLINE  ·  BOTS  ·  %d MODES  ·  %d MAPS" % [modes, maps], "display", 72, txt, 0.86, 0.0]]},
		{"name": "end", "w": 1920, "h": 1080, "dur": 6.0, "logo": true, "logo_y": 0.37, "logo_px": 180, "fade": false, "lines": [
			["FREE  —  WINDOWS & ANDROID", "display", 76, txt, 0.6, 0.5],
			[_url, "caps", 40, neon, 0.69, 0.9],
			[credit, "caps", 20, Color(dim, 0.85), 0.94, 1.2]]},
		# 9:16 cut: header + footer frame the 1080x1080 picture (y 440..1520)
		{"name": "v_head", "w": 1080, "h": 1920, "dur": 30.0, "still": true, "logo": true, "logo_y": 0.105, "logo_px": 150,
			"lines": [["2D JETPACK SHOOTER", "caps", 34, Color(txt, 0.9), 0.175, 0.0]]},
		{"name": "v_foot", "w": 1080, "h": 1920, "dur": 30.0, "still": true, "lines": [
			["FREE  —  WINDOWS & ANDROID", "display", 64, txt, 0.865, 0.0],
			[_url, "caps", 34, neon, 0.915, 0.0]]},
		{"name": "v_end", "w": 1080, "h": 1920, "dur": 3.6, "logo": true, "logo_y": 0.44, "logo_px": 165, "fade": false,
			"band": 0.85, "band_y": 0.5, "band_h": 1.2, "lines": [
			["FREE  —  WINDOWS & ANDROID", "display", 64, txt, 0.56, 0.4],
			[_url, "caps", 34, neon, 0.61, 0.7],
			[credit, "caps", 18, Color(dim, 0.85), 0.95, 0.9]]},
		# itch.io cover overlay (630x500)
		{"name": "cover", "w": 630, "h": 500, "dur": 30.0, "still": true, "logo": true, "logo_y": 0.74, "logo_px": 92,
			"band": 0.75, "band_y": 0.84, "band_h": 0.42,
			"lines": [["FREE  ·  WINDOWS & ANDROID", "caps", 20, Color(txt, 0.95), 0.94, 0.0]]},
	]


func _cards_tick() -> bool:
	if _card_vp == null:
		_card_list = _card_defs()
		_card_vp = SubViewport.new()
		_card_vp.transparent_bg = true
		_card_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(_card_vp)
		_card_i = 0
		_card_frame = 0
		_new_card()
		return false
	# The viewport drew last frame's state: save it, then advance.
	if _card_pending >= 0:
		var c: Dictionary = _card_list[_card_i]
		var img := _card_vp.get_texture().get_image()
		img.save_png(_out.path_join("card_" + str(c["name"])).path_join("f_%04d.png" % _card_pending))
		_card_frame += 1
		var frames := 1 if bool(c.get("still", false)) else int(float(c["dur"]) * FPS)
		if _card_frame >= frames:
			print("TRAILER card %s frames=%d" % [c["name"], _card_frame])
			_card_i += 1
			if _card_i >= _card_list.size():
				quit()
				return true
			_card_frame = 0
			_new_card()
			return false
	var cn := _card_node as TitleCard
	cn.t = 2.0 if bool(_card_list[_card_i].get("still", false)) else float(_card_frame) / FPS
	cn.queue_redraw()
	_card_pending = _card_frame
	return false


func _new_card() -> void:
	if _card_node != null:
		_card_node.queue_free()
	var c: Dictionary = _card_list[_card_i]
	DirAccess.make_dir_recursive_absolute(_out.path_join("card_" + str(c["name"])))
	_card_vp.size = Vector2i(int(c["w"]), int(c["h"]))
	var n := TitleCard.new()
	n.size = Vector2(float(c["w"]), float(c["h"]))
	n.dur = float(c["dur"])
	n.logo = bool(c.get("logo", false))
	n.logo_y = float(c.get("logo_y", 0.45))
	n.logo_px = int(c.get("logo_px", 160))
	n.band = float(c.get("band", 0.0))
	n.band_y = float(c.get("band_y", 0.5))
	n.band_h = float(c.get("band_h", 0.36))
	n.fade_out = bool(c.get("fade", true)) and not bool(c.get("still", false))
	n.lines = c["lines"]
	_card_vp.add_child(n)
	_card_node = n
	_card_pending = -1
