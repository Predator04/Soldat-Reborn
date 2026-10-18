extends PanelContainer
## Training — a short guided first match (main menu -> TRAINING).
##
## Runs on Arena2 in Deathmatch with no bots. Each step waits for the player
## to actually do the thing (move, jump, jet, shoot, reload, switch weapon,
## throw a grenade, crouch), then one easy bot joins for the final step.
## The match settings it overrides are restored when the scene exits.
## Key names come from the live bindings (touch devices get button names).
##
## Phase 2 (#262): the movement course — "Now the moves that make a pro".
## After the shooting steps Training loads the Movement Course micro-map
## (scripts/movement_course.gd) and runs its gates with the same step system:
## tap hop under spikes, a wider hop, a held full jump, a prone-cancel drop
## into a ring and a timed bunny-hop lane. Falling or touching the spikes
## resets you to the section start (no death). Finishing shows the total
## time; the best time is kept in Stats, and RELOAD runs it again. The menu's
## MOVEMENT COURSE button starts phase 2 directly.

const ControlsMap = preload("res://scripts/controls_map.gd")
const Course = preload("res://scripts/movement_course.gd")

var main: Node
var _step := 0
var _t := 0.0
var _done_t := -1.0
var _moved := 0.0
var _last_x := INF
var _jet_t := 0.0
var _shots := 0
var _start_weapon := -1
var _start_kills := 0
var _held: Dictionary = {}
var _title: Label
var _body: Label
var _prog: Label
var _live: Label
var _saved: Dictionary = {}
var _steps: Array = STEPS
# Movement course (#262).
var _course := false          # this overlay runs the movement course
var _handoff := false         # phase 1 -> 2 scene change: keep the training settings
var _phase2_t := -1.0         # phase 1 finished; loading the course at this _t
var _c_t0 := -1.0             # course clock start (first move)
var _c_end := -1.0            # course finished (total time in s), -1 = running
var _body_id := 0             # player node we last saw (respawn -> back to the section)
var _resets := 0
var _drop_air := false
var _drop_prone := false
var _lane_t0 := -1.0
var _lane_speed: PackedFloat32Array = PackedFloat32Array()   # |vx| history across the lane
var _lane_air: Array = []

const PHASE2_DELAY := 4.0

const STEPS := [
	["MOVE", "Run left and right with %s / %s.", ["move_left", "move_right"]],
	["JUMP", "Jump with %s. Tip: jumping again as you land keeps your speed (bunny hop).", ["jump"]],
	["JET BOOTS", "Hold %s in the air to fly. The blue JET bar drains while you fly and refills on the ground.", ["jet"]],
	["SHOOT", "Aim and fire with %s. Fire 5 shots.", ["fire"]],
	["RELOAD", "Reload with %s. The yellow bar is your magazine.", ["reload"]],
	["SWITCH WEAPON", "Pick another gun with the number keys (%s = Deagles … %s = Minigun), or swap to your pistol with %s.", ["weapon_1", "weapon_10", "secondary_swap"]],
	["GRENADE", "Throw a grenade with %s. Holding it pulls the pin and throws harder — but the fuse is burning (ring over your head). Hold it too long and it goes off in your hand!", ["grenade"]],
	["CROUCH", "Crouch with %s — smaller target, steadier aim. %s lies prone.", ["crouch", "prone"]],
	["FIGHT", "A training bot has joined. Take it down!", []],
]

## Movement course steps, in Course.S_* order: [title, body, done note].
## Bodies use {jump} / {prone} / {right} / {limit} placeholders; every string
## goes through tr() (assets/i18n/ui.csv).
const COURSE_STEPS := [
	["SHORT HOP", "Tap {jump} to hop the gap under the spikes. A quick tap is a short hop; holding jump makes a full jump, straight into them. (Jets are off on this course.)", "Tap = short hop."],
	["WIDER HOP", "Run and tap {jump} again: a hop clears this wider gap too. Jump close to the edge.", "A hop carries further than it looks."],
	["FULL JUMP", "Too far for a hop. Hold {jump} through the whole jump for full height and distance, and take off near the edge.", "Hold = full jump."],
	["PRONE DROP", "Run off the ledge holding {right}, then press {prone} in mid-air. Going prone drops you faster, so you land in the yellow ring instead of past it.", "Prone in the air = drop short."],
	["BUNNY HOP", "Cross the lane, green post to yellow, in {limit} s. Running is too slow: jump again the moment you land ({jump}) and keep holding {right} to carry your speed.", "Chained hops keep your speed."],
]


