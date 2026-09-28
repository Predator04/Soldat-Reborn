extends Node
## Sfx — real-sample playback backed by assets/sfx/*.wav.
## Autoload singleton ("Sfx"). Public API preserved for legacy callers.
## Same shape as the old procedural module: shoot / jump / jet / gib / explode / reload / empty.

const SFX_DIR := "res://assets/sfx/"
const POOL_SIZE := 14
# World sounds (v1.18): pass `at` (a global position) and the sample plays from
# there — quieter with distance, panned left/right. Vector2.INF = "on the
# listener" (UI, your own confirmation cues).
const POOL2D_SIZE := 28
const HEAR_DIST := 2400.0       # near samples fade out to silence here
const DIST_GUN_FROM := 1150.0   # beyond this, gunfire swaps to the dist-gun* tails
const DIST_GUN_HEAR := 5200.0
const NOWHERE := Vector2.INF

# Mapping of a "logical event" -> a single sample filename (no path, no extension).
# Weapons resolve through _weapon_fire / _weapon_reload — kept out of this table.
const EVENT_FILES := {
	"jump": "jump",
	"gib": "bodyfall",
	"explode": "grenade-explosion",
	"empty": "minigun-empty",
	"jet_loop": "hum",
	"reload_generic": "clipin",
	"melee_swing": "knife",
	"m79_thump": "m79-explosion",
	"grenade_throw": "grenade-throw",
	"minigun_spinup": "minigun-start",
	"barrett_spinup": "changespin",
	"flame_fire": "flamer",
	"bow_fire": "bow-fire",
	"bow_reload": "bow-reload",
	"cluster_explode": "cluster-explosion",
}

const WEAPON_FIRE := {
	"Deagles":      "deserteagle-fire",
	"MP5":          "mp5-fire",
	"AK-74":        "ak74-fire",
	"Steyr AUG":    "steyraug-fire",
	"Spas-12":      "spas12-fire",
	"Ruger 77":     "ruger77-fire",
	"M79":          "m79-fire",
	"Barrett":      "barretm82-fire",
	"Minimi":       "m249-fire",
	"Minigun":      "minigun-fire",
	"USSOCOM":      "colt1911-fire",
	"Knife":        "knife",
	"Chainsaw":     "chainsaw-o",
	"LAW":          "law-start",
	"Flamethrower": "flamer",
	"Rambo Bow":    "bow-fire",
}

const WEAPON_RELOAD := {
	"Deagles":      "deserteagle-reload",
	"MP5":          "mp5-reload",
	"AK-74":        "ak74-reload",
	"Steyr AUG":    "steyraug-reload",
	"Spas-12":      "spas12-reload",
	"Ruger 77":     "ruger77-reload",
	"M79":          "m79-reload",
	"Barrett":      "barretm82-reload",
	"Minimi":       "m249-reload",
	"Minigun":      "minigun-reload",
	"USSOCOM":      "colt1911-reload",
	"Knife":        "clipin",
	"Chainsaw":     "chainsaw-r",
	"LAW":          "m79-reload",
	"Flamethrower": "m249-reload",
	"Rambo Bow":    "bow-reload",
}

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _idx := 0
var _jet_player: AudioStreamPlayer
var _last_weapon := ""
var _players2d: Array[AudioStreamPlayer2D] = []
var _idx2d := 0
var _last_at: Dictionary = {}   # throttle key -> msec of last play
# Sample key -> times requested (tools/sound_test.gd reads this).
var play_counts: Dictionary = {}


func _ready() -> void:
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for _i in POOL2D_SIZE:
		var p2 := AudioStreamPlayer2D.new()
		p2.max_distance = HEAR_DIST
		p2.attenuation = 1.6
		add_child(p2)
		_players2d.append(p2)

	_jet_player = AudioStreamPlayer.new()
	_jet_player.volume_db = -12.0
	var jet_src := _load("jet_loop")
	if jet_src != null:
		# Duplicate so loop_mode mutation doesn't leak onto the shared cached stream.
		var jet_stream: AudioStreamWAV = jet_src.duplicate() as AudioStreamWAV
		jet_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		jet_stream.loop_begin = 0
		# hum.wav is 8-bit mono; derive per-sample byte count from actual format so
		# the loop point lands at the real end instead of halfway through.
		var bytes_per_sample: int = (2 if jet_stream.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if jet_stream.stereo else 1)
		jet_stream.loop_end = jet_stream.data.size() / bytes_per_sample
		_jet_player.stream = jet_stream
	add_child(_jet_player)


