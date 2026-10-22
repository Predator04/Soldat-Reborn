class_name TrustGuard
extends RefCounted
## Host-side checks on what a client says about its own soldier.
##
## Human players are simulated by their own peer: the client moves its body,
## jets, aims and fires, and reports all of that in its state stream. That
## keeps the game feeling instant on every connection, but it means a modified
## client could lie. Since #266 the HOST decides every hit on a human (see
## host_hits.gd: the host's copy keeps the health ledger and declares deaths),
## so taking partial / no damage is impossible by construction. What the
## client still says about itself is checked here, one guard per remote human
## body on the host:
##
## * Health: the client's figure is compared with the host's ledger as it was
##   over the last round trip. A client that drifts gets the host's number sent
##   back (`net_hit` with no damage); one that keeps reporting more than it was
##   ever given after corrections is logged (`TRUST hp`). The ledger wins anyway.
## * Movement: faster than anything in the game can push a soldier (teleports,
##   speed hacks) or leaving the world.
## * Jet fuel: a shadow tank drains while the client reports its jets on and
##   refills (generously, even in the air) while they are off. Jetting on an
##   empty shadow tank for a while is a violation; the relayed fuel is clamped.
## * Shots (net_shoot / net_grenade): pellet count and unit directions, the
##   muzzle must be at the shooter's own body (and not through a wall), the
##   direction must agree with the aim the client streams, a magazine can't
##   outlast its size without a reload the host saw, and the long-run fire rate
##   can't beat the weapon's (a token bucket on top of the #243 minimum gap).
## * Kill credit for someone who wasn't attacking (client-reported deaths are
##   now only self-inflicted ones: the kill line, hazards, /kill).
##
## Escalation is the same everywhere: a refused shot / clamp is logged
## (`TRUST <kind>: ...`, rate-limited) and counted (HostHits.stats); enough of
## them in one life is a host-side forced death and a strike; three strikes in
## five minutes is a kick. One borderline event never kicks anyone. Bots and
## the host's own player are never checked. None of this runs in single player
## or on clients.

const MAX_SPEED := 4000.0          # px/s; roll 650, fall cap 1200, rocket jumps well under this
const SPEED_SPAN_MS := 250         # measure speed over at least this much host time
const SPAWN_GRACE_MS := 2500       # fresh bodies / round resets may jump to a spawn
const WORLD_MARGIN := 2000.0
const MOVES_PER_LIFE := 2          # movement violations tolerated before a forced death
const ACTIVITY_WINDOW_MS := 10000  # kill credit needs an attack within this
const STRIKE_WINDOW_MS := 300000
const STRIKES_TO_KICK := 3
# Health (#266): the client's number lags the ledger by a round trip.
const HP_TOL := 6.0
const HP_LAG_PAD_MS := 300         # beyond the measured round trip
const HP_FIX_AFTER_MS := 400       # off for this long -> send the host's number
const HP_FIX_GAP_MS := 500
# Still too high this long and over this many state updates after 2+ fixes
# -> log "host hits ignored". Only a log: nothing acts on it (the ledger
# decides deaths), so #293's 3 s bar for acting on "ignored damage" has
# nothing to guard here; the update count keeps one stalled burst of late
# reports from logging it.
const HP_IGNORED_MS := 1500
const HP_IGNORED_UPDATES := 10
# Spawn protection mirrors Player.CEASEFIRE_SECS; the host sees the body one
# trip late, so it protects a round trip (+ this) longer.
const PROTECT_SLACK_MS := 150
# Jet fuel shadow.
const FUEL_SLACK := 15.0           # shadow may dip this far below empty
const FUEL_DRY_MS := 600           # jetting on an empty shadow this long = one violation
const FUEL_PER_LIFE := 2
# Shots.
const BURST_SECS := 0.5            # token bucket depth, in seconds of the weapon's rate
const RATE_SLACK := 0.97           # refill a hair faster than the weapon fires
const SHOT_FLAGS_PER_LIFE := 8     # refused shots tolerated before a forced death
const AIM_SLACK := 0.35            # rad beyond spread + max bink, vs the last streamed aim
const AIM_ARC_SLACK := 0.2         # rad beyond spread + max bink, vs the aim arc around the shot
const BINK_MAX := 0.18             # Player._shoot: bink adds up to 0.18 rad of spread
const AIM_STALE_MS := 400          # no recent aim sample: nothing to compare with
const GRENADE_GAP_MS := 250        # Player: grenade_cd 0.6 s between throws

