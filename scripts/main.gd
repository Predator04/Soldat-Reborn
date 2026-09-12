extends Node2D
## Main — builds the sky, arena terrain, player, and bots.

var player_scene := preload("res://scenes/player.tscn")
var bot_scene := preload("res://scenes/bot.tscn")
var sky_scene := preload("res://scripts/sky.gd")

var player: Node2D = null
var spawn_point := Vector2(180, 560)


func _ready() -> void:
	_build_sky()
	_build_terrain()
	_spawn_player()
	_spawn_bots()
	_show_hint()


func _build_sky() -> void:
	var sky := Node2D.new()
	sky.name = "Sky"
	sky.z_index = -10
	sky.set_script(sky_scene)
	add_child(sky)


func _make_platform(pos: Vector2, size: Vector2, col: Color) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([
		Vector2(-size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, size.y / 2.0),
		Vector2(-size.x / 2.0, size.y / 2.0),
	])
	vis.color = col
	body.add_child(vis)
	add_child(body)
	return body


func _build_terrain() -> void:
	# ground
	_make_platform(Vector2(640, 690), Vector2(1400, 80), Color(0.22, 0.26, 0.32))
	# platforms
	_make_platform(Vector2(320, 520), Vector2(240, 22), Color(0.28, 0.32, 0.4))
	_make_platform(Vector2(760, 430), Vector2(220, 22), Color(0.28, 0.32, 0.4))
	_make_platform(Vector2(1080, 340), Vector2(220, 22), Color(0.28, 0.32, 0.4))
	_make_platform(Vector2(560, 270), Vector2(200, 22), Color(0.28, 0.32, 0.4))
	# side walls
	_make_platform(Vector2(0, 360), Vector2(30, 720), Color(0.2, 0.23, 0.28))
	_make_platform(Vector2(1280, 360), Vector2(30, 720), Color(0.2, 0.23, 0.28))


func _spawn_player() -> void:
	var p := player_scene.instantiate()
	p.position = spawn_point
	p.team = 0
	p.died.connect(_on_player_died)
	add_child(p)
	player = p


func _on_player_died() -> void:
	get_tree().create_timer(2.0).timeout.connect(_spawn_player)


func _spawn_bots() -> void:
	var spots := [Vector2(900, 620), Vector2(1100, 300), Vector2(420, 240)]
	for s in spots:
		var b := bot_scene.instantiate()
		b.position = s
		b.team = 1
		add_child(b)


func _show_hint() -> void:
	var label := Label.new()
	label.name = "Hint"
	label.text = "A/D move   ·   SPACE jump + jet boots (hold in air)   ·   mouse aim   ·   LMB shoot"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	label.position = Vector2(14, 8)
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.add_child(label)
	add_child(layer)
