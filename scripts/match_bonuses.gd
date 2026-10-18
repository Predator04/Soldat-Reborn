extends Node
## Main's pickups (#258 split of main.gd): bonus boxes (#78), medikits /
## grenade kits, and the weapon-pickup stream.
##
## Host owns spawn slots + collection detection. Boxes are Area2D nodes; the
## BonusPickup script emits `touched` on host only. Application of the effect
## is routed via each player's net_bonus_apply RPC (call_local) so every peer
## applies the same effect to the target replica. Weapon pickups are host
## physics bodies mirrored to clients by net_pickup_state (#34, #247).
##
## The @rpc entry points stay on Main (same node path + name). Slot bookkeeping
## lives here; shared match state (_bonus_boxes, _ready_peers, ...) stays on Main.

const Main = preload("res://scripts/main.gd")
const WeaponPickup = preload("res://scripts/weapon_pickup.gd")
const BonusPickup = preload("res://scripts/bonus_pickup.gd")

var main: Main

# ── Bonus pickups (#78) ───────────────────────────────
# Host-authoritative: host places boxes, detects collection, applies effect
# to the toucher and schedules the box slot's respawn. Clients mirror boxes
# via net_bonus_spawn / net_bonus_despawn.
const BONUS_RESPAWN := 20.0
const BONUS_EFFECT_DURATION := 30.0
const BONUS_MAX_SLOTS := 3
# Medikits / grenade kits (v1.18) — Soldat map pickups, bots take them too.
const KIT_RESPAWN := 25.0
const KIT_MAX_EACH := 6
var _bonus_slot_kind: Array = []     # host: "" = random bonus, else fixed kit kind
var _kit_poll_t := 0.0
var _bonus_slots: Array = []         # host: list of Vector2 spawn positions
var _bonus_slot_cd: Array = []       # host: seconds until each slot respawns
var _bonus_slot_active: Array = []   # host: bonus_id currently occupying each slot (0 = empty)
var _next_bonus_id: int = 1          # host: monotonic id minter
var _next_pickup_id: int = 1


func _spawn_map_weapon_pickups() -> void:
	# #113: map editor can place resting weapon pickups. Only the host spawns
	# them — clients receive them via the normal pickup state stream.
	var wps: Array = main._map.get("weapon_pickups", [])
	if wps.is_empty():
		return
	if Net.is_networked() and not Net.is_host():
		return
	for wp_def in wps:
		if typeof(wp_def) != TYPE_DICTIONARY:
			continue
		# #256: banned weapons don't enter the world at all.
		if MatchConfig.weapon_banned(str(wp_def.get("weapon", "AK-74"))):
			continue
		var wp := WeaponPickup.new()
		wp.weapon_name = str(wp_def.get("weapon", "AK-74"))
		wp.team = -1
		wp.thrower_name = ""
		wp.damage_on_hit = 0.0
		wp.global_position = wp_def.get("pos", Vector2.ZERO)
		# #241: a map slot is part of the level, not a 20 s prop — never expire.
		wp.persistent = true
		wp.set_meta("map_spawn", true)
		if Net.is_networked() and Net.is_host():
			wp.pickup_id = next_pickup_id()
		main.add_child(wp)


func _spawn_bonus_boxes_init() -> void:
	# Client: waits for host to broadcast net_bonus_spawn. No local slots needed.
	if Net.is_networked() and not Net.is_host():
		return
	# #113: map editor can supply an explicit "bonus_spawns" list; fall back to
	# bot spawns when not specified so procedural + legacy maps still spawn bonus
	# boxes at bot positions.
	var explicit: Array = main._map.get("bonus_spawns", [])
	var spots: Array = explicit.duplicate() if not explicit.is_empty() \
		else (main._map.get("bot_spawns", []) as Array).duplicate()
	spots.shuffle()
	var count: int = mini(BONUS_MAX_SLOTS, spots.size())
	for i in count:
		# Lift each slot a bit above the ground so the crate reads floating and
		# isn't clipped by the terrain body.
		_bonus_slots.append((spots[i] as Vector2) + Vector2(0, -22.0))
		_bonus_slot_cd.append(0.0)
		_bonus_slot_active.append(0)
		_bonus_slot_kind.append("")
	# Kits sit on the ground where the map maker put them.
	for pair in [["medkits", "medkit"], ["grenade_kits", "grenades"]]:
		var pts: Array = (main._map.get(pair[0], []) as Array).duplicate()
		pts.shuffle()
		for i in mini(KIT_MAX_EACH, pts.size()):
			var v = pts[i]
			var kp: Vector2 = v if v is Vector2 else Vector2(float(v[0]), float(v[1]))
			_bonus_slots.append(kp + Vector2(0, -14.0))
			_bonus_slot_cd.append(0.0)
			_bonus_slot_active.append(0)
			_bonus_slot_kind.append(pair[1])
	for i in _bonus_slots.size():
		_spawn_bonus_at_slot(i)


