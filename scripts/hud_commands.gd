extends LineEdit
## The HUD's typed line: "/" opens it for commands and gestures, T for global
## chat, Y for team chat. Submitting runs vote commands (#77), host commands
## (#257), gestures, or sends the chat line. Hidden until opened; the local
## player's input is locked while it's up.

var hud: Node = null            # the HUD (CanvasLayer); its parent is Main
var is_open := false
var _line_mode := "cmd"  # "cmd" | "global" | "team"


func _init() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 12
	offset_right = -12
	offset_top = -110
	offset_bottom = -80
	placeholder_text = "/votemap N   /votekick name   /addbot   /kick name   /gamemode N   /map name   /restart   /say   /ff   /victory  /kill"
	custom_minimum_size = Vector2(0, 28)
	visible = false
	text_submitted.connect(_on_command_submitted)
	gui_input.connect(_on_command_gui_input)


func _player() -> Node2D:
	return hud.player if hud != null else null


func _main() -> Node:
	return hud.get_parent() if hud != null else null


func _post(author: String, msg: String) -> void:
	hud.post_chat(author, msg, false)


func open_command(prefill: String = "/") -> void:
	_open_line("cmd", prefill, "/votemap N   /addbot   /kick name   /gamemode N   /map name   /restart   /say   /ff   /victory  /kill")


func open_chat(scope: String) -> void:
	if scope == "team":
		_open_line("team", "", "[TEAM] Y — say to your team")
	else:
		_open_line("global", "", "[GLOBAL] T — say to everyone")


func _open_line(mode: String, prefill: String, placeholder: String) -> void:
	var player := _player()
	if not is_instance_valid(player) or bool(player.get("dead")):
		return
	if is_open:
		return
	is_open = true
	_line_mode = mode
	text = prefill
	placeholder_text = placeholder
	visible = true
	grab_focus()
	caret_column = text.length()
	player.set("input_locked", true)


func close_command() -> void:
	is_open = false
	visible = false
	text = ""
	release_focus()
	var player := _player()
	if is_instance_valid(player):
		player.set("input_locked", false)


func _on_command_submitted(submitted: String) -> void:
	var t := submitted.strip_edges()
	var player := _player()
	if is_instance_valid(player) and t != "":
		if _line_mode == "cmd" and t.begins_with("/") and (try_vote_command(t) or try_host_command(t)):
			close_command()
			return
		if _line_mode == "cmd":
			if t.begins_with("/") and player.has_method("apply_gesture"):
				player.apply_gesture(t)
			elif player.has_method("send_chat"):
				player.send_chat("global", t)
		elif _line_mode == "team" and player.has_method("send_chat"):
			player.send_chat("team", t)
		elif player.has_method("send_chat"):
			player.send_chat("global", t)
	close_command()


func _on_command_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_command()


# Vote chat commands (#77): /votemap <n|name>, /votekick <peer|name>,
# /votecancel (host only). Returns true if the text was a vote command so the
# caller skips the gesture / chat path.
func try_vote_command(raw: String) -> bool:
	var lower := raw.to_lower()
	var main := _main()
	if main == null:
		return false
	if lower == "/votemap" or lower.begins_with("/votemap "):
		var arg := raw.substr("/votemap".length()).strip_edges()
		if arg == "":
			_post("VOTE", "Usage: /votemap <index-or-name>")
			return true
		if main.has_method("request_vote"):
			main.request_vote("votemap", arg)
		return true
	if lower == "/votekick" or lower.begins_with("/votekick "):
		var arg := raw.substr("/votekick".length()).strip_edges()
		if arg == "":
			_post("VOTE", "Usage: /votekick <peer-id-or-name>")
			return true
		if main.has_method("request_vote"):
			main.request_vote("votekick", arg)
		return true
	if lower == "/votecancel":
		if main.has_method("cancel_vote"):
			main.cancel_vote()
		return true
	return false


# Host chat commands (#257) — the classic Soldat server set. Host / SP only.
# Returns true when the text was one of ours (the caller skips chat/gestures).
func try_host_command(raw: String) -> bool:
	var main := _main()
	if main == null or not main.has_method("host_addbot"):
		return false
	var parts := raw.split(" ", false)
	var cmd := parts[0].to_lower()
	var body := raw.substr(parts[0].length()).strip_edges()
	var cmds := ["/addbot", "/kick", "/bots", "/gamemode", "/map", "/restart", "/say", "/ff"]
	var hit := false
	for c in cmds:
		if cmd == c:
			hit = true
			break
	if not hit:
		return false
	if Net.is_networked() and not Net.is_host():
		_post("HOST", "That command is host only.")
		return true
	match cmd:
		"/addbot":
			var skill := 0
			var bot_name := body
			if body != "" and body.split(" ")[0].is_valid_int():
				skill = int(body.split(" ")[0])
				bot_name = body.substr(body.split(" ")[0].length()).strip_edges()
			if skill != 0 and (skill < 1 or skill > 5):
				_post("HOST", "Usage: /addbot [skill 1-5] [name]")
				return true
			main.host_addbot(skill, bot_name)
			_post("HOST", "Bot added." + (" %s" % bot_name if bot_name != "" else ""))
		"/bots":
			if body.is_valid_int():
				main.host_set_bots(int(body))
			else:
				_post("HOST", "Usage: /bots <count>")
		"/kick":
			if body == "":
				_post("HOST", "Usage: /kick <name>")
			elif not main.host_kick(body):
				_post("HOST", "No player or bot named \"%s\"." % body)
		"/gamemode":
			var mi := resolve_mode_arg(body)
			if mi < 0:
				_post("HOST", "Usage: /gamemode <0-9 or name>")
			else:
				main.host_restart_to(int(Settings.map_index), mi)
		"/map":
			var mp := resolve_map_arg(body)
			if mp < 0:
				_post("HOST", "Usage: /map <name or index>")
			else:
				main.host_restart_to(mp, int(Settings.game_mode))
		"/restart":
			main.host_restart_to(int(Settings.map_index), int(Settings.game_mode))
		"/say":
			if body == "":
				_post("HOST", "Usage: /say <message>")
			else:
				main.host_say(body)
		"/ff":
			main.host_toggle_ff()
	return true


func resolve_mode_arg(a: String) -> int:
	if a.is_valid_int():
		return clampi(int(a), 0, Net.MODE_NAMES.size() - 1)
	var la := a.to_lower()
	for i in Net.MODE_NAMES.size():
		if str(Net.MODE_NAMES[i]).to_lower().begins_with(la):
			return i
	return -1


func resolve_map_arg(a: String) -> int:
	if a.is_valid_int():
		return clampi(int(a), 0, Net.MAP_NAMES.size() - 1)
	var la := a.to_lower()
	for i in Net.MAP_NAMES.size():
		if str(Net.MAP_NAMES[i]).to_lower().begins_with(la):
			return i
	return -1
