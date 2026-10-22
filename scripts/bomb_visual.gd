extends Node2D
## The bomb (#304): a charge strapped to the carrier's back, lying on the
## ground when dropped, or planted with a blinking light and a beep that
## speeds up as the fuse runs down. Cosmetic only — reads main._bomb on every
## peer (sounds through Sfx with its own RNG, nothing touches the match).

var main: Node = null
var _t := 0.0
var _beep_cd := 0.0
var _blink := 0.0


func _ready() -> void:
	z_index = 6


func _process(delta: float) -> void:
	_t += delta
	_blink = maxf(0.0, _blink - delta)
	if main == null or not is_instance_valid(main) or main.get("_bomb") == null:
		visible = false
		return
	var b = main._bomb
	var st := str(b.bomb_state)
	visible = st == "carried" or st == "dropped" or st == "planted"
	if not visible:
		return
	if st == "carried" and b.carrier != null and is_instance_valid(b.carrier):
		var c := b.carrier as Node2D
		var face: float = float(c.get("facing")) if c.get("facing") != null else 1.0
		global_position = c.global_position + Vector2(-face * 6.0, -15.0)
	else:
		global_position = b.bomb_pos
	if st == "planted":
		_beep_cd -= delta
		if _beep_cd <= 0.0:
			var frac: float = clampf(float(b.fuse_t) / float(b.FUSE_TIME), 0.0, 1.0)
			_beep_cd = lerpf(0.13, 1.0, frac)
			_blink = 0.09
			Sfx.bomb_beep(global_position, frac < 0.25)
	else:
		_beep_cd = 0.0
	queue_redraw()


func _draw() -> void:
	if main == null or not is_instance_valid(main) or main.get("_bomb") == null:
		return
	var b = main._bomb
	var st := str(b.bomb_state)
	var small := st == "carried"
	var k := 0.7 if small else 1.0
	var w := 22.0 * k
	var h := 12.0 * k
	var base := Vector2(-w * 0.5, -h - (0.0 if small else 1.0))
	# Charge: three sticks taped together + a little timer box.
	var body := Rect2(base, Vector2(w, h))
	draw_rect(body.grow(1.0), Color(0, 0, 0, 0.55))
	var stick := h / 3.0
	for i in 3:
		draw_rect(Rect2(base + Vector2(0, stick * i), Vector2(w, stick - 0.6)), Color(0.72, 0.28, 0.18) if i != 1 else Color(0.62, 0.22, 0.14))
	draw_rect(Rect2(base + Vector2(w * 0.3, 0), Vector2(2.0 * k, h)), Color(0.15, 0.15, 0.16))
	draw_rect(Rect2(base + Vector2(w * 0.62, 0), Vector2(2.0 * k, h)), Color(0.15, 0.15, 0.16))
	var tb := Rect2(base + Vector2(w * 0.28, -5.0 * k), Vector2(w * 0.44, 5.0 * k))
	draw_rect(tb, Color(0.12, 0.13, 0.14))
	var led_on: bool = (st == "planted" and _blink > 0.0) or (st != "planted" and fmod(_t, 1.2) < 0.15)
	var led := Color(1.0, 0.18, 0.12) if led_on else Color(0.35, 0.08, 0.06)
	draw_circle(tb.get_center(), 1.8 * k, led)
	if st == "planted" and led_on:
		draw_circle(tb.get_center(), 9.0, Color(1.0, 0.2, 0.15, 0.25))
	if st == "dropped":
		var font := UITheme.font("caps")
		if font != null:
			var txt := tr("BOMB")
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var y := -h - 14.0 - 3.0 * sin(_t * 3.0)
			draw_string_outline(font, Vector2(-tw * 0.5, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(-tw * 0.5, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.85, 0.3))