func _spawn_bonus_at_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _bonus_slots.size():
		return
	if int(_bonus_slot_active[slot_idx]) != 0:
		return  # slot already occupied
	var pos: Vector2 = _bonus_slots[slot_idx]
	var kind: String = str(_bonus_slot_kind[slot_idx]) if slot_idx < _bonus_slot_kind.size() else ""
	if kind == "":
		kind = BonusPickup.KINDS[randi() % BonusPickup.KINDS.size()]
	var bid: int = _next_bonus_id
	_next_bonus_id += 1
	_bonus_slot_active[slot_idx] = bid
	_make_bonus_box_local(bid, pos, kind, slot_idx)
	# Mirror to every client whose main.tscn is loaded (see #84 for why we key
	# off _connected_peers rather than the acked-only _ready_peers).
	if Net.is_networked() and Net.is_host():
		for pid in main._connected_peers.keys():
			main.rpc_id(int(pid), "net_bonus_spawn", bid, pos, kind)


func _make_bonus_box_local(bid: int, pos: Vector2, kind: String, slot_idx: int) -> void:
	# Idempotent: if a box with this id already exists (e.g., late client spawn
	# arrived after we joined), free it before mounting the replacement.
	if main._bonus_boxes.has(bid):
		var old = main._bonus_boxes[bid]
		if is_instance_valid(old):
			old.queue_free()
	var box: Area2D = BonusPickup.new()
	box.bonus_id = bid
	box.bonus_kind = kind
	box.position = pos
	box.name = "Bonus_%d" % bid
	box.set_meta("slot", slot_idx)
	# Host: bind the collision-triggered signal to our collect handler. Client
	# replicas don't need this — the box is inert until the host says so.
	if not Net.is_networked() or Net.is_host():
		box.touched.connect(main._on_bonus_touched.bind(bid, slot_idx))
	main._bonus_boxes[bid] = box
	main.add_child(box)


func _on_bonus_touched(body: Node, bid: int, slot_idx: int) -> void:
	# Host-only collection. In SP the local player is the sole eligible toucher;
	# in MP we resolve peer_id via _players_by_id. Bots are ignored — the bonus
	# system is a player perk.
	if Net.is_networked() and not Net.is_host():
		return
	var box: Node = main._bonus_boxes.get(bid, null)
	if not is_instance_valid(box):
		return
	var kind: String = str(box.get("bonus_kind"))
	if kind in BonusPickup.KIT_KINDS:
		_collect_kit(body, bid, slot_idx, kind)
		return
	var peer_id: int = 0
	if not Net.is_networked():
		if body != main.player:
			return  # bots + non-player bodies don't collect
		peer_id = 1
	else:
		for pid in main._players_by_id.keys():
			if main._players_by_id[pid] == body:
				peer_id = int(pid)
				break
		if peer_id == 0:
			return  # not a player peer (bot) — ignore
	# Apply the effect via the target player's call_local RPC so every peer's
	# replica of that soldier ticks the same effect state.
	if main._players_by_id.has(peer_id):
		var p = main._players_by_id[peer_id]
		if is_instance_valid(p) and p.has_method("apply_bonus"):
			p.apply_bonus(kind, BONUS_EFFECT_DURATION)
	elif not Net.is_networked() and is_instance_valid(main.player):
		main.player.apply_bonus(kind, BONUS_EFFECT_DURATION)
	# Despawn on every peer.
	if Net.is_networked() and Net.is_host():
		main.bcast("net_bonus_despawn", [bid], false)
	_despawn_bonus_local(bid)
	# Free the slot and start the respawn countdown so a new random-kind box
	# will land there in BONUS_RESPAWN seconds.
	if slot_idx >= 0 and slot_idx < _bonus_slot_cd.size():
		_bonus_slot_active[slot_idx] = 0
		_bonus_slot_cd[slot_idx] = BONUS_RESPAWN


