class_name TrustGuard
extends RefCounted
## Host-side checks on what a client says about its own soldier.
##
## Human players are simulated by their own peer: the client computes the
## damage it takes, moves its body, and reports its own death (who killed it).
## That keeps the game feeling instant on every connection, but it means a
## modified client could ignore damage, teleport, or hand kills to a friend.
## The host keeps a shadow of what it saw happen and steps in when the client's
## story can't be true:
##
## * Ignored damage — the host's own hit detection saw this body take far more
##   than a lethal amount since its last heal, but the client reported almost
##   none of it. Host and client views differ by latency, so the threshold is
##   several lives' worth and a ratio, not a per-hit comparison.
## * HP above the cap, or HP rising with no heal the host knows about.
## * Moving faster than anything in the game can push a soldier (teleports,
##   speed hacks) or leaving the world.
## * Kill credit for someone who wasn't attacking: the named killer must have
##   fired / swung / driven recently and (without friendly fire) be an enemy.
##
## Enforcement is a host-side death (everyone, including the owner, sees it;
## the host ignores the old body's packets) and a strike; three strikes in
## five minutes is a kick. Bots and the host's own player are never checked.
## None of this runs in single player or on clients.

const SHADOW_KILL_DMG := 200.0     # host-seen damage since the last heal (two lives)...
const SHADOW_RATIO := 0.10         # ...while the client reported at most this share of it
const MAX_SPEED := 4000.0          # px/s; roll 650, fall cap 1200, rocket jumps well under this
const SPEED_SPAN_MS := 250         # measure speed over at least this much host time
const SPAWN_GRACE_MS := 2500       # fresh bodies / round resets may jump to a spawn
const WORLD_MARGIN := 2000.0
const HP_EPS := 0.5
const HEAL_WINDOW_MS := 2000       # a kit / round reset heal lands within this
const CLAMPS_PER_LIFE := 5         # HP clamps tolerated before a forced death
const MOVES_PER_LIFE := 2          # movement violations tolerated before a forced death
const ACTIVITY_WINDOW_MS := 10000  # kill credit needs an attack within this
const STRIKE_WINDOW_MS := 300000
const STRIKES_TO_KICK := 3

# name -> [ms, team] of the last attack (shot, throw, swing, ram) seen by the host.
static var _activity: Dictionary = {}
# peer id -> Array of strike times (ms).
static var _strikes: Dictionary = {}


static func reset_match() -> void:
	_activity.clear()
	_strikes.clear()


static func enabled() -> bool:
	return Net.is_networked() and Net.is_host()


static func note_activity(attacker: String, attacker_team: int) -> void:
	if attacker == "" or not enabled():
		return
	_activity[attacker] = [Time.get_ticks_msec(), attacker_team]


## Whether `killer` may be credited for the death of `victim` (on `victim_team`).
static func kill_credit_ok(killer: String, victim: String, victim_team: int) -> bool:
	if killer == "" or killer == victim:
		return true
	var a = _activity.get(killer)
	if a == null:
		return false
	if Time.get_ticks_msec() - int(a[0]) > ACTIVITY_WINDOW_MS:
		return false
	if int(a[1]) == victim_team and not MatchConfig.friendly_fire_on():
		return false
	return true


static func add_strike(peer_id: int) -> int:
	var now := Time.get_ticks_msec()
	var list: Array = _strikes.get(peer_id, [])
	list = list.filter(func(t) -> bool: return now - int(t) <= STRIKE_WINDOW_MS)
	list.append(now)
	_strikes[peer_id] = list
	return list.size()


# ── per-body state (one guard per remote human body on the host) ──

var born_ms := 0
var amnesty_until_ms := 0
var heal_until_ms := 0
var last_hp := 100.0
var shadow := 0.0          # damage the host saw land since the last heal
var reported := 0.0        # damage the client reported since the last heal
var fired := false         # attacked since spawning (spawn protection is over)
var last_hitter := ""
var last_hitter_weapon := ""
var last_hitter_team := -1
var clamps := 0
var moves := 0
var _hist: Array = []      # [ms, pos] of recent state packets
var _last_clamp_log_ms := -100000
var _ride_until_ms := 0   # riding (or just got in / out of) a vehicle or M2