# name -> [ms, team] of the last attack (shot, throw, swing, ram) seen by the host.
static var _activity: Dictionary = {}
# peer id -> Array of strike times (ms).
static var _strikes: Dictionary = {}


static func reset_match() -> void:
	_activity.clear()
	_strikes.clear()
	_clocks.clear()
	HostHits.reset_match()


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
var protect_until_ms := 0
var fired := false         # attacked since spawning (spawn protection is over)
var last_hitter := ""
var last_hitter_weapon := ""
var last_hitter_team := -1
var moves := 0
var fuel_flags := 0
var shot_flags := 0
var fuel_shadow := 100.0
var grenades := 3
var _hist: Array = []      # [ms, pos] of recent state packets
var _ride_until_ms := 0    # riding (or just got in / out of) a vehicle or M2
var _got_state := false    # the owner's first state packet has arrived
var _hp_hist: Array = []   # [ms, ledger hp] whenever it changed (and now and then)
var _hp_off_since := -1
var _hp_off_n := 0         # state updates while off
var _hp_fixes := 0
var _hp_last_fix := -100000
var _hp_flagged := false
var _fuel_ms := -1
var _dry_ms := 0.0
var _aims: Array = []      # [ms, angle] of the last streamed aim directions
var _buckets: Dictionary = {}   # weapon name -> [tokens, ms]
var _mags: Dictionary = {}      # net_shoot slot -> rounds left (lazy: full)
var _last_round: Dictionary = {}   # net_shoot slot -> stamp of the last round taken
var _reload_slot := -999
var _reload_since := 0
var _last_gren_ms := -100000
var _log_ms: Dictionary = {}


func _init(protect_ms: int = 3000, rtt_ms: int = 0) -> void:
	born_ms = Time.get_ticks_msec()
	amnesty_until_ms = born_ms + SPAWN_GRACE_MS
	protect_until_ms = born_ms + protect_ms + clampi(rtt_ms, 0, HostHits.REWIND_MAX_MS) + PROTECT_SLACK_MS
	note_ledger(100.0)


## Round reset: the body jumps to a spawn at full health with a fresh
## magazine, three grenades, a full tank and spawn protection.
func amnesty(protect_ms: int = 3000, rtt_ms: int = 0) -> void:
	var now := Time.get_ticks_msec()
	amnesty_until_ms = now + SPAWN_GRACE_MS
	protect_until_ms = now + protect_ms + clampi(rtt_ms, 0, HostHits.REWIND_MAX_MS) + PROTECT_SLACK_MS
	fired = false
	_hist.clear()
	_track.clear()
	for w in _stamps.keys():
		_rate_reset[w] = true
	refill_all()
	grenades = 3
	fuel_shadow = 100.0
	_dry_ms = 0.0
	note_ledger(100.0)


func note_fired() -> void:
	fired = true


## Just spawned / reset / in or out of a seat: the body may have jumped to a
## spot the host hasn't heard about yet, so "where it is" is not reliable.
func placed_recently() -> bool:
	var now := Time.get_ticks_msec()
	return now < amnesty_until_ms or now < _ride_until_ms


func protected() -> bool:
	return not fired and Time.get_ticks_msec() < protect_until_ms


func note_hitter(killer: String, weapon: String, killer_team: int) -> void:
	last_hitter = killer
	last_hitter_weapon = weapon
	last_hitter_team = killer_team


## A refused shot / clamp: count it, log it (once a second per kind) and say
## whether this life has had enough of them for a forced death.
func flag(kind: String, msg: String) -> bool:
	HostHits.count("refused_" + kind)
	shot_flags += 1
	var now := Time.get_ticks_msec()
	if now - int(_log_ms.get(kind, -100000)) > 1000:
		_log_ms[kind] = now
		print("TRUST %s: %s" % [kind, msg])
	return shot_flags >= SHOT_FLAGS_PER_LIFE


