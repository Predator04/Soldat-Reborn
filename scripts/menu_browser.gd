extends Node
## The main menu's server browser (#258 batch 1, split out of menu.gd): the
## BROWSE SERVERS screen (local network via LAN beacons, recently joined games,
## the master server list with live pings from each server's query reply),
## QUICK JOIN / Quick Play (best open game by ping, players and skill gap,
## #33 skill matchmaking; bot-match fallback), and joining a picked row.
##
## Screen state the menu or tests read (_browse_root, _master_rows, my_skill, ...)
## stays on menu.gd; this helper reaches it through `menu`.

const Menu = preload("res://scripts/menu.gd")
const UITheme = preload("res://scripts/ui_theme.gd")

var menu: Menu

var _lan_list: VBoxContainer
var _lan_t := 0.0
var _lan_listening := false
var _lan_sig := ""
var _browse_panel: VBoxContainer
var _browse_list: VBoxContainer
var _browse_http: HTTPRequest
var _recent_list: VBoxContainer
var _recent_sig := ""
var _master_sig := ""
var _ping_t := 0.0
var _qj_active := false
var _qj_t := 0.0
var _skill_http: HTTPRequest = null
var _qp_fallback := false   # Quick Play (main menu): fall back to bots


## LAN games, pings and a pending Quick Join refresh live while the Browse
## screen is open; leaving it stops the LAN listener.
func _tick_browse(_delta: float) -> void:
	if menu._browse_root != null and menu._browse_root.visible:
		_lan_t -= _delta
		if _lan_t <= 0.0:
			_lan_t = 0.5
			_refresh_lan()
		_ping_t -= _delta
		if _ping_t <= 0.0:
			_ping_t = 1.0
			var targets: Array = []
			for d in (Net.lan_poll() if _lan_listening else []):
				targets.append([str(d.get("ip")), int(d.get("port"))])
			for d in menu._master_rows:
				targets.append([str(d.get("ip")), int(d.get("port"))])
			for d in _recent_rows():
				targets.append([str(d.get("ip")), int(d.get("port"))])
			Net.query_send(targets)
			_render_master()
			_render_recent()
		if _qj_active:
			_qj_t -= _delta
			if _qj_t <= 0.0:
				_quick_join_pick()
	elif _lan_listening:
		Net.lan_listen_stop()
		_lan_listening = false


func _refresh_lan() -> void:
	if _lan_list == null:
		return
	if not _lan_listening:
		_lan_listening = Net.lan_listen_start()
	var found: Array = Net.lan_poll() if _lan_listening else []
	var sig := str(found.map(func(d): return [d.get("ip"), d.get("port"), d.get("players"), d.get("map"), d.get("mode"), _ping_bucket(str(d.get("ip")), int(d.get("port")))]))
	if sig == _lan_sig and _lan_list.get_child_count() > 0:
		return
	_lan_sig = sig
	for c in _lan_list.get_children():
		c.queue_free()
	if found.is_empty():
		var l := Label.new()
		l.text = "Looking for games on your network..." if _lan_listening else "Can't listen for LAN games (port %d busy)." % Net.LAN_PORT
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
		_lan_list.add_child(l)
		return
	for d in found:
		_lan_list.add_child(_server_row(d))


