class_name UITheme
extends Object
## Shared retro-military UI palette + style factories.
##
## Every menu / panel / HUD strip goes through this to keep panels, buttons,
## headers and text colors cohesive across the whole game. Colors + metrics are
## defined once here; consumers grab a StyleBoxFlat or apply a helper.
##
## Aesthetic: dark gunmetal panels, thin steel borders, amber accent for
## selection/hover, muted blue-grey for text — homage to classic Soldat/UT-era
## military UIs, not modern glassmorphism.

# ── Palette ─────────────────────────────────────────────
const COL_BG := Color(0.045, 0.055, 0.075)              # near-black screen backdrop
const COL_BG_STRIPE := Color(0.09, 0.10, 0.13, 0.5)     # subtle overlay stripe for depth
const COL_PANEL := Color(0.10, 0.12, 0.15, 0.94)        # gunmetal panel bg
const COL_PANEL_HI := Color(0.14, 0.16, 0.20, 0.96)     # elevated / header strip
const COL_PANEL_ROW := Color(0.13, 0.15, 0.18, 0.55)    # alternating list row shading
const COL_BORDER := Color(0.28, 0.32, 0.38, 0.85)       # steel border
const COL_BORDER_HI := Color(0.55, 0.62, 0.72, 0.9)     # highlighted / focused border
const COL_ACCENT := Color(0.98, 0.66, 0.18)             # amber selection color
const COL_ACCENT_HI := Color(1.0, 0.82, 0.34)           # amber hover
const COL_ACCENT_DIM := Color(0.55, 0.38, 0.10, 0.85)   # muted amber (chevrons/rules)
const COL_TEXT := Color(0.90, 0.93, 0.96)               # primary text
const COL_TEXT_DIM := Color(0.68, 0.72, 0.78)           # secondary text
const COL_TEXT_MUTED := Color(0.48, 0.52, 0.58)         # tertiary / footnotes
const COL_ALERT := Color(0.95, 0.42, 0.32)              # destructive / warning
const COL_GOOD := Color(0.55, 0.85, 0.42)               # OK / connected
const COL_INFO := Color(0.62, 0.82, 1.0)                # info blue (network status)
const COL_SHADOW := Color(0, 0, 0, 0.9)                 # text outline

# HUD-specific
const COL_HUD_HEALTH := Color(0.98, 0.42, 0.35)
const COL_HUD_FUEL := Color(0.45, 0.82, 1.0)
const COL_HUD_AMMO := Color(0.95, 0.95, 0.95)
const COL_HUD_WEAPON := Color(0.98, 0.85, 0.5)
const COL_HUD_GRENADE := Color(0.62, 0.95, 0.55)

# ── Metrics ─────────────────────────────────────────────
const BTN_W := 320
const BTN_H := 44
const BTN_FONT := 19
const HEAD_FONT := 30
const SUB_FONT := 14
const LABEL_FONT := 15
const SECTION_FONT := 13
const RADIUS := 4
const PAD := 12


# ── Panels ─────────────────────────────────────────────

static func panel_style(bg: Color = COL_PANEL, border: Color = COL_BORDER, radius: int = RADIUS) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_color = border
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	return s


static func card_style() -> StyleBoxFlat:
	# Inner card inside a settings panel — slightly lighter than the panel bg
	# with a thin left accent bar drawn separately by the caller.
	var s := panel_style(COL_PANEL_HI, COL_BORDER, RADIUS)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_size = 4
	return s


static func hud_strip_style() -> StyleBoxFlat:
	# Backing strip for the top-of-screen and left HUD clusters — dark and
	# translucent so it darkens bright terrain without hiding it.
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.03, 0.05, 0.55)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	s.border_color = Color(0.30, 0.34, 0.40, 0.5)
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func title_bar_style() -> StyleBoxFlat:
	# Header strip that sits at the top of a panel; darker than the panel bg
	# with a bottom amber rule.
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.08, 0.11, 0.95)
	s.corner_radius_top_left = RADIUS
	s.corner_radius_top_right = RADIUS
	s.border_width_bottom = 2
	s.border_color = COL_ACCENT
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


# ── Buttons ────────────────────────────────────────────