# ── health ──

func note_ledger(hp: float) -> void:
	var now := Time.get_ticks_msec()
	_hp_hist.append([now, hp])
	while _hp_hist.size() > 2 and now - int(_hp_hist[1][0]) > 6000:
		_hp_hist.pop_front()


## Compare the client's reported health with the ledger. Returns true when
## the host should send its number back (`net_hit` with no damage).
func check_hp(reported: float, ledger: float, rtt_ms: int, who := "", behind_ms := 0) -> bool:
	var now := Time.get_ticks_msec()
	if _hp_hist.is_empty() or float(_hp_hist[-1][1]) != ledger or now - int(_hp_hist[-1][0]) > 250:
		note_ledger(ledger)
	# Every ledger value the client could still be showing: anything from the
	# last round trip (plus jitter), and whatever stood at the start of it.
	var span := clampi(rtt_ms, 0, HostHits.REWIND_MAX_MS) + HP_LAG_PAD_MS + clampi(behind_ms, 0, 5000)
	var lo := ledger
	var hi := ledger
	for i in range(_hp_hist.size() - 1, -1, -1):
		var e: Array = _hp_hist[i]
		lo = minf(lo, float(e[1]))
		hi = maxf(hi, float(e[1]))
		if now - int(e[0]) > span:
			break
	var too_high := reported > hi + HP_TOL
	if not too_high and reported >= lo - HP_TOL:
		_hp_off_since = -1
		_hp_off_n = 0
		return false
	if _hp_off_since < 0:
		_hp_off_since = now
	_hp_off_n += 1
	var fix := false
	if now - _hp_off_since >= HP_FIX_AFTER_MS and now - _hp_last_fix >= HP_FIX_GAP_MS:
		_hp_last_fix = now
		_hp_fixes += 1
		fix = true
	if too_high and not _hp_flagged and _hp_fixes >= 2 and now - _hp_off_since >= HP_IGNORED_MS and _hp_off_n >= HP_IGNORED_UPDATES:
		_hp_flagged = true
		HostHits.count("hp_ignored")
		print("TRUST hp: %s reports %.0f, host has %.0f (host hits ignored)" % [who, reported, ledger])
	return fix


# ── movement ──

## Check one state packet's position. Returns a forced-death reason or "".
## (`gstamp`: the owner's game clock on this packet, kept with the sample;
## the speed itself is measured in host time — a client's clock must not
## be able to stretch it.)
func check_move(pos: Vector2, world: Rect2, riding := false, gstamp := 0) -> String:
	var now := Time.get_ticks_msec()
	if not _got_state:
		# A fresh body's grace runs from its owner's first state, not from
		# when the host made it: a client still loading the map (a join, a
		# map change on a slow machine) spawns — and may jump — seconds later.
		_got_state = true
		amnesty_until_ms = maxi(amnesty_until_ms, now + SPAWN_GRACE_MS)
	if riding:
		_ride_until_ms = now + 1500   # covers the seat snap in and the eject out
	if now < amnesty_until_ms or now < _ride_until_ms:
		_hist = [[now, pos, gstamp]]
		return ""
	_hist.append([now, pos, gstamp])
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
	if moved == "":
		return ""
	moves += 1
	HostHits.count("refused_move")
	print("TRUST move: %s (%.1f s after the last spawn / reset)" % [moved, float(now - amnesty_until_ms + SPAWN_GRACE_MS) / 1000.0])
	_hist = [[now, pos, gstamp]]
	if moves >= MOVES_PER_LIFE:
		return "movement (%s)" % moved
	return ""


# ── jet fuel ──

