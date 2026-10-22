extends Area2D
## Bullet — fast projectile with a tracer trail.

var direction := Vector2.RIGHT
var speed := 900.0
var damage := 12.0
var team := 0
var killer_name := ""
const DamagePopup = preload("res://scripts/damage_popup.gd")
const ImpactFx = preload("res://scripts/impact_fx.gd")
var weapon_name := ""
# Visual style overrides. "flame" = short-lived orange puff, "arrow" = long thin shaft.
# Default "" = classic yellow tracer.
var visual := ""
# Custom lifetime; 0 = default 3s. Flames get ~0.35s so the cone is short.
var life := 0.0
# Optional gravity — arrows sag slightly, standard bullets are 0.
var grav := 0.0
var _hit := false
## Damage falloff over distance travelled (shotgun pellets): Vector3(start px,
## end px, multiplier at / past end); x = y = 0 means none. From the weapon
## table's "falloff", so every peer computes the same number.
var falloff := Vector3.ZERO
var _travel := 0.0   # px flown, counted per physics step (same on every peer)
# Lag compensation (bullets from a remote player): also test the local
# player's hitbox from this many ms ago, i.e. where the shooter saw them.
var lag_ms := 0
var tint := Color(1, 1, 1)   # tracer color (shooter's customization)
var _ray_exclude: Array[RID] = []
# Bodies this round passes through (a buggy and its crew for the buggy gun).
var ignore_bodies: Array = []
var _velocity := Vector2.ZERO
var _sprite: Texture2D = null
var _sprite_size := Vector2.ZERO
# #266 (host_hits.gd): on the host, remote humans are tested against their
# hitboxes as the shooter saw them, `_rewind_ms` back (the shooter's round
# trip; 0 for the host's own player, bots, turrets the host runs).
var _host_side := false
var _rewind_ms := 0
var rewind_override := -1   # set by the shot (its own view stamp); else by shooter
var shot_id := 0            # the shot's projectile id (same on every peer; tests)
# A shot whose aim waits for a re-check (player._host_shot_check): its hits
# on humans are parked in hold["hits"] until then.
var hold: Dictionary = {}
# Shooter-side hit predictions (the local player's rounds hitting someone),
# for tests comparing them with what the host decided.
static var predicted_hits := 0
static var predicted_damage := 0.0
# The same for splash / melee (local_hit_feedback): rockets, grenades, knife.
static var predicted_other_hits := 0
static var predicted_other_damage := 0.0
static var _hh_log := OS.get_cmdline_user_args().has("--hosthits-log")


