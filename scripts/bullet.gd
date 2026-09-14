extends Area2D
## Bullet — fast projectile with a tracer trail.

var direction := Vector2.RIGHT
var speed := 900.0
var damage := 12.0
var team := 0
var killer_name := ""
var weapon_name := ""
# Visual style overrides. "flame" = short-lived orange puff, "arrow" = long thin shaft.
# Default "" = classic yellow tracer.
var visual := ""
# Custom lifetime; 0 = default 3s. Flames get ~0.35s so the cone is short.
var life := 0.0
# Optional gravity — arrows sag slightly, standard bullets are 0.
var grav := 0.0
var _hit := false
var _velocity := Vector2.ZERO
var _sprite: Texture2D = null
var _sprite_size := Vector2.ZERO


func _ready() -> void:
	add_to_group("bullet")
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
	if grav > 0.0:
		_velocity.y += grav * delta
		position += _velocity * delta
		direction = _velocity.normalized()
	else:
		position += direction * speed * delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	# queue_free() is deferred; a second body_entered in the same physics flush would
	# otherwise apply damage to a second soldier stacked on the first.
	if _hit:
		return
	if body is CharacterBody2D:
		if body.has_method("take_damage"):
			var same_team: bool = int(body.get("team")) == team
			var is_self: bool = str(body.get("display_name")) == killer_name
			# Same-team bullets pass through unless the host has friendly fire on
			# (or the mode is FFA, where MatchConfig.friendly_fire_on returns true).
			# Self-hits are always allowed so the shooter's own bullet doesn't
			# eat a wall / crate collision path silently.
			if same_team and not is_self and not MatchConfig.friendly_fire_on():
				return
			_hit = true
			var dmg := damage
			var wname := weapon_name
			# Realistic: hit region above ~-14 (local) counts as a head-shot 1HK.
			# Prone soldiers have a much smaller head hitbox — offset accordingly.
			if Settings.realistic:
				var head_top: float = -14.0
				if bool(body.get("prone")):
					head_top = -4.0
				elif bool(body.get("crouching")):
					head_top = -10.0
				var rel_y: float = global_position.y - body.global_position.y
				if rel_y < head_top:
					dmg = 999.0
					wname = weapon_name + " (headshot)"
			if multiplayer.multiplayer_peer == null or body.is_multiplayer_authority():
				body.take_damage(dmg, killer_name, wname, team)
			# Local stats: only when the local player fired this bullet.
			_maybe_record_hit()
			queue_free()
			return
		return
	_hit = true
	queue_free()


func _maybe_record_hit() -> void:
	# Route stats through the local player only. Main.player is the human peer's node.
	var m := get_tree().current_scene
	if m == null:
		return
	var pl = m.get("player")
	if pl != null and is_instance_valid(pl) and str(pl.get("display_name")) == killer_name:
		Stats.record_hit()
		Sfx.hit()


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
			draw_texture_rect(_sprite, Rect2(-w * 0.5, -h * 0.5, w, h), false, Color(1, 1, 1, 0.9))
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