static func _btn_normal_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.14, 0.16, 0.20, 0.95)
	s.border_color = COL_BORDER
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = RADIUS
	s.corner_radius_top_right = RADIUS
	s.corner_radius_bottom_left = RADIUS
	s.corner_radius_bottom_right = RADIUS
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func _btn_hover_style() -> StyleBoxFlat:
	var s := _btn_normal_style()
	s.bg_color = Color(0.18, 0.20, 0.24, 0.98)
	s.border_color = COL_ACCENT
	# Left accent bar via wider left border — reads as a "target-locked" indicator.
	s.border_width_left = 3
	return s


static func _btn_pressed_style() -> StyleBoxFlat:
	var s := _btn_normal_style()
	s.bg_color = Color(0.22, 0.16, 0.06, 0.98)
	s.border_color = COL_ACCENT_HI
	s.border_width_left = 3
	return s


static func _btn_focus_style() -> StyleBoxFlat:
	var s := _btn_normal_style()
	s.bg_color = Color(0.16, 0.18, 0.22, 0.95)
	s.border_color = COL_ACCENT
	s.border_width_left = 3
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	return s


static func _btn_disabled_style() -> StyleBoxFlat:
	var s := _btn_normal_style()
	s.bg_color = Color(0.09, 0.10, 0.12, 0.85)
	s.border_color = Color(0.22, 0.24, 0.28, 0.7)
	return s


static func style_button(b: Button, font_size: int = BTN_FONT, primary: bool = false) -> void:
	# Applies the shared button skin. If primary, tints the normal state with a
	# faint amber wash so key actions ("PLAY", "START HOSTING") stand out.
	b.add_theme_stylebox_override("normal", _btn_normal_style() if not primary else _btn_normal_primary_style())
	b.add_theme_stylebox_override("hover", _btn_hover_style())
	b.add_theme_stylebox_override("pressed", _btn_pressed_style())
	b.add_theme_stylebox_override("focus", _btn_focus_style())
	b.add_theme_stylebox_override("disabled", _btn_disabled_style())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_ACCENT_HI)
	b.add_theme_color_override("font_pressed_color", COL_ACCENT_HI)
	b.add_theme_color_override("font_focus_color", COL_ACCENT_HI)
	b.add_theme_color_override("font_disabled_color", COL_TEXT_MUTED)


static func _btn_normal_primary_style() -> StyleBoxFlat:
	# Slight amber wash so primary CTAs read as the intended path without
	# needing a different shape.
	var s := _btn_normal_style()
	s.bg_color = Color(0.20, 0.16, 0.09, 0.95)
	s.border_color = Color(0.55, 0.42, 0.16, 0.9)
	return s


static func make_button(text: String, primary: bool = false, w: int = BTN_W, h: int = BTN_H) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	style_button(b, BTN_FONT, primary)
	return b


static func make_small_button(text: String, w: int = 200, h: int = 34) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	style_button(b, 15, false)
	return b


# ── Text ───────────────────────────────────────────────

static func style_title(l: Label, size: int = 56) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", COL_ACCENT)
	l.add_theme_color_override("font_outline_color", COL_SHADOW)
	l.add_theme_constant_override("outline_size", 8)


static func style_head(l: Label, size: int = HEAD_FONT) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", COL_ACCENT)
	l.add_theme_color_override("font_outline_color", COL_SHADOW)
	l.add_theme_constant_override("outline_size", 6)


static func style_body(l: Label, size: int = LABEL_FONT, col: Color = COL_TEXT) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)


static func style_hud_label(l: Label, col: Color) -> void:
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", COL_SHADOW)
	l.add_theme_constant_override("outline_size", 4)


# Uppercase section header with underline rule — for grouping controls / cards.
static func make_section_header(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.process_mode = Node.PROCESS_MODE_ALWAYS
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 4)
	v.add_child(pad)
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", SECTION_FONT)
	lbl.add_theme_color_override("font_color", COL_ACCENT)
	lbl.add_theme_color_override("font_outline_color", COL_SHADOW)
	lbl.add_theme_constant_override("outline_size", 3)
	# Light letter-spacing tracking would be ideal, but Godot 4 fonts don't
	# expose it uniformly — the outline + uppercase gives us enough weight.
	v.add_child(lbl)
	var rule := ColorRect.new()
	rule.color = COL_ACCENT_DIM
	rule.custom_minimum_size = Vector2(0, 1)
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


# ── LineEdit / OptionButton skins ──────────────────────