## One state packet's jets. `drain` / `regen` are per second at this match's
## jet mod; `cap` is 0 in Realistic (no jets at all). Returns {fuel, force}.
func check_fuel(jetting: bool, reported: float, drain: float, regen: float, cap: float) -> Dictionary:
	var now := Time.get_ticks_msec()
	var dt := 0.0
	if _fuel_ms >= 0:
		dt = clampf(float(now - _fuel_ms) / 1000.0, 0.0, 2.0)
	_fuel_ms = now
	var force := ""
	if jetting:
		# Packets bunched by a stall would over-drain: count at most 0.1 s each.
		var jdt := minf(dt, 0.1)
		fuel_shadow = maxf(-FUEL_SLACK * 2.0, fuel_shadow - drain * jdt)
		if fuel_shadow < -FUEL_SLACK:
			_dry_ms += jdt * 1000.0
			if _dry_ms >= FUEL_DRY_MS:
				_dry_ms = 0.0
				fuel_flags += 1
				HostHits.count("refused_fuel")
				print("TRUST fuel: jetting on an empty tank (host fuel %.0f, client says %.0f)" % [maxf(0.0, fuel_shadow), reported])
				if fuel_flags >= FUEL_PER_LIFE:
					force = "fuel (jetting with an empty tank)"
	else:
		# Real regen only happens on the ground; refilling in the air too keeps
		# the shadow at or above an honest client's tank.
		fuel_shadow = minf(cap, fuel_shadow + regen * dt)
		_dry_ms = 0.0
	return {"fuel": clampf(minf(reported, maxf(0.0, fuel_shadow + FUEL_SLACK)), 0.0, 100.0), "force": force}


# ── the owner's own timeline (its game clock) ──
# Every state packet carries the client's game clock (`gstamp`) and so does
# every shot, so where the body was and where it aimed when it fired are read
# off this timeline by the shot's own stamp: a shot the network delayed (a lost
# reliable packet re-sent a round trip later, a stall) is checked against its
# own moment, not against whatever arrived since.
const TRACK_MS := 3000
const TRACK_AHEAD_MS := 150        # a shot newer than the newest state: extrapolate this far
var _track: Array = []   # [gstamp, pos, vel, aim angle or INF], oldest first


func note_track(gstamp: int, pos: Vector2, vel: Vector2, aim: Vector2) -> void:
	if gstamp <= 0 or (not _track.is_empty() and gstamp <= int(_track[-1][0])):
		return
	_track.append([gstamp, pos, vel, aim.angle() if aim.length_squared() > 0.0001 else INF])
	while _track.size() > 2 and gstamp - int(_track[0][0]) > TRACK_MS:
		_track.pop_front()


## Index of the newest sample at or before `stamp` (-1: none kept).
func _track_at(stamp: int) -> int:
	var i := _track.size() - 1
	while i >= 0 and int(_track[i][0]) > stamp:
		i -= 1
	return i


## Where the owner said it was at its game-clock moment `stamp` (null: unknown).
func pos_at_stamp(stamp: int) -> Variant:
	var i := _track_at(stamp)
	if stamp <= 0 or i < 0:
		return null
	var e: Array = _track[i]
	if i + 1 < _track.size():
		var n: Array = _track[i + 1]
		return (e[1] as Vector2).lerp(n[1], float(stamp - int(e[0])) / float(maxi(1, int(n[0]) - int(e[0]))))
	return (e[1] as Vector2) + (e[2] as Vector2) * minf(float(stamp - int(e[0])), float(TRACK_AHEAD_MS)) / 1000.0


## How far `at` (a muzzle) lies beyond where the body could have been at its
## moment `stamp`, going by the state samples either side of that moment
## (within ORIGIN_WINDOW_MS): each bounds the body to its position give or
## take what it could cover in between (its speed then, plus room to speed
## up), and the body had to satisfy both. INF: no sample that near.
## `window`: a held shot settled after a gap in the stream (a stall, lost
## packets) looks further either side — the bound just grows with the gap.
const ORIGIN_WINDOW_MS := 500
const ORIGIN_GAP_MS := 2500
const ORIGIN_ACCEL := 600.0        # px/s of speed change allowed in between

