extends Node2D
## Tiny hit puff: dust + sparks kicked back from a bullet impact (kind
## "wall"), or a red spray when a soldier is hit (kind "blood"). Pure _draw,
## ~0.25 s, capped by a global live counter so a minigun can't flood it.

static var live := 0
const MAX_LIVE := 48
const LIFE := 0.25

var normal := Vector2.UP      # direction the debris flies (back toward the shooter)
var kind := "wall"
var _t := 0.0
var _rays: Array = []


static func spawn(parent: Node, at: Vector2, dir: Vector2, k: String) -> void:
	if parent == null or live >= MAX_LIVE or Settings.lofi:
		return
	if k == "blood" and float(Settings.blood_intensity) <= 0.0:
		return
	var n := Node2D.new()
	n.set_script(load("res://scripts/impact_fx.gd"))
	n.set("normal", dir.normalized() if dir.length() > 0.01 else Vector2.UP)
	n.set("kind", k)
	n.global_position = at
	parent.add_child(n)


func _ready() -> void:
	live += 1
	z_index = 5
	var count := 6 if kind == "wall" else int(5 + 4 * clampf(float(Settings.blood_intensity), 0.0, 1.5))
	for i in count:
		var a := normal.angle() + randf_range(-0.9, 0.9)
		_rays.append([Vector2.RIGHT.rotated(a) * randf_range(60.0, 160.0), randf_range(1.2, 2.4)])


func _exit_tree() -> void:
	live -= 1


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / LIFE
	var a := 1.0 - k
	if kind == "wall":
		draw_circle(normal * 4.0 * k, 3.0 + 7.0 * k, Color(0.75, 0.7, 0.6, 0.35 * a))
	for r in _rays:
		var v: Vector2 = r[0]
		var p: Vector2 = v * _t + Vector2(0, 220.0) * _t * _t
		var col := Color(1.0, 0.85, 0.45, a) if kind == "wall" else Color(0.7, 0.05, 0.05, a)
		draw_line(p - v.normalized() * 3.0, p, col, float(r[1]))