func _ready() -> void:
	# Terrain layer 2 = ported "only bullets collide" polys (see main.gd).
	collision_mask = 1 | 2 | 8  # terrain, bullets-only terrain, soldiers
	add_to_group("bullet")
	# Kill credit is checked against who was attacking (trust_guard.gd).
	TrustGuard.note_activity(killer_name, team)
	if Net.is_networked() and Net.is_host() and multiplayer.has_multiplayer_peer():
		_host_side = true
		_rewind_ms = rewind_override if rewind_override >= 0 else HostHits.rewind_for(get_tree(), killer_name)
	_load_sprite()
	body_entered.connect(_on_body_entered)
	var shape := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 3.0
	shape.shape = cs
	add_child(shape)
	_velocity = direction * speed
	var l := life if life > 0.0 else 3.0
	get_tree().create_timer(l).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	var step: Vector2
	if grav > 0.0:
		_velocity.y += grav * delta
		step = _velocity * delta
		direction = _velocity.normalized()
	else:
		step = direction * speed * delta
	_travel += step.length()
	# Swept hit test (v1.18): a Barrett round moves 40 px a frame and a soldier
	# is ~14 px wide, so overlap checks alone let fast rounds pass straight
	# through people (bots with the Barrett couldn't hit a standing target).
	var long_step := step.length() > 4.0
	if not _hit and is_inside_tree() and (long_step or _host_side):
		var hit := {}
		if long_step:
			if _ray_exclude.is_empty() and not ignore_bodies.is_empty():
				for ib in ignore_bodies:
					if is_instance_valid(ib) and ib is CollisionObject2D:
						_ray_exclude.append((ib as CollisionObject2D).get_rid())
			var excl: Array[RID] = _ray_exclude
			if _host_side and not HostHits.remote_humans().is_empty():
				# Remote humans (and vehicles carrying one) are tested rewound
				# below, not where they are now.
				excl = _ray_exclude.duplicate()
				excl.append_array(HostHits.remote_rids())
				if _rewind_ms > 0:
					for v in _rewound_vehicles():
						excl.append((v as CollisionObject2D).get_rid())
			var q := PhysicsRayQueryParameters2D.create(global_position, global_position + step, collision_mask, excl)
			hit = get_world_2d().direct_space_state.intersect_ray(q)
		if _host_side and _rewound_hit(step, hit):
			queue_redraw()
			return
		if long_step:
			if lag_ms > 0 and _lag_comp_hit(step, hit):
				queue_redraw()
				return
			if not hit.is_empty():
				global_position = hit["position"]
				_on_body_entered(hit["collider"])
				if _hit:
					queue_redraw()
					return
				# Passed through (a teammate): don't test that body again.
				_ray_exclude.append(hit["rid"])
	position += step
	_whizz_check()
	queue_redraw()


# Rewound test against the local player: a hit there counts unless a wall (or
# someone else) is closer along this step.
func _lag_comp_hit(step: Vector2, hit: Dictionary) -> bool:
	var m := get_tree().current_scene
	var lp = m.get("player") if m != null else null
	if lp == null or not is_instance_valid(lp) or bool(lp.get("dead")) or not lp.has_method("hitbox_at"):
		return false
	if lp in ignore_bodies or str(lp.display_name) == killer_name:
		return false
	if int(lp.team) == team and not MatchConfig.friendly_fire_on():
		return false
	if multiplayer.multiplayer_peer != null and not lp.is_multiplayer_authority():
		return false
	var t := segment_rect_t(global_position, global_position + step, (lp.hitbox_at(lag_ms) as Rect2).grow(3.0))
	if t < 0.0:
		return false
	if not hit.is_empty() and hit.get("collider") != lp:
		var ht: float = global_position.distance_to(hit["position"]) / maxf(step.length(), 0.001)
		if ht < t:
			return false
	global_position += step * t
	_on_body_entered(lp)
	return _hit


# Host (#266): the nearest remote human whose hitbox, as the shooter saw it,
# this step enters — unless a wall (or someone the ray found) is closer.
func _rewound_hit(step: Vector2, hit: Dictionary) -> bool:
	var list: Array = HostHits.remote_humans()
	if list.is_empty():
		return false
	var a := global_position
	var b := a + step
	var near := Rect2(a, Vector2.ZERO).expand(b).grow(float(_rewind_ms) * HostHits.BROAD_SPEED / 1000.0 + 40.0)
	var ff: bool = MatchConfig.friendly_fire_on()
	var best_t := 2.0
	var best: Node = null
	var best_rect := Rect2()
	for s in list:
		if not is_instance_valid(s) or bool(s.dead) or s in ignore_bodies:
			continue
		if str(s.display_name) == killer_name or (int(s.team) == team and not ff):
			continue
		if not near.intersects(s.hitbox_now()):
			continue
		var r := HostHits.rect_at(s, _rewind_ms)
		# (Grown a little for a rewound test: measured best agreement with the
		# shooter's screen. A shot tested where the host has bodies now — a
		# relayed vehicle gun — uses the bare box, as the shooter's copy does.)
		var t := segment_rect_t(a, b, r.grow(3.0) if _rewind_ms > 0 else r)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = s
			best_rect = r
	# A vehicle carrying a remote human, as the shooter saw it too.
	var best_v: Node = null
	if _rewind_ms > 0:
		for v in _rewound_vehicles():
			if v in ignore_bodies or not near.intersects(Rect2((v as Node2D).global_position, Vector2.ZERO).grow(80.0)):
				continue
			var tv: float = v.segment_t_at(a, b, _rewind_ms)
			if tv >= 0.0 and tv < best_t:
				best_t = tv
				best_v = v
	if best == null and best_v == null:
		return false
	if not hit.is_empty():
		var ht: float = a.distance_to(hit["position"]) / maxf(step.length(), 0.001)
		if ht < best_t:
			return false
	global_position = a + step * best_t
	if best_v != null:
		_on_body_entered(best_v)
		if _hit:
			return true
		# (A team-mate's: the round passes through, as with the ray's bodies.)
		ignore_bodies.append(best_v)
		global_position = a
		return _rewound_hit(step, hit)
	_on_body_entered(best, best_rect.end.y)
	return _hit


