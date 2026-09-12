extends Node2D
## Main — sky, terrain, player, bots, HUD.

var player_scene := preload("res://scenes/player.tscn")
var bot_scene := preload("res://scenes/bot.tscn")
var sky_script := preload("res://scripts/sky.gd")
var parallax_script := preload("res://scripts/parallax.gd")
var hud_script := preload("res://scripts/hud.gd")

signal kill(killer_name: String, victim_name: String, weapon_name: String, killer_team: int)

var player: Node2D = null
var hud: CanvasLayer = null
var spawn_point := Vector2(200, 1050)

const MAP_W := 3200.0
const MAP_H := 1200.0
const GROUND_Y := 1150.0


func _ready() -> void:
	_build_sky()
	_build_parallax()
	_build_terrain()
	_spawn_player()
	_spawn_bots()
	_build_hud()


func _build_sky() -> void:
	var sky := Node2D.new()
	sky.name = "Sky"
	sky.set_script(sky_script)
	var layer := CanvasLayer.new()
	layer.layer = -20
	layer.add_child(sky)
	add_child(layer)


func _build_parallax() -> void:
	var par := Node2D.new()
	par.name = "Parallax"
	par.set_script(parallax_script)
	var layer := CanvasLayer.new()
	layer.layer = -15
	layer.add_child(par)
	add_child(layer)


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
	_make_platform(Vector2(MAP_W / 2.0, GROUND_Y), Vector2(MAP_W + 200, 200), Color(0.22, 0.26, 0.32))
	_make_platform(Vector2(450, 900), Vector2(260, 22), Color(0.28, 0.32, 0.4))
	_make_platform(Vector2(900, 760), Vector2(240, 22), Color(0.28, 0.32, 0.4))
	_make_platform(Vector2(1350, 640), Vector2(240, 22), Color(0.28, 0.32, 0.4))
	_make_platform(Vector2(1800, 540), Vector2(240, 22), Color(0.28, 0.32, 0.4))
	_make_platform(Vector2(2250, 660), Vector2(240, 22), Color(0.28, 0.32, 0.4))
	_make_platform(Vector2(2700, 800), Vector2(240, 22), Color(0.28, 0.32, 0.4))
	_make_platform(Vector2(0, MAP_H / 2.0), Vector2(40, MAP_H * 2.0), Color(0.2, 0.23, 0.28))
	_make_platform(Vector2(MAP_W, MAP_H / 2.0), Vector2(40, MAP_H * 2.0), Color(0.2, 0.23, 0.28))


func _spawn_player() -> void:
	var p := player_scene.instantiate()
	p.position = spawn_point
	p.team = 0
	p.died.connect(_on_player_died)
	add_child(p)
	player = p
	p.cam.limit_left = 0
	p.cam.limit_right = int(MAP_W)
	p.cam.limit_top = -500
	p.cam.limit_bottom = int(GROUND_Y + 200)
	if hud:
		hud.player = p


func _on_player_died() -> void:
	get_tree().create_timer(2.0).timeout.connect(_spawn_player)


func _spawn_bots() -> void:
	var spots := [Vector2(1000, 1050), Vector2(1600, 500), Vector2(2400, 1050), Vector2(2900, 760)]
	for i in spots.size():
		var b := bot_scene.instantiate()
		b.position = spots[i]
		b.team = 1
		b.display_name = "Bot %d" % (i + 1)
		add_child(b)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.set_script(hud_script)
	add_child(hud)
	hud.player = player
	kill.connect(hud._on_kill)