static func start_training(course: bool = false) -> void:
	## Called from the menu: remember the player's match settings, set up the
	## training match and load it. main.gd builds the overlay when it sees
	## Settings.training. course = straight to the movement course (#262).
	Settings.training_saved = {
		"game_mode": Settings.game_mode, "map_index": Settings.map_index,
		"custom_map_path": Settings.custom_map_path, "bot_count": Settings.bot_count,
		"bot_skill": Settings.bot_skill, "survival": Settings.survival,
		"realistic": Settings.realistic, "advance": Settings.advance,
	}
	Settings.training = true
	Settings.training_course = false
	Settings.game_mode = 0
	# #250: was a hardcoded index 19 — the map list order evolves, so find
	# Arena2 by name and keep whatever the player had if it's ever missing.
	var arena2_idx: int = Net.MAP_NAMES.find("Arena2")
	if arena2_idx >= 0:
		Settings.map_index = arena2_idx
	Settings.custom_map_path = ""
	Settings.bot_count = 0
	Settings.bot_skill = 1
	Settings.survival = false
	Settings.realistic = false
	Settings.advance = false
	if course:
		_use_course()


## Point the next match at the movement course (inside a Training session).
static func _use_course() -> void:
	Settings.training_course = true
	Settings.game_mode = 0
	Settings.bot_count = 0
	Settings.custom_map_path = Course.PATH


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.hud_strip_style())
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_prog = Label.new()
	_prog.add_theme_font_size_override("font_size", 12)
	_prog.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	box.add_child(_prog)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", UITheme.COL_ACCENT)
	box.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(520, 0)
	_body.add_theme_font_size_override("font_size", 15)
	_body.add_theme_color_override("font_color", UITheme.COL_TEXT)
	box.add_child(_body)
	_live = Label.new()
	_live.add_theme_font_size_override("font_size", 14)
	_live.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_live.visible = false
	box.add_child(_live)
	tree_exiting.connect(_restore)
	_course = bool(Settings.training_course)
	if _course:
		_steps = COURSE_STEPS
		_body.custom_minimum_size = Vector2(380, 0)
	_show_step()


func _touch() -> bool:
	return OS.has_feature("android") or OS.has_feature("mobile") \
		or DisplayServer.is_touchscreen_available() or "--force-touch" in OS.get_cmdline_user_args()


func _key(action: String) -> String:
	if _touch():
		var names := {"move_left": "the left stick", "move_right": "the left stick", "jump": "the left stick (push up)",
			"jet": "JET", "fire": "the right side of the screen", "reload": "RELOAD", "secondary_swap": "SWAP",
			"grenade": "GRENADE", "crouch": "the left stick (pull down)", "prone": "PRONE",
			"weapon_1": "the weapon menu", "weapon_10": "the weapon menu"}
		return str(names.get(action, action))
	var k := ControlsMap.primary_label(action)
	# A controller is plugged in: name its button too (#262).
	if not Input.get_connected_joypads().is_empty() and InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				return ControlsMap.event_display(ev) if k == "—" else "%s / %s" % [k, ControlsMap.event_display(ev)]
	return k


## Course text: translated, then the {placeholders} filled in.
func _fmt(s: String) -> String:
	return tr(s).format({"jump": _tkey("jump"), "prone": _tkey("prone"), "right": _tkey("move_right"),
		"reload": _tkey("reload"), "pause": _tkey("pause") if not _touch() else tr("BACK"),
		"limit": "%.1f" % Course.lane_limit()})


## _key for translated sentences: the touch descriptions ("the left stick")
## translate too; key and button names stay as printed on the keys / buttons.
func _tkey(action: String) -> String:
	var k := _key(action)
	return tr(k) if k.begins_with("the ") else k


static func fmt_time(s: float) -> String:
	var tenths := maxi(0, roundi(s * 10.0))   # round first: 59.96 s is 1:00.0, not 0:60.0
	return "%d:%04.1f" % [floori(tenths / 600.0), float(tenths % 600) / 10.0]


func _show_step() -> void:
	if _step >= _steps.size():
		return
	var st: Array = _steps[_step]
	if _course:
		_title.text = tr(st[0])
		_body.text = _fmt(st[1])
		_course_prog()
		_place.call_deferred()
		_reset_step_state()
		var p = _player()
		if p != null:
			_check_section(p)
		return
	var keys: Array = []
	for a in st[2]:
		keys.append(_key(a))
	var fmt: String = st[1]
	_body.text = fmt % keys if not keys.is_empty() else fmt
	_title.text = st[0]
	_prog.text = "TRAINING  ·  STEP %d / %d" % [_step + 1, STEPS.size()]
	_place.call_deferred()
	_moved = 0.0
	_jet_t = 0.0
	_shots = 0
	_held.clear()
	var p = _player()
	_start_weapon = int(p.get("weapon_index")) if p != null else -1
	if st[0] == "FIGHT":
		_start_kills = _my_kills()
		Settings.bot_count = 1
		if main != null and main.has_method("_reconcile_bots"):
			main._reconcile_bots()


