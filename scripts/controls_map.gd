extends Object
## ControlsMap — action list, defaults, persistence for the Controls settings screen.
##
## The single source of truth for what actions the game exposes to the rebind UI.
## Defaults mirror project.godot's [input] section so "Reset to defaults" restores
## exactly what a fresh install ships with, and load-on-start won't diverge if the
## user has never opened the Controls panel.

const PATH := "user://controls.cfg"

# Sections group the rebind rows in the UI (#73). Each entry above the "section:X"
# marker lands in that section header. Order still matters for the UI list order.
const SECTIONS := ["Movement", "Combat", "Weapons", "Chat", "Utility"]

# Section membership — [action_id] → section name. Anything unlisted defaults to
# "Utility" so a new action still appears somewhere without a code change here.
const ACTION_SECTION := {
	"move_left": "Movement", "move_right": "Movement", "jump": "Movement",
	"jet": "Movement", "crouch": "Movement", "prone": "Movement",
	"fire": "Combat", "grenade": "Combat", "reload": "Combat", "grenade_toggle": "Combat",
	"secondary_swap": "Weapons", "weapon_throw": "Weapons",
	"weapon_1": "Weapons", "weapon_2": "Weapons", "weapon_3": "Weapons",
	"weapon_4": "Weapons", "weapon_5": "Weapons", "weapon_6": "Weapons",
	"weapon_7": "Weapons", "weapon_8": "Weapons", "weapon_9": "Weapons",
	"weapon_10": "Weapons",
	"chat": "Chat", "team_chat": "Chat", "taunt": "Chat", "command": "Chat",
	"vote_yes": "Utility", "vote_no": "Utility",
	"record_gif": "Utility",
}

# Order matters — the Controls screen renders rows in this order.
# Each entry: [action_id, human_label, [default_event_dict, ...]]
# default event dicts are decoded by _apply_defaults / event_from_dict.
const ACTIONS := [
	["move_left",       "Move Left",        [{"type": "key", "physical_keycode": 65}]],       # A
	["move_right",      "Move Right",       [{"type": "key", "physical_keycode": 68}]],       # D
	["jump",            "Jump",             [{"type": "key", "physical_keycode": 87},         # W
											 {"type": "key", "physical_keycode": 32}]],      # Space
	["jet",             "Jet Boots",        [{"type": "mouse", "button_index": 2}]],          # RMB
	["crouch",          "Crouch",           [{"type": "key", "physical_keycode": 83}]],       # S
	["prone",           "Prone",            [{"type": "key", "physical_keycode": 88}]],       # X
	["fire",            "Fire",             [{"type": "mouse", "button_index": 1}]],          # LMB
	["grenade",         "Throw Grenade",    [{"type": "key", "physical_keycode": 69}]],       # E
	["reload",          "Reload",           [{"type": "key", "physical_keycode": 82}]],       # R
	["grenade_toggle",  "Grenade Type",     [{"type": "key", "physical_keycode": 71}]],       # G
	["secondary_swap",  "Swap Weapon",      [{"type": "key", "physical_keycode": 81}]],       # Q
	["weapon_throw",    "Throw / Mount",    [{"type": "key", "physical_keycode": 70}]],       # F
	["weapon_1",        "Weapon Slot 1",    [{"type": "key", "physical_keycode": 49}]],       # 1
	["weapon_2",        "Weapon Slot 2",    [{"type": "key", "physical_keycode": 50}]],
	["weapon_3",        "Weapon Slot 3",    [{"type": "key", "physical_keycode": 51}]],
	["weapon_4",        "Weapon Slot 4",    [{"type": "key", "physical_keycode": 52}]],
	["weapon_5",        "Weapon Slot 5",    [{"type": "key", "physical_keycode": 53}]],
	["weapon_6",        "Weapon Slot 6",    [{"type": "key", "physical_keycode": 54}]],
	["weapon_7",        "Weapon Slot 7",    [{"type": "key", "physical_keycode": 55}]],
	["weapon_8",        "Weapon Slot 8",    [{"type": "key", "physical_keycode": 56}]],
	["weapon_9",        "Weapon Slot 9",    [{"type": "key", "physical_keycode": 57}]],
	["weapon_10",       "Weapon Slot 10",   [{"type": "key", "physical_keycode": 48}]],       # 0
	["chat",            "Chat",             [{"type": "key", "physical_keycode": 84}]],       # T
	["team_chat",       "Team Chat",        [{"type": "key", "physical_keycode": 89}]],       # Y
	["taunt",           "Taunt Modifier",   [{"type": "key", "physical_keycode": 4194328}]],  # Alt
	["command",         "Command Console",  [{"type": "key", "physical_keycode": 47}]],       # /
	["vote_yes",        "Vote Yes",         [{"type": "key", "physical_keycode": 4194332}]],  # F1
	["vote_no",         "Vote No",          [{"type": "key", "physical_keycode": 4194333}]],  # F2
	["record_gif",      "Record GIF",       [{"type": "key", "physical_keycode": 4194340}]],  # F9
]


static func section_for(action_id: String) -> String:
	return String(ACTION_SECTION.get(action_id, "Utility"))


static func action_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for row in ACTIONS:
		out.append(String(row[0]))
	return out


