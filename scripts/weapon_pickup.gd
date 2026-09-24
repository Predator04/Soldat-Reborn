extends RigidBody2D
## Weapon pickup — spawned by F (thrown) or dropped by dead players.
## Acts as a physics prop that settles on terrain; touching a friendly-or-hostile
## soldier grants that weapon (with a full magazine). Knife specifically damages
## the first enemy it hits while still airborne.

const SoldierArt = preload("res://scripts/soldier_art.gd")

var weapon_name := "AK-74"
var team := 0            # thrower's team — used by the knife-in-flight damage check
var thrower_name := ""
var damage_on_hit := 0.0 # non-zero for Knife
# Mag rounds remaining when the pickup was dropped. Preserved so an empty-mag
# throw → walk-over-pickup cycle can't be used as a free reload. -1 = full.
var mag_on_drop: int = -1
var _consumed := false
var _life := 20.0        # despawn if not picked up in 20s
var _grace := 0.15       # brief window where the thrower can't re-grab it
# Unique id assigned by host so client-side pickups can be tracked in state sync.
var pickup_id: int = 0


func _ready() -> void:
	# Detect soldiers (layer bit 8) as well as resting on terrain (bit 1).
	collision_mask = 1 | 8
	add_to_group("weapon_pickup")
	var shape := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 6.0
	shape.shape = cs
	add_child(shape)
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.25
	mat.friction = 0.7
	physics_material_override = mat
	# Host-authoritative drops (#34): only the host runs physics for pickups. Clients
	# freeze their local body and receive periodic pos/vel snapshots via net_pickups
	# from Main. Without this each peer's RigidBody2D drifted apart on every bounce.
	if Net.is_networked() and Net.is_client():
		freeze = true
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC


func _physics_process(delta: float) -> void:
	_life -= delta
	_grace = maxf(0.0, _grace - delta)
	if _life <= 0.0:
		queue_free()
		return
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if _consumed:
		return
	if not (body is CharacterBody2D):
		return
	if bool(body.get("dead")):
		return
	# In MP the host is the single source of truth for contacts; clients would
	# otherwise pick up ghosts that got frozen at slightly different positions.
	if Net.is_networked() and not Net.is_host():
		return
	var body_team: int = int(body.get("team"))
	# Knife thrown → deal damage on the first hostile impact while still flying.
	if damage_on_hit > 0.0 and body_team != team and linear_velocity.length() > 220.0:
		_consumed = true
		if multiplayer.multiplayer_peer == null or body.is_multiplayer_authority():
			body.take_damage(damage_on_hit, thrower_name, weapon_name, team)
		elif body.has_method("net_remote_damage"):
			# Remote-owned victim: host detected the contact, but only the victim's
			# authority peer may mutate its health. Route the damage over RPC (#83).
			body.rpc_id(body.get_multiplayer_authority(), "net_remote_damage", damage_on_hit, thrower_name, weapon_name, team)
		queue_free()
		return
	# Pickup path — grant weapon + full magazine.
	if _grace > 0.0 and str(body.get("display_name")) == thrower_name:
		return
	if body.has_method("try_pickup_weapon"):
		var picked: bool = false
		if multiplayer.multiplayer_peer == null or body.is_multiplayer_authority():
			picked = body.try_pickup_weapon(weapon_name, mag_on_drop)
		elif body.has_method("net_remote_pickup"):
			# Host is authoritative for pickup contacts, but the loadout lives on
			# the body's owning peer. Pre-check the body's loadout so we don't
			# route a grant a client will silently reject — otherwise the pickup
			# is consumed with no weapon delivered (#98).
			if _body_has_weapon(body, weapon_name):
				body.rpc_id(body.get_multiplayer_authority(), "net_remote_pickup", weapon_name, mag_on_drop)
				picked = true
		if picked:
			_consumed = true
			Sfx.ui()
			queue_free()


func _body_has_weapon(body: Node, wname: String) -> bool:
	# Mirrors try_pickup_weapon's check on player.gd: the weapon must live in
	# either the body's primary `weapons` list or its `secondary` list for the
	# grant to land. Both arrays are dicts with a "name" key.
	var primaries: Variant = body.get("weapons")
	if primaries != null:
		for w in primaries:
			if str(w.get("name", "")) == wname:
				return true
	var secondaries: Variant = body.get("secondary")
	if secondaries != null:
		for w in secondaries:
			if str(w.get("name", "")) == wname:
				return true
	# Bots today only understand AK-74 / LAW — mirror bot.try_pickup_weapon's
	# rule so a bot-owned peer doesn't ghost-eat a Barrett drop.
	if body.get("weapons") == null and body.get("secondary") == null:
		return wname == "AK-74" or wname == "LAW"
	return false


func _draw() -> void:
	var tex: Texture2D = SoldierArt._weapon_texture(weapon_name)
	if tex != null:
		var size := tex.get_size() * (1.0 / 3.0)
		draw_texture_rect(tex, Rect2(Vector2(-size.x * 0.5, -size.y * 0.5), size), false)
	else:
		draw_rect(Rect2(-12, -3, 24, 6), Color(0.85, 0.85, 0.95))
