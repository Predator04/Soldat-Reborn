extends Object
## UI motion for the Tracerfall design language (graphics Phase C, #272).
##
## Buttons — bind_button(): hover / focus scale 1.03, press 0.97 (tweened about
## the centre), a one-shot neon sweep across the face on hover / focus, and the
## Sfx click / hover ticks. Colours come from the stylebox states (ui_theme.gd).
##
## Screens — watch(c, dir): whenever `c` becomes visible in the tree it slides
## SLIDE px in from `dir` while fading in (DUR_IN s, cubic ease-out). Only
## modulate.a and a temporary offset delta are animated: input works from the
## first frame (nothing waits on the tween), a hide mid-way cancels it and
## restores the exact layout, and a re-show restarts it — interruptible by
## construction. Callers keep toggling `visible` as before.
##
## Reduce motion (Settings → Video): every animation here becomes an instant
## state change (no scale, no slide, no fade, no sweep).
##
## Everything is cosmetic: no game state, no RPCs, no global RNG.

const DUR_IN := 0.2
const SLIDE := 28.0
const HOVER_SCALE := 1.03
const PRESS_SCALE := 0.97
const SWEEP_DUR := 0.45


static func _root() -> Window:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null


static func reduce_motion() -> bool:
	var r := _root()
	var s: Node = r.get_node_or_null("Settings") if r != null else null
	return s != null and bool(s.get("reduce_motion"))


static func _sfx(method: String) -> void:
	var r := _root()
	var s: Node = r.get_node_or_null("Sfx") if r != null else null
	if s != null and s.has_method(method):
		s.call(method)


# ── Buttons ────────────────────────────────────────────

## Hover / press feedback on a button. scale_fx false = colour + sweep + sound
## only (option buttons, check rows, flat links — wide rows look wrong scaled).
static func bind_button(b: BaseButton, scale_fx: bool = true) -> void:
	if b == null or b.has_meta("uifx_btn"):
		return
	var st := {"hover": false, "focus": false, "down": false, "sweep": -1.0, "scale": scale_fx}
	b.set_meta("uifx_btn", st)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void:
		var was: bool = st.hover or st.focus
		st.hover = true
		_refresh(b, st, not was))
	b.mouse_exited.connect(func() -> void:
		st.hover = false
		st.down = false
		_refresh(b, st, false))
	b.focus_entered.connect(func() -> void:
		var was: bool = st.hover or st.focus
		st.focus = true
		_refresh(b, st, not was))
	b.focus_exited.connect(func() -> void:
		st.focus = false
		_refresh(b, st, false))
	b.button_down.connect(func() -> void:
		st.down = true
		_refresh(b, st, false))
	b.button_up.connect(func() -> void:
		st.down = false
		_refresh(b, st, false))
	b.pressed.connect(func() -> void: _sfx("ui"))
	b.visibility_changed.connect(func() -> void:
		if not b.is_visible_in_tree():
			st.hover = false
			st.down = false
			st.sweep = -1.0
			_kill(b, "uifx_scale_tw")
			b.scale = Vector2.ONE)
	b.draw.connect(func() -> void: _draw_sweep(b, st))


static func _kill(n: Node, key: String) -> void:
	if not n.has_meta(key):
		return
	var tw: Variant = n.get_meta(key)
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	n.remove_meta(key)


## Target scale for a button state (also read by the UI test).
static func target_scale(b: BaseButton) -> float:
	var st: Dictionary = b.get_meta("uifx_btn", {})
	if st.is_empty() or not bool(st.get("scale", false)) or b.disabled:
		return 1.0
	if bool(st.get("down", false)):
		return PRESS_SCALE
	if bool(st.get("hover", false)) or bool(st.get("focus", false)):
		return HOVER_SCALE
	return 1.0


static func _refresh(b: BaseButton, st: Dictionary, entered: bool) -> void:
	if not b.is_inside_tree():
		return
	if entered and not b.disabled:
		_sfx("ui_hover")
	var target := target_scale(b)
	_kill(b, "uifx_scale_tw")
	if reduce_motion() or not bool(st.scale):
		b.scale = Vector2.ONE
	else:
		b.pivot_offset = b.size * 0.5
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(target, target), 0.08 if bool(st.down) else 0.14) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		b.set_meta("uifx_scale_tw", tw)
	if entered and not b.disabled and not reduce_motion():
		_kill(b, "uifx_sweep_tw")
		var sw := b.create_tween()
		sw.tween_method(func(t: float) -> void:
			st.sweep = t
			b.queue_redraw(), 0.0, 1.0, SWEEP_DUR).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sw.tween_callback(func() -> void:
			st.sweep = -1.0
			b.queue_redraw())
		b.set_meta("uifx_sweep_tw", sw)


