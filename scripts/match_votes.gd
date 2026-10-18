extends Node
## Main's player votes and host controls (#258 split of main.gd):
## /votemap + /votekick (#77), the end-of-round next-map vote, and the host
## chat commands (#257: /addbot /kick /bots /gamemode /map /restart /say /ff).
##
## Host-authoritative: any player calls a vote, F1/F2 cast, majority passes;
## the tally is broadcast alongside match state. The @rpc entry points stay on
## Main (same node path + name); the vote_* fields the HUD reads stay on Main.

const Main = preload("res://scripts/main.gd")

var main: Main

var _nm_votes: Dictionary = {}       # voter peer id (1 = host / SP) -> choice
# ── Vote system (#77) ─────────────────────────────────
# Host-authoritative: any player calls /votemap or /votekick, F1/F2 to cast,
# majority passes. Broadcast alongside match state at MATCH_SYNC_HZ.
const VOTE_DURATION := 30.0
const VOTE_COOLDOWN := 30.0
var _vote_voters: Dictionary = {}  # host-only: peer_id → true (already voted)
var _vote_cooldown := 0.0          # host-only: gate between votes


func _tick_vote(delta: float) -> void:
	if main.vote_active:
		main.vote_time_left = maxf(0.0, main.vote_time_left - delta)
	# Only host owns cooldown + resolution.
	if Net.is_networked() and not Net.is_host():
		return
	if main.vote_active and main.vote_time_left <= 0.0:
		_resolve_vote(main.vote_yes * 2 > _eligible_voters())
	if not main.vote_active:
		_vote_cooldown = maxf(0.0, _vote_cooldown - delta)


## /addbot [skill 1-5] [name] — one more bot, optionally skilled and named.
func host_addbot(skill: int, bot_name: String) -> void:
	if Net.is_networked() and not Net.is_host():
		return
	if skill > 0:
		Settings.bot_skill = clampi(skill, 1, 5)
	# Remember who exists so the new arrival can be picked out afterwards —
	# _bots_by_id is only populated in MP, and _live_bots() order is spawn order.
	var before: Dictionary = {}
	for b in main._live_bots():
		before[b.get_instance_id()] = true
	Settings.bot_count = clampi(Settings.bot_count + 1, 0, 32)
	main._reconcile_bots()
	if bot_name != "":
		for b in main._live_bots():
			if not before.has(b.get_instance_id()):
				b.set("display_name", bot_name.left(24))
				break
	Settings.save()
	MatchConfig.host_broadcast()


## /bots <n> — set the bot count live.
func host_set_bots(n: int) -> void:
	if Net.is_networked() and not Net.is_host():
		return
	Settings.bot_count = clampi(n, 0, 32)
	main._reconcile_bots()
	Settings.save()
	MatchConfig.host_broadcast()


## /kick <name> — disconnect a peer or remove a bot (case-insensitive,
## unique-prefix match). Returns false when nobody matched.
func host_kick(name: String) -> bool:
	if name == "":
		return false
	var want := name.to_lower()
	if Net.is_networked() and Net.is_host():
		for pid in main._peer_names.keys():
			if str(main._peer_names[pid]).to_lower().begins_with(want):
				if main.multiplayer.multiplayer_peer != null:
					main.multiplayer.multiplayer_peer.disconnect_peer(int(pid))
				return true
	for b in main._live_bots():
		if str(b.get("display_name")).to_lower().begins_with(want):
			# Keep the configured count in step so reconcile doesn't respawn it.
			Settings.bot_count = maxi(0, Settings.bot_count - 1)
			main._bots._despawn_bot(b)
			Settings.save()
			MatchConfig.host_broadcast()
			return true
	return false


## /restart, /map <name|index>, /gamemode <n|name> — full match restart onto
## the given map + mode, on every peer.
func host_restart_to(map_idx: int, mode_idx: int) -> void:
	if Net.is_networked():
		if not Net.is_host():
			return
		main.bcast("net_match_restart", [clampi(map_idx, 0, main.MAPS.size() - 1), clampi(mode_idx, 0, Net.MODE_NAMES.size() - 1)], true)
	else:
		main.net_match_restart(map_idx, mode_idx)


