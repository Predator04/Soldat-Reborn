class_name UITheme
extends Object
## Tracerfall design language (graphics Phase C, #272) — one source for every
## menu, panel, toast and HUD element.
##
## Direction: dark, gritty, high-contrast, cinematic. Near-black blue-grey glass
## panels (translucent darkening, no blur), off-white text, ONE warm accent
## (ember orange: primary actions, section headers, the score you care about)
## and ONE cool neon accent (cyan: hover edges, gamepad focus ring, highlights).
## Type: Barlow (body) + Barlow Condensed (headings, buttons, HUD numerals),
## OFL, in assets/fonts. Corners 6 (controls) / 8 (panels); borders 1 px at low
## alpha; the glow is a zero-offset StyleBoxFlat shadow.
##
## install_global() (called from Settings._ready) puts a Theme with the fonts
## and the control skins on the root window, so every Control, popup and
## tooltip in the game picks the look up. The style_* / make_* helpers below
## add the per-widget extras (button motion via ui_fx.gd, sizes, accents).

const UIFx = preload("res://scripts/ui_fx.gd")

# ── Palette ─────────────────────────────────────────────
const COL_BG := Color(0.027, 0.035, 0.05)               # near-black screen backdrop
const COL_BG_STRIPE := Color(0.08, 0.10, 0.13, 0.5)     # subtle overlay stripe for depth
const COL_PANEL := Color(0.045, 0.058, 0.08, 0.86)      # glass panel (translucent darkening)
const COL_PANEL_HI := Color(0.075, 0.092, 0.122, 0.92)  # raised card / header strip
const COL_PANEL_ROW := Color(1.0, 1.0, 1.0, 0.035)      # alternating list row shading
const COL_BORDER := Color(0.62, 0.72, 0.88, 0.16)       # hairline border
const COL_BORDER_HI := Color(0.66, 0.78, 0.94, 0.42)    # emphasised border
const COL_ACCENT := Color(1.0, 0.58, 0.16)              # warm accent (ember orange)
const COL_ACCENT_HI := Color(1.0, 0.74, 0.40)           # warm accent, lit
const COL_ACCENT_DIM := Color(1.0, 0.58, 0.16, 0.38)    # warm rules / chevrons
const COL_NEON := Color(0.30, 0.88, 1.0)                # cool neon (hover edge, focus, highlights)
const COL_NEON_DIM := Color(0.30, 0.88, 1.0, 0.32)
const COL_TEXT := Color(0.93, 0.95, 0.97)               # primary text
const COL_TEXT_DIM := Color(0.66, 0.71, 0.78)           # secondary text
const COL_TEXT_MUTED := Color(0.46, 0.51, 0.58)         # tertiary / footnotes / disabled
const COL_ALERT := Color(1.0, 0.36, 0.30)               # destructive / warning / low health
const COL_GOOD := Color(0.45, 0.90, 0.56)               # OK / connected
const COL_INFO := Color(0.58, 0.86, 1.0)                # info (network status)
const COL_SHADOW := Color(0, 0, 0, 0.85)                # text outline / drop shadow

# HUD-specific
const COL_HUD_HEALTH := Color(0.94, 0.96, 0.98)
const COL_HUD_FUEL := Color(0.36, 0.86, 1.0)
const COL_HUD_AMMO := Color(1.0, 0.70, 0.30)
const COL_HUD_WEAPON := Color(0.93, 0.95, 0.97)
const COL_HUD_GRENADE := Color(0.70, 0.92, 0.55)

# ── Type scale + metrics ────────────────────────────────
const FS_TITLE := 64      # logo / winner banner
const FS_H1 := 34         # screen titles
const FS_H2 := 22         # sub-headings, big HUD numerals
const FS_BODY := 16
const FS_CAPTION := 13
const BTN_W := 320
const BTN_H := 44
const BTN_FONT := 20
const HEAD_FONT := FS_H1
const SUB_FONT := 14
const LABEL_FONT := 15
const SECTION_FONT := 13
const RADIUS := 6          # controls
const RADIUS_PANEL := 8    # panels / cards
const PAD := 12

const FONT_FILES := {
	"body": "res://assets/fonts/Barlow-Medium.ttf",
	"semi": "res://assets/fonts/Barlow-SemiBold.ttf",
	"head": "res://assets/fonts/BarlowCondensed-Bold.ttf",
	"display": "res://assets/fonts/BarlowCondensed-ExtraBold.ttf",
}
# kind -> [file key, extra px per glyph]
const FONT_KINDS := {
	"body": ["body", 0], "semi": ["semi", 0], "head": ["head", 0],
	"caps": ["head", 2], "title": ["head", 1], "display": ["display", 0],
	"logo": ["display", 5], "hud": ["head", 0],
}

static var _fonts: Dictionary = {}
static var _sys_font: Font = null
static var _theme: Theme = null
static var _installed := false
static var _tex: Dictionary = {}


# ── Fonts + global theme ───────────────────────────────