# ── Public API ──────────────────────────────────────────

func shoot(weapon_name := "", at := NOWHERE) -> void:
	if at == NOWHERE:
		_last_weapon = weapon_name
	var key := _weapon_fire_key(weapon_name)
	if at != NOWHERE and at.distance_to(listener_pos()) > DIST_GUN_FROM:
		# Far-off firefight: Soldat's muffled distance tails, not the crisp shot.
		if not _throttle("distgun", 70):
			return
		var far := "dist-m79" if weapon_name in ["M79", "LAW"] else "dist-gun%d" % (randi() % 4 + 1)
		_play_far(far, -10.0, randf_range(0.95, 1.05), at)
		return
	_play_key(key, -6.0, randf_range(0.97, 1.03), at)


func jump(at := NOWHERE) -> void:
	_play_event("jump", -10.0, randf_range(0.95, 1.05), at)


func jet(on: bool) -> void:
	if on:
		if Settings.sfx_volume <= 0.0 or _jet_player.stream == null:
			return
		_jet_player.volume_db = -12.0 + _master_db()
		if not _jet_player.playing:
			_jet_player.play()
	else:
		_jet_player.stop()


func gib(at := NOWHERE) -> void:
	_play_event("gib", -4.0, randf_range(0.9, 1.1), at)
	_play_key("bonecrack", -8.0, randf_range(0.9, 1.1), at)


func explode(at := NOWHERE) -> void:
	if not _throttle("boom", 35):
		return
	if at != NOWHERE and at.distance_to(listener_pos()) > HEAR_DIST * 0.8:
		_play_far("dist-grenade", -6.0, randf_range(0.95, 1.05), at)
		return
	_play_event("explode", -2.0, randf_range(0.97, 1.03), at)


func reload(weapon_name := "", at := NOWHERE) -> void:
	# Fall back to the last fired weapon only if the caller didn't specify one;
	# otherwise switching weapons before firing would play the wrong reload sample.
	var wn := weapon_name if weapon_name != "" else _last_weapon
	var key := _weapon_reload_key(wn)
	_play_key(key, -8.0, 1.0, at)


func empty() -> void:
	_play_event("empty", -8.0, 1.0)


# Wind-up tell for Barrett/Minigun — plays once when the trigger is first pulled.
func spinup(weapon_name: String) -> void:
	if weapon_name == "Minigun":
		_play_event("minigun_spinup", -6.0, 1.0)
	elif weapon_name == "Barrett":
		_play_event("barrett_spinup", -6.0, 1.0)


# Melee swing (Knife) — tuned quieter than a fire sample.
func melee_swing() -> void:
	_play_event("melee_swing", -8.0, randf_range(0.95, 1.05))


# "You hit someone" grunt — picks a random Soldat hit-arg sample for variety.
# Called from bullet.gd only when the LOCAL player's shot lands, so it reads as
# your own hit confirmation and stays silent for remote players.
func hit() -> void:
	_play_key(["hit-arg", "hit-arg2", "hit-arg3"][randi() % 3], -6.0, randf_range(0.9, 1.1))


# Grenade throw arm-swing.
func grenade_throw(at := NOWHERE) -> void:
	_play_event("grenade_throw", -10.0, 1.0, at)


# M79 grenade impact — distinct, thumpier than the generic frag explosion.
func m79_thump(at := NOWHERE) -> void:
	if at != NOWHERE and at.distance_to(listener_pos()) > HEAR_DIST * 0.8:
		_play_far("dist-m79", -6.0, 1.0, at)
		return
	_play_event("m79_thump", -2.0, 1.0, at)


# Cluster grenade explosion + child fragment cascade.
func cluster_explode(at := NOWHERE) -> void:
	if at != NOWHERE and at.distance_to(listener_pos()) > HEAR_DIST * 0.8:
		_play_far("dist-grenade", -6.0, 0.9, at)
		return
	_play_event("cluster_explode", -2.0, 1.0, at)


# ── World events (v1.18) ────────────────────────────────

