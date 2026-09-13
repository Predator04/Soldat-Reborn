extends Node
## Sfx — real-sample playback backed by assets/sfx/*.wav.
## Autoload singleton ("Sfx"). Public API preserved for legacy callers.
## Same shape as the old procedural module: shoot / jump / jet / gib / explode / reload / empty.

const SFX_DIR := "res://assets/sfx/"
const POOL_SIZE := 14

# Mapping of a "logical event" -> a single sample filename (no path, no extension).
# Weapons resolve through _weapon_fire / _weapon_reload — kept out of this table.
const EVENT_FILES := {
	"jump": "jump",
	"gib": "bodyfall",
	"explode": "grenade-explosion",
	"empty": "minigun-empty",
	"jet_loop": "hum",
	"reload_generic": "clipin",
}

const WEAPON_FIRE := {
	"Deagles": "deserteagle-fire",
	"AK-74": "ak74-fire",
	"MP5": "mp5-fire",
	"Spas-12": "spas12-fire",
	"LAW": "m79-fire",
}

const WEAPON_RELOAD := {
	"Deagles": "deserteagle-reload",
	"AK-74": "ak74-reload",
	"MP5": "mp5-reload",
	"Spas-12": "spas12-reload",
	"LAW": "m79-reload",
}

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _idx := 0
var _jet_player: AudioStreamPlayer
var _last_weapon := ""


func _ready() -> void:
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

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

func shoot(weapon_name := "") -> void:
	_last_weapon = weapon_name
	var key := _weapon_fire_key(weapon_name)
	_play_key(key, -6.0, randf_range(0.97, 1.03))


func jump() -> void:
	_play_event("jump", -10.0, randf_range(0.95, 1.05))


func jet(on: bool) -> void:
	if on:
		if Settings.sfx_volume <= 0.0 or _jet_player.stream == null:
			return
		_jet_player.volume_db = -12.0 + _master_db()
		if not _jet_player.playing:
			_jet_player.play()
	else:
		_jet_player.stop()


func gib() -> void:
	_play_event("gib", -4.0, randf_range(0.9, 1.1))


func explode() -> void:
	_play_event("explode", -2.0, randf_range(0.97, 1.03))


func reload() -> void:
	var key := _weapon_reload_key(_last_weapon)
	_play_key(key, -8.0, 1.0)


func empty() -> void:
	_play_event("empty", -8.0, 1.0)


# Fired-once UI/menu blip. Kept as a no-op if no matching sample exists so callers stay simple.
func ui() -> void:
	_play_key("menuclick", -8.0, 1.0)


# ── Internals ───────────────────────────────────────────

func _weapon_fire_key(weapon_name: String) -> String:
	return WEAPON_FIRE.get(weapon_name, "ak74-fire")


func _weapon_reload_key(weapon_name: String) -> String:
	return WEAPON_RELOAD.get(weapon_name, "clipin")


func _play_event(event: String, vol_db: float, pitch: float) -> void:
	var key: String = EVENT_FILES.get(event, "")
	if key == "":
		return
	_play_key(key, vol_db, pitch)


func _play_key(file_key: String, vol_db: float, pitch: float) -> void:
	if Settings.sfx_volume <= 0.0:
		return
	var stream := _load(file_key)
	if stream == null:
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
