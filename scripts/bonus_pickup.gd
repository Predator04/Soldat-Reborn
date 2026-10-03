extends Area2D
## Bonus pickup crate (#78) — glowing box scattered on maps that grants a
## timed effect on touch. Host-authoritative: only the host detects contact
## and drives collection; clients render a visual mirror kept in sync via
## Main's net_bonus_spawn / net_bonus_despawn RPCs.

signal touched(body)

const GameInfo = preload("res://scripts/game_info.gd")
const ItemLabel = preload("res://scripts/item_label.gd")

# Class-static list is convenient for Main to pick a random kind at spawn time.
const KINDS := ["predator", "berserker", "vest", "cluster"]

var bonus_id: int = 0
var bonus_kind: String = "predator"
var _pulse_t: float = 0.0


func _ready() -> void:
	# Soldiers live on physics layer bit 8.
	collision_mask = 1 | 8
	add_to_group("bonus_pickup")
	var col := CollisionShape2D.new()
	var cs := CircleShape2D.new()
	cs.radius = 16.0
	col.shape = cs
	add_child(col)
	body_entered.connect(_on_body_entered)
	z_index = 1
	ItemLabel.attach(self, GameInfo.item_label(bonus_kind), kind_color(bonus_kind), 24.0)


func _process(delta: float) -> void:
	_pulse_t += delta
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if not (body is CharacterBody2D):
		return
	if body.is_in_group("vehicle") or body.get("dead") == true:
		return
	# Host is the sole source of truth for collection; client-side boxes only
	# despawn when Main receives the authoritative net_bonus_despawn.
	if Net.is_networked() and not Net.is_host():
		return
	touched.emit(body)


# Soldat's own kit sprites (v1.18); medikits / grenade kits are map pickups
# that share this node (see Main._collect_kit).
const KIT_KINDS := ["medkit", "grenades"]
const TEX := {
	"predator": preload("res://assets/textures/objects/predatorkit.png"),
	"berserker": preload("res://assets/textures/objects/berserkerkit.png"),
	"vest": preload("res://assets/textures/objects/vestkit.png"),
	"cluster": preload("res://assets/textures/objects/clusterkit.png"),
	"medkit": preload("res://assets/textures/objects/medikit.png"),
	"grenades": preload("res://assets/textures/objects/grenadekit.png"),
}


func _draw() -> void:
	var tex: Texture2D = TEX.get(bonus_kind, null)
	var bob: float = sin(_pulse_t * 2.5) * 1.5
	if bonus_kind in KIT_KINDS:
		# Plain supply crate: soft ground shadow, gentle bob.
		draw_circle(Vector2(0, 12), 9.0, Color(0, 0, 0, 0.18))
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2(-12, -12 + bob), Vector2(24, 24)), false)
		return
	var col := kind_color(bonus_kind)
	var pulse: float = 0.6 + 0.4 * sin(_pulse_t * 4.0)
	# Outer soft glow — reads as "grab me" from a distance.
	draw_circle(Vector2.ZERO, 22.0 + pulse * 5.0, Color(col.r, col.g, col.b, 0.10))
	draw_circle(Vector2.ZERO, 15.0, Color(col.r, col.g, col.b, 0.32 * pulse))
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2(-13, -13 + bob), Vector2(26, 26)), false)
		return
	draw_rect(Rect2(-10, -10, 20, 20), Color(0.1, 0.1, 0.13, 0.95))
	draw_rect(Rect2(-10, -10, 20, 20), col, false, 2.0)


static func kind_color(k: String) -> Color:
	match k:
		"predator": return Color(0.6, 0.35, 1.0)
		"berserker": return Color(1.0, 0.35, 0.25)
		"vest": return Color(0.35, 0.85, 1.0)
		"cluster": return Color(1.0, 0.75, 0.25)
		"medkit": return Color(0.45, 1.0, 0.45)
		"grenades": return Color(0.8, 0.9, 0.5)
		"buggy": return Color(0.95, 0.85, 0.5)
		"tank": return Color(0.8, 0.85, 0.55)
	return Color(1, 1, 1)


static func kind_label(k: String) -> String:
	match k:
		"predator": return TranslationServer.translate("PREDATOR")
		"berserker": return TranslationServer.translate("BERSERKER")
		"vest": return TranslationServer.translate("VEST")
		"cluster": return TranslationServer.translate("CLUSTER")
		"medkit": return TranslationServer.translate("MEDIKIT")
		"grenades": return TranslationServer.translate("GRENADES")
	return k.to_upper()
