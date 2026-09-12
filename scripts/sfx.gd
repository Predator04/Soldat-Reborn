extends Node
## Sfx — procedural sound effects generated in code (zero asset files).
## Autoload singleton ("Sfx"). A pool of one-shot players + a dedicated looping jet player.

const MIX_RATE := 22050

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _idx := 0
var _jet_player: AudioStreamPlayer


func _ready() -> void:
	_streams["shoot"] = _build_shoot()
	_streams["shotgun"] = _build_shotgun()
	_streams["jump"] = _build_jump()
	_streams["jet"] = _build_jet()
	_streams["gib"] = _build_gib()
	_streams["explode"] = _build_explode()
	_streams["reload"] = _build_reload()
	_streams["empty"] = _build_empty()

	for _i in 12:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)

	_jet_player = AudioStreamPlayer.new()
	_jet_player.stream = _streams["jet"]
	_jet_player.volume_db = -9.0
	add_child(_jet_player)


# ── Public API ──────────────────────────────────────────

func shoot(weapon_name := "") -> void:
	if weapon_name == "Spas-12":
		_play("shotgun", -4.0, randf_range(0.95, 1.05))
	else:
		_play("shoot", -6.0, randf_range(0.9, 1.1))


func jump() -> void:
	_play("jump", -10.0, randf_range(0.95, 1.05))


func jet(on: bool) -> void:
	if on:
		if Settings.sfx_volume <= 0.0:
			return
		_jet_player.volume_db = -9.0 + _master_db()
		if not _jet_player.playing:
			_jet_player.play()
	else:
		_jet_player.stop()


func gib() -> void:
	_play("gib", -4.0, randf_range(0.9, 1.1))


func explode() -> void:
	_play("explode", -2.0, randf_range(0.95, 1.05))


func reload() -> void:
	_play("reload", -8.0, 1.0)


func empty() -> void:
	_play("empty", -8.0, 1.0)


# ── Internals ───────────────────────────────────────────

func _play(name: String, vol_db := -6.0, pitch := 1.0) -> void:
	if Settings.sfx_volume <= 0.0 or not _streams.has(name):
		return
	var p := _players[_idx]
	_idx = (_idx + 1) % _players.size()
	p.stream = _streams[name]
	p.volume_db = vol_db + _master_db()
	p.pitch_scale = pitch
	p.play()


func _master_db() -> float:
	return linear_to_db(clampf(Settings.sfx_volume, 0.0001, 1.0))


func _make_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = _pcm16(samples)
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var s := int(clampf(samples[i], -1.0, 1.0) * 32766.0)
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	return bytes


## 2ms linear attack ramp to kill the click at the start of noise-based sounds.
func _attack(out: PackedFloat32Array, ms := 2.0) -> void:
	var ramp := int(MIX_RATE * ms / 1000.0)
	for i in mini(ramp, out.size()):
		out[i] *= float(i) / maxf(1.0, float(ramp))


func _build_shoot() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.13)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		out[i] = (randf() * 2.0 - 1.0) * pow(1.0 - t, 3.0) * 0.8
	_attack(out)
	return _make_wav(out)


func _build_shotgun() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.26)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		out[i] = (randf() * 2.0 - 1.0) * pow(1.0 - t, 2.2) * 0.9
	_attack(out)
	return _make_wav(out)


func _build_jump() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.12)
	var out := PackedFloat32Array()
	out.resize(n)
	var f0 := 300.0
	var f1 := 640.0
	for i in n:
		var t := float(i) / n
		var phase := TAU * (f0 * t + 0.5 * (f1 - f0) * t * t)
		out[i] = sin(phase) * (1.0 - t) * 0.35
	return _make_wav(out)


## Jet loop: 70 sine partials at integer multiples of the loop fundamental
## (1/duration) => perfectly seamless loop, 1/f amplitude taper for rumble + hiss.
func _build_jet() -> AudioStreamWAV:
	var dur := 0.5
	var n := int(MIX_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var fundamental := 1.0 / dur
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for _j in 70:
		var f := fundamental * rng.randi_range(20, 2200)
		var amp := 0.6 / sqrt(f)
		var phase := rng.randf() * TAU
		for i in n:
			out[i] += sin(TAU * f * float(i) / MIX_RATE + phase) * amp
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(out[i]))
	if peak > 0.0:
		for i in n:
			out[i] = out[i] / peak * 0.45
	return _make_wav(out, true)


func _build_gib() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.3)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		var env := pow(1.0 - t, 2.5)
		var thud := sin(TAU * 90.0 * float(i) / MIX_RATE) * env * 0.7
		var noise := (randf() * 2.0 - 1.0) * env * 0.25
		out[i] = thud + noise
	_attack(out)
	return _make_wav(out)


func _build_explode() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.6)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		var env := pow(1.0 - t, 2.0)
		var f := 70.0 - 40.0 * t
		var boom := sin(TAU * f * float(i) / MIX_RATE) * env * 0.7
		var noise := (randf() * 2.0 - 1.0) * env * 0.35
		out[i] = boom + noise
	_attack(out, 3.0)
	return _make_wav(out)


func _build_reload() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.18)
	var out := PackedFloat32Array()
	out.resize(n)
	var click_len := int(MIX_RATE * 0.008)
	for c in [0.0, 0.09]:
		var start := int(c * MIX_RATE)
		for i in click_len:
			if start + i >= n:
				break
			var env := 1.0 - float(i) / click_len
			out[start + i] = (randf() * 2.0 - 1.0) * env * 0.5
	return _make_wav(out)


func _build_empty() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.06)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = (randf() * 2.0 - 1.0) * (1.0 - float(i) / n) * 0.5
	_attack(out)
	return _make_wav(out)
