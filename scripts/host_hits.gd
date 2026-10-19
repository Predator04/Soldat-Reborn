class_name HostHits
extends RefCounted
## Host-decided hits on human players (#266).
##
## Every peer still simulates every shot, tracer, grenade and rocket (so firing
## and being shot at look and sound instant), but only the HOST decides whether
## one of them hurts a human player and by how much:
##
## * On the host, a remote human's health is a ledger (`player.health` on the
##   host's copy). Bullets / melee / splash / vehicles / the BR ring reach it
##   through `HostHits.damage()` -> `player.host_damage()`, which applies spawn
##   protection and the vest exactly like `Player.take_damage`, then tells the
##   owner (`net_hit`, carrying the resulting health). When the ledger reaches
##   zero the host declares the death (killer from the ledger) to everyone.
## * The owner never applies hits from its own simulation any more; its state
##   packets report health, which the host only compares (and corrects).
## * Lag compensation: the host keeps ~0.5 s of hitbox history for every remote
##   human (its own smoothed view, which the shooter's screen shows one relay
##   hop later). The host stamps the state it relays with its clock; a shot
##   says which host moment its shooter was looking at (`view_now`), and its
##   hits on remote humans are tested against their boxes at that moment
##   (`rewind_from_view`, capped near the shooter's measured round trip and at
##   REWIND_MAX_MS), so what the shooter saw is what counts. Bots and the
##   host's own player keep the old rules (current position / `lag_ms`).
##
## Routing for any damage source (`route`):
##   APPLY  this peer owns the body: single player, the host's own player, bots.
##   HOST   the host and a remote human's body: decide it here.
##   NONE   a client: the host decides (the local copy only shows the impact).

enum { NONE, APPLY, HOST }

const REWIND_MAX_MS := 300       # never reach back further than this
const HIST_MS := 520             # hitbox history kept per body
const BROAD_SPEED := 1300.0      # px/s no soldier exceeds (falls cap at 1200)

## Counters (host): what was decided and what was refused. Tests read these
## (and the HOSTHITS / TRUST log lines); reset per match.
static var stats: Dictionary = {}
## Per shooter name: [hits, damage] the host applied to remote humans.
static var by_shooter: Dictionary = {}
## Test switch (--hosthit-rewind=0): host-side hit tests without rewind.
static var rewind_off := false

# Remote human bodies on the host (registered by player.gd).
static var _remote: Array = []
static var _remote_rids: Array[RID] = []
static var _rids_dirty := true


static func reset_match() -> void:
	stats.clear()
	by_shooter.clear()
	_remote = _remote.filter(func(n) -> bool: return is_instance_valid(n))
	_rids_dirty = true
	_view_host = 0
	_view_local = 0
	rewind_off = OS.get_cmdline_user_args().has("--hosthit-rewind=0")


static func count(key: String, n: float = 1.0) -> void:
	stats[key] = float(stats.get(key, 0.0)) + n


static func summary() -> String:
	var keys := stats.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%s" % [k, str(snappedf(float(stats[k]), 0.1))])
	var sh: PackedStringArray = []
	for n in by_shooter.keys():
		sh.append("%s:%d/%.0f" % [n, int(by_shooter[n][0]), float(by_shooter[n][1])])
	return "%s shooters=[%s]" % [" ".join(parts), ",".join(sh)]


# ── routing ──

static func route(s: Node) -> int:
	if s == null or not is_instance_valid(s):
		return NONE
	if s.multiplayer.multiplayer_peer == null:
		return APPLY
	var human := s.has_method("host_damage")
	if s.is_multiplayer_authority():
		# A client's own soldier: the host decides what hits it.
		if human and Net.is_networked() and not Net.is_host():
			return NONE
		return APPLY
	if human and Net.is_networked() and Net.is_host():
		return HOST
	return NONE


## Apply a hit on soldier `s` wherever this peer is the one that decides it.
## `ignore_protection` mirrors callers that clear ceasefire first (run-overs).
static func damage(s: Node, amount: float, killer: String, weapon: String, killer_team: int, ignore_protection := false, coalesce := false) -> void:
	match route(s):
		APPLY:
			if ignore_protection:
				s.set("ceasefire_t", 0.0)
			s.take_damage(amount, killer, weapon, killer_team)
		HOST:
			s.host_damage(amount, killer, weapon, killer_team, ignore_protection, coalesce)


static func is_remote_human(s: Node) -> bool:
	return s != null and s.has_method("host_damage") and s.multiplayer.multiplayer_peer != null \
			and not s.is_multiplayer_authority() and Net.is_networked() and Net.is_host()


# ── remote human registry (host) ──

static func register(s: Node) -> void:
	if not _remote.has(s):
		_remote.append(s)
		_rids_dirty = true