func _build_browse() -> void:
	_browse_http = HTTPRequest.new()
	_browse_http.request_completed.connect(_on_browse_http_done)
	menu.add_child(_browse_http)

	menu._browse_root = PanelContainer.new()
	menu._browse_root.add_theme_stylebox_override("panel", UITheme.panel_style())
	menu._browse_root.set_anchors_preset(Control.PRESET_CENTER, true)
	menu._browse_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu._browse_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu._browse_root.visible = false
	menu.add_child(menu._browse_root)

	_browse_panel = VBoxContainer.new()
	_browse_panel.add_theme_constant_override("separation", 8)
	_browse_panel.custom_minimum_size = Vector2(600, 0)
	menu._browse_root.add_child(_browse_panel)

	_browse_panel.add_child(UITheme.make_screen_title("BROWSE SERVERS"))
	_browse_panel.add_child(UITheme.make_section_header("Local Network"))
	_lan_list = VBoxContainer.new()
	_lan_list.add_theme_constant_override("separation", 4)
	_browse_panel.add_child(_lan_list)
	_browse_panel.add_child(UITheme.make_section_header("Recent"))
	_recent_list = VBoxContainer.new()
	_recent_list.add_theme_constant_override("separation", 4)
	_browse_panel.add_child(_recent_list)
	_browse_panel.add_child(UITheme.make_section_header("Master Server"))

	_browse_list = VBoxContainer.new()
	_browse_list.add_theme_constant_override("separation", 4)
	_browse_panel.add_child(_browse_list)

	_browse_panel.add_child(UITheme.spacer(4))
	var hint := Label.new()
	hint.text = "Grey rows are full or a different version.  \"— ms\": no ping reply (internet hosts forward UDP port+1 too)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
	_browse_panel.add_child(hint)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	var refresh := menu._make_button("REFRESH")
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.pressed.connect(menu._refresh_browse)
	brow.add_child(refresh)
	var qj := menu._make_button("QUICK JOIN", true)
	qj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qj.pressed.connect(_quick_join)
	brow.add_child(qj)
	_browse_panel.add_child(brow)

	var back := menu._make_button("BACK")
	back.pressed.connect(func() -> void:
		_qj_active = false
		menu._browse_root.visible = false
		menu._join_root.visible = true)
	_browse_panel.add_child(back)


func _on_browse_pressed() -> void:
	Settings.master_url = menu._master_edit.text.strip_edges()
	Settings.save()
	menu._join_root.visible = false
	menu._browse_root.visible = true
	_refresh_browse()


func _refresh_browse() -> void:
	menu._master_rows.clear()
	_master_sig = ""
	_recent_sig = ""
	_render_recent()
	for c in _browse_list.get_children():
		c.queue_free()
	var wait := Label.new()
	wait.text = "Fetching server list..."
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait.add_theme_font_size_override("font_size", 15)
	wait.add_theme_color_override("font_color", UITheme.COL_INFO)
	_browse_list.add_child(wait)
	var url: String = Settings.master_url
	_lan_t = 0.0
	_lan_sig = ""
	if url == "":
		wait.text = "No master server set (Join screen) — LAN games show above."
		wait.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
		return
	if _browse_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_browse_http.cancel_request()
	_browse_http.request(url.rstrip("/") + "/list")