static func _draw_sweep(b: BaseButton, st: Dictionary) -> void:
	var t: float = st.sweep
	if t < 0.0 or t > 1.0:
		return
	var sz := b.size
	if sz.x < 4.0 or sz.y < 4.0:
		return
	var w := sz.y * 0.55
	var x := lerpf(-w * 2.0, sz.x + w, t)
	var band := PackedVector2Array([Vector2(x, sz.y), Vector2(x + w, 0.0), Vector2(x + w * 1.7, 0.0), Vector2(x + w * 0.7, sz.y)])
	var box := PackedVector2Array([Vector2(2, 2), Vector2(sz.x - 2, 2), Vector2(sz.x - 2, sz.y - 2), Vector2(2, sz.y - 2)])
	var a := 0.16 * sin(t * PI)
	for poly in Geometry2D.intersect_polygons(band, box):
		if poly.size() >= 3:
			b.draw_colored_polygon(poly, Color(0.78, 0.96, 1.0, a))


# ── Screen transitions ─────────────────────────────────

## Slide + fade `c` in from `dir` (unit vector; ZERO = fade only).
static func enter(c: Control, dir: Vector2 = Vector2.RIGHT, dur: float = DUR_IN) -> void:
	cancel(c)
	if reduce_motion() or not c.is_inside_tree():
		return
	var slide := dir * SLIDE
	var can_slide: bool = slide != Vector2.ZERO and not (c.get_parent() is Container)
	c.modulate.a = 0.0
	if can_slide:
		_set_shift(c, slide)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if can_slide:
		tw.tween_method(func(k: float) -> void: _set_shift(c, slide * k), 1.0, 0.0, dur + 0.03) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void:
		if c.has_meta("uifx_tw"):
			c.remove_meta("uifx_tw")
		_set_shift(c, Vector2.ZERO)
		c.modulate.a = 1.0)
	c.set_meta("uifx_tw", tw)


## Stop a running enter and restore the final state (alpha 1, layout exact).
static func cancel(c: Control) -> void:
	var running: bool = c.has_meta("uifx_tw")
	_kill(c, "uifx_tw")
	_set_shift(c, Vector2.ZERO)
	if running:
		c.modulate.a = 1.0


static func is_animating(c: Control) -> bool:
	if not c.has_meta("uifx_tw"):
		return false
	var tw: Variant = c.get_meta("uifx_tw")
	return tw is Tween and (tw as Tween).is_valid() and (tw as Tween).is_running()


static func _set_shift(c: Control, v: Vector2) -> void:
	var cur: Vector2 = c.get_meta("uifx_shift", Vector2.ZERO)
	if cur == v:
		return
	# Shift the four offsets (not `position`, which would bake the current —
	# possibly still settling — size into them): size and growth stay intact
	# and subtracting the same delta restores the layout exactly.
	var d := v - cur
	c.offset_left += d.x
	c.offset_right += d.x
	c.offset_top += d.y
	c.offset_bottom += d.y
	if v == Vector2.ZERO:
		c.remove_meta("uifx_shift")
	else:
		c.set_meta("uifx_shift", v)


## Animate `c` in every time it becomes visible in the tree.
static func watch(c: Control, dir: Vector2 = Vector2.RIGHT) -> void:
	if c == null:
		return
	var had: bool = c.has_meta("uifx_watch")
	c.set_meta("uifx_watch", dir)
	if had:
		return
	c.visibility_changed.connect(func() -> void:
		if c.is_visible_in_tree():
			enter(c, c.get_meta("uifx_watch", Vector2.ZERO))
		else:
			cancel(c))


## watch() every direct Control child of `root` (now and when added later);
## `dirs` maps a child to its own direction (default: from the right).
static func watch_children(root: Node, dirs: Dictionary = {}, skip: Array = []) -> void:
	for ch in root.get_children():
		if ch is Control and not skip.has(ch):
			watch(ch, dirs.get(ch, Vector2.RIGHT))
	root.child_entered_tree.connect(func(ch: Node) -> void:
		if ch is Control and not skip.has(ch) and not ch.has_meta("uifx_watch"):
			watch(ch, dirs.get(ch, Vector2.RIGHT))
			(func() -> void:
				if is_instance_valid(ch) and ch.is_inside_tree() and ch.is_visible_in_tree():
					enter(ch, ch.get_meta("uifx_watch", Vector2.RIGHT))).call_deferred())


## One-shot pop for HUD banners / toasts: scale 0.92 → 1 + fade (about the
## centre). Instant with Reduce motion.
static func pop(c: Control, dur: float = 0.18) -> void:
	_kill(c, "uifx_pop_tw")
	if reduce_motion() or not c.is_inside_tree():
		c.scale = Vector2.ONE
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.92, 0.92)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	c.set_meta("uifx_pop_tw", tw)