## /say <text> — host announcement in everyone's chat feed.
## Remove a client whose reported state kept failing the host's checks
## (trust_guard.gd). Announced in chat so the room knows what happened.
func trust_kick(peer_id: int, who: String) -> void:
	if not (Net.is_networked() and Net.is_host()) or main.multiplayer.multiplayer_peer == null:
		return
	if not main.multiplayer.get_peers().has(peer_id):
		return
	print("TRUST kick: %s (peer %d)" % [who, peer_id])
	host_say("%s was removed: their game kept reporting impossible state." % who)
	# Stop addressing them now (projectile / pickup streams use the ready list),
	# then drop the connection a moment later so the chat line goes out first.
	main._ready_peers.erase(peer_id)
	main._net._push_ready_list()
	main.get_tree().create_timer(0.25).timeout.connect(func() -> void:
		if main.multiplayer.multiplayer_peer != null and main.multiplayer.get_peers().has(peer_id):
			main.multiplayer.multiplayer_peer.disconnect_peer(peer_id))


func host_say(text: String) -> void:
	if text == "":
		return
	if Net.is_networked() and Net.is_host():
		main.bcast("net_chat", ["HOST", text.left(200), "global", -1], true)
	else:
		var hud := main.get_node_or_null("HUD")
		if hud != null and hud.has_method("post_chat"):
			hud.post_chat("HOST", text.left(200), false)


## /ff — flip friendly fire and tell everyone.
func host_toggle_ff() -> void:
	if Net.is_networked() and not Net.is_host():
		return
	MatchConfig.host_friendly_fire = not MatchConfig.host_friendly_fire
	MatchConfig.host_broadcast()
	var hud := main.get_node_or_null("HUD")
	if hud != null and hud.has_method("post_chat"):
		hud.post_chat("HOST", "Friendly fire is now %s." % ("ON" if MatchConfig.host_friendly_fire else "OFF"), false)


func request_vote(kind: String, arg: String) -> void:
	# Called from HUD when a player submits /votemap or /votekick.
	if Net.is_networked() and not Net.is_host():
		main.rpc_id(1, "net_vote_start", kind, arg)
	else:
		_host_start_vote(kind, arg, Net.local_id())


func cast_vote(is_yes: bool) -> void:
	if not main.vote_active:
		return
	if Net.is_networked() and not Net.is_host():
		main.rpc_id(1, "net_vote_cast", is_yes)
	else:
		_host_apply_vote(Net.local_id(), is_yes)


func cancel_vote() -> void:
	# Host-only power (SP owner too). Silently no-op for clients.
	if Net.is_networked() and not Net.is_host():
		return
	if not main.vote_active:
		return
	_resolve_vote(false, "Cancelled by host")


func _peer_display_name(peer_id: int) -> String:
	if main._players_by_id.has(peer_id):
		var p = main._players_by_id[peer_id]
		if is_instance_valid(p):
			return str(p.display_name)
	if peer_id == 1:
		return "Host"
	return "Peer %d" % peer_id


func _vote_chat(msg: String) -> void:
	if main.hud != null and main.hud.has_method("post_chat"):
		main.hud.post_chat("VOTE", msg, false)


func _resolve_map_name(idx: int) -> String:
	# Prefer the actual runtime rotation (procedural + bundled classics), fall
	# back to the shared game_lists.gd list (#251 — the host-admin copy is
	# that same list now).
	if idx >= 0 and idx < main.MAPS.size():
		return str(main.MAPS[idx].get("name", "Map %d" % idx))
	return "Map %d" % idx


func _resolve_vote_map_arg(arg: String) -> int:
	# Accepts an integer index OR a case-insensitive map name.
	var s := arg.strip_edges()
	if s == "":
		return -1
	if s.is_valid_int():
		var n := int(s)
		if n >= 0 and n < main.MAPS.size():
			return n
		return -1
	var needle := s.to_lower()
	for i in main.MAPS.size():
		if str(main.MAPS[i].get("name", "")).to_lower() == needle:
			return i
	return -1


func _resolve_vote_kick_arg(arg: String) -> int:
	# Accepts integer peer id or a case-insensitive display_name match (partial ok).
	var s := arg.strip_edges()
	if s == "":
		return 0
	if s.is_valid_int():
		var n := int(s)
		if main._players_by_id.has(n):
			return n
		return 0
	var needle := s.to_lower()
	for pid in main._players_by_id.keys():
		var p = main._players_by_id[pid]
		if not is_instance_valid(p):
			continue
		if str(p.display_name).to_lower() == needle:
			return int(pid)
	# Partial contains-match as a fallback (typing /votekick red matches "Red 3").
	for pid in main._players_by_id.keys():
		var p = main._players_by_id[pid]
		if not is_instance_valid(p):
			continue
		if str(p.display_name).to_lower().find(needle) >= 0:
			return int(pid)
	return 0