# Medikit heals to full, grenade kit refills to 3 — for players and bots, and
# only when it would do something (a full-health soldier leaves the medikit).
func _collect_kit(body: Node, bid: int, slot_idx: int, kind: String) -> void:
	if not is_instance_valid(body) or body.get("dead") == true or body.get("health") == null:
		return
	if kind == "medkit" and float(body.get("health")) >= 100.0:
		return
	if kind == "grenades" and int(body.get("grenades")) >= 3:
		return
	if body.has_method("apply_kit"):
		body.apply_kit(kind)   # player: routed to its owner
	elif kind == "medkit":
		body.set("health", 100.0)
	else:
		body.set("grenades", 3)
	main.kits_taken += 1
	if Net.is_networked() and Net.is_host():
		main.bcast("net_bonus_despawn", [bid], false)
	_despawn_bonus_local(bid)
	if slot_idx >= 0 and slot_idx < _bonus_slot_cd.size():
		_bonus_slot_active[slot_idx] = 0
		_bonus_slot_cd[slot_idx] = KIT_RESPAWN


func _despawn_bonus_local(bid: int) -> void:
	var box: Node = main._bonus_boxes.get(bid, null)
	if is_instance_valid(box):
		# Every peer runs this on collection, so everyone hears the pickup.
		Sfx.pickup_kit(str(box.get("bonus_kind")), (box as Node2D).global_position)
		box.queue_free()
	main._bonus_boxes.erase(bid)


func _tick_bonus_boxes(delta: float) -> void:
	if _bonus_slots.is_empty():
		return
	# body_entered fires once; a soldier already standing on a kit when he
	# gets hurt (or throws his last grenade) should still pick it up.
	_kit_poll_t -= delta
	if _kit_poll_t <= 0.0:
		_kit_poll_t = 0.3
		for bid in main._bonus_boxes.keys():
			var box = main._bonus_boxes[bid]
			if not is_instance_valid(box) or not (str(box.get("bonus_kind")) in BonusPickup.KIT_KINDS):
				continue
			for b in (box as Area2D).get_overlapping_bodies():
				if b is CharacterBody2D:
					_collect_kit(b, int(bid), int(box.get_meta("slot", -1)), str(box.get("bonus_kind")))
					break
	for i in _bonus_slot_cd.size():
		if int(_bonus_slot_active[i]) != 0:
			continue
		var cd: float = float(_bonus_slot_cd[i]) - delta
		_bonus_slot_cd[i] = cd
		if cd <= 0.0:
			_spawn_bonus_at_slot(i)


func net_bonus_spawn(bid: int, pos: Vector2, kind: String) -> void:
	# Host already has this locally; this RPC targets clients only.
	if Net.is_host():
		return
	_make_bonus_box_local(bid, pos, kind, -1)


func net_bonus_despawn(bid: int) -> void:
	if Net.is_host():
		return
	_despawn_bonus_local(bid)


func next_pickup_id() -> int:
	var id: int = _next_pickup_id
	_next_pickup_id += 1
	return id


## One pickup's stream entry — shared by the 10 Hz broadcast and the late-joiner
## push so both produce byte-identical arrays (the per-peer change signature
## seeded at join must match what the next tick would send, #247/#254).
func _pickup_entry(wp) -> Dictionary:
	return {
		"id": int(wp.get("pickup_id")),
		"name": str(wp.get("weapon_name")),
		"team": int(wp.get("team")),
		"thrower": str(wp.get("thrower_name")),
		# #254: client copies must know a slot is persistent, or their local
		# 20 s _life expires a map slot the host keeps forever.
		"p": bool(wp.get("persistent")),
		# #247: quantize motion to stop resting bodies from flickering the
		# change signature (and the wire format) with 1e-5 velocities.
		"pos": (wp.global_position as Vector2).snapped(Vector2(0.25, 0.25)),
		"vel": (wp.linear_velocity as Vector2).snapped(Vector2.ONE),
		"ang": roundf(float(wp.angular_velocity) * 8.0) / 8.0,
		"rot": roundf(float(wp.rotation) * 1000.0) / 1000.0,
		# #94: carry damage explicitly so future damage-on-hit weapons
		# (axe/bayonet/etc.) don't silently lose their damage on clients
		# because we re-derived by name.
		"dmg": float(wp.get("damage_on_hit")),
	}


