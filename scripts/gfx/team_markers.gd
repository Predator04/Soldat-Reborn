extends Node2D
## Team markers (#306) — one world-space canvas item per match (added by
## match_world._build_gfx_world, z above the soldiers) that draws, in team
## modes only:
##   * a small team-coloured chevron over every living TEAMMATE (always), with
##     the name above it while they are within ALLY_NAME_RANGE of you;
##   * an ENEMY's name, in their team colour, only while you aim at them or
##     they are close (Soldat-style) — never for one cloaked by the Predator
##     bonus (alpha < 0.6) or hidden in a vehicle.
## It also keeps TeamColors.viewer_team (your team), which makes enemy outlines
## stronger than allies'. VISUAL ONLY: reads soldier nodes, writes nothing but
## its own drawing and that static; no RNG, no physics, no RPCs. One draw pass
## for all markers (no node per soldier), redrawn only while there is something
## to show.

const TeamColors = preload("res://scripts/team_colors.gd")

const ALLY_NAME_RANGE := 900.0
const ENEMY_NEAR := 230.0          # px: enemy names show this close …
const ENEMY_AIM_RANGE := 1200.0    # … or when aimed at within this range
const ENEMY_AIM_COS := 0.988       # ~9 degrees off the aim line
const HEAD_Y := -31.0              # chevron tip, local to the soldier (HP bar at -21)
const FONT_SIZE := 10

var main: Node = null
## Last collect() result (tests / diagnostics): [{node, ally, name, col}].
var marks: Array = []
var _drawn := false


func _ready() -> void:
	name = "TeamMarkers"
	z_index = 61


func _exit_tree() -> void:
	TeamColors.viewer_team = 0


## Who is the local viewer's team (1 / 2), 0 when none / free-for-all.
func viewer_team() -> int:
	var me = main.get("player") if main != null else null
	if me == null or not is_instance_valid(me):
		return 0
	return TeamColors.team_of(int(me.get("team")))


## The markers to draw this frame (pure: reads soldier nodes only).
func collect() -> Array:
	var out: Array = []
	var vt := viewer_team()
	if vt == 0:
		return out
	var me: Node2D = main.get("player")
	var eye := me.global_position + Vector2(0, -10)
	var aim: Vector2 = me.get("aim_dir") if me.get("aim_dir") != null else Vector2.RIGHT
	aim = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	var me_dead := bool(me.get("dead"))
	for s in get_tree().get_nodes_in_group("soldier"):
		var n := s as Node2D
		if n == null or n == me or not is_instance_valid(n) or bool(n.get("dead")) or not n.is_visible_in_tree():
			continue
		var t := TeamColors.team_of(int(n.get("team")))
		if t == 0:
			continue
		var d := n.global_position - eye
		var dist := d.length()
		if t == vt:
			out.append({"node": n, "ally": true, "name": dist <= ALLY_NAME_RANGE, "col": TeamColors.for_team(t, true)})
			continue
		if me_dead or n.modulate.a < 0.6 or n.self_modulate.a < 0.6:
			continue
		var aimed := dist <= ENEMY_AIM_RANGE and dist > 1.0 and (d / dist).dot(aim) >= ENEMY_AIM_COS
		if dist <= ENEMY_NEAR or aimed:
			out.append({"node": n, "ally": false, "name": true, "col": TeamColors.for_team(t, true)})
	return out


func _process(_d: float) -> void:
	TeamColors.viewer_team = viewer_team()
	if DisplayServer.get_name() == "headless":
		return
	marks = collect()
	if not marks.is_empty() or _drawn:
		queue_redraw()


func _draw() -> void:
	_drawn = not marks.is_empty()
	if marks.is_empty():
		return
	var font: Font = UITheme.font("semi")
	for m in marks:
		var n: Node2D = m["node"]
		if not is_instance_valid(n):
			continue
		var at := to_local(n.global_position)
		var col: Color = m["col"]
		var top := at.y + HEAD_Y
		if bool(m["ally"]):
			var chev := PackedVector2Array([Vector2(at.x - 4.5, top - 5.0), Vector2(at.x, top - 1.8),
					Vector2(at.x + 4.5, top - 5.0), Vector2(at.x, top)])
			draw_colored_polygon(chev, col)
			draw_polyline(PackedVector2Array([chev[0], chev[3], chev[2]]), Color(0, 0, 0, 0.7), 1.0, true)
			top -= 6.0
		if bool(m["name"]):
			var txt := str(n.get("display_name"))
			if txt == "":
				continue
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var p := Vector2(at.x - w * 0.5, top - 2.0)
			draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color(0, 0, 0, 0.8))
			draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col.lerp(Color.WHITE, 0.2))
