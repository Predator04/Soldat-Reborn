extends PanelContainer
## Vote prompt (#77) — centered near the top-third of the screen so it doesn't
## eat the crosshair. Semi-opaque background so the tally reads over any map.
## The HUD calls refresh(main) every frame; it mirrors main.vote_* (host
## authoritative, replicated to clients).

var lbl_vote_title: Label
var lbl_vote_tally: Label
var lbl_vote_timer: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_top = 250
	offset_bottom = 240
	offset_left = -260
	offset_right = 260
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vote_bg := StyleBoxFlat.new()
	vote_bg.bg_color = Color(0.05, 0.05, 0.09, 0.85)
	vote_bg.border_color = Color(0.95, 0.82, 0.4, 0.9)
	vote_bg.border_width_left = 2
	vote_bg.border_width_right = 2
	vote_bg.border_width_top = 2
	vote_bg.border_width_bottom = 2
	vote_bg.corner_radius_top_left = 6
	vote_bg.corner_radius_top_right = 6
	vote_bg.corner_radius_bottom_left = 6
	vote_bg.corner_radius_bottom_right = 6
	vote_bg.content_margin_left = 14
	vote_bg.content_margin_right = 14
	vote_bg.content_margin_top = 8
	vote_bg.content_margin_bottom = 8
	add_theme_stylebox_override("panel", vote_bg)
	visible = false
	var vote_col := VBoxContainer.new()
	vote_col.add_theme_constant_override("separation", 4)
	add_child(vote_col)
	lbl_vote_title = Label.new()
	lbl_vote_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_vote_title.add_theme_font_size_override("font_size", 18)
	lbl_vote_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	lbl_vote_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_vote_title.add_theme_constant_override("outline_size", 3)
	vote_col.add_child(lbl_vote_title)
	lbl_vote_tally = Label.new()
	lbl_vote_tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_vote_tally.add_theme_font_size_override("font_size", 16)
	lbl_vote_tally.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	lbl_vote_tally.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl_vote_tally.add_theme_constant_override("outline_size", 3)
	vote_col.add_child(lbl_vote_tally)
	lbl_vote_timer = Label.new()
	lbl_vote_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_vote_timer.add_theme_font_size_override("font_size", 13)
	lbl_vote_timer.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	vote_col.add_child(lbl_vote_timer)


func refresh(main: Node) -> void:
	if main == null or main.get("vote_active") == null:
		visible = false
		return
	var active: bool = bool(main.get("vote_active"))
	if not active:
		visible = false
		return
	var kind: String = str(main.get("vote_kind"))
	var target: String = str(main.get("vote_target_str"))
	var yes_ct: int = int(main.get("vote_yes"))
	var no_ct: int = int(main.get("vote_no"))
	var tl: float = float(main.get("vote_time_left"))
	var starter: String = str(main.get("vote_starter"))
	var verb: String = tr("change map to") if kind == "votemap" else tr("kick")
	lbl_vote_title.text = tr("Vote (%s): %s %s?") % [starter, verb, target]
	lbl_vote_tally.text = tr("[F1] Yes %d    ·    [F2] No %d") % [yes_ct, no_ct]
	if not Input.get_connected_joypads().is_empty():
		lbl_vote_tally.text += "   (" + tr("pad: R3 = yes") + ")"
	lbl_vote_timer.text = "%ds" % int(ceil(tl))
	visible = true
