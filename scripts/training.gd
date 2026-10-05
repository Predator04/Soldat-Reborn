extends PanelContainer
## Training — a short guided first match (main menu -> TRAINING).
##
## Runs on Arena2 in Deathmatch with no bots. Each step waits for the player
## to actually do the thing (move, jump, jet, shoot, reload, switch weapon,
## throw a grenade, crouch), then one easy bot joins for the final step.
## The match settings it overrides are restored when the scene exits.
## Key names come from the live bindings (touch devices get button names).

const ControlsMap = preload("res://scripts/controls_map.gd")

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
var _saved: Dictionary = {}

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


static func start_training() -> void:
	## Called from the menu: remember the player's match settings, set up the
	## training match and load it. main.gd builds the overlay when it sees
	## Settings.training.
	Settings.training_saved = {
		"game_mode": Settings.game_mode, "map_index": Settings.map_index,
		"custom_map_path": Settings.custom_map_path, "bot_count": Settings.bot_count,
		"bot_skill": Settings.bot_skill, "survival": Settings.survival,
		"realistic": Settings.realistic, "advance": Settings.advance,
	}
	Settings.training = true
	Settings.game_mode = 0
	Settings.map_index = 19
	Settings.custom_map_path = ""
	Settings.bot_count = 0
	Settings.bot_skill = 1
	Settings.survival = false
	Settings.realistic = false
	Settings.advance = false


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
	tree_exiting.connect(_restore)
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
	return ControlsMap.primary_label(action)


func _show_step() -> void:
	if _step >= STEPS.size():
		return
	var st: Array = STEPS[_step]
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


func _process(delta: float) -> void:
	_t += delta
	if _done_t >= 0.0:
		if _t - _done_t > 0.9:
			_done_t = -1.0
			_step += 1
			if _step >= STEPS.size():
				_finish()
			else:
				_show_step()
		return
	if _step >= STEPS.size():
		return
	var p = _player()
	if p == null:
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
	Stats.record_event("trained")
	_prog.text = "TRAINING COMPLETE"
	_title.text = "YOU'RE READY"
	_body.text = "That's the basics. Press %s for the pause menu to go back and pick a real match — try Capture the Flag. %s shows the controls any time." % [_key("pause") if not _touch() else "Back", _key("help") if not _touch() else "The pause menu"]
	_place.call_deferred()


func _restore() -> void:
	if Settings.training_saved.is_empty():
		Settings.training = false
		return
	for k in Settings.training_saved.keys():
		Settings.set(k, Settings.training_saved[k])
	Settings.training_saved = {}
	Settings.training = false
	Settings.save()