func _host_start_vote(kind: String, arg: String, starter_id: int) -> void:
	if main.vote_active:
		_vote_chat("A vote is already in progress.")
		return
	if _vote_cooldown > 0.0:
		_vote_chat("Vote cooldown: %ds left." % int(ceil(_vote_cooldown)))
		return
	var starter := _peer_display_name(starter_id)
	match kind:
		"votemap":
			var idx := _resolve_vote_map_arg(arg)
			if idx < 0:
				_vote_chat("%s: unknown map '%s'." % [starter, arg])
				return
			main.vote_kind = "votemap"
			main.vote_target_arg = idx
			main.vote_target_str = _resolve_map_name(idx)
		"votekick":
			if not Net.is_networked():
				_vote_chat("votekick only works in multiplayer.")
				return
			var pid := _resolve_vote_kick_arg(arg)
			if pid <= 0:
				_vote_chat("%s: unknown player '%s'." % [starter, arg])
				return
			if pid == starter_id:
				_vote_chat("You can't votekick yourself.")
				return
			main.vote_kind = "votekick"
			main.vote_target_arg = pid
			main.vote_target_str = _peer_display_name(pid)
		_:
			return
	main.vote_active = true
	main.vote_yes = 1  # starter's implicit yes vote
	main.vote_no = 0
	_vote_voters = {starter_id: true}
	main.vote_time_left = VOTE_DURATION
	main.vote_starter = starter
	_vote_chat("%s called a %s: %s   ([F1]/[F2] to vote)" % [starter, main.vote_kind, main.vote_target_str])
	if Net.is_networked() and Net.is_host():
		_broadcast_vote_state()


func _host_apply_vote(peer_id: int, is_yes: bool) -> void:
	if not main.vote_active:
		return
	if _vote_voters.has(peer_id):
		return  # already voted, no changing minds
	_vote_voters[peer_id] = true
	if is_yes:
		main.vote_yes += 1
	else:
		main.vote_no += 1
	# Resolve early once the outcome is certain.
	var eligible := _eligible_voters()
	if main.vote_yes * 2 > eligible:
		_resolve_vote(true)
		return
	if main.vote_no * 2 >= eligible:
		_resolve_vote(false)
		return
	if Net.is_networked() and Net.is_host():
		_broadcast_vote_state()


func _eligible_voters() -> int:
	# Majority of the humans in the match (a lone starter's own yes no longer
	# passes a kick/map vote by default). The kick target doesn't vote.
	if not Net.is_networked():
		return 1
	var n := main._ready_peers.size() + (0 if Net.is_dedicated else 1)
	if main.vote_kind == "votekick" and n > 1:
		n -= 1
	return maxi(1, n)


func _resolve_vote(passed: bool, reason: String = "") -> void:
	if not main.vote_active:
		return
	# Snapshot pre-clear so the summary + apply steps see the right values even
	# after the state reset below.
	var kind := main.vote_kind
	var target := main.vote_target_arg
	var target_label := main.vote_target_str
	var yes_ct := main.vote_yes
	var no_ct := main.vote_no
	var summary: String
	if reason != "":
		summary = reason
	else:
		summary = "PASSED (%d-%d)" % [yes_ct, no_ct] if passed else "FAILED (%d-%d)" % [yes_ct, no_ct]
	_vote_chat("%s %s — %s" % [kind, target_label, summary])
	# Broadcast end state so clients clear their prompt in sync.
	if Net.is_networked() and Net.is_host():
		main.bcast("net_vote_end", [kind, target_label, passed, yes_ct, no_ct, reason], false)
	# Clear locally BEFORE triggering restart/kick — scene reload otherwise fires
	# with stale vote_active still true on the next frame.
	main.vote_active = false
	main.vote_kind = ""
	main.vote_target_str = ""
	main.vote_target_arg = 0
	main.vote_yes = 0
	main.vote_no = 0
	main.vote_time_left = 0.0
	_vote_voters.clear()
	_vote_cooldown = VOTE_COOLDOWN
	if not passed:
		return
	match kind:
		"votemap":
			if Net.is_networked() and Net.is_host():
				main.bcast("net_match_restart", [target, Settings.game_mode], true)
			elif not Net.is_networked():
				Settings.map_index = target
				Settings.custom_map_path = ""
				Settings.save()
				main.call_deferred("_do_reload_main")
		"votekick":
			if Net.is_networked() and Net.is_host() and main.multiplayer.multiplayer_peer != null and target > 1:
				main.multiplayer.multiplayer_peer.disconnect_peer(target)


func _broadcast_vote_state() -> void:
	if not Net.is_host():
		return
	for pid in main._ready_peers.keys():
		main.rpc_id(int(pid), "net_vote_state", main.vote_active, main.vote_kind, main.vote_target_str, main.vote_yes, main.vote_no, main.vote_time_left, main.vote_starter)