func _place() -> void:
	reset_size()
	var vp := get_viewport_rect().size
	if _course:
		# Left, under the HUD readout: the course runs left to right, so the
		# gap, spikes and ring ahead of the soldier stay in view (#262).
		position = Vector2(8.0, 146.0)
		return
	position = Vector2(roundf((vp.x - size.x) * 0.5), 150.0)


func _player() -> Node:
	if main == null:
		return null
	var p = main.get("player")
	return p if p != null and is_instance_valid(p) and not bool(p.get("dead")) else null


func _my_kills() -> int:
	var stats = main.get("player_stats") if main != null else null
	if stats is Dictionary and stats.has(Settings.display_name()):
		return int(stats[Settings.display_name()].get("k", 0))
	return 0


func _pressed(action: String) -> bool:
	## Rising edge (works for injected presses too).
	var down := InputMap.has_action(action) and Input.is_action_pressed(action)
	var was: bool = _held.get(action, false)
	_held[action] = down
	return down and not was


func _physics_process(_delta: float) -> void:
	# Jets are off on the movement course (a jet flight would skip every gate).
	# The overlay sits before the soldier in the tree, so this runs ahead of
	# the soldier's own physics tick.
	if _course:
		var p = _player()
		if p != null:
			p.fuel = 0.0


func _process(delta: float) -> void:
	_t += delta
	if _course:
		_course_tick(delta)
	if _phase2_t >= 0.0:
		if _t - _phase2_t > PHASE2_DELAY:
			_go_course()
		return
	if _done_t >= 0.0:
		if _t - _done_t > 0.9:
			_done_t = -1.0
			_step += 1
			if _step >= _steps.size():
				_finish()
			else:
				_show_step()
		return
	if _step >= _steps.size():
		return
	var p = _player()
	if p == null:
		return
	if _course:
		if _course_gate(p):
			_step_done()
		return
	var ok := false
	match STEPS[_step][0]:
		"MOVE":
			if _last_x != INF:
				_moved += absf(p.global_position.x - _last_x)
			ok = _moved > 300.0
		"JUMP":
			ok = not p.is_on_floor() and p.velocity.y < -150.0 and not bool(p.get("jet_on"))
		"JET BOOTS":
			if bool(p.get("jet_on")):
				_jet_t += delta
			ok = _jet_t > 0.8
		"SHOOT":
			if _pressed("fire"):
				_shots += 1
			ok = _shots >= 5 or (Input.is_action_pressed("fire") and _hold_fire(delta))
		"RELOAD":
			ok = _pressed("reload") or bool(p.get("reloading"))
		"SWITCH WEAPON":
			# Any weapon key counts (you may already hold the gun you picked).
			var any_key := false
			for i in range(1, 11):
				if _pressed("weapon_%d" % i):
					any_key = true
			ok = any_key or _pressed("secondary_swap") or int(p.get("weapon_index")) != _start_weapon
		"GRENADE":
			ok = _pressed("grenade")
		"CROUCH":
			ok = bool(p.get("crouching")) or bool(p.get("prone"))
		"FIGHT":
			ok = _my_kills() > _start_kills
	_last_x = p.global_position.x
	if ok:
		_title.text = STEPS[_step][0] + "  ✓"
		_done_t = _t


var _fire_hold := 0.0
func _hold_fire(delta: float) -> bool:
	# Automatic weapons fire on hold: 1.2 s of holding counts as the 5 shots.
	_fire_hold += delta
	return _fire_hold > 1.2


func _finish() -> void:
	if _course:
		_course_finish()
		return
	# Phase 1 done: on to the movement course (#262).
	Stats.record_event("trained")
	_prog.text = tr("TRAINING  ·  PHASE 2")
	_title.text = tr("NOW THE MOVES THAT MAKE A PRO")
	_body.text = tr("That's the basics. Next, a short course against the clock: hops, full jumps, prone drops and bunny hops. Loading…")
	_place.call_deferred()
	_phase2_t = _t