func origin_off(at: Vector2, stamp: int, window := ORIGIN_WINDOW_MS) -> float:
	if stamp <= 0 or _track.is_empty():
		return INF
	var i := _track_at(stamp)
	var off := -1.0
	for k in [i, i + 1]:
		if k < 0 or k >= _track.size():
			continue
		var e: Array = _track[k]
		var dt := float(absi(int(e[0]) - stamp)) / 1000.0
		if dt * 1000.0 > float(window):
			continue
		var reach := ((e[2] as Vector2).length() * 1.25 + ORIGIN_ACCEL) * dt
		off = maxf(off, maxf(0.0, at.distance_to(e[1]) - reach))
	return off if off >= 0.0 else INF


## The streamed aims just before and just after the moment `stamp`: [a0, a1]
## (angles; null where there is none yet / any more).
func aims_around(stamp: int) -> Array:
	var i := _track_at(stamp)
	var a0 = null
	var a1 = null
	if i >= 0 and float(_track[i][3]) != INF:
		a0 = float(_track[i][3])
		if int(_track[i][0]) == stamp:
			a1 = a0
	if a1 == null and i + 1 < _track.size() and float(_track[i + 1][3]) != INF:
		a1 = float(_track[i + 1][3])
	return [a0, a1]


func track_newest() -> int:
	return int(_track[-1][0]) if not _track.is_empty() else 0


## For --hosthits-log: the kept timeline's span around `stamp`.
func track_note(stamp: int) -> String:
	if _track.is_empty():
		return "track empty"
	var i := _track_at(stamp)
	var prev := int(_track[i][0]) - stamp if i >= 0 else 0
	var nxt := int(_track[i + 1][0]) - stamp if i + 1 < _track.size() else 0
	return "track %d..%d (%+d ms / %+d ms around the shot)" % [int(_track[0][0]) - stamp, int(_track[-1][0]) - stamp, prev, nxt]


# ── aim ──

func note_aim(v: Vector2) -> void:
	if v.length_squared() < 0.0001:
		return
	_aims.append([Time.get_ticks_msec(), v.angle()])
	if _aims.size() > 6:
		_aims.pop_front()


## The streamed aim the client had just before this shot (null if none recent).
func last_aim() -> Variant:
	if _aims.is_empty() or Time.get_ticks_msec() - int(_aims[-1][0]) > AIM_STALE_MS:
		return null
	return float(_aims[-1][1])


## Does a shot fired along `dir` agree with the aim streamed just before it?
func aim_ok_now(dir: Vector2, spread: float) -> bool:
	if last_aim() == null:
		return true
	var a := dir.angle()
	var last: Array = _aims[-1]
	var omega := 0.0
	if _aims.size() >= 2:
		var prev: Array = _aims[-2]
		omega = absf(angle_difference(float(prev[1]), float(last[1]))) / maxf(0.016, float(int(last[0]) - int(prev[0])) / 1000.0)
	# (A fast-swinging aim widens this a little; a bigger flick is held and
	# settled on the swept arc instead — a spinning aim must not open it up.)
	var tol := spread + BINK_MAX + AIM_SLACK + minf(omega * 0.05, 0.5)
	if absf(angle_difference(float(last[1]), a)) <= tol:
		return true
	return _aims.size() >= 2 and absf(angle_difference(float(_aims[-2][1]), a)) <= tol


## Second look once the next aim sample is in: the shot must lie on the arc
## the aim swept from `a0` (before the shot) to `a1` (after it).
static func aim_ok_between(dir: Vector2, spread: float, a0: float, a1: float) -> bool:
	return aim_off_arc(dir, a0, a1) <= spread + BINK_MAX + AIM_ARC_SLACK


## How far (rad) `dir` lies outside the arc the aim swept from a0 to a1.
static func aim_off_arc(dir: Vector2, a0: float, a1: float) -> float:
	var span := angle_difference(a0, a1)
	var rel := angle_difference(a0, dir.angle())
	var near := clampf(rel, minf(0.0, span), maxf(0.0, span))
	return absf(rel - near)


## Refusals this far off the swept arc are flagged; nearer ones (odd but
## possible input) are refused quietly. Silent aim / spin-bots shoot far off.
const AIM_FLAG_RAD := 1.2


# ── fire rate, magazines, grenades ──