## Host: vehicles to test rewound (they carry a remote human).
func _rewound_vehicles() -> Array:
	var out: Array = []
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.has_method("carries_remote_human") and bool(v.get("alive")) and v.carries_remote_human():
			out.append(v)
	return out


# First point (0..1 along a->b) where the segment enters rect, or -1.
static func segment_rect_t(a: Vector2, b: Vector2, r: Rect2) -> float:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var p: float = a[axis]
		var dd: float = d[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(dd) < 0.000001:
			if p < lo or p > hi:
				return -1.0
		else:
			var ta := (lo - p) / dd
			var tb := (hi - p) / dd
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return -1.0
	return t0


## Shotgun falloff: full damage up to `f.x` px flown, easing linearly to
## `f.z` x at `f.y` px and beyond.
static func falloff_mul(f: Vector3, travel: float) -> float:
	if f.y <= f.x or travel <= f.x:
		return 1.0
	return lerpf(1.0, f.z, clampf((travel - f.x) / (f.y - f.x), 0.0, 1.0))


## `feet_y`: the victim's feet in the rewound hitbox (host tests, #266).
func _on_body_entered(body: Node, feet_y: float = INF) -> void:
	# queue_free() is deferred; a second body_entered in the same physics flush would
	# otherwise apply damage to a second soldier stacked on the first.
	if _hit:
		return
	if body in ignore_bodies:
		return
	if body is CharacterBody2D:
		# Host: a remote human counts only through the rewound test, never
		# where its body happens to overlap now.
		if _host_side and feet_y == INF and HostHits.is_remote_human(body):
			return
		if body.has_method("take_damage"):
			var same_team: bool = int(body.get("team")) == team
			var is_self: bool = str(body.get("display_name")) == killer_name
			# Same-team bullets pass through unless the host has friendly fire on
			# (or the mode is FFA, where MatchConfig.friendly_fire_on returns true).
			# Self-hits are always allowed so the shooter's own bullet doesn't
			# eat a wall / crate collision path silently.
			if same_team and not is_self and not MatchConfig.friendly_fire_on():
				return
			# Your own rounds never hit you (a sagging Rambo arrow, now a
			# one-shot kill, could drop back onto the archer).
			if is_self:
				return
			_hit = true
			ImpactFx.spawn(get_parent(), global_position, -direction, "blood")
			var dmg := damage * falloff_mul(falloff, _travel)
			var wname := weapon_name
			# Realistic: hit region above ~-14 (local) counts as a head-shot 1HK.
			# Prone soldiers have a much smaller head hitbox — offset accordingly.
			if MatchConfig.realistic():
				var head_top: float = -14.0
				if body.get("prone") == true:
					head_top = -4.0
				elif body.get("crouching") == true:
					head_top = -10.0
				var rel_y: float = global_position.y - (feet_y if feet_y != INF else body.global_position.y)
				if rel_y < head_top:
					dmg = 999.0
					wname = weapon_name + " (headshot)"
			# Whoever decides this body's hits applies it (host_hits.gd); a
			# shot held for an aim re-check parks its hits until then.
			if _hh_log and _host_side and HostHits.is_remote_human(body):
				print("HOSTSHOT shot=%d rewind=%d by=%s" % [shot_id, _rewind_ms, killer_name])
			if hold.is_empty():
				HostHits.damage(body, dmg, killer_name, wname, team)
			elif not bool(hold["done"]):
				(hold["hits"] as Array).append([body, dmg, killer_name, wname, team])
			elif bool(hold["ok"]):
				HostHits.damage(body, dmg, killer_name, wname, team)
			# Local stats: only when the local player fired this bullet.
			if _maybe_record_hit() and not is_self:
				# (Predictions count soldiers only: a round into a hull is no hit
				# on its crew.)
				if body.is_in_group("soldier"):
					predicted_hits += 1
					predicted_damage += dmg
					if _hh_log:
						print("PREDHIT shot=%d %.1f" % [shot_id, dmg])
				_spawn_popup(minf(dmg, 100.0), dmg >= 999.0 or wname.ends_with("(headshot)"))
			queue_free()
			return
		return
	_hit = true
	if visual != "flame":
		ImpactFx.spawn(get_parent(), global_position - direction * 3.0, -direction, "wall")
		Sfx.ricochet(global_position)
	queue_free()


func _maybe_record_hit() -> bool:
	# Route stats through the local player only. Main.player is the human peer's node.
	var m := get_tree().current_scene
	if m == null:
		return false
	var pl = m.get("player")
	if pl != null and is_instance_valid(pl) and str(pl.get("display_name")) == killer_name:
		Stats.record_hit()
		Sfx.hit()
		return true
	return false


## Hit confirmation for damage that isn't a bullet (rockets, M79, grenades,
## knife, chainsaw): the local shooter hears the hit tick, gets a damage number
## and it counts toward accuracy, same as a bullet hit. Splash used to land
## silently, so you couldn't tell whether a grenade did anything.
static var _last_hit_ms := 0


static func local_hit_feedback(tree: SceneTree, killer: String, pos: Vector2, amount: float, count_hit: bool = false, victim: Node = null) -> void:
	var m := tree.current_scene
	if m == null or amount <= 0.5:
		return
	var pl = m.get("player")
	if pl == null or not is_instance_valid(pl) or str(pl.get("display_name")) != killer:
		return
	if victim != pl:
		predicted_other_hits += 1
		predicted_other_damage += amount
		if _hh_log:
			print("PREDOTHER %s %.1f" % [str(victim.get("display_name")) if victim != null else "?", amount])
	var now := Time.get_ticks_msec()
	# Splash can tag several soldiers per throw/rocket; only direct hits
	# (melee swings) count toward accuracy so it can't pass 100%.
	if count_hit:
		Stats.record_hit()
	if now - _last_hit_ms > 90:  # chainsaw ticks 10x a second
		Sfx.hit()
		_last_hit_ms = now
	if Settings.damage_numbers:
		var p := Node2D.new()
		p.set_script(DamagePopup)
		p.set("amount", minf(amount, 100.0))
		p.set("big", amount >= 99.0)
		p.global_position = pos + Vector2(0, -24)
		m.add_child(p)


func _spawn_popup(amount: float, big: bool) -> void:
	if not Settings.damage_numbers:
		return
	var m := get_tree().current_scene
	if m == null:
		return
	var p := Node2D.new()
	p.set_script(DamagePopup)
	p.set("amount", amount)
	p.set("big", big)
	p.global_position = global_position
	m.add_child(p)


func _draw() -> void:
	if visual == "flame":
		# Small orange puff, brighter core — no long tracer.
		draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.35, 0.05, 0.35))
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.55, 0.1, 0.7))
		draw_circle(Vector2.ZERO, 2.2, Color(1.0, 0.9, 0.55, 0.95))
	elif visual == "arrow":
		draw_line(-direction * 18.0, Vector2.ZERO, Color(0.75, 0.55, 0.3, 0.9), 1.6)
		draw_line(Vector2.ZERO, direction * 3.0, Color(0.9, 0.9, 0.9), 2.0)
	else:
		if _sprite != null:
			# Original Soldat renders bullets as the weapon's bullet sprite, rotated
			# along travel and stretched by speed into a tracer, at ~1/3 HD downscale.
			var stretch := clampf(speed / 780.0, 0.7, 3.5)
			var w := _sprite_size.x * stretch
			var h := _sprite_size.y
			draw_set_transform(Vector2.ZERO, direction.angle(), Vector2.ONE)
			draw_texture_rect(_sprite, Rect2(-w * 0.5, -h * 0.5, w, h), false, Color(tint.r, tint.g, tint.b, 0.9))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


