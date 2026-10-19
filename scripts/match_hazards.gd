extends Node
## Main's map hazards (#286, Maker mode): kill zones (spikes / lava) and jump
## pads from the map JSON ("hazards": [{kind, rect, dir}], "jump_pads":
## [{pos, power}]). They are static map data every peer has (custom maps
## travel with the map RPC), so — exactly like the kill line in
## match_world._tick_soldier_safety — each soldier's AUTHORITY applies them:
## the host / single player for bots and its own soldier, a client for its own
## body. A kill goes through take_damage on that authority (the trust guard's
## normal self-reported death path, "Spikes" / "Lava"), a launch only sets the
## owner's velocity (well under the trust guard's speed cap). The look lives in
## scripts/maker/hazard_visual.gd (cosmetic).
##
## Bots read hazard_at() (pit guard) and safe_goal() (goal picking) so they
## don't walk into them.

const Main = preload("res://scripts/main.gd")
const HazardVisual = preload("res://scripts/maker/hazard_visual.gd")

const PAD_HALF_W := 28.0       # trigger: feet within this of the pad centre...
const PAD_TRIGGER_UP := 24.0   # ...and at most this far above its base
const PAD_COOLDOWN_MS := 400
const GOAL_CLEARANCE := 28.0   # bot goals are kept this far out of a zone

var main: Main
var zones: Array = []          # {kind, rect: Rect2, dir}
var pads: Array = []           # {pos: Vector2, power: float}
var launches := 0              # pad launches this match (tests)
var kills := 0                 # hazard deaths this match (tests)
var _pad_cd: Dictionary = {}   # soldier instance id -> msec of its last launch
var _visual: Node2D = null


func _build() -> void:
	zones.clear()
	pads.clear()
	for h in main._map.get("hazards", []):
		if typeof(h) == TYPE_DICTIONARY and h.get("rect") is Rect2:
			zones.append(h)
	for j in main._map.get("jump_pads", []):
		if typeof(j) == TYPE_DICTIONARY and j.get("pos") is Vector2:
			pads.append(j)
	if (zones.is_empty() and pads.is_empty()) or Net.is_dedicated:
		return
	_visual = HazardVisual.new()
	_visual.name = "MapHazards"
	_visual.zones = zones
	_visual.pads = pads
	main.add_child(_visual)


func hazard_at(p: Vector2, grow: float = 0.0) -> bool:
	for z in zones:
		if (z["rect"] as Rect2).grow(grow).has_point(p):
			return true
	return false


## A bot goal inside (or right next to) a kill zone moves to the nearer side
## of it.
func safe_goal(p: Vector2) -> Vector2:
	if zones.is_empty() or not is_finite(p.x) or not is_finite(p.y):
		return p
	for z in zones:
		var r: Rect2 = (z["rect"] as Rect2).grow(GOAL_CLEARANCE)
		if r.has_point(p):
			p.x = r.position.x if absf(p.x - r.position.x) <= absf(r.end.x - p.x) else r.end.x
	return p


func _tick(_delta: float) -> void:
	if zones.is_empty() and pads.is_empty():
		return
	var now := Time.get_ticks_msec()
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if not is_instance_valid(s) or bool(s.get("dead")) or not (s is CharacterBody2D):
			continue
		if main.multiplayer.multiplayer_peer != null and not s.is_multiplayer_authority():
			continue
		var body := s as CharacterBody2D
		var feet := body.global_position
		for z in zones:
			var r: Rect2 = z["rect"]
			if r.has_point(feet + Vector2(0, -2)) or r.has_point(feet + Vector2(0, -12)) or r.has_point(feet + Vector2(0, -22)) \
					or r.has_point(feet + Vector2(-6, -2)) or r.has_point(feet + Vector2(6, -2)):
				s.set("ceasefire_t", 0.0)
				s.take_damage(9999.0, str(s.get("display_name")), "Spikes" if str(z.get("kind", "")) == "spikes" else "Lava", int(s.get("team")))
				kills += 1
				break
		if bool(s.get("dead")):
			continue
		for i in pads.size():
			var pp: Vector2 = pads[i]["pos"]
			if absf(feet.x - pp.x) > PAD_HALF_W or feet.y < pp.y - PAD_TRIGGER_UP or feet.y > pp.y + 6.0:
				continue
			if body.velocity.y < -150.0:
				continue   # already on the way up
			var id := s.get_instance_id()
			if now - int(_pad_cd.get(id, -100000)) < PAD_COOLDOWN_MS:
				continue
			_pad_cd[id] = now
			body.velocity.y = -float(pads[i].get("power", 1150.0))
			# Not a jump: the player's early-release jump cut / hold sustain
			# (#262) must not shorten or stretch a pad launch.
			s.set("_jump_cut_done", true)
			s.set("_jump_hold_t", 1.0)
			launches += 1
			if _visual != null and is_instance_valid(_visual):
				_visual.pad_fired(i)
			Sfx.jump(pp)
			break