## Long-run fire rate: a token bucket per weapon, BURST_SECS deep (it
## replaces #243's minimum gap between arrivals, which dropped honest shots
## the network had bunched together). Returns RATE_OK, RATE_BUNCHED (refused,
## but it arrived in a clump right behind the previous shot: a network stall,
## not worth a flag) or RATE_FAST (refused, sustained: flag it).
enum { RATE_OK, RATE_BUNCHED, RATE_FAST }
const BUNCH_MS := 12


func rate_check(wname: String, rate: float) -> int:
	var r := maxf(rate, 0.03)
	var cap := BURST_SECS / r + 1.0
	var now := Time.get_ticks_msec()
	var b: Array = _buckets.get(wname, [cap, now, -100000])
	var tokens := minf(cap, float(b[0]) + float(now - int(b[1])) / 1000.0 / (r * RATE_SLACK))
	var gap := now - int(b[2])
	if tokens < 1.0:
		_buckets[wname] = [tokens, now, now]
		# Only a shot that itself came well inside the weapon's rate is a
		# flag; one in a clump (a stall flushing) or near the rate (just after
		# such a clump) is refused quietly.
		if gap <= BUNCH_MS or gap >= int(r * 800.0):
			HostHits.count("refused_burst")
			return RATE_BUNCHED
		return RATE_FAST
	_buckets[wname] = [tokens - 1.0, now, now]
	return RATE_OK


## Personal weapons (#266): every shot carries the shooter's game clock (its
## physics frames), so a clump the network delivered at once still shows its
## real spacing. A shot is refused if it claims to come sooner after the last
## one with that weapon than the weapon fires (only a modified client can:
## RATE_FAST, flagged), or if that clock has run ahead of the host's
## (RATE_BUNCHED: quiet) — see clock_note.
const FRAME_SLACK_MS := 18        # one physics frame of rounding
var _stamps: Dictionary = {}      # weapon name -> stamp of the last accepted shot
var _rate_reset: Dictionary = {}  # weapon name -> true: may fire once early (round reset)


func stamp_check(peer: int, wname: String, rate: float, stamp: int) -> int:
	if stamp <= 0:
		return RATE_FAST
	if _stamps.has(wname) and stamp - int(_stamps[wname]) < int(rate * 1000.0) - FRAME_SLACK_MS:
		# (A round reset zeroes the owner's cooldown — `restore_for_round` —
		# so a trigger held through it fires again at once: one early shot
		# per weapon, inside the reset's grace, is not a cheat.)
		if Time.get_ticks_msec() >= amnesty_until_ms or not _rate_reset.has(wname):
			return RATE_FAST
		_rate_reset.erase(wname)
		HostHits.count("rate_reset")
	if not clock_ok(peer, stamp):
		HostHits.count("refused_clock")
		return RATE_BUNCHED
	_stamps[wname] = stamp
	return RATE_OK


# ── the client's game clock vs the host's (per connection) ──
# lead = client game clock - host clock at arrival = offset - latency, and a
# game clock never runs ahead of real time, so an honest lead stays at or
# below its best (lowest-latency) value. The reference is learned from the
# 30 Hz state stream: freely (up to CLOCK_LEARN_MS above the first sample)
# for the connection's first CLOCK_LEARN_SECS, then rising at most CLOCK_RISE
# ms per second (latency drops). A shot may lead the reference by
# CLOCK_SLACK_MS. A client faking its clock to fire faster banks half a
# second once and a few % after that.
const CLOCK_SLACK_MS := 100
const CLOCK_RISE := 0.05
const CLOCK_LEARN_SECS := 3.0
const CLOCK_LEARN_MS := 400.0
const CLOCK_BANK_MS := 300.0
static var _clocks: Dictionary = {}   # peer -> [ref, last rise ms, first ms, first lead]