## A design-language font: body | semi | head | caps (letter-spaced heading) |
## title | display | logo | hud (tabular figures). Glyphs the cut lacks
## (arrows, ✔, ●, ▸ …) fall back to the engine's default font.
static func font(kind: String = "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	if _sys_font == null:
		_sys_font = ThemeDB.fallback_font
	var spec: Array = FONT_KINDS.get(kind, FONT_KINDS["body"])
	var path: String = FONT_FILES[spec[0]]
	var f: Font = null
	if ResourceLoader.exists(path):
		var base: Font = load(path)
		var fv := FontVariation.new()
		fv.base_font = base
		fv.spacing_glyph = int(spec[1])
		if kind == "hud":
			fv.opentype_features = {"tnum": 1}
		if _sys_font != null:
			fv.fallbacks = [_sys_font]
		f = fv
	else:
		f = _sys_font
	_fonts[kind] = f
	return f


## Merges the Tracerfall theme (fonts, buttons, fields, popups, tooltips,
## sliders, scrollbars) into the engine's default theme — so it reaches every
## Control, including the ones under CanvasLayers (HUD, pause menu), which do
## not inherit a theme set on the root window — and makes the semibold body
## font the fallback for code that draws text with ThemeDB.fallback_font.
## Idempotent; the root argument is kept for callers.
static func install_global(_root: Window = null) -> void:
	if _installed:
		return
	_installed = true
	if _sys_font == null:
		_sys_font = ThemeDB.fallback_font
	var dt := ThemeDB.get_default_theme()
	var t := build_theme()
	if dt != null:
		dt.merge_with(t)
		dt.default_font = t.default_font
		dt.default_font_size = t.default_font_size
	ThemeDB.fallback_font = font("semi")


static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = FS_BODY
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, _btn_normal_style())
		t.set_stylebox("hover", type, _btn_hover_style())
		t.set_stylebox("pressed", type, _btn_pressed_style())
		t.set_stylebox("hover_pressed", type, _btn_pressed_style())
		t.set_stylebox("focus", type, _btn_focus_style())
		t.set_stylebox("disabled", type, _btn_disabled_style())
		t.set_color("font_color", type, COL_TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, COL_ACCENT_HI)
		t.set_color("font_hover_pressed_color", type, COL_ACCENT_HI)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, COL_TEXT_MUTED)
	t.set_font("font", "Button", font("head"))
	t.set_font_size("font_size", "Button", BTN_FONT)
	t.set_font("font", "OptionButton", font("semi"))
	t.set_font_size("font_size", "OptionButton", 16)
	for type in ["CheckBox", "CheckButton"]:
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 4
		empty.content_margin_right = 4
		empty.content_margin_top = 4
		empty.content_margin_bottom = 4
		for st in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
			t.set_stylebox(st, type, empty)
		var hov := _row_hover_style()
		t.set_stylebox("hover", type, hov)
		t.set_stylebox("hover_pressed", type, hov)
		t.set_stylebox("focus", type, _btn_focus_style())
		t.set_font("font", type, font("body"))
		t.set_font_size("font_size", type, 15)
		t.set_color("font_color", type, COL_TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, COL_TEXT)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, COL_TEXT_MUTED)
	t.set_icon("unchecked", "CheckBox", _box_icon(false))
	t.set_icon("checked", "CheckBox", _box_icon(true))
	t.set_icon("unchecked_disabled", "CheckBox", _box_icon(false, true))
	t.set_icon("checked_disabled", "CheckBox", _box_icon(true, true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false))
	t.set_icon("checked", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false, true))
	t.set_icon("checked_disabled", "CheckButton", _switch_icon(true, true))
	t.set_icon("unchecked_mirrored", "CheckButton", _switch_icon(false))
	t.set_icon("checked_mirrored", "CheckButton", _switch_icon(true))
	# Text fields
	var le := _field_style(false)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", _field_style(true))
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", COL_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", COL_TEXT_MUTED)
	t.set_color("caret_color", "LineEdit", COL_NEON)
	t.set_color("selection_color", "LineEdit", Color(COL_NEON, 0.28))
	t.set_font("font", "LineEdit", font("semi"))
	t.set_font_size("font_size", "LineEdit", 16)
	# Panels
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	# Labels / rich text
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_color("default_color", "RichTextLabel", COL_TEXT)
	t.set_font("normal_font", "RichTextLabel", font("body"))
	t.set_font("bold_font", "RichTextLabel", font("semi"))
	t.set_font("italics_font", "RichTextLabel", font("body"))
	# Popups (OptionButton lists) + tooltips
	var pop := panel_style(Color(0.05, 0.065, 0.09, 0.97), COL_BORDER_HI, RADIUS)
	pop.content_margin_left = 6
	pop.content_margin_right = 6
	pop.content_margin_top = 6
	pop.content_margin_bottom = 6
	t.set_stylebox("panel", "PopupMenu", pop)
	var ph := _flat(Color(COL_NEON, 0.16), RADIUS - 2)
	ph.border_width_left = 2
	ph.border_color = COL_NEON
	t.set_stylebox("hover", "PopupMenu", ph)
	t.set_color("font_color", "PopupMenu", COL_TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", COL_TEXT_MUTED)
	t.set_font("font", "PopupMenu", font("semi"))
	t.set_font_size("font_size", "PopupMenu", 16)
	t.set_constant("v_separation", "PopupMenu", 8)
	var tip := panel_style(Color(0.04, 0.05, 0.07, 0.96), COL_NEON_DIM, RADIUS)
	tip.content_margin_left = 10
	tip.content_margin_right = 10
	tip.content_margin_top = 6
	tip.content_margin_bottom = 6
	tip.shadow_size = 6
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", COL_TEXT)
	t.set_font("font", "TooltipLabel", font("body"))
	t.set_font_size("font_size", "TooltipLabel", 14)
	# Sliders
	var track := _flat(Color(1, 1, 1, 0.08), 3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := _flat(Color(COL_ACCENT, 0.85), 3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := fill.duplicate()
	fill_hi.bg_color = COL_ACCENT_HI
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	t.set_icon("grabber", "HSlider", _knob_icon(false))
	t.set_icon("grabber_highlight", "HSlider", _knob_icon(true))
	t.set_icon("grabber_disabled", "HSlider", _knob_icon(false))
	var sl_focus := _flat(Color(0, 0, 0, 0), RADIUS)
	sl_focus.draw_center = false
	sl_focus.set_border_width_all(1)
	sl_focus.border_color = COL_NEON
	t.set_stylebox("focus", "HSlider", sl_focus)
	# Slim scrollbars
	for sb in ["VScrollBar", "HScrollBar"]:
		var trk := _flat(Color(1, 1, 1, 0.04), 4)
		trk.content_margin_left = 4
		trk.content_margin_right = 4
		trk.content_margin_top = 4
		trk.content_margin_bottom = 4
		t.set_stylebox("scroll", sb, trk)
		t.set_stylebox("scroll_focus", sb, trk)
		var g := _flat(Color(1, 1, 1, 0.20), 4)
		t.set_stylebox("grabber", sb, g)
		t.set_stylebox("grabber_highlight", sb, _flat(Color(COL_NEON, 0.55), 4))
		t.set_stylebox("grabber_pressed", sb, _flat(Color(COL_NEON, 0.75), 4))
	_theme = t
	return t


# ── Focus helpers ─────────────────────────────────────

# #101: safe deferred grab_focus. Callers use this instead of
# c.call_deferred("grab_focus") so the focus attempt no-ops if the target has
# been freed or removed from the tree by the time the deferred queue drains
# (dedicated server boot: menu.tscn → main.tscn scene change fires between the
# queue and the flush, leaving orphaned Control instances the built-in grab_focus
# would error on with `!is_inside_tree()`).
static func safe_grab_focus_deferred(c: Control) -> void:
	if c == null:
		return
	(func() -> void:
		if is_instance_valid(c) and c.is_inside_tree():
			c.grab_focus()).call_deferred()


# ── UI scale (Settings → Video → UI scale) ─────────────

static func _settings() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		return (ml as SceneTree).root.get_node_or_null("Settings")
	return null


static func ui_scale() -> float:
	var s := _settings()
	if s == null or s.get("ui_scale") == null:
		return 1.0
	return clampf(float(s.get("ui_scale")), 0.75, 1.5)


## Scale a full-screen UI root (main menu, pause overlay, HUD layer) by the UI
## scale setting: the root's rect becomes viewport / scale and it is drawn at
## `scale`, so anchored children still hug the real screen edges. Follows
## window resizes and live setting changes (refresh_ui_scale).
static func apply_ui_scale(c: Control) -> void:
	if c == null:
		return
	if not c.has_meta("ui_scale_cb"):
		var cb := func() -> void:
			if not is_instance_valid(c) or not c.is_inside_tree():
				return
			var s := ui_scale()
			var vp := c.get_viewport_rect().size
			if absf(s - 1.0) < 0.001:
				c.scale = Vector2.ONE
				c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			else:
				c.set_anchors_preset(Control.PRESET_TOP_LEFT)
				c.pivot_offset = Vector2.ZERO
				c.position = Vector2.ZERO
				c.size = vp / s
				c.scale = Vector2(s, s)
		c.set_meta("ui_scale_cb", cb)
		c.add_to_group("ui_scaled")
		var hook := func() -> void:
			var vpp := c.get_viewport()
			if vpp != null and not vpp.size_changed.is_connected(cb):
				vpp.size_changed.connect(cb)
			cb.call()
		var unhook := func() -> void:
			var vpp := c.get_viewport()
			if vpp != null and vpp.size_changed.is_connected(cb):
				vpp.size_changed.disconnect(cb)
		c.tree_entered.connect(hook)
		c.tree_exiting.connect(unhook)
		if c.is_inside_tree():
			hook.call()
	else:
		(c.get_meta("ui_scale_cb") as Callable).call()


## Size of the screen in the UI's own (possibly scaled) units for a node
## under a UI-scaled root; the viewport size otherwise.
static func ui_view_size(ci: CanvasItem) -> Vector2:
	var n: Node = ci
	while n != null:
		if n is Control and n.is_in_group("ui_scaled"):
			return (n as Control).size
		n = n.get_parent()
	return ci.get_viewport_rect().size


## The HUD CanvasLayer above a HUD part (parts now sit under its UIRoot).
static func hud_of(n: Node) -> Node:
	var p := n.get_parent()
	while p != null and not (p is CanvasLayer):
		p = p.get_parent()
	return p


static func refresh_ui_scale(tree: SceneTree) -> void:
	if tree == null:
		return
	for n in tree.get_nodes_in_group("ui_scaled"):
		if n.has_meta("ui_scale_cb"):
			(n.get_meta("ui_scale_cb") as Callable).call()


# ── Style primitives ───────────────────────────────────

static func _flat(bg: Color, radius: int = RADIUS) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


# ── Panels ─────────────────────────────────────────────

static func panel_style(bg: Color = COL_PANEL, border: Color = COL_BORDER, radius: int = RADIUS_PANEL) -> StyleBoxFlat:
	var s := _flat(bg, radius)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 6)
	return s


static func card_style() -> StyleBoxFlat:
	# Inner card inside a panel (settings sections) — one step lighter.
	var s := panel_style(COL_PANEL_HI, COL_BORDER, RADIUS)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_size = 0
	return s


static func hud_strip_style() -> StyleBoxFlat:
	# HUD backing: dark translucent glass that darkens bright terrain without
	# hiding it; hairline border, no shadow (reads clean at speed).
	var s := _flat(Color(0.02, 0.028, 0.04, 0.62), RADIUS_PANEL)
	s.set_border_width_all(1)
	s.border_color = Color(0.62, 0.72, 0.88, 0.12)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


## Compact pill behind a HUD line (toasts, kill feed rows, chat, banners).
static func hud_pill_style(accent: Color = Color(0, 0, 0, 0), alpha: float = 0.55) -> StyleBoxFlat:
	var s := _flat(Color(0.02, 0.028, 0.04, alpha), 5)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 4
	if accent.a > 0.0:
		s.border_width_left = 3
		s.border_color = accent
	return s


static func title_bar_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.065, 0.09, 0.95)
	s.corner_radius_top_left = RADIUS_PANEL
	s.corner_radius_top_right = RADIUS_PANEL
	s.border_width_bottom = 2
	s.border_color = COL_ACCENT
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func _row_hover_style() -> StyleBoxFlat:
	var s := _flat(Color(1, 1, 1, 0.045), RADIUS)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func _field_style(focused: bool) -> StyleBoxFlat:
	var s := _flat(Color(0.02, 0.028, 0.04, 0.9), RADIUS)
	s.set_border_width_all(1)
	s.border_color = COL_NEON if focused else COL_BORDER
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	if focused:
		s.shadow_color = Color(COL_NEON, 0.22)
		s.shadow_size = 5
	return s


# ── Buttons ────────────────────────────────────────────

static func _btn_base(bg: Color, border: Color) -> StyleBoxFlat:
	var s := _flat(bg, RADIUS)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func _btn_normal_style() -> StyleBoxFlat:
	return _btn_base(Color(0.075, 0.092, 0.122, 0.9), COL_BORDER)


static func _btn_hover_style() -> StyleBoxFlat:
	# Neon edge + soft cyan glow (zero-offset shadow).
	var s := _btn_base(Color(0.10, 0.13, 0.17, 0.96), Color(COL_NEON, 0.75))
	s.shadow_color = Color(COL_NEON, 0.20)
	s.shadow_size = 7
	return s


static func _btn_pressed_style() -> StyleBoxFlat:
	var s := _btn_base(Color(0.22, 0.12, 0.04, 0.97), COL_ACCENT)
	s.shadow_color = Color(COL_ACCENT, 0.22)
	s.shadow_size = 5
	return s


static func _btn_focus_style() -> StyleBoxFlat:
	# Drawn OVER the state box: a 2 px neon ring for gamepad / keyboard focus.
	var s := _flat(Color(0, 0, 0, 0), RADIUS + 1)
	s.draw_center = false
	s.set_border_width_all(2)
	s.border_color = COL_NEON
	s.expand_margin_left = 2
	s.expand_margin_right = 2
	s.expand_margin_top = 2
	s.expand_margin_bottom = 2
	s.shadow_color = Color(COL_NEON, 0.18)
	s.shadow_size = 6
	return s


static func _btn_disabled_style() -> StyleBoxFlat:
	return _btn_base(Color(0.05, 0.06, 0.08, 0.6), Color(0.62, 0.72, 0.88, 0.07))


static func _btn_normal_primary_style() -> StyleBoxFlat:
	# Primary CTA: solid ember fill, dark text — the one loud thing on a screen.
	var s := _btn_base(Color(COL_ACCENT, 0.94), Color(1.0, 0.78, 0.5, 0.9))
	s.shadow_color = Color(COL_ACCENT, 0.22)
	s.shadow_size = 8
	return s


static func _btn_hover_primary_style() -> StyleBoxFlat:
	var s := _btn_base(COL_ACCENT_HI, Color(1.0, 0.92, 0.78))
	s.shadow_color = Color(COL_ACCENT, 0.42)
	s.shadow_size = 12
	return s


static func _btn_pressed_primary_style() -> StyleBoxFlat:
	var s := _btn_base(Color(0.80, 0.42, 0.08), COL_ACCENT)
	s.shadow_color = Color(COL_ACCENT, 0.3)
	s.shadow_size = 6
	return s


const COL_ON_ACCENT := Color(0.07, 0.05, 0.03)   # text on a solid ember fill


static func style_button(b: Button, font_size: int = BTN_FONT, primary: bool = false) -> void:
	# The shared button skin + motion (ui_fx.gd: hover / press scale, neon
	# sweep, click sound). Primary = the intended path ("PLAY", "START").
	b.add_theme_stylebox_override("normal", _btn_normal_primary_style() if primary else _btn_normal_style())
	b.add_theme_stylebox_override("hover", _btn_hover_primary_style() if primary else _btn_hover_style())
	b.add_theme_stylebox_override("pressed", _btn_pressed_primary_style() if primary else _btn_pressed_style())
	b.add_theme_stylebox_override("hover_pressed", _btn_pressed_primary_style() if primary else _btn_pressed_style())
	b.add_theme_stylebox_override("focus", _btn_focus_style())
	b.add_theme_stylebox_override("disabled", _btn_disabled_style())
	b.add_theme_font_override("font", font("head"))
	b.add_theme_font_size_override("font_size", font_size)
	if primary:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(k, COL_ON_ACCENT)
	else:
		b.add_theme_color_override("font_color", COL_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", COL_ACCENT_HI)
		b.add_theme_color_override("font_hover_pressed_color", COL_ACCENT_HI)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", COL_TEXT_MUTED)
	UIFx.bind_button(b)


static func make_button(text: String, primary: bool = false, w: int = BTN_W, h: int = BTN_H) -> Button:
	var b := Button.new()
	b.text = text
	if is_touch():
		h = maxi(h, 48)
	b.custom_minimum_size = Vector2(w, h)
	style_button(b, BTN_FONT, primary)
	return b


static func make_small_button(text: String, w: int = 200, h: int = 34) -> Button:
	var b := Button.new()
	b.text = text
	# Phones: at least ~44 px tall so rows of WATCH / JOIN / DOWNLOAD are easy
	# to hit with a thumb.
	if is_touch():
		h = maxi(h, 44)
	b.custom_minimum_size = Vector2(w, h)
	style_button(b, 16, false)
	return b


## Flat text link ("Credits & licenses"): dim → neon on hover / focus.
static func style_link(b: Button, size: int = FS_CAPTION) -> void:
	b.flat = true
	b.add_theme_font_override("font", font("semi"))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", COL_TEXT_DIM)
	b.add_theme_color_override("font_hover_color", COL_NEON)
	b.add_theme_color_override("font_focus_color", COL_NEON)
	b.add_theme_color_override("font_pressed_color", COL_ACCENT_HI)
	UIFx.bind_button(b, false)


static func is_touch() -> bool:
	return OS.has_feature("android") or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() \
		or "--force-touch" in OS.get_cmdline_user_args()


# ── Text ───────────────────────────────────────────────

static func style_title(l: Label, size: int = FS_TITLE) -> void:
	l.add_theme_font_override("font", font("display"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", COL_TEXT)
	l.add_theme_color_override("font_outline_color", COL_SHADOW)
	l.add_theme_constant_override("outline_size", 8)


static func style_head(l: Label, size: int = HEAD_FONT) -> void:
	l.add_theme_font_override("font", font("title"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", COL_TEXT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("outline_size", 0)


static func style_body(l: Label, size: int = LABEL_FONT, col: Color = COL_TEXT) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)


static func style_hud_label(l: Label, col: Color, size: int = 17) -> void:
	l.add_theme_font_override("font", font("hud"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", COL_SHADOW)
	l.add_theme_constant_override("outline_size", 4)


## HUD text over the world: condensed, outlined for any background.
static func style_hud_text(l: Label, size: int, col: Color, outline: int = 5) -> void:
	l.add_theme_font_override("font", font("head"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", COL_SHADOW)
	l.add_theme_constant_override("outline_size", outline)


# Uppercase section header: letter-spaced warm caps, a short ember tick and a
# hairline rule — for grouping controls / cards.
static func make_section_header(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.process_mode = Node.PROCESS_MODE_ALWAYS
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 4)
	v.add_child(pad)
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_override("font", font("caps"))
	lbl.add_theme_font_size_override("font_size", SECTION_FONT + 1)
	lbl.add_theme_color_override("font_color", COL_ACCENT)
	v.add_child(lbl)
	var rule := HBoxContainer.new()
	rule.add_theme_constant_override("separation", 0)
	var tick := ColorRect.new()
	tick.color = COL_ACCENT
	tick.custom_minimum_size = Vector2(22, 2)
	rule.add_child(tick)
	var line := ColorRect.new()
	line.color = COL_BORDER
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_END
	rule.add_child(line)
	v.add_child(rule)
	return v


static func make_screen_title(text: String, size: int = HEAD_FONT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style_head(l, size)
	return l


static func make_sub_label(text: String, col: Color = COL_TEXT_DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", SUB_FONT)
	l.add_theme_color_override("font_color", col)
	return l


# Small transparent spacer, in place of empty labels.
static func spacer(px: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	return c


## A hairline rule with a centred ember tick (under screen titles).
static func make_rule() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 3)
	c.draw.connect(func() -> void:
		var w := c.size.x
		c.draw_rect(Rect2(0, 1, w, 1), COL_BORDER)
		c.draw_rect(Rect2(w * 0.5 - 18.0, 0, 36.0, 3), COL_ACCENT))
	return c


# ── LineEdit / OptionButton skins ──────────────────────

static func style_lineedit(le: LineEdit) -> void:
	le.add_theme_stylebox_override("normal", _field_style(false))
	le.add_theme_stylebox_override("focus", _field_style(true))
	le.add_theme_color_override("font_color", COL_TEXT)
	le.add_theme_color_override("font_placeholder_color", COL_TEXT_MUTED)
	le.add_theme_color_override("caret_color", COL_NEON)
	le.add_theme_font_override("font", font("semi"))
	le.add_theme_font_size_override("font_size", 16)


static func style_option_button(o: OptionButton) -> void:
	o.add_theme_stylebox_override("normal", _btn_normal_style())
	o.add_theme_stylebox_override("hover", _btn_hover_style())
	o.add_theme_stylebox_override("pressed", _btn_pressed_style())
	o.add_theme_stylebox_override("focus", _btn_focus_style())
	o.add_theme_stylebox_override("disabled", _btn_disabled_style())
	o.add_theme_font_override("font", font("semi"))
	o.add_theme_font_size_override("font_size", 16)
	o.add_theme_color_override("font_color", COL_TEXT)
	o.add_theme_color_override("font_hover_color", Color.WHITE)
	o.add_theme_color_override("font_pressed_color", COL_ACCENT_HI)
	o.add_theme_color_override("font_focus_color", Color.WHITE)
	if is_touch():
		o.custom_minimum_size.y = maxf(o.custom_minimum_size.y, 44.0)
	UIFx.bind_button(o, false)


static func style_checkbox(cb: BaseButton) -> void:
	# CheckBox and CheckButton share the "font_*" theme keys we care about.
	cb.add_theme_font_override("font", font("body"))
	cb.add_theme_font_size_override("font_size", 15)
	cb.add_theme_color_override("font_color", COL_TEXT)
	cb.add_theme_color_override("font_hover_color", Color.WHITE)
	cb.add_theme_color_override("font_pressed_color", COL_TEXT)
	cb.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	cb.add_theme_color_override("font_focus_color", Color.WHITE)
	cb.add_theme_stylebox_override("focus", _btn_focus_style())
	if cb is CheckBox:
		cb.add_theme_icon_override("unchecked", _box_icon(false))
		cb.add_theme_icon_override("checked", _box_icon(true))
		cb.add_theme_icon_override("unchecked_disabled", _box_icon(false, true))
		cb.add_theme_icon_override("checked_disabled", _box_icon(true, true))
	elif cb is CheckButton:
		cb.add_theme_icon_override("unchecked", _switch_icon(false))
		cb.add_theme_icon_override("checked", _switch_icon(true))
	if is_touch():
		cb.custom_minimum_size.y = maxf(cb.custom_minimum_size.y, 40.0)
	UIFx.bind_button(cb, false)


static func style_slider(s: HSlider) -> void:
	# The global theme skins sliders; this only gives touch a taller hit area.
	if is_touch():
		s.custom_minimum_size.y = maxf(s.custom_minimum_size.y, 36.0)


# ── Generated icons (no image assets) ──────────────────

static func _aa_disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			if a > 0.0:
				var under := img.get_pixel(x, y)
				img.set_pixel(x, y, under.blend(Color(col, col.a * a)))


static func _rrect(img: Image, rect: Rect2, r: float, col: Color, ring: float = 0.0) -> void:
	# Anti-aliased rounded rect (filled, or a ring `ring` px wide).
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - rect.get_center()).abs() - (rect.size * 0.5 - Vector2(r, r))
			var dist := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r
			var a := clampf(0.5 - dist, 0.0, 1.0)
			if ring > 0.0:
				a = minf(a, clampf(dist + ring + 0.5, 0.0, 1.0))
			if a > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(Color(col, col.a * a)))


static func _box_icon(on: bool, disabled := false) -> Texture2D:
	var key := "box_%s_%s" % [on, disabled]
	if _tex.has(key):
		return _tex[key]
	var n := 20
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var k := 0.45 if disabled else 1.0
	var r := Rect2(1, 1, n - 2, n - 2)
	if on:
		_rrect(img, r, 4.0, Color(COL_ACCENT, k))
		var ink := Color(0.06, 0.05, 0.04)
		for i in 7:
			var t := float(i) / 6.0
			_aa_disc(img, Vector2(5.5, 10.5).lerp(Vector2(8.5, 13.5), t), 1.3, ink)
		for i in 10:
			var t := float(i) / 9.0
			_aa_disc(img, Vector2(8.5, 13.5).lerp(Vector2(14.5, 6.5), t), 1.3, ink)
	else:
		_rrect(img, r, 4.0, Color(0, 0, 0, 0.45))
		_rrect(img, r, 4.0, Color(COL_TEXT_DIM, 0.8 * k), 1.5)
	var tx := ImageTexture.create_from_image(img)
	_tex[key] = tx
	return tx


static func _switch_icon(on: bool, disabled := false) -> Texture2D:
	var key := "sw_%s_%s" % [on, disabled]
	if _tex.has(key):
		return _tex[key]
	var w := 40
	var h := 22
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var k := 0.45 if disabled else 1.0
	var r := Rect2(1, 2, w - 2, h - 4)
	if on:
		_rrect(img, r, 9.0, Color(COL_ACCENT, 0.9 * k))
		_aa_disc(img, Vector2(w - 11.5, h * 0.5), 6.5, Color(1, 1, 1, k))
	else:
		_rrect(img, r, 9.0, Color(1, 1, 1, 0.08))
		_rrect(img, r, 9.0, Color(COL_TEXT_DIM, 0.45 * k), 1.2)
		_aa_disc(img, Vector2(11.5, h * 0.5), 6.0, Color(COL_TEXT_DIM, 0.9 * k))
	var tx := ImageTexture.create_from_image(img)
	_tex[key] = tx
	return tx


static func _knob_icon(hot: bool) -> Texture2D:
	var key := "knob_%s" % hot
	if _tex.has(key):
		return _tex[key]
	var n := 20
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if hot:
		_aa_disc(img, Vector2(10, 10), 9.5, Color(COL_NEON, 0.30))
	_aa_disc(img, Vector2(10, 10), 7.0, Color(0, 0, 0, 0.5))
	_aa_disc(img, Vector2(10, 10), 6.0, Color.WHITE if hot else COL_TEXT)
	var tx := ImageTexture.create_from_image(img)
	_tex[key] = tx
	return tx


## Clean vector HUD icons drawn into any CanvasItem's _draw: health, jet,
## ammo, grenade, headshot, flag, clock, skull. `c` = centre, `s` = size (px).
static func draw_icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var h := s * 0.5
	match kind:
		"health":
			var t := s * 0.30
			ci.draw_rect(Rect2(c.x - t * 0.5, c.y - h, t, s), col)
			ci.draw_rect(Rect2(c.x - h, c.y - t * 0.5, s, t), col)
		"jet":
			# Twin chevrons pointing up: thrust.
			for i in 2:
				var y0 := c.y + h - float(i) * s * 0.42
				ci.draw_polyline(PackedVector2Array([Vector2(c.x - h * 0.85, y0), Vector2(c.x, y0 - s * 0.42), Vector2(c.x + h * 0.85, y0)]), col, maxf(1.5, s * 0.16), true)
		"ammo":
			# A round: case + ogive tip.
			var bw := s * 0.36
			ci.draw_rect(Rect2(c.x - bw * 0.5, c.y - h * 0.15, bw, h * 1.15), col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - bw * 0.5, c.y - h * 0.22), Vector2(c.x, c.y - h), Vector2(c.x + bw * 0.5, c.y - h * 0.22)]), col)
		"grenade":
			ci.draw_circle(c + Vector2(0, s * 0.08), h * 0.78, col)
			ci.draw_rect(Rect2(c.x - s * 0.14, c.y - h * 0.92, s * 0.28, s * 0.2), col)
			ci.draw_arc(c + Vector2(s * 0.22, -h * 0.8), s * 0.14, PI * 0.9, PI * 2.4, 10, col, maxf(1.0, s * 0.08), true)
		"headshot":
			ci.draw_arc(c, h * 0.8, 0.0, TAU, 24, col, maxf(1.2, s * 0.12), true)
			ci.draw_circle(c, s * 0.12, col)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * h * 0.55, c + d * h * 1.05, col, maxf(1.2, s * 0.12), true)
		"flag":
			ci.draw_line(Vector2(c.x - h * 0.6, c.y - h), Vector2(c.x - h * 0.6, c.y + h), col, maxf(1.2, s * 0.12), true)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - h * 0.5, c.y - h), Vector2(c.x + h, c.y - h * 0.55), Vector2(c.x - h * 0.5, c.y - h * 0.05)]), col)
		"clock":
			ci.draw_arc(c, h * 0.85, 0.0, TAU, 24, col, maxf(1.2, s * 0.11), true)
			ci.draw_line(c, c + Vector2(0, -h * 0.55), col, maxf(1.2, s * 0.11), true)
			ci.draw_line(c, c + Vector2(h * 0.4, 0), col, maxf(1.2, s * 0.11), true)
		"skull":
			ci.draw_circle(c + Vector2(0, -s * 0.06), h * 0.78, col)
			ci.draw_rect(Rect2(c.x - h * 0.45, c.y + h * 0.3, h * 0.9, h * 0.55), col)
			var hole := Color(0, 0, 0, 0.85)
			ci.draw_circle(c + Vector2(-h * 0.32, -s * 0.06), h * 0.2, hole)
			ci.draw_circle(c + Vector2(h * 0.32, -s * 0.06), h * 0.2, hole)


## Texture of a vector icon (TextureRects: kill feed headshot marker …).
static func icon_texture(kind: String, px: int = 16, col: Color = Color.WHITE) -> Texture2D:
	var key := "ic_%s_%d_%s" % [kind, px, col.to_html()]
	if _tex.has(key):
		return _tex[key]
	# Rasterise the vector shapes once through the shared disc / rect helpers.
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(px, px) * 0.5
	var h := px * 0.5
	match kind:
		"headshot":
			for i in 48:
				var a := TAU * float(i) / 48.0
				_aa_disc(img, c + Vector2(cos(a), sin(a)) * h * 0.72, maxf(0.8, px * 0.06), col)
			_aa_disc(img, c, px * 0.13, col)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				for j in 4:
					_aa_disc(img, c + d * h * (0.55 + 0.13 * j), maxf(0.8, px * 0.06), col)
		_:
			_aa_disc(img, c, h * 0.8, col)
	var tx := ImageTexture.create_from_image(img)
	_tex[key] = tx
	return tx


# ── Backdrops ─────────────────────────────────────────

# Main menu backdrop: the animated cinematic scene (menu_backdrop.gd).
static func build_menu_backdrop(root: Control) -> Node:
	var bd: Node = load("res://scripts/menu_backdrop.gd").new()
	bd.name = "MenuBackdrop"
	root.add_child(bd)
	return bd


# Framed panel container for sub-screens (Host/Join/Stats/etc.). Wraps a VBox
# in a PanelContainer with the shared panel style + title and ember rule.
static func wrap_panel(inner: Control, title: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", panel_style())
	pc.set_anchors_preset(Control.PRESET_CENTER, true)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pc.add_child(col)
	col.add_child(make_screen_title(title))
	col.add_child(make_rule())
	col.add_child(inner)
	return pc


## #256: grid of per-weapon toggle chips for the host's weapon-ban set.
## `bans` is the current list of banned names; on_toggle gets (name, banned)
## and is expected to update the source of truth (the grid refreshes itself).
static func make_weapon_ban_grid(bans: Array, on_toggle: Callable) -> Control:
	var GameLists = preload("res://scripts/game_lists.gd")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for nm in GameLists.WEAPON_NAMES:
		var banned := bans.has(nm)
		var b := Button.new()
		b.toggle_mode = true
		b.text = nm
		b.custom_minimum_size = Vector2(112, 40 if is_touch() else 30)
		b.tooltip_text = "Remove %s from the match (menus, spawns, bots, pickups). Gun Game rungs and the Rambo bow are match rules and stay." % nm
		b.button_pressed = banned
		style_button(b, 15, false)
		_style_ban_chip(b, banned)
		b.toggled.connect(func(on: bool) -> void:
			_style_ban_chip(b, on)
			on_toggle.call(nm, on))
		grid.add_child(b)
	return grid


static func _style_ban_chip(b: Button, banned: bool) -> void:
	if banned:
		b.add_theme_color_override("font_color", COL_ALERT)
		b.add_theme_color_override("font_pressed_color", COL_ALERT)
		b.add_theme_color_override("font_hover_pressed_color", COL_ALERT)
		var s := _btn_base(Color(0.22, 0.06, 0.05, 0.9), Color(COL_ALERT, 0.7))
		b.add_theme_stylebox_override("pressed", s)
		b.add_theme_stylebox_override("hover_pressed", s)
		if not b.text.ends_with(" ✕"):
			b.text += " ✕"
	else:
		b.add_theme_color_override("font_color", COL_TEXT)
		b.add_theme_color_override("font_pressed_color", COL_TEXT)
		b.text = b.text.trim_suffix(" ✕")