func _init() -> void:
	born_ms = Time.get_ticks_msec()
	amnesty_until_ms = born_ms + SPAWN_GRACE_MS


## Round reset / anything the host does that legitimately moves or heals the body.
func amnesty() -> void:
	var now := Time.get_ticks_msec()
	amnesty_until_ms = now + SPAWN_GRACE_MS
	heal_until_ms = now + HEAL_WINDOW_MS
	_hist.clear()


func allow_heal() -> void:
	heal_until_ms = Time.get_ticks_msec() + HEAL_WINDOW_MS


func note_fired() -> void:
	fired = true


## Damage the host's own hit detection saw this body take (the owner applies the
## real damage). `vest` / spawn protection mirror Player.take_damage.
func observe_hit(amount: float, killer: String, weapon: String, killer_team: int, own_name: String, vest: bool, ceasefire_secs: float) -> void:
	if killer != own_name and not fired and Time.get_ticks_msec() - born_ms < int((ceasefire_secs + 0.5) * 1000.0):
		return
	if vest and killer != own_name:
		amount *= 0.5
	shadow += maxf(0.0, amount)
	if OS.get_cmdline_user_args().has("--trust-debug"):
		print("TRUSTDBG hit %.1f by %s total %.1f" % [amount, killer, shadow])
	if killer != "" and killer != own_name:
		last_hitter = killer
		last_hitter_weapon = weapon
		last_hitter_team = killer_team


## Check one state packet. Returns {"hp": hp to accept, "force": reason or ""}.
func check_state(pos: Vector2, hp: float, heal_ok_now: bool, world: Rect2, riding := false) -> Dictionary:
	var now := Time.get_ticks_msec()
	if riding:
		_ride_until_ms = now + 1500   # covers the seat snap in and the eject out
	var force := ""
	var h := hp
	# ── health ──
	if h > 100.0 + HP_EPS or (h > last_hp + HP_EPS and not heal_ok_now and now > heal_until_ms):
		h = minf(last_hp, 100.0)
		clamps += 1
		if now - _last_clamp_log_ms > 1000:
			_last_clamp_log_ms = now
			print("TRUST hp clamp: reported %.0f, kept %.0f" % [hp, h])
		if clamps >= CLAMPS_PER_LIFE:
			force = "hp"
	elif h > last_hp + HP_EPS:
		shadow = 0.0      # a real heal starts a fresh account
		reported = 0.0
	elif h < last_hp:
		reported += last_hp - h
		if OS.get_cmdline_user_args().has("--trust-debug"):
			print("TRUSTDBG reported %.1f shadow %.1f" % [reported, shadow])
	last_hp = h
	if force == "" and shadow >= SHADOW_KILL_DMG and reported <= shadow * SHADOW_RATIO:
		force = "ignored damage (host saw %.0f, client reported %.0f)" % [shadow, reported]
	# ── movement ──
	if now < amnesty_until_ms or now < _ride_until_ms:
		_hist = [[now, pos]]
	else:
		_hist.append([now, pos])
		while _hist.size() > 2 and now - int(_hist[1][0]) >= SPEED_SPAN_MS:
			_hist.pop_front()
		var moved := ""
		if _hist.size() >= 2 and now - int(_hist[0][0]) >= SPEED_SPAN_MS:
			var span: float = float(now - int(_hist[0][0])) / 1000.0
			var spd: float = pos.distance_to(_hist[0][1]) / span
			if spd > MAX_SPEED:
				moved = "speed %.0f px/s" % spd
		if moved == "" and world.size != Vector2.ZERO and not world.grow(WORLD_MARGIN).has_point(pos):
			moved = "out of world at (%.0f, %.0f)" % [pos.x, pos.y]
		if moved != "":
			moves += 1
			print("TRUST move: %s" % moved)
			_hist = [[now, pos]]
			if moves >= MOVES_PER_LIFE and force == "":
				force = "movement (%s)" % moved
	return {"hp": h, "force": force}