static func clock_note(peer: int, gstamp: int) -> void:
	if gstamp <= 0:
		return
	var now := Time.get_ticks_msec()
	var lead := float(gstamp - now)
	var c: Array = _clocks.get(peer, [])
	if c.is_empty():
		_clocks[peer] = [lead, now, now, lead]
		return
	var ref: float = c[0]
	if lead <= ref:
		return
	if now - int(c[2]) < int(CLOCK_LEARN_SECS * 1000.0):
		c[0] = minf(lead, float(c[3]) + CLOCK_LEARN_MS)
	else:
		var allow := minf(CLOCK_BANK_MS, float(now - int(c[1])) * CLOCK_RISE)
		c[0] = minf(lead, ref + allow)
	c[1] = now


## How much later than its connection's best this game-clock moment reached
## the host (ms, ≥ 0, ≤ `cap`): a stall held it back that long.
static func clock_late(peer: int, gstamp: int, cap := 1000) -> int:
	var c: Array = _clocks.get(peer, [])
	if c.is_empty() or gstamp <= 0:
		return 0
	return clampi(int(float(c[0]) - float(gstamp - Time.get_ticks_msec())), 0, cap)


static func clock_ok(peer: int, gstamp: int) -> bool:
	var c: Array = _clocks.get(peer, [])
	if c.is_empty():
		clock_note(peer, gstamp)
		return true
	clock_note(peer, gstamp)
	var lead := float(gstamp - Time.get_ticks_msec())
	if lead <= float(c[0]) + CLOCK_SLACK_MS:
		return true
	if OS.get_cmdline_user_args().has("--hosthits-log"):
		print("HOSTCLOCK peer=%d lead=%.0f ref=%.0f learned_for=%d" % [peer, lead, float(c[0]), Time.get_ticks_msec() - int(c[2])])
	return false


## One round out of `slot`'s magazine (`mag` rounds; one round of slack).
## `stamp` / `reload_secs`: a magazine is full again once the owner has gone
## 60 % of a reload without firing it (its game clock) — whether or not the
## host heard its reload flag through a lossy or stalled stream, and however
## many rounds the host thought were left (a reload with one round in the
## shadow's slack, then a full magazine, is honest).
func take_round(slot: int, mag: int, stamp := 0, reload_secs := 0.0) -> bool:
	var left: int = int(_mags.get(slot, mag))
	if left < mag and stamp > 0 and _last_round.has(slot) \
			and stamp - int(_last_round[slot]) >= maxi(200, int(reload_secs * 600.0)):
		left = mag
	if left <= -1:
		return false
	_mags[slot] = left - 1
	if stamp > 0:
		_last_round[slot] = stamp
	return true


## For the log: the magazine shadow of `slot` at a refused round.
func mag_note(slot: int, stamp: int) -> String:
	return "left %d, %d ms since the last round, reload seen for %d ms" % [int(_mags.get(slot, -99)),
		stamp - int(_last_round.get(slot, stamp)), (track_newest() - _reload_since) if _reload_slot == slot else -1]


## The state stream's reload flag for the active slot: a reload the host saw
## run for most of its length refills the magazine. Timed on the owner's game
## clock (`gstamp`) when it says: packets a stall bunched together still show
## how long the reload really ran.
func note_reload(slot: int, reloading: bool, mag: int, reload_secs: float, gstamp := 0) -> void:
	var now := gstamp if gstamp > 0 else Time.get_ticks_msec()
	if not reloading:
		# (The first sample after a reload ends it: it ran at least this long.)
		if _reload_slot == slot and now - _reload_since >= maxi(200, int(reload_secs * 600.0)):
			_mags[slot] = mag
		_reload_slot = -999
		return
	if _reload_slot != slot:
		_reload_slot = slot
		_reload_since = now
	if now - _reload_since >= maxi(200, int(reload_secs * 600.0)):
		_mags[slot] = mag


func refill_all() -> void:
	_mags.clear()


func refill_slot(slot: int) -> void:
	_mags.erase(slot)


## One grenade from the belt, no sooner after the last than a throw allows
## (by the thrower's game clock `stamp` when it says, else arrivals).
func take_grenade(stamp := 0) -> bool:
	var now := stamp if stamp > 0 else Time.get_ticks_msec()
	if now - _last_gren_ms < GRENADE_GAP_MS:
		return false
	if grenades <= -1:
		return false
	_last_gren_ms = now
	grenades -= 1
	return true
