extends Area2D
## Bonus pickup crate (#78) — glowing box scattered on maps that grants a
## timed effect on touch. Host-authoritative: only the host detects contact
## and drives collection; clients render a visual mirror kept in sync via
## Main's net_bonus_spawn / net_bonus_despawn RPCs.

signal touched(body)

# Class-static list is convenient for Main to pick a random kind at spawn time.
const KINDS := ["predator", "berserker", "vest", "cluster"]

var bonus_id: int = 0
var bonus_kind: String = "predator"
var _pulse_t: float = 0.0


func _ready() -> void:
	add_to_group("bonus_pickup")
	var col := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 16.0
	col.shape = cs
	add_child(col)
	body_entered.connect(_on_body_entered)
	z_index = 1


func _process(delta: float) -> void:
	_pulse_t += delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if not (body is CharacterBody2D):
		return
	if bool(body.get("dead")):
		return
	# Host is the sole source of truth for collection; client-side boxes only
	# despawn when Main receives the authoritative net_bonus_despawn.
	if Net.is_networked() and not Net.is_host():
		return
	touched.emit(body)


func _draw() -> void:
	var col := kind_color(bonus_kind)
	var pulse: float = 0.6 + 0.4 * sin(_pulse_t * 4.0)
	# Outer soft glow — reads as "grab me" from a distance.
	draw_circle(Vector2.ZERO, 22.0 + pulse * 5.0, Color(col.r, col.g, col.b, 0.10))
	draw_circle(Vector2.ZERO, 15.0, Color(col.r, col.g, col.b, 0.32 * pulse))
	# Crate body — dark box with team-colored border so the kind reads even
	# when the glow is fading between pulses.
	draw_rect(Rect2(-10, -10, 20, 20), Color(0.1, 0.1, 0.13, 0.95))
	draw_rect(Rect2(-10, -10, 20, 20), col, false, 2.0)
	# Kind glyph — hand-drawn icons keep this self-contained (no font asset).
	match bonus_kind:
		"predator":
			# Stealth eye — outer ring + pupil.
			draw_arc(Vector2.ZERO, 5.5, 0.0, TAU, 16, col, 1.5)
			draw_circle(Vector2.ZERO, 2.0, col)
		"berserker":
			# Angry X.
			draw_line(Vector2(-5, -5), Vector2(5, 5), col, 2.2)
			draw_line(Vector2(-5, 5), Vector2(5, -5), col, 2.2)
		"vest":
			# Vest silhouette.
			draw_rect(Rect2(-5, -6, 10, 12), col, false, 1.8)
			draw_line(Vector2(-5, -2), Vector2(5, -2), col, 1.2)
		"cluster":
			# Three fragmentation dots.
			draw_circle(Vector2(0, -3), 2.4, col)
			draw_circle(Vector2(-3, 3), 2.4, col)
			draw_circle(Vector2(3, 3), 2.4, col)


static func kind_color(k: String) -> Color:
	match k:
		"predator": return Color(0.6, 0.35, 1.0)
		"berserker": return Color(1.0, 0.35, 0.25)
		"vest": return Color(0.35, 0.85, 1.0)
		"cluster": return Color(1.0, 0.75, 0.25)
	return Color(1, 1, 1)


static func kind_label(k: String) -> String:
	match k:
		"predator": return "PREDATOR"
		"berserker": return "BERSERKER"
		"vest": return "VEST"
		"cluster": return "CLUSTER"
	return k.to_upper()