const _BULLET_STEMS := {
	"Deagles": "eagles-bullet",
	"MP5": "mp5-bullet",
	"AK-74": "ak74-bullet",
	"Steyr AUG": "steyraug-bullet",
	"Spas-12": "spas12-bullet",
	"Ruger 77": "ruger77-bullet",
	"Barrett": "barretm82-bullet",
	"Minimi": "m249-bullet",
	"Minigun": "minigun-bullet",
	"USSOCOM": "colt-bullet",
}
# #95: preload every bullet sprite once at file scope instead of load()-ing per
# spawn. Minigun @ 15 rps × 4 bots pumped thousands of ResourceLoader dict hits
# a second through here. `_BULLET_TEX[stem]` returns the cached Texture2D so
# _load_sprite is a single dict lookup + get_size().
const _BULLET_TEX := {
	"bullet":             preload("res://assets/weapons-gfx/bullet.png"),
	"eagles-bullet":      preload("res://assets/weapons-gfx/eagles-bullet.png"),
	"mp5-bullet":         preload("res://assets/weapons-gfx/mp5-bullet.png"),
	"ak74-bullet":        preload("res://assets/weapons-gfx/ak74-bullet.png"),
	"steyraug-bullet":    preload("res://assets/weapons-gfx/steyraug-bullet.png"),
	"spas12-bullet":      preload("res://assets/weapons-gfx/spas12-bullet.png"),
	"ruger77-bullet":     preload("res://assets/weapons-gfx/ruger77-bullet.png"),
	"barretm82-bullet":   preload("res://assets/weapons-gfx/barretm82-bullet.png"),
	"m249-bullet":        preload("res://assets/weapons-gfx/m249-bullet.png"),
	"minigun-bullet":     preload("res://assets/weapons-gfx/minigun-bullet.png"),
	"colt-bullet":        preload("res://assets/weapons-gfx/colt-bullet.png"),
}


func _load_sprite() -> void:
	# Per-weapon bullet sprite (original Soldat draws bullets as sprites, not lines).
	var stem: String = String(_BULLET_STEMS.get(weapon_name, "bullet"))
	_sprite = _BULLET_TEX.get(stem, _BULLET_TEX.get("bullet"))
	if _sprite != null:
		_sprite_size = _sprite.get_size() * (1.0 / 3.0)


# v1.18: an enemy round passing close to the local player's head zips by.
var _whizz_done := false


func _whizz_check() -> void:
	if _whizz_done or visual == "flame":
		return
	var m := get_tree().current_scene
	var pl = m.get("player") if m != null else null
	if pl == null or not is_instance_valid(pl) or pl.get("dead") == true:
		_whizz_done = true
		return
	if str(pl.get("display_name")) == killer_name:
		_whizz_done = true
		return
	if int(pl.get("team")) == team and not MatchConfig.friendly_fire_on():
		_whizz_done = true
		return
	var head: Vector2 = pl.global_position + Vector2(0, -14)
	if global_position.distance_to(head) < 70.0:
		_whizz_done = true
		Sfx.whizz(global_position)
