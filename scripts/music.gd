extends Node
## Music — autoload singleton that loops one Soldat track through menu + gameplay.
##
## The three .ogg tracks live under assets/music/. On boot we pick one at random,
## then keep looping it until the game quits. Volume + mute follow Settings.music_*.
##
## Kept intentionally simple: one AudioStreamPlayer, no crossfade, no shuffle
## between tracks mid-session (avoids the awkward mid-fight scene change silence).

const TRACKS := ["bloody", "gore", "necro"]
const MUSIC_DIR := "res://assets/music/"

var _player: AudioStreamPlayer
var _current_track := ""


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	# PROCESS_MODE_ALWAYS so the pause menu doesn't cut the music.
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	_pick_and_play()
	apply_volume()


func _pick_and_play() -> void:
	# Roll a random track and force ogg loop_mode on the resource. Godot's ogg
	# importer defaults to loop=false on plain files; we can't rely on it here.
	var pick: String = TRACKS[randi() % TRACKS.size()]
	_current_track = pick
	var path: String = MUSIC_DIR + pick + ".ogg"
	if not ResourceLoader.exists(path):
		return
	var stream := load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_player.stream = stream
	_player.play()


func apply_volume() -> void:
	# Called on boot and every time the settings slider / mute toggle changes.
	# Muted → silence via stop(); un-muted → resume with the current volume.
	if _player == null:
		return
	if Settings.music_muted or Settings.music_volume <= 0.001:
		if _player.playing:
			_player.stop()
		return
	_player.volume_db = linear_to_db(clampf(Settings.music_volume, 0.001, 1.0))
	if not _player.playing and _player.stream != null:
		_player.play()


func current_track() -> String:
	return _current_track


func skip_track() -> void:
	# Handy from the settings screen if we ever want a "next track" button.
	_pick_and_play()
	apply_volume()