static func style_lineedit(le: LineEdit) -> void:
	var norm := StyleBoxFlat.new()
	norm.bg_color = Color(0.07, 0.08, 0.10, 0.98)
	norm.border_color = COL_BORDER
	norm.border_width_left = 1
	norm.border_width_right = 1
	norm.border_width_top = 1
	norm.border_width_bottom = 1
	norm.corner_radius_top_left = RADIUS
	norm.corner_radius_top_right = RADIUS
	norm.corner_radius_bottom_left = RADIUS
	norm.corner_radius_bottom_right = RADIUS
	norm.content_margin_left = 10
	norm.content_margin_right = 10
	norm.content_margin_top = 6
	norm.content_margin_bottom = 6
	le.add_theme_stylebox_override("normal", norm)
	var focus := norm.duplicate()
	focus.border_color = COL_ACCENT
	focus.border_width_left = 2
	focus.border_width_right = 2
	focus.border_width_top = 2
	focus.border_width_bottom = 2
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_color_override("font_color", COL_TEXT)
	le.add_theme_color_override("font_placeholder_color", COL_TEXT_MUTED)
	le.add_theme_color_override("caret_color", COL_ACCENT_HI)
	le.add_theme_font_size_override("font_size", 16)


static func style_option_button(o: OptionButton) -> void:
	# OptionButton reuses Button styleboxes internally, so pull the shared skin.
	o.add_theme_stylebox_override("normal", _btn_normal_style())
	o.add_theme_stylebox_override("hover", _btn_hover_style())
	o.add_theme_stylebox_override("pressed", _btn_pressed_style())
	o.add_theme_stylebox_override("focus", _btn_focus_style())
	o.add_theme_stylebox_override("disabled", _btn_disabled_style())
	o.add_theme_font_size_override("font_size", 16)
	o.add_theme_color_override("font_color", COL_TEXT)
	o.add_theme_color_override("font_hover_color", COL_ACCENT_HI)
	o.add_theme_color_override("font_pressed_color", COL_ACCENT_HI)
	o.add_theme_color_override("font_focus_color", COL_ACCENT_HI)


static func style_checkbox(cb: BaseButton) -> void:
	# CheckBox and CheckButton share the "font_*" theme keys we care about.
	cb.add_theme_font_size_override("font_size", 15)
	cb.add_theme_color_override("font_color", COL_TEXT)
	cb.add_theme_color_override("font_hover_color", COL_ACCENT_HI)
	cb.add_theme_color_override("font_pressed_color", COL_ACCENT_HI)
	cb.add_theme_color_override("font_focus_color", COL_ACCENT_HI)


static func style_slider(_s: HSlider) -> void:
	# Godot's default HSlider skin already reads fine on our dark palette;
	# we don't rebuild the grabber texture (no reliable asset to swap in).
	# Left in as a hook so consumers can call it uniformly.
	pass


# ── Backdrops ─────────────────────────────────────────

# Full-viewport dark backdrop with a subtle diagonal stripe overlay + amber
# accent frame at top/bottom. Used by the main menu.
static func build_menu_backdrop(root: Control) -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Horizontal darkening band at the very top so the title reads on any
	# accidental bright content behind it, plus an amber pin-stripe.
	var top_band := ColorRect.new()
	top_band.color = Color(0.02, 0.03, 0.05, 0.85)
	top_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_band.offset_bottom = 220
	top_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_band)

	var top_rule := ColorRect.new()
	top_rule.color = COL_ACCENT
	top_rule.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_rule.offset_top = 218
	top_rule.offset_bottom = 220
	top_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_rule)

	# Matching bottom band + amber rule for the footer.
	var bot_band := ColorRect.new()
	bot_band.color = Color(0.02, 0.03, 0.05, 0.85)
	bot_band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_band.offset_top = -60
	bot_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bot_band)

	var bot_rule := ColorRect.new()
	bot_rule.color = COL_ACCENT
	bot_rule.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_rule.offset_top = -62
	bot_rule.offset_bottom = -60
	bot_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bot_rule)


# Framed panel container for sub-screens (Host/Join/Stats/etc.). Wraps a VBox
# in a PanelContainer with the shared panel style + amber-underlined header.
static func wrap_panel(inner: Control, title: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", panel_style())
	pc.set_anchors_preset(Control.PRESET_CENTER, true)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pc.add_child(col)
	var head := make_screen_title(title)
	col.add_child(head)
	var rule := ColorRect.new()
	rule.color = COL_ACCENT_DIM
	rule.custom_minimum_size = Vector2(0, 1)
	col.add_child(rule)
	col.add_child(inner)
	return pc
