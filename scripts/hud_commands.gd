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


# Host chat commands (#257) — the classic Soldat server set. On the host / SP
# they run here (match_votes.run_host_command); a client sends them to the
# server (#317: a dedicated server's admins — server.cfg `admins` or
# /login <password> — may use them; /myid shows the id for `admins`).
# Returns true when the text was one of ours (the caller skips chat/gestures).
func try_host_command(raw: String) -> bool:
	var main := _main()
	if main == null or not main.has_method("host_addbot"):
		return false
	var parts := raw.split(" ", false)
	var cmd := parts[0].to_lower()
	var body := raw.substr(parts[0].length()).strip_edges()
	var remote_only := ["/login", "/myid"]
	if not (cmd in main._votes.HOST_COMMANDS or cmd in remote_only):
		return false
	if Net.is_networked() and not Net.is_host():
		main.rpc_id(1, "net_admin_cmd", raw)
		return true
	if cmd == "/myid":
		_post("HOST", "Your player id: %s" % Settings.profile_id.to_lower().sha256_text())
		return true
	if cmd == "/login":
		_post("HOST", "You are the host here.")
		return true
	var reply: String = main._votes.run_host_command(cmd, body)
	if reply != "":
		_post("HOST", reply)
	return true


static func resolve_mode_arg(a: String) -> int:
	if a.is_valid_int():
		return clampi(int(a), 0, Net.MODE_NAMES.size() - 1)
	var la := a.to_lower()
	for i in Net.MODE_NAMES.size():
		if str(Net.MODE_NAMES[i]).to_lower().begins_with(la):
			return i
	return -1


static func resolve_map_arg(a: String) -> int:
	if a.is_valid_int():
		return clampi(int(a), 0, Net.MAP_NAMES.size() - 1)
	var la := a.to_lower()
	for i in Net.MAP_NAMES.size():
		if str(Net.MAP_NAMES[i]).to_lower().begins_with(la):
			return i
	return -1