func _go_course() -> void:
	_phase2_t = -1.0
	_use_course()
	_handoff = true
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ── Movement course (#262) ───────────────────────────────────────────────

## The step whose section the player is in (the next one while the "✓"
## of the last one is still showing).
func _cur() -> int:
	return mini(_step + (1 if _done_t >= 0.0 else 0), Course.STEP_COUNT - 1)


func _reset_step_state() -> void:
	_drop_air = false
	_drop_prone = false
	_lane_t0 = -1.0
	_lane_speed = PackedFloat32Array()
	_lane_air = []


func _course_prog() -> void:
	var tm := fmt_time(_t - _c_t0) if _c_t0 >= 0.0 else fmt_time(0.0)
	if _c_end >= 0.0:
		return
	_prog.text = "%s  ·  %s  ·  %s" % [tr("MOVEMENT COURSE"), tr("STEP %d / %d") % [mini(_step + 1, _steps.size()), _steps.size()], tm]


func _teleport(p: Node, pos: Vector2) -> void:
	var b := p as CharacterBody2D
	b.global_position = pos
	b.velocity = Vector2.ZERO
	p.set("prone", false)
	p.set("roll_t", 0.0)
	var cam = p.get("cam")
	if cam is Camera2D:
		(cam as Camera2D).reset_smoothing()


func _fail(step: int, title: String, desc: String) -> void:
	_resets += 1
	var p = _player()
	if p != null:
		_teleport(p, Course.step_start(step))
	_reset_step_state()
	_last_fail = title
	_toast(tr(title), _fmt(desc), Color(1.0, 0.45, 0.35))


var _last_fail := ""   # for tools/movement_course_test.gd


func _toast(title: String, desc: String, col: Color) -> void:
	var hud = main.get("hud") if main != null else null
	if hud != null and hud.has_method("toast"):
		hud.toast(title, desc, col)


## A step was just shown (or the player respawned): put them back at the
## section start if they are already past it or below it.
func _check_section(p: Node) -> void:
	var pos: Vector2 = (p as Node2D).global_position
	var s := _cur()
	var off := false
	if s <= Course.S_DROP:
		off = pos.y > Course.TOP_Y + Course.PIT_DROP
	elif s == Course.S_BUNNY:
		off = pos.y < Course.TOP_Y + Course.PIT_DROP or pos.x > Course.LANE.x - 20.0
	if off:
		_teleport(p, Course.step_start(s))


## Runs every frame on the course, also while a step's ✓ shows: clock,
## jets off, pits, spikes, respawns, replay.
func _course_tick(_delta: float) -> void:
	if main != null and main.get("time_left") != null:
		main.set("time_left", maxf(float(main.get("time_left")), 60.0))   # no round end mid-course
	var p = _player()
	if p == null:
		return
	if p.get_instance_id() != _body_id:
		var first := _body_id == 0
		_body_id = p.get_instance_id()
		if not first and _c_end < 0.0:
			_teleport(p, Course.step_start(_cur()))
	if _c_end >= 0.0:
		if _pressed("reload"):
			_restart_course()
		return
	_pressed("reload")
	var b := p as CharacterBody2D
	if _c_t0 < 0.0:
		if absf(b.velocity.x) > 1.0 or not b.is_on_floor():
			_c_t0 = _t
	_course_prog()
	var s := _cur()
	var pos := b.global_position
	if Course.spike_rect().intersects(p.hitbox_now()):
		_fail(s, "SPIKES!", "You held jump too long. Tap it for a short hop.")
		return
	if s <= Course.S_LONG or (s == Course.S_DROP and pos.x < Course.LEDGE_X - 8.0):
		if pos.y > Course.TOP_Y + Course.PIT_DROP:
			if s == Course.S_LONG:
				_fail(s, "MISSED", "A hop is too short here. Hold {jump} for the full jump.")
			elif s == Course.S_DROP:
				_fail(s, "MISSED", "The drop is the other way: run off the right edge.")
			else:
				_fail(s, "MISSED", "Tap {jump} close to the edge.")
			return
	if s == Course.S_BUNNY:
		_live.visible = true
		var el := (_t - _lane_t0) if _lane_t0 >= 0.0 else 0.0
		_live.text = tr("SPEED %d  ·  RUN %d  ·  %.1f / %.1f s") % [int(absf(b.velocity.x)), int(Course.run_speed()), el, Course.lane_limit()]
	else:
		_live.visible = false


## The current step's gate (not while its ✓ shows).
func _course_gate(p: Node) -> bool:
	var b := p as CharacterBody2D
	var pos := b.global_position
	var on_floor := b.is_on_floor()
	match _step:
		Course.S_SHORT, Course.S_MEDIUM, Course.S_LONG:
			var deck: Vector2 = Course.landing_deck(_step)
			return on_floor and absf(pos.y - Course.TOP_Y) < 6.0 and pos.x > deck.x + 8.0 and pos.x < deck.y
		Course.S_DROP:
			if on_floor and pos.y < Course.TOP_Y + 6.0:
				_drop_air = false   # still (or back) on the ledge
				_drop_prone = false
			if not on_floor and pos.x > Course.LEDGE_X - 10.0:
				_drop_air = true
			if _drop_air and not on_floor and bool(p.get("prone")):
				_drop_prone = true
			if _drop_air and on_floor and pos.y > Course.GROUND_Y - 6.0:
				var dx := pos.x - Course.LEDGE_X
				_last_drop_dx = dx
				if dx < Course.RING.x:
					_fail(_step, "TOO SHORT", "Keep holding {right} as you run off, then go prone.")
				elif dx > Course.RING.y:
					if _drop_prone:
						_fail(_step, "TOO LONG", "Go prone sooner, right after you leave the ledge.")
					else:
						_fail(_step, "TOO LONG", "Press {prone} in mid-air: prone drops you faster.")
				elif not _drop_prone or not bool(p.get("prone")):
					_fail(_step, "NOT PRONE", "Press {prone} in mid-air before you land.")
				else:
					return true
		Course.S_BUNNY:
			if pos.x < Course.LANE.x:
				if _lane_t0 >= 0.0:
					_reset_step_state()   # backed out of the lane: start again
				return false
			if _lane_t0 < 0.0:
				_lane_t0 = _t
			_lane_speed.append(absf(b.velocity.x))
			_lane_air.append(not on_floor)
			var el := _t - _lane_t0
			if pos.x >= Course.LANE.y:
				_last_lane_t = el
				if el > Course.lane_limit():
					_fail(_step, "TOO SLOW", tr("%.2f s.") % el + " " + tr("Chain hops: jump again the moment you land."))
				elif not _lane_hopped():
					_fail(_step, "KEEP HOPPING", "That wasn't hopping. Chain jumps across: don't run or roll.")
				else:
					return true
			elif el > Course.lane_limit():
				_last_lane_t = el
				_fail(_step, "TOO SLOW", tr("%.2f s.") % el + " " + tr("Chain hops: jump again the moment you land."))
	return false


var _last_drop_dx := 0.0   # for the test
var _last_lane_t := 0.0


## Velocity history check: most of the lane faster than RUN_SPEED (read
## from player.gd) and most of it in the air.
func _lane_hopped() -> bool:
	var n := _lane_speed.size()
	if n == 0:
		return false
	var fast := 0
	var air := 0
	for i in n:
		if _lane_speed[i] > Course.run_speed() + 1.0:
			fast += 1
		if _lane_air[i]:
			air += 1
	return float(fast) / n >= Course.LANE_FAST_SHARE and float(air) / n >= Course.LANE_AIR_SHARE


func _step_done() -> void:
	_title.text = tr(_steps[_step][0]) + "  ✓"
	_toast(tr(_steps[_step][0]) + "  ✓", tr(_steps[_step][2]), Color(0.55, 1.0, 0.6))
	_done_t = _t


func _course_finish() -> void:
	_c_end = _t - maxf(_c_t0, 0.0)
	var prev_best: int = Stats.course_best_ms()
	var ms := int(round(_c_end * 1000.0))
	var new_best: bool = Stats.record_course_time(ms)
	var best_s := float(Stats.course_best_ms()) / 1000.0
	_live.visible = false
	_prog.text = tr("MOVEMENT COURSE COMPLETE")
	_title.text = tr("TIME %s") % fmt_time(_c_end) + ("   " + tr("NEW BEST!") if new_best and prev_best > 0 else "")
	_body.text = tr("Best: %s.") % fmt_time(best_s) + " " + _fmt("Press {reload} to run it again, or open the pause menu ({pause}) to leave and pick a real match. Try Capture the Flag.")
	_toast(tr("COURSE COMPLETE"), tr("Time %s  ·  best %s") % [fmt_time(_c_end), fmt_time(best_s)], Color(1.0, 0.85, 0.4))
	_place.call_deferred()


func _restart_course() -> void:
	_step = 0
	_done_t = -1.0
	_c_t0 = -1.0
	_c_end = -1.0
	_resets = 0
	var p = _player()
	if p != null:
		_teleport(p, Course.step_start(Course.S_SHORT))
	_show_step()


func _restore() -> void:
	if _handoff:
		return   # phase 1 -> 2: the course scene picks the session up
	if Settings.training_saved.is_empty():
		Settings.training = false
		Settings.training_course = false
		return
	for k in Settings.training_saved.keys():
		Settings.set(k, Settings.training_saved[k])
	Settings.training_saved = {}
	Settings.training = false
	Settings.training_course = false
	Settings.save()
