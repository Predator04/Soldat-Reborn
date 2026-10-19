extends Node2D
## In-game look of the Maker-mode hazards (#286): spike rows and jump pads at
## the terrain's depth (soldiers drawn in front), lava pools on a child canvas
## item above the soldiers (they sink into it). Cosmetic only — the kill zones
## and the pad launches live in scripts/match_hazards.gd.

const Art = preload("res://scripts/maker/hazard_art.gd")

var zones: Array = []    # {kind, rect, dir}
var pads: Array = []     # {pos, power}
var _fired: PackedFloat32Array = PackedFloat32Array()   # seconds since each pad fired
var _lava: Node2D = null
var _has_lava := false
var _t := 0.0
var _acc := 0.0
var _animate := true


func _ready() -> void:
	_animate = DisplayServer.get_name() != "headless"
	_fired.resize(pads.size())
	_fired.fill(9.0)
	for z in zones:
		if str(z.get("kind", "")) == "lava":
			_has_lava = true
	_lava = Node2D.new()
	_lava.name = "Lava"
	_lava.z_index = 4
	_lava.draw.connect(_draw_lava)
	add_child(_lava)
	set_process(_animate)


## A pad launched a soldier (match_hazards): pop its plate.
func pad_fired(i: int) -> void:
	if i >= 0 and i < _fired.size():
		_fired[i] = 0.0


func _process(delta: float) -> void:
	_t += delta
	var busy := _has_lava
	for i in _fired.size():
		if _fired[i] < 0.6:
			_fired[i] += delta
			busy = true
	if not busy:
		return
	_acc += delta
	if _acc < 1.0 / 30.0:
		return
	_acc = 0.0
	queue_redraw()
	if _has_lava:
		_lava.queue_redraw()


func _draw() -> void:
	for z in zones:
		if str(z.get("kind", "")) == "spikes":
			Art.draw_spikes(self, z["rect"], int(z.get("dir", 0)))
	for i in pads.size():
		var p: Dictionary = pads[i]
		Art.draw_pad(self, p.get("pos", Vector2.ZERO), float(p.get("power", 1150.0)) > 1400.0, _fired[i] if i < _fired.size() else 9.0)


func _draw_lava() -> void:
	for z in zones:
		if str(z.get("kind", "")) == "lava":
			Art.draw_lava(_lava, z["rect"], _t)