func net_vote_start(kind: String, arg: String) -> void:
	if not Net.is_host():
		return
	_host_start_vote(kind, arg, main.multiplayer.get_remote_sender_id())


func net_vote_cast(is_yes: bool) -> void:
	if not Net.is_host():
		return
	_host_apply_vote(main.multiplayer.get_remote_sender_id(), is_yes)


func net_vote_state(active: bool, kind: String, target: String, yes_ct: int, no_ct: int, tl: float, starter: String) -> void:
	main.vote_active = active
	main.vote_kind = kind
	main.vote_target_str = target
	main.vote_yes = yes_ct
	main.vote_no = no_ct
	main.vote_time_left = tl
	main.vote_starter = starter


func net_vote_end(kind: String, target_label: String, passed: bool, yes_ct: int, no_ct: int, reason: String) -> void:
	var summary: String
	if reason != "":
		summary = reason
	else:
		summary = "PASSED (%d-%d)" % [yes_ct, no_ct] if passed else "FAILED (%d-%d)" % [yes_ct, no_ct]
	_vote_chat("%s %s — %s" % [kind, target_label, summary])
	main.vote_active = false
	main.vote_kind = ""
	main.vote_target_str = ""
	main.vote_yes = 0
	main.vote_no = 0
	main.vote_time_left = 0.0


func _pick_next_map_choices() -> void:
	main.next_map_choices = []
	main.next_map_tally = [0, 0, 0]
	_nm_votes.clear()
	main.my_next_map_vote = -1
	# Custom / editor maps (and Survival BR-style resets) keep playing the same map.
	if main.cur_map_index < 0 or Settings.custom_map_path != "" or Net.custom_map_json != "" or main.MAPS.size() < 4:
		return
	var cur: int = main.cur_map_index
	var pool: Array = []
	for i in main.MAPS.size():
		if i != cur:
			pool.append(i)
	pool.shuffle()
	main.next_map_choices = pool.slice(0, 3)
	_push_next_maps()


func _push_next_maps() -> void:
	if Net.is_networked() and Net.is_host():
		main.bcast("net_next_maps", [main.next_map_choices, main.next_map_tally], true)


func net_next_maps(choices: Array, tally: Array) -> void:
	if choices != main.next_map_choices:
		main.my_next_map_vote = -1
	main.next_map_choices = choices
	main.next_map_tally = tally


func next_map_name(i: int) -> String:
	if i < 0 or i >= main.next_map_choices.size():
		return ""
	var mi: int = int(main.next_map_choices[i])
	return str(main.MAPS[mi].get("name", "?")) if mi >= 0 and mi < main.MAPS.size() else "?"


# Local player's vote (HUD: keys 1-3, D-pad, tap).
func vote_next_map(i: int) -> void:
	if main.round_active or i < 0 or i >= main.next_map_choices.size():
		return
	main.my_next_map_vote = i
	if Net.is_networked() and not Net.is_host():
		main.rpc_id(1, "net_next_map_vote", i)
	else:
		_record_next_map_vote(1, i)


func net_next_map_vote(i: int) -> void:
	if Net.is_host():
		_record_next_map_vote(main.multiplayer.get_remote_sender_id(), i)


func _record_next_map_vote(voter: int, i: int) -> void:
	if main.round_active or i < 0 or i >= main.next_map_choices.size():
		return
	_nm_votes[voter] = i
	main.next_map_tally = [0, 0, 0]
	for v in _nm_votes.values():
		main.next_map_tally[int(v)] += 1
	_push_next_maps()


# Host / SP at the end of the winner screen: switch maps if anyone voted (or a
# dedicated server rotates). Returns true when a map change was started.
func _apply_next_map_vote() -> bool:
	if Net.is_networked() and not Net.is_host():
		return false
	if main.next_map_choices.is_empty():
		return false
	var best := -1
	var best_ct := 0
	for i in main.next_map_choices.size():
		if int(main.next_map_tally[i]) > best_ct:
			best_ct = int(main.next_map_tally[i])
			best = i
	if best < 0:
		if Net.is_dedicated:
			best = 0
		else:
			main.next_map_choices = []
			return false
	var target: int = int(main.next_map_choices[best])
	print("NEXT-MAP %s (%d votes)" % [next_map_name(best), best_ct])
	main.next_map_choices = []
	if Net.is_networked():
		main.bcast("net_match_restart", [target, Settings.game_mode], true)
	else:
		Settings.map_index = target
		Settings.custom_map_path = ""
		Settings.save()
		main.call_deferred("_do_reload_main")
	return true