static func label_for(action_id: String) -> String:
	for row in ACTIONS:
		if String(row[0]) == action_id:
			return String(row[1])
	return action_id


static func defaults_for(action_id: String) -> Array:
	for row in ACTIONS:
		if String(row[0]) == action_id:
			return row[2]
	return []


# Convert a saved dict back into a live InputEvent. Returns null on unknown type.
static func event_from_dict(d: Dictionary) -> InputEvent:
	var t := String(d.get("type", ""))
	if t == "key":
		var ev := InputEventKey.new()
		ev.physical_keycode = int(d.get("physical_keycode", 0))
		return ev
	if t == "mouse":
		var mb := InputEventMouseButton.new()
		mb.button_index = int(d.get("button_index", 0))
		return mb
	return null


# Convert a live InputEvent into a persistable dict. Non-key/mouse events are dropped.
static func event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var kc: int = (ev as InputEventKey).physical_keycode
		if kc == 0:
			kc = (ev as InputEventKey).keycode
		return {"type": "key", "physical_keycode": kc}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button_index": int((ev as InputEventMouseButton).button_index)}
	return {}


# Human-readable text for the "current binding" cell.
static func event_display(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var kc: int = (ev as InputEventKey).physical_keycode
		if kc == 0:
			kc = (ev as InputEventKey).keycode
		var name := OS.get_keycode_string(kc)
		if name == "":
			name = "Key %d" % kc
		return name
	if ev is InputEventMouseButton:
		match int((ev as InputEventMouseButton).button_index):
			1: return "Mouse Left"
			2: return "Mouse Right"
			3: return "Mouse Middle"
			4: return "Wheel Up"
			5: return "Wheel Down"
			8: return "Mouse 4"
			9: return "Mouse 5"
			_: return "Mouse %d" % (ev as InputEventMouseButton).button_index
	return "—"


# Primary binding label — first key/mouse event on the action, or "—" if unbound.
static func primary_label(action_id: String) -> String:
	if not InputMap.has_action(action_id):
		return "—"
	for ev in InputMap.action_get_events(action_id):
		if ev is InputEventKey or ev is InputEventMouseButton:
			return event_display(ev)
	return "—"


# Which OTHER action (if any) currently owns this key/button. Used to warn about
# collisions on rebind. Returns "" if the binding is free.
static func find_conflict(new_ev: InputEvent, ignore_action: String) -> String:
	for row in ACTIONS:
		var aid := String(row[0])
		if aid == ignore_action:
			continue
		if not InputMap.has_action(aid):
			continue
		for ev in InputMap.action_get_events(aid):
			if _events_equal(ev, new_ev):
				return aid
	return ""


static func _events_equal(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ak: int = (a as InputEventKey).physical_keycode
		if ak == 0:
			ak = (a as InputEventKey).keycode
		var bk: int = (b as InputEventKey).physical_keycode
		if bk == 0:
			bk = (b as InputEventKey).keycode
		return ak == bk
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


# Rebind: erase existing events on `action_id`, add `new_ev`, and remove
# `new_ev` from any conflicting action so the same key isn't bound twice.
static func rebind(action_id: String, new_ev: InputEvent) -> void:
	if not InputMap.has_action(action_id):
		return
	for row in ACTIONS:
		var aid := String(row[0])
		if aid == action_id:
			continue
		if not InputMap.has_action(aid):
			continue
		for ev in InputMap.action_get_events(aid):
			if _events_equal(ev, new_ev):
				InputMap.action_erase_event(aid, ev)
	InputMap.action_erase_events(action_id)
	InputMap.action_add_event(action_id, new_ev)


# Load bindings from disk (if any) and apply them over the defaults already
# baked in from project.godot. Called from Settings._ready.
static func load_and_apply() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for row in ACTIONS:
		var aid := String(row[0])
		if not InputMap.has_action(aid):
			continue
		var raw: Variant = cf.get_value("bindings", aid, null)
		if raw == null:
			continue
		var list: Array = raw as Array
		if list.is_empty():
			continue
		# Replace all events for this action with the saved set.
		InputMap.action_erase_events(aid)
		for entry in list:
			var d: Dictionary = entry as Dictionary
			var ev: InputEvent = event_from_dict(d)
			if ev != null:
				InputMap.action_add_event(aid, ev)


# Serialize the current InputMap state (for our known actions) to disk.
static func save() -> void:
	var cf := ConfigFile.new()
	for row in ACTIONS:
		var aid := String(row[0])
		if not InputMap.has_action(aid):
			continue
		var out: Array = []
		for ev in InputMap.action_get_events(aid):
			var d: Dictionary = event_to_dict(ev)
			if not d.is_empty():
				out.append(d)
		cf.set_value("bindings", aid, out)
	cf.save(PATH)


# Restore every action to its default binding set, then save.
static func reset_all() -> void:
	for row in ACTIONS:
		var aid := String(row[0])
		if not InputMap.has_action(aid):
			continue
		InputMap.action_erase_events(aid)
		for entry in (row[2] as Array):
			var ev: InputEvent = event_from_dict(entry as Dictionary)
			if ev != null:
				InputMap.action_add_event(aid, ev)
	save()