# Footstep while running. Throttled per soldier by the caller's own cadence.
func footstep(at: Vector2, crouched := false) -> void:
	if crouched:
		_play_key("crouch-move", -20.0, randf_range(0.9, 1.1), at)
		return
	_play_key("step" if randi() % 8 == 0 else "step%d" % (randi() % 7 + 2), -17.0, randf_range(0.9, 1.1), at)


# Touchdown after a fall. `hard` for big drops.
func land(at: Vector2, hard := false) -> void:
	_play_key("fall-hard" if hard else "fall", -12.0 if hard else -15.0, randf_range(0.95, 1.05), at)


# Bullet hitting terrain.
func ricochet(at: Vector2) -> void:
	if not _throttle("ric", 45):
		return
	_play_key("ric" if randi() % 7 == 0 else "ric%d" % (randi() % 6 + 2), -16.0, randf_range(0.9, 1.1), at)


# An enemy round zipping past the local player's head.
func whizz(at: Vector2) -> void:
	if not _throttle("whizz", 90):
		return
	_play_key("bulletby" if randi() % 5 == 0 else "bulletby%d" % (randi() % 4 + 2), -10.0, randf_range(0.9, 1.1), at)


# Pin pulled — start of a grenade cook.
func grenade_pull() -> void:
	_play_key("grenade-pullout", -8.0, 1.0)


func grenade_bounce(at: Vector2) -> void:
	if not _throttle("gbounce", 60):
		return
	_play_key("grenade-bounce", -12.0, randf_range(0.95, 1.08), at)


# Death cry; headshots get the Soldat head-chop crunch on top.
func death(at: Vector2, headshot := false) -> void:
	_play_key(["playerdeath", "death2", "death3", "death"][randi() % 4], -8.0, randf_range(0.93, 1.07), at)
	if headshot:
		_play_key("headchop", -6.0, 1.0, at)


func weapon_switch() -> void:
	_play_key("changeweapon", -12.0, 1.0)


func pickup(at := NOWHERE) -> void:
	_play_key("pickupgun", -8.0, 1.0, at)


func throw_gun(at := NOWHERE) -> void:
	_play_key("throwgun", -10.0, 1.0, at)


func roll(at: Vector2) -> void:
	_play_key("roll", -12.0, 1.0, at)


func prone(at: Vector2, down: bool) -> void:
	_play_key("goprone" if down else "standup", -14.0, 1.0, at)


func spawn(at: Vector2) -> void:
	_play_key("spawn", -10.0, 1.0, at)


func shell(at: Vector2, shotgun := false) -> void:
	if not _throttle("shell", 110):
		return
	_play_key("gaugeshell" if shotgun else ("shell" if randi() % 2 == 0 else "shell2"), -22.0, randf_range(0.9, 1.1), at)


func minigun_stop(at := NOWHERE) -> void:
	_play_key("minigun-end", -8.0, 1.0, at)


# Where the ears are: centre of what the local screen shows.
func listener_pos() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	return vp.get_canvas_transform().affine_inverse() * (vp.get_visible_rect().size * 0.5)


# Flame short-range spray tick (looped by weapon, one call per shot).
func flame_fire() -> void:
	_play_event("flame_fire", -8.0, randf_range(0.95, 1.05))


# Bow shot.
func bow_fire() -> void:
	_play_event("bow_fire", -6.0, 1.0)


# Fired-once UI/menu blip. Kept as a no-op if no matching sample exists so callers stay simple.
# Objective cues (Soldat's own CTF/INF samples).
const OBJECTIVE_SOUNDS := {
	"grab": ["flag", -4.0, 1.0],
	"drop": ["flag2", -6.0, 0.85],
	"return": ["flag2", -4.0, 1.1],
	"capture": ["capture", -2.0, 1.0],
	"dom": ["infilt-point", -4.0, 1.0],
	"point": ["takemedikit", -10.0, 1.2],
}


func objective(kind: String) -> void:
	var e: Array = OBJECTIVE_SOUNDS.get(kind, [])
	if e.is_empty():
		return
	_play_key(str(e[0]), float(e[1]), float(e[2]))


# Weather bed (v1.18): looping rain / snow-wind under the match. "" stops it.
var _amb_player: AudioStreamPlayer = null
var _amb_kind := ""