func _on_browse_http_done(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not is_instance_valid(_browse_list) or not menu._browse_root.visible:
		return
	for c in _browse_list.get_children():
		c.queue_free()
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null or not (parsed is Dictionary) or not parsed.has("servers"):
		var err := Label.new()
		err.text = "No response from master server."
		err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err.add_theme_font_size_override("font_size", 15)
		err.add_theme_color_override("font_color", UITheme.COL_ALERT)
		_browse_list.add_child(err)
		return
	if not (parsed.get("servers", []) is Array):
		var err2 := Label.new()
		err2.text = "Malformed master server response."
		err2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err2.add_theme_font_size_override("font_size", 15)
		err2.add_theme_color_override("font_color", UITheme.COL_ALERT)
		_browse_list.add_child(err2)
		return
	var servers: Array = parsed["servers"]
	menu._master_rows.clear()
	for sv in servers:
		if sv is Dictionary:
			var row: Dictionary = (sv as Dictionary).duplicate()
			row["v"] = str(sv.get("version", sv.get("v", "")))
			menu._master_rows.append(row)
	_master_sig = ""
	_ping_t = 0.0
	if servers.is_empty():
		var empty := Label.new()
		empty.text = "No servers online."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", UITheme.COL_INFO)
		_browse_list.add_child(empty)
		return
	_render_master()


func _recent_rows() -> Array:
	var out: Array = []
	for k in Settings.recent_servers:
		var parts := str(k).rsplit(":", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			out.append({"ip": parts[0], "port": int(parts[1]), "name": str(k), "map": "?", "mode": "?", "players": 0, "max": 0, "v": ""})
	return out


# Games you joined before, with a live ping when they're up.
func _render_recent() -> void:
	if _recent_list == null:
		return
	var rows := _recent_rows()
	var sig := str(rows.map(func(d): return [d.get("ip"), d.get("port"), _ping_bucket(str(d.get("ip")), int(d.get("port"))), str(_live(d).get("players"))]))
	if sig == _recent_sig and _recent_list.get_child_count() > 0:
		return
	_recent_sig = sig
	for c in _recent_list.get_children():
		c.queue_free()
	if rows.is_empty():
		var l := Label.new()
		l.text = "Games you join show up here."
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", UITheme.COL_TEXT_DIM)
		_recent_list.add_child(l)
		return
	for d in rows:
		var up := Net.ping_of(str(d.get("ip")), int(d.get("port"))) >= 0
		var b := _server_row(d)
		if not up:
			b.text = "  %s   — offline or not answering   " % str(d.get("name"))
			b.disabled = false   # still let people try (hosts behind a firewall don't answer pings)
		_recent_list.add_child(b)


func _ping_bucket(ip: String, port: int) -> int:
	var p := Net.ping_of(ip, port)
	return -1 if p < 0 else p / 10


# Live numbers from the server's own query reply win over the (up to 30 s old)
# master listing / LAN beacon.
func _live(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	var info := Net.query_info(str(d.get("ip")), int(d.get("port")))
	if not info.is_empty() and Net.ping_of(str(d.get("ip")), int(d.get("port"))) >= 0:
		for k in ["players", "max", "map", "mode", "v", "name"]:
			if info.has(k):
				out[k] = info[k]
	return out


func _row_ok(d: Dictionary) -> bool:
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	var v := str(d.get("v", ""))
	var full: bool = int(d.get("max", 0)) > 0 and int(d.get("players", 0)) >= int(d.get("max", 0))
	return (v == "" or v == mine) and not full and not bool(d.get("password", false))


func _server_row(d0: Dictionary) -> Button:
	var d := _live(d0)
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	var ver := str(d.get("v", ""))
	var ping := Net.ping_of(str(d.get("ip")), int(d.get("port")))
	var full: bool = int(d.get("max", 0)) > 0 and int(d.get("players", 0)) >= int(d.get("max", 0))
	var note := ""
	if ver != "" and ver != mine:
		note = "   (v%s)" % ver
	elif full:
		note = "   FULL"
	elif bool(d.get("password", false)):
		note = "   (locked)"
	elif menu.my_skill >= 0 and d.get("skill", null) != null and menu.skill_penalty(menu.my_skill, d.get("skill")) < 45.0:
		note = "   " + menu.tr("your level")
	var btn := Button.new()
	btn.text = "  %s   [%d/%d]   %s · %s   %s%s" % [str(d.get("name", "?")), int(d.get("players", 0)), int(d.get("max", 0)),
			str(d.get("map", "?")), str(d.get("mode", "?")), ("%d ms" % ping) if ping >= 0 else "— ms", note]
	btn.tooltip_text = "%s:%d" % [str(d.get("ip")), int(d.get("port"))]
	btn.custom_minimum_size = Vector2(580, 40)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.style_button(btn, 15, false)
	# Data rows read better in the body face than in the condensed caps (#272).
	btn.add_theme_font_override("font", UITheme.font("semi"))
	if UITheme.is_touch():
		btn.custom_minimum_size.y = 48
	btn.disabled = not _row_ok(d)   # the host would refuse a different build / no room
	var relay := str(d.get("relay", ""))
	if relay != "":
		btn.text = btn.text.replace("— ms", "RELAY")
		btn.tooltip_text = "Joins through the relay with code %s" % relay
		btn.pressed.connect(_join_server.bind(relay, 0))
	else:
		btn.pressed.connect(_join_server.bind(str(d.get("ip")), int(d.get("port"))))
	if ping >= 0 and not btn.disabled:
		btn.add_theme_color_override("font_color", Color(0.55, 0.95, 0.5) if ping < 80 else (Color(0.95, 0.85, 0.4) if ping < 160 else Color(0.95, 0.45, 0.35)))
	return btn


func _render_master() -> void:
	if _browse_list == null or menu._master_rows.is_empty():
		return
	var rows: Array = menu._master_rows.map(func(d): return _live(d))
	var sig := str(rows.map(func(d): return [d.get("ip"), d.get("port"), d.get("players"), d.get("map"), _ping_bucket(str(d.get("ip")), int(d.get("port")))]))
	if sig == _master_sig:
		return
	_master_sig = sig
	for c in _browse_list.get_children():
		c.queue_free()
	# Joinable first, then busiest, then lowest ping.
	var order: Array = menu._master_rows.duplicate()
	order.sort_custom(func(a, b) -> bool:
		var la := _live(a)
		var lb := _live(b)
		if _row_ok(la) != _row_ok(lb):
			return _row_ok(la)
		if int(la.get("players", 0)) != int(lb.get("players", 0)):
			return int(la.get("players", 0)) > int(lb.get("players", 0))
		var pa := Net.ping_of(str(a.get("ip")), int(a.get("port")))
		var pb := Net.ping_of(str(b.get("ip")), int(b.get("port")))
		return (pa if pa >= 0 else 9999) < (pb if pb >= 0 else 9999))
	for d in order:
		_browse_list.add_child(_server_row(d))


# QUICK JOIN: listen / fetch for a moment, then join the best open game.
func _quick_join(bot_fallback := false) -> void:
	menu._browse_root.visible = true
	_refresh_browse()
	_fetch_my_skill()
	_qj_active = true
	_qj_t = 3.5
	_qp_fallback = bot_fallback
	menu._status_label.text = menu.tr("Quick play: looking for a game...")


func _quick_join_pick() -> void:
	_qj_active = false
	var cands: Array = []
	for d in (Net.lan_poll() if _lan_listening else []):
		cands.append(d)
	for d in menu._master_rows:
		cands.append(d)
	var best = null
	var best_score := INF
	for d0 in cands:
		var d := _live(d0)
		if not _row_ok(d):
			continue
		var score := qp_score(d)
		if score < best_score:
			best_score = score
			best = d
	if best == null:
		if _qp_fallback:
			_qp_bot_match()
			return
		menu._status_label.text = "No open games found. Host one with HOST GAME, or try again."
		return
	menu._status_label.text = menu.tr("Quick play: joining %s") % str(best.get("name", "?"))
	menu._qp_joining = _qp_fallback
	if str(best.get("relay", "")) != "":
		_join_server(str(best.get("relay")), 0)
	else:
		_join_server(str(best.get("ip")), int(best.get("port")))


## Quick play: lower is better. Ping, people over empty, then skill gap.
func qp_score(d: Dictionary) -> float:
	var ping := Net.ping_of(str(d.get("ip")), int(d.get("port")))
	var score: float = (float(ping) if ping >= 0 else 400.0)
	if int(d.get("players", 0)) > 0:
		score -= 150.0   # a game with people in it beats an empty one
	return score + menu.skill_penalty(menu.my_skill, d.get("skill", null))


func _fetch_my_skill() -> void:
	var url: String = Settings.master_url.strip_edges().trim_suffix("/")
	if url == "":
		return
	if _skill_http == null:
		_skill_http = HTTPRequest.new()
		_skill_http.timeout = 3.0
		menu.add_child(_skill_http)
		_skill_http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			if code != 200:
				return
			var d = JSON.parse_string(body.get_string_from_utf8())
			if d is Dictionary and d.has("skill"):
				menu.my_skill = int(d["skill"]))
	_skill_http.cancel_request()
	_skill_http.request(url + "/profile?id=" + Settings.profile_hash())


# Nobody online (or the join failed): play a bot match right away instead of
# leaving the player on an empty server list.
func _qp_bot_match() -> void:
	_qp_fallback = false
	menu._qp_joining = false
	if menu._browse_root != null:
		menu._browse_root.visible = false
	if menu._join_root != null:
		menu._join_root.visible = false
	menu._status_label.text = menu.tr("Nobody online right now - starting a bot match.")
	Net.set_singleplayer()
	menu._go_to_match()


func _join_server(ip: String, port: int) -> void:
	menu._ip_edit.text = ip
	menu._port_edit.text = str(port)
	menu._browse_root.visible = false
	menu._join_root.visible = true
	menu._on_connect_pressed()