func _broadcast_pickup_state() -> void:
	# Collect every host-authoritative pickup body + its live physics state.
	var arr: Array = []
	for wp in main.get_tree().get_nodes_in_group("weapon_pickup"):
		if not is_instance_valid(wp):
			continue
		if int(wp.get("pickup_id")) <= 0:
			continue
		# #241: a regenerating map slot is absent from the stream — clients
		# despawn it, and it comes back the same way when the slot rearms.
		var wp_active = wp.get("active")
		if wp_active != null and not bool(wp_active):
			continue
		arr.append(_pickup_entry(wp))
	# #247: this full snapshot used to fire reliably at 10 Hz regardless of
	# change — a resting battlefield head-of-line-blocked the unreliable
	# state streams for nothing. Send only when the world actually changed
	# (or to a peer that hasn't seen the current state yet, e.g. a fresh
	# joiner).
	var sig := str(arr)
	for pid in main._ready_peers.keys():
		if str(main._pickup_peer_sig.get(int(pid), "")) == sig:
			continue
		main._pickup_peer_sig[int(pid)] = sig
		main.rpc_id(int(pid), "net_pickup_state", arr)


func net_pickup_state(arr: Array) -> void:
	# Map existing frozen pickups by id, spawn any we haven't seen, and reconcile
	# positions. Host-only pickups that vanish trigger client-side despawn.
	var seen: Dictionary = {}
	var by_id: Dictionary = {}
	for wp in main.get_tree().get_nodes_in_group("weapon_pickup"):
		if not is_instance_valid(wp):
			continue
		var pid: int = int(wp.get("pickup_id"))
		if pid > 0:
			by_id[pid] = wp
	for entry in arr:
		var id: int = int(entry.get("id", 0))
		if id <= 0:
			continue
		seen[id] = true
		var wp: Node = by_id.get(id) as Node
		if wp == null:
			# First time we're hearing about this pickup — spawn a client-frozen copy.
			# #69: give it a stable name matching the id so future per-instance RPCs
			# (should we ever add pickup-level state sync) resolve on both peers.
			var new_wp := WeaponPickup.new()
			new_wp.pickup_id = id
			new_wp.name = "Pickup_%d" % id
			new_wp.weapon_name = str(entry.get("name", "AK-74"))
			new_wp.team = int(entry.get("team", 0))
			new_wp.thrower_name = str(entry.get("thrower", ""))
			# #254: map slots are persistent on the host — the client copy must
			# not run its own 20 s _life (the signature-gated stream only
			# re-sends on change, so nothing would resurrect it).
			new_wp.persistent = bool(entry.get("p", false))
			# #94: pull damage from the host's payload instead of reconstructing
			# by weapon name. Fallback to the legacy Knife=55 rule when the host
			# is running a pre-#94 build with no "dmg" field.
			if entry.has("dmg"):
				new_wp.damage_on_hit = float(entry.get("dmg", 0.0))
			else:
				new_wp.damage_on_hit = 55.0 if str(entry.get("name", "")) == "Knife" else 0.0
			new_wp.global_position = entry.get("pos", Vector2.ZERO)
			main.add_child(new_wp)
			wp = new_wp
		wp.global_position = entry.get("pos", wp.global_position)
		wp.linear_velocity = entry.get("vel", Vector2.ZERO)
		wp.angular_velocity = float(entry.get("ang", 0.0))
		wp.rotation = float(entry.get("rot", 0.0))
	# Despawn any client-side pickup whose id no longer appears in the host's list.
	for pid in by_id.keys():
		if not seen.has(pid):
			var wp: Node = by_id[pid]
			if is_instance_valid(wp):
				wp.queue_free()