func ambience(kind: String) -> void:
	kind = kind.strip_edges().to_lower()
	if kind == _amb_kind and _amb_player != null and _amb_player.playing:
		return
	_amb_kind = kind
	if _amb_player == null:
		_amb_player = AudioStreamPlayer.new()
		add_child(_amb_player)
	_amb_player.stop()
	var key := ""
	var vol := -18.0
	match kind:
		"rain":
			key = "sfx_rain"
		"snow":
			key = "sfx_snow"
			vol = -20.0
		"wind":
			key = "sfx_wind"
			vol = -22.0
	if key == "" or Settings.sfx_volume <= 0.0:
		return
	var src := _load(key)
	if src == null:
		return
	var st: AudioStreamWAV = src.duplicate() as AudioStreamWAV
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	var bps: int = (2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if st.stereo else 1)
	st.loop_end = st.data.size() / bps
	_amb_player.stream = st
	_amb_player.volume_db = vol + _master_db()
	_amb_player.play()
	play_counts[key] = int(play_counts.get(key, 0)) + 1


# Crate / kit collected (heard by everyone nearby).
const PICKUP_SOUNDS := {
	"medkit": ["takemedikit", -6.0],
	"grenades": ["pickupgun", -6.0],
	"vest": ["vesttake", -4.0],
	"berserker": ["berserker", -4.0],
	"predator": ["predator", -4.0],
	"cluster": ["clustergrenade", -4.0],
}


func pickup_kit(kind: String, at: Vector2) -> void:
	var e: Array = PICKUP_SOUNDS.get(kind, ["pickupgun", -6.0])
	_play_key(str(e[0]), float(e[1]), 1.0, at)


# Team radio voice line (assets/sfx/radio/<code>.wav, e.g. efcup).
func radio(code: String) -> void:
	_play_key("radio/" + code.replace("_", ""), -2.0, 1.0)


func ui() -> void:
	_play_key("menuclick", -8.0, 1.0)


# ── Internals ───────────────────────────────────────────

func _weapon_fire_key(weapon_name: String) -> String:
	return WEAPON_FIRE.get(weapon_name, "ak74-fire")


func _weapon_reload_key(weapon_name: String) -> String:
	return WEAPON_RELOAD.get(weapon_name, "clipin")


func _play_event(event: String, vol_db: float, pitch: float, at := NOWHERE) -> void:
	var key: String = EVENT_FILES.get(event, "")
	if key == "":
		return
	_play_key(key, vol_db, pitch, at)


# Rate limiter for sounds that can fire dozens of times a frame (sprays, bots).
func _throttle(key: String, min_ms: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_at.get(key, -100000)) < min_ms:
		return false
	_last_at[key] = now
	return true


func _play_far(file_key: String, vol_db: float, pitch: float, at: Vector2) -> void:
	_play_key(file_key, vol_db, pitch, at, DIST_GUN_HEAR)


func _play_key(file_key: String, vol_db: float, pitch: float, at := NOWHERE, hear := HEAR_DIST) -> void:
	play_counts[file_key] = int(play_counts.get(file_key, 0)) + 1
	if Settings.sfx_volume <= 0.0:
		return
	if at != NOWHERE and at.distance_to(listener_pos()) > hear:
		return
	var stream := _load(file_key)
	if stream == null:
		return
	if at != NOWHERE:
		var q := _players2d[_idx2d]
		_idx2d = (_idx2d + 1) % _players2d.size()
		q.stream = stream
		q.max_distance = hear
		q.global_position = at
		q.volume_db = vol_db + _master_db()
		q.pitch_scale = pitch
		q.play()
		return
	var p := _players[_idx]
	_idx = (_idx + 1) % _players.size()
	p.stream = stream
	p.volume_db = vol_db + _master_db()
	p.pitch_scale = pitch
	p.play()


func _load(file_key: String) -> AudioStreamWAV:
	if _cache.has(file_key):
		return _cache[file_key]
	var path := SFX_DIR + file_key + ".wav"
	if not ResourceLoader.exists(path):
		_cache[file_key] = null
		return null
	var res := load(path)
	if res is AudioStreamWAV:
		_cache[file_key] = res
		return res
	_cache[file_key] = null
	return null


func _master_db() -> float:
	return linear_to_db(clampf(Settings.sfx_volume, 0.0001, 1.0))