static func unregister(s: Node) -> void:
	var i := _remote.find(s)
	if i >= 0:
		_remote.remove_at(i)
		_rids_dirty = true


static func remote_humans() -> Array:
	return _remote


static func remote_rids() -> Array[RID]:
	if _rids_dirty:
		_rids_dirty = false
		_remote_rids.clear()
		_remote = _remote.filter(func(n) -> bool: return is_instance_valid(n))
		for n in _remote:
			_remote_rids.append((n as CollisionObject2D).get_rid())
	return _remote_rids


# ── lag compensation ──

## How far back the host should look for a shot by `killer_name`: the round
## trip between that player and the host. Zero for the host's own player,
## bots and anything the host simulates itself.
static func rewind_for(tree: SceneTree, killer_name: String) -> int:
	if rewind_off or killer_name == "" or not (Net.is_networked() and Net.is_host()):
		return 0
	var m := tree.current_scene
	if m == null or m.get("_players_by_id") == null:
		return 0
	var pbi: Dictionary = m.get("_players_by_id")
	for pid in pbi.keys():
		var p = pbi[pid]
		if is_instance_valid(p) and str(p.display_name) == killer_name:
			if int(pid) == 1 or int(pid) == Net.local_id():
				return 0
			var net = m.get("_net")
			if net != null and net.has_method("peer_rtt_ms"):
				return clampi(int(net.peer_rtt_ms(int(pid))), 0, REWIND_MAX_MS)
			return 0
	return 0


## Client: the newest host stamp we've seen on a relayed state packet and when.
static var _view_host := 0
static var _view_local := 0


static func note_view(host_ms: int) -> void:
	if host_ms >= _view_host or host_ms < _view_host - 10000:   # (a different host)
		_view_host = host_ms
		_view_local = Time.get_ticks_msec()


## This peer's game clock in ms (physics frames: never runs ahead of real
## time). Shots carry it so the host can see their real spacing.
static func game_ms() -> int:
	return int(Engine.get_physics_frames() * 1000 / maxi(1, Engine.physics_ticks_per_second))


## Client: the host-clock moment our screen shows right now (0 if unknown).
## Sent with every shot: the host rewinds it to exactly what we saw, however
## much the connection's delay wobbles.
static func view_now() -> int:
	if _view_host <= 0 or not Net.is_networked() or Net.is_host():
		return 0
	return _view_host + (Time.get_ticks_msec() - _view_local)


## Host: rewind for a shot that says it was aimed at our moment `view_ms`,
## received now from a player whose round trip is about `rtt` ms. Capped near
## the measured round trip, so claiming an old view buys little.
static func rewind_from_view(view_ms: int, rtt: int) -> int:
	if rewind_off:
		return 0
	if view_ms <= 0:
		return clampi(rtt, 0, REWIND_MAX_MS)
	var r := Time.get_ticks_msec() - view_ms
	var cap := mini(REWIND_MAX_MS, maxi(rtt, 0) + 100)
	count("rewind_shots")
	count("rewind_ms", float(clampi(r, 0, cap)))
	count("rewind_over_rtt_ms", float(r - rtt))
	if r > cap:
		count("rewind_capped")
	return clampi(r, 0, cap)


## The hitbox to test for a shot rewound by `ms`: the host's own view of the
## body that long ago (interpolated between recorded frames). Measured against
## shooter-side predictions at 100-200 ms (tools/hosthits_test.gd), one box at
## the shot's own rewind agrees best; testing neighbouring moments too only
## adds hits the shooter never saw.
static func rect_at(s: Node, ms: int) -> Rect2:
	if ms <= 0:
		return s.hitbox_now()
	return s.hitbox_at(ms)


## First hit of a ray from `a` to `b` against level geometry (terrain and
## bullets-only terrain; loose physics objects like dropped weapons don't
## count — their positions differ a little from peer to peer). {} if clear.
static func solid_ray(world: World2D, a: Vector2, b: Vector2, exclude: Array[RID] = []) -> Dictionary:
	var ex: Array[RID] = exclude.duplicate()
	var space := world.direct_space_state
	for _i in 4:
		var q := PhysicsRayQueryParameters2D.create(a, b, 1 | 2, ex)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.get("collider") is StaticBody2D:
			return hit
		ex.append(hit["rid"])
	return {}


## Feet position of `s` as a shooter `ms` behind saw it (splash / melee).
static func pos_at(s: Node, ms: int) -> Vector2:
	if ms <= 0 or not is_remote_human(s):
		return (s as Node2D).global_position
	var r: Rect2 = s.hitbox_at(ms)
	return Vector2(r.get_center().x, r.end.y)
