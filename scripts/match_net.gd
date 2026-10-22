extends Node
## Main's multiplayer session (#258 split of main.gd): joining clients
## (version / name handshake, rejoin, full-world hydration in _handle_client_ready
## + net_spawn_ack), player bodies (net_spawn_player / net_despawn_player, team
## assignment, respawn scheduling), disconnects, the bcast / ready_peer_ids
## fan-out helpers, chat / radio / kill-feed / objective relays, and the
## periodic match / mode / flag state streams + pings.
##
## Every @rpc stays on Main: Godot resolves an RPC by node path + method name,
## so the stubs there keep the exact names and annotations and call in here.
## Peer tables (_players_by_id, _ready_peers, _connected_peers, ...) stay on Main.

const Main = preload("res://scripts/main.gd")
const RadioMenu = preload("res://scripts/radio_menu.gd")

var main: Main

var _left_team: Dictionary = {}   # host: display name -> team of players who dropped
# Rocket / grenade sync (see rocket.gd _net_send). Only the projectile's
# authority may drive it; unknown names (already exploded here, or spawned
# before we loaded) are ignored.
const _PROJ_METHODS := ["net_projectile_state", "net_explode", "net_consume"]
# Clients learn which peers have loaded the match (host pushes the list on
# every ack / disconnect) so their own projectiles only address those.
var _client_ready_list: Array = []
var _peer_tokens: Dictionary = {}   # host: peer id -> the client's session token
var _recent_t := 5.0


func _spawn_networked_player(peer_id: int) -> void:
	# FFA MP (DM/RM): spawn joining players at a random bot_spawn — classic Soldat
	# spawn-point behavior. Puts them in the action zone instead of the map corner
	# where player_spawn typically sits (Ascent/Towers/Pillars have player_spawn at
	# (200,1775) but every bot_spawn is >2000px away, so a fresh joiner would never
	# actually meet a bot within the first ~10s). Team modes keep player_spawn so
	# team sides stay coherent. (#57)
	var t: int = _assign_team_for_peer(peer_id)
	var base: Vector2 = main._map["player_spawn"]
	if Settings.is_team_mode():
		base = main._team_spawn_pick(t)
	if Net.is_networked() and not Settings.is_team_mode():
		var bs: Array = main._map.get("bot_spawns", [])
		if not bs.is_empty():
			base = main._pick_spawn_away(bs, t)
	var spawn_pos := main._modes._jitter_spawn(base)
	var display_name: String = Settings.display_name() if peer_id == 1 else str(main._peer_names.get(peer_id, "Player %d" % peer_id))
	bcast("net_spawn_player", [peer_id, spawn_pos, display_name, t], true)


func _assign_team_for_peer(peer_id: int) -> int:
	# Deathmatch / Rambomatch stay FFA — team = peer_id so every soldier is a
	# distinct hostile entity.
	if not Settings.is_team_mode():
		return peer_id
	# #314 Zombie: the round decides (a join mid-round = a zombie).
	if Settings.game_mode == Settings.MODE_ZOMBIE and main._zombie.active():
		return main._zombie.team_for(Settings.display_name() if peer_id == 1 else str(main._peer_names.get(peer_id, "Player %d" % peer_id)))
	var back_as := str(main._peer_names.get(peer_id, ""))
	if _left_team.has(back_as) and Settings.game_mode != Settings.MODE_INF:
		var tb: int = int(_left_team[back_as])
		_left_team.erase(back_as)
		if tb == main.TEAM_BLUE or tb == main.TEAM_RED:
			return tb
	# Team modes: alternate BLUE/RED to keep sides balanced. INF is asymmetric —
	# first peer defends (BLUE), everyone else attacks.
	var blue_count := 0
	var red_count := 0
	for pid in main._players_by_id.keys():
		if int(pid) == peer_id:
			continue
		var p = main._players_by_id[pid]
		if not is_instance_valid(p):
			continue
		if int(p.team) == main.TEAM_BLUE:
			blue_count += 1
		elif int(p.team) == main.TEAM_RED:
			red_count += 1
	if Settings.game_mode == Settings.MODE_INF:
		return main.TEAM_BLUE if blue_count == 0 else main.TEAM_RED
	return main.TEAM_BLUE if blue_count <= red_count else main.TEAM_RED


func _schedule_peer_respawn(peer_id: int, t: int) -> void:
	if not Net.is_host():
		return
	# Survival: _reset_round rebuilds everyone's body; no timer.
	if MatchConfig.survival():
		return
	var delay: float = main._respawn_delay_for_team(t)
	var mode_at_schedule: int = Net.mode
	# Human players may be watching the kill cam rewind: wait for their
	# "ready" (sent right away when there's nothing to watch) or the pad.
	main._respawn_gate(peer_id, delay, main._killcam_pad(delay), func() -> void:
		if Net.mode != mode_at_schedule or not main.is_inside_tree():
			return
		# A round reset in between may already have given this peer a body.
		var cur: Variant = main._players_by_id.get(peer_id)
		if cur != null and is_instance_valid(cur) and not bool((cur as Node).get("dead")):
			return
		_respawn_peer(peer_id))


func _respawn_peer(peer_id: int) -> void:
	if not Net.is_host():
		return
	# still connected?
	if peer_id != 1 and not main.multiplayer.get_peers().has(peer_id):
		return
	_spawn_networked_player(peer_id)


func _on_net_peer_disconnected(id: int) -> void:
	if Net.is_host():
		# Remember the leaver's side so a rejoin (same name) lands on it again;
		# their K/D stays in player_stats (name-keyed) already.
		if main.ranked != null:
			main.ranked.player_left(id)
		Net.heartbeat_soon()
		var lp = main._players_by_id.get(id, null)
		if lp != null and is_instance_valid(lp) and main._peer_names.has(id):
			_left_team[str(main._peer_names[id])] = int(lp.team)
		main._peer_names.erase(id)
		_peer_tokens.erase(id)
		_rtt.erase(id)
		_rtt_sent.erase(id)
		main._ready_peers.erase(id)
		main._pickup_peer_sig.erase(id)
		main._connected_peers.erase(id)
		_push_ready_list()
		bcast("net_despawn_player", [id], true)
		# If the disconnecting peer was the votekick target, resolve the vote
		# immediately — no one benefits from a countdown against a phantom.
		if main.vote_active and main.vote_kind == "votekick" and main.vote_target_arg == id:
			main._votes._resolve_vote(false, "Target left the server")
		if main._bots._bot_fill_active():
			main.call_deferred("_reconcile_bots")


func net_stats_sync(stats: Dictionary) -> void:
	if typeof(stats) == TYPE_DICTIONARY:
		main.player_stats = stats.duplicate(true)


func net_proj(node_name: String, method: String, args: Array) -> void:
	if not (method in _PROJ_METHODS) or node_name.contains("/") or node_name.contains(".."):
		return
	var n := main.get_node_or_null(NodePath(node_name))
	if n == null or not n.has_method(method):
		return
	if main.multiplayer.get_remote_sender_id() != n.get_multiplayer_authority():
		return
	Net.proj_msgs_seen += 1
	n.callv(method, args)


func ready_peer_ids() -> Array:
	return main._ready_peers.keys()


func _push_ready_list() -> void:
	if not Net.is_host():
		return
	var ids: Array = main._ready_peers.keys()
	for pid in ids:
		main.rpc_id(int(pid), "net_ready_list", ids)


func net_ready_list(ids: Array) -> void:
	_client_ready_list = ids


func client_send_peer_ids() -> Array:
	var me := main.multiplayer.get_unique_id()
	var out: Array = [1]
	for pid in _client_ready_list:
		if int(pid) != me and int(pid) != 1:
			out.append(int(pid))
	return out


## Host broadcast that only reaches peers whose Main scene exists
## (_connected_peers, set in _handle_client_ready). A plain rpc() also hits
## peers still loading the match, which log "Node not found: Main" and drop
## the packet. The joiner gets a full snapshot on ready anyway. `local`
## mirrors call_local. Non-host callers fall back to a plain rpc().
func bcast(method: StringName, args: Array = [], local: bool = false) -> void:
	if not Net.is_networked() or not main.multiplayer.has_multiplayer_peer():
		if local:
			main.callv(method, args)
		return
	if not Net.is_host():
		main.callv("rpc", [method] + args)
		return
	if local:
		main.callv(method, args)
	var me := main.multiplayer.get_unique_id()
	for pid in main._connected_peers.keys():
		if int(pid) != me and main.multiplayer.get_peers().has(int(pid)):
			main.callv("rpc_id", [int(pid), method] + args)


func _handle_client_ready(sender_id: int, joiner_name: String = "", client_version: String = "", token: String = "") -> void:
	if not Net.is_host():
		return
	var sender := sender_id
	# One ready per connection — a repeat call used to be a free respawn/rename.
	if main._connected_peers.has(sender):
		return
	# Version handshake: mismatched builds desync maps/nav/RPCs in odd ways, so
	# refuse them with a readable reason instead.
	# The string carries the online protocol too (game_info.gd NET_PROTOCOL):
	# a same-version build from before #266 (host-decided hits) is refused.
	var GI := preload("res://scripts/game_info.gd")
	var host_version: String = GI.net_version()
	if client_version != host_version:
		main.rpc_id(sender, "net_reject", "Version mismatch: host %s, you %s" % [GI.pretty_net_version(host_version), GI.pretty_net_version(client_version)])
		main.get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if main.multiplayer.has_multiplayer_peer() and main.multiplayer.multiplayer_peer is ENetMultiplayerPeer \
					and main.multiplayer.get_peers().has(sender):
				(main.multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(sender))
		return
	# Remember the joiner's chosen display name (sanitized, unique) so
	# _spawn_networked_player uses it instead of "Player N". Duplicate names
	# broke kill credit, spawn protection and Gun Game rungs (all name-keyed).
	# Room for a clan tag ("«TAG» "); square brackets become round so a name
	# can't inject rich-text markup into everyone's kill feed / scoreboard.
	var clean_name: String = str(joiner_name).strip_edges().replace("[", "(").replace("]", ")").left(32)
	if clean_name == "":
		clean_name = "Player %d" % sender
	# Rejoin after a drop: the host may not have timed the old connection out
	# yet. Same name from the same address = the same player coming back, so
	# retire the stale peer now (keeps their name, score and team).
	var stale := _stale_peer_for(sender, clean_name, token)
	if token != "":
		_peer_tokens[sender] = token
	if stale > 0:
		_on_net_peer_disconnected(stale)
		if main.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			(main.multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(stale, true)
	main._peer_names[sender] = _unique_display_name(clean_name, sender)
	# Mark the peer as able to receive reliable spawn RPCs BEFORE we mirror — any
	# host-initiated spawn between now and net_spawn_ack still needs to reach
	# this peer, otherwise it'd be permanently invisible (#84).
	main._connected_peers[sender] = true
	# #97: send the Gun Game rung snapshot FIRST so the spawn RPCs below read
	# from a populated _gg_levels. Previously the joiner spawned replicas at
	# rung 0 and only self-healed on the next kill.
	if Settings.game_mode == Settings.MODE_GG:
		main.rpc_id(sender, "net_gg_state_sync", main._gg_levels)
	# tell the new peer about all currently living players
	for existing_id in main._players_by_id.keys():
		var p = main._players_by_id[existing_id]
		if not is_instance_valid(p) or bool(p.get("dead")):
			continue   # dead husks respawn through the normal broadcast
		main.rpc_id(sender, "net_spawn_player", existing_id, p.position, p.display_name, int(p.team))
		p.rpc_id(sender, "net_cosmetics", p.cosmetics)
		# #305: an active power-up (kind + time left) through the same host
		# grant path the pickup uses, so the joiner's replica shows it too.
		var bk := str(p.get("bonus_kind"))
		if bk != "" and float(p.get("bonus_t")) > 0.0:
			p.rpc_id(sender, "net_bonus_apply", bk, float(p.get("bonus_t")))
	# Mirror every live bot to the joining peer so they see the current roster
	# (dedicated server pre-populates before any client connects — issue #55).
	for bid in main._bots_by_id.keys():
		var b = main._bots_by_id[bid]
		if not is_instance_valid(b):
			continue
		main.rpc_id(sender, "net_spawn_bot", int(bid), b.position, int(b.team), str(b.display_name), str(b.loadout), b.cosmetics)
	# Mirror every live bonus box (#78) so the joiner sees the same crates.
	for bid in main._bonus_boxes.keys():
		var box = main._bonus_boxes[bid]
		if not is_instance_valid(box):
			continue
		main.rpc_id(sender, "net_bonus_spawn", int(bid), box.position, str(box.get("bonus_kind")))
	# Buggies (v1.19): where they are, their health, who's in them.
	for vid in main._vehicles.keys():
		var v = main._vehicles[vid]
		if not is_instance_valid(v):
			continue
		main.rpc_id(sender, "net_vehicle_spawn", int(vid), v.get("spawn_pos"), (v as Node2D).global_position, float(v.get("hp")), bool(v.get("alive")), str(v.get("kind")))
		var seats: Array = v.get("seats")
		for i in seats.size():
			if not is_instance_valid(seats[i]):
				continue
			if seats[i].get("bot_id") != null:
				main.rpc_id(sender, "net_vehicle_seat_bot", int(vid), i, int(seats[i].get("bot_id")), true)
			else:
				main.rpc_id(sender, "net_vehicle_seat", int(vid), i, int(seats[i].get_multiplayer_authority()), true)
	main.rpc_id(sender, "net_stats_sync", main.player_stats)
	# then spawn a body for the new peer on everyone
	_spawn_networked_player(sender)
	if main.ranked != null:
		main.ranked.player_joined(sender)
	Net.heartbeat_soon()
	if main._bots._bot_fill_active():
		main.call_deferred("_reconcile_bots")
	# NOTE: _ready_peers[sender] is set only when the client acks the spawn (net_spawn_ack).
	# Otherwise net_state (unreliable_ordered) can beat the reliable spawn RPC and error out.


func _peer_address(id: int) -> String:
	if not (main.multiplayer.multiplayer_peer is ENetMultiplayerPeer):
		return ""
	var pc := (main.multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id)
	return pc.get_remote_address() if pc != null else ""


func _stale_peer_for(sender: int, want: String, token: String) -> int:
	var addr := _peer_address(sender)
	if addr == "" or token == "":
		return 0
	for pid in main._peer_names.keys():
		if int(pid) != sender and str(main._peer_names[pid]) == want and _peer_address(int(pid)) == addr \
				and str(_peer_tokens.get(pid, "")) == token:
			return int(pid)
	return 0


func _unique_display_name(want: String, for_peer: int) -> String:
	var taken := {}
	if not Net.is_dedicated:
		taken[Settings.display_name()] = true
	for pid in main._peer_names.keys():
		if int(pid) != for_peer:
			taken[str(main._peer_names[pid])] = true
	for s in main.get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(s):
			taken[str(s.get("display_name"))] = true
	var nm := want
	var n := 2
	while taken.has(nm):
		nm = "%s (%d)" % [want, n]
		n += 1
	return nm


func net_reject(reason: String) -> void:
	_leave_to_menu(reason)


func _on_lost_host() -> void:
	# A drop (not a kick / reject): the menu offers to rejoin the same game.
	var ip := Net.last_server_ip
	var port := Net.last_server_port
	_leave_to_menu("Lost connection to the host")
	Net.last_server_ip = ip
	Net.last_server_port = port
	Net.rejoin_offer = ip != ""


func _leave_to_menu(reason: String) -> void:
	# Client lost its host (quit / kicked / rejected): back to the menu with a
	# message instead of silently running single-player logic in a dead match.
	if Net.disconnected.is_connected(main._on_lost_host):
		Net.disconnected.disconnect(main._on_lost_host)
	Net.leave()
	print("NET left the match: %s" % reason)
	Net.status = reason
	Net.last_disconnect_reason = reason
	main.get_tree().paused = false
	main.get_tree().call_deferred("change_scene_to_file", "res://scenes/menu.tscn")


func net_spawn_ack() -> void:
	if not Net.is_host():
		return
	var sender := main.multiplayer.get_remote_sender_id()
	main._ready_peers[sender] = true
	_push_ready_list()
	# Push the current MatchConfig snapshot (#74) so the joining peer applies
	# the host's mods / friendly-fire / bot roster immediately instead of
	# running under its own local Settings until the next admin-menu change.
	main.rpc_id(sender, "net_match_config_apply", MatchConfig.to_dict())
	# #317: server.cfg message of the day (once per connection).
	if Net.is_dedicated and Net.server_cfg != null:
		Net.server_cfg.on_peer_ready(main, sender)
	# Send an immediate pickup snapshot + M2 mount ownership so a late-joiner
	# sees currently-thrown weapons on the ground and knows which turrets are
	# already occupied, instead of waiting for the next 10Hz broadcast tick.
	var arr: Array = []
	for wp in main.get_tree().get_nodes_in_group("weapon_pickup"):
		if not is_instance_valid(wp):
			continue
		if int(wp.get("pickup_id")) <= 0:
			continue
		# #254 review nit: skip regenerating map slots — a joiner shouldn't
		# see a ghost the next broadcast tick would immediately despawn.
		var wp_active = wp.get("active")
		if wp_active != null and not bool(wp_active):
			continue
		arr.append(main._bonuses._pickup_entry(wp))
	# ...and seed the per-peer signature (same builder = same bytes as the
	# next 10 Hz tick, so it isn't resent, #247 review nit).
	main._pickup_peer_sig[sender] = str(arr)
	if not arr.is_empty():
		main.rpc_id(sender, "net_pickup_state", arr)
	for m2 in main.get_tree().get_nodes_in_group("m2_gun"):
		if not is_instance_valid(m2):
			continue
		var op = m2.get("operator")
		if is_instance_valid(op):
			main.rpc_id(sender, "net_m2_mount", int(m2.get("m2_id")), int(op.get_multiplayer_authority()))
	# #108: hydrate scoreboard / flag / mode state immediately so a joiner
	# landing during e.g. the winner-display window or with a flag being
	# carried doesn't render 0-0-0 / flag-at-home for up to a broadcast tick.
	main.rpc_id(sender, "net_match_state", main.scores, main.time_left, main.round_active, main.winner_team, main.winner_end_t, main.winner_note, main._gg_levels, main._gg_kills)
	if main.flags.size() > 0:
		var flag_arr: Array = []
		for f in main.flags:
			if not is_instance_valid(f):
				flag_arr.append({"pos": Vector2.ZERO, "carrier": 0})
				continue
			var cid := 0
			var carrier: Variant = f.get_meta("carrier") if f.has_meta("carrier") else null
			if is_instance_valid(carrier):
				var nm := String(carrier.name)
				if nm.begins_with("Player_"):
					cid = int(nm.substr(7))
			flag_arr.append({"pos": f.position, "carrier": cid})
		main.rpc_id(sender, "net_flag_state", flag_arr)
	var mode: int = Settings.game_mode
	if mode == Settings.MODE_DOM or mode == Settings.MODE_PM or mode == Settings.MODE_BR:
		var mp: Dictionary = {}
		if mode == Settings.MODE_DOM:
			var dom: Array = []
			for a in main._dom_points:
				if not is_instance_valid(a):
					dom.append([0, 0.0, 0])
					continue
				dom.append([int(a.get_meta("owner_team", 0)), float(a.get_meta("progress", 0.0)), int(a.get_meta("cap_team", 0))])
			mp["dom"] = dom
		elif mode == Settings.MODE_PM:
			var pm: Array = []
			for p in main.get_tree().get_nodes_in_group("point_pickup"):
				if is_instance_valid(p):
					pm.append(p.get_meta("spawn_pos", p.global_position))
			mp["pm"] = pm
		elif mode == Settings.MODE_BR:
			mp["br"] = {"c": main._br_zone_center, "r": main._br_zone_radius}
		if not mp.is_empty():
			main.rpc_id(sender, "net_mode_state", mp)
	# #304: the whole bomb state, reliably (a planted bomb, its fuse, the sites).
	if mode == Settings.MODE_BOMB and main._bomb.active():
		main.rpc_id(sender, "net_bomb_sync", main._bomb.net_payload(true))
	# #314: the Zombie round state (the joiner's own side came with its body).
	if mode == Settings.MODE_ZOMBIE and main._zombie.active():
		main.rpc_id(sender, "net_zombie_sync", main._zombie.net_payload(true))


func net_match_config_apply(cfg: Dictionary) -> void:
	# Thin trampoline to MatchConfig.apply_dict — kept on Main so the RPC target
	# lives on a scene-node the multiplayer stack always resolves (autoloads
	# resolve too, but co-locating the match state RPCs here matches the pattern
	# used by net_match_state / net_flag_state / net_pickup_state).
	MatchConfig.apply_dict(cfg)


func net_match_restart(map_idx: int, mode_idx: int) -> void:
	# Host-driven full-match restart (#74). Everyone lands on the same map+mode
	# by updating the shared knobs BEFORE reloading main.tscn — main._ready()
	# then reads them and rebuilds terrain / spawns cleanly.
	Net.chosen_map_index = clampi(map_idx, 0, main.MAPS.size() - 1)
	Settings.map_index = Net.chosen_map_index
	Settings.custom_map_path = ""  # networked matches always use built-in maps
	Net.custom_map_json = ""       # ...and must not rebuild the previous custom map
	Settings.game_mode = clampi(mode_idx, 0, Net.MODE_NAMES.size() - 1)
	Settings.save()
	main.call_deferred("_do_reload_main")


func _do_reload_main() -> void:
	main.get_tree().paused = false
	main.get_tree().change_scene_to_file("res://scenes/main.tscn")


func net_spawn_player(peer_id: int, spawn_pos: Vector2, display_name: String, assigned_team: int = -1) -> void:
	if assigned_team >= 0:
		main._peer_team_by_id[peer_id] = assigned_team
	# Free stale record if this peer had a prior body (e.g., on respawn).
	if main._players_by_id.has(peer_id):
		var old = main._players_by_id[peer_id]
		if is_instance_valid(old):
			old.queue_free()
		main._players_by_id.erase(peer_id)
	# The new body MUST get the exact name "Player_<peer>": every RPC to it is
	# addressed by that path. A queue_free()d old body is still in the tree
	# this frame, so add_child silently renamed the newcomer ("@CharacterBody2D@N")
	# and every later state / shot RPC for it failed ("Node not found") on that
	# peer. Rename the outgoing body first.
	var clash := main.get_node_or_null("Player_%d" % peer_id)
	if clash != null:
		clash.name = "Player_%d_gone_%d" % [peer_id, clash.get_instance_id()]
		if not clash.is_queued_for_deletion():
			clash.queue_free()
	var p := main.player_scene.instantiate()
	p.name = "Player_%d" % peer_id
	p.position = spawn_pos
	p.display_name = display_name
	# Backward-compat: pre-#22 callers may send no team. In FFA the peer_id acts
	# as a distinct hostile team; in team modes we resolve via the balancer so a
	# raw peer id (millions-range) never leaks into team/colour checks (#85).
	var t: int
	if assigned_team >= 0:
		t = assigned_team
	elif Settings.is_team_mode():
		t = _assign_team_for_peer(peer_id)
	else:
		t = peer_id
	p.team = t
	if t == main.TEAM_BLUE:
		p.color = preload("res://scripts/team_colors.gd").blue()
	elif t == main.TEAM_RED:
		p.color = preload("res://scripts/team_colors.gd").red()
	p.set_multiplayer_authority(peer_id)
	# Gun Game: restore persisted rung on respawn so death doesn't reset progress.
	if Settings.game_mode == Settings.MODE_GG:
		p.gg_level = main._modes._gg_get(display_name)
	if peer_id == Net.local_id():
		main._apply_spawn_loadout(p)
	main.add_child(p)
	# Re-apply after add_child so children created in _ready (cam, jet_particles) inherit authority.
	p.set_multiplayer_authority(peer_id, true)
	main._players_by_id[peer_id] = p
	if peer_id == Net.local_id():
		main.player = p
		main._bind_local_camera(p)
		if main.hud:
			main.hud.player = p
		# Wire death signal so MP local respawn goes through _on_player_died — that's
		# where the spectator kicks in (#75) and the death UI is shown consistently.
		if not p.died.is_connected(main._on_player_died):
			p.died.connect(main._on_player_died)
		# Respawn happened — cut the spectator cam and hide the "you died" overlay
		# so the freshly-spawned body's own camera takes over cleanly.
		main._end_spectator()
		if main.hud and main.hud.has_method("_hide_death"):
			main.hud._hide_death()
		# Tell the host our body is spawned locally so it can start sending state.
		if Net.is_client():
			main.rpc_id(1, "net_spawn_ack")


func net_despawn_player(peer_id: int) -> void:
	if main._players_by_id.has(peer_id):
		var p = main._players_by_id[peer_id]
		if is_instance_valid(p):
			# Same inert husk as a death: packets the leaver sent just before
			# going still address this node on the other peers.
			if Net.is_networked() and p.has_method("_become_husk"):
				p.dead = true
				p._become_husk()
				p.display_name = ""   # free the name for a rejoin right away
				main.get_tree().create_timer(1.5).timeout.connect(p.queue_free)
			else:
				p.queue_free()
		main._players_by_id.erase(peer_id)
	if peer_id == Net.local_id():
		main.player = null


func net_objective_event(kind: String, team: int, who: String) -> void:
	main.objective.emit(kind, team, who)
	if kind == "capture" or kind == "point":
		main._modes._stat_add(who, "c", 1)
	elif kind == "bomb_plant" or kind == "bomb_defuse":
		main._modes._stat_add(who.get_slice("@", 0), "c", 1)   # #304: plants / defuses count as captures
	elif kind == "zombie_turn" and who.get_slice("@", 1) != "":
		main._modes._stat_add(who.get_slice("@", 1), "c", 1)   # #314: a zombie's turns count as captures
	if kind == "capture" and is_instance_valid(main.player) and who == str(main.player.display_name):
		Stats.record_event("capture")
	if main.hud != null and main.hud.has_method("announce_objective"):
		main.hud.announce_objective(kind, team, who)
	Sfx.objective(kind)


func net_kill_feed(killer_name: String, victim_name: String, weapon_name: String, killer_team: int, victim_team: int) -> void:
	main.kill.emit(killer_name, victim_name, weapon_name, killer_team, victim_team)


# Team radio (v1.18). Same sender validation as net_chat; only the sender's
# team hears the voice line and sees the chat line.
func net_radio(author: String, code: String, sender_team: int) -> void:
	var text: String = RadioMenu.label_for(code)
	if text == "":
		return
	if Net.is_networked():
		var sender: int = main.multiplayer.get_remote_sender_id()
		if sender > 0 and sender != main.multiplayer.get_unique_id():
			if main._players_by_id.has(sender) and is_instance_valid(main._players_by_id[sender]):
				author = str(main._players_by_id[sender].display_name)
				sender_team = int(main._players_by_id[sender].team)
			elif main._peer_team_by_id.has(sender):
				author = str(main._peer_names.get(sender, "Player %d" % sender))
				sender_team = int(main._peer_team_by_id[sender])
			else:
				return
	main.radio_count += 1
	if not is_instance_valid(main.player) or int(main.player.team) != sender_team:
		return
	Sfx.radio(code)
	if main.hud != null and main.hud.has_method("post_radio"):
		main.hud.post_radio(author, text)


func net_chat(author: String, msg: String, scope: String, sender_team: int) -> void:
	# #105: never trust client-supplied author / sender_team. In a networked
	# match, resolve both from the sender's peer_id so a client can't
	# impersonate other players or leak team chat across teams. Host-local
	# announcer messages (see hud.post_chat calls elsewhere) bypass this RPC.
	msg = msg.left(200)
	if Net.is_networked():
		var sender: int = main.multiplayer.get_remote_sender_id()
		# The host (peer 1) is the authority and may post as "HOST" / "SERVER"
		# (a dedicated host has no body to resolve a name from, so its /say,
		# MOTD and admin replies used to be dropped here, #317).
		if sender > 1 and sender != main.multiplayer.get_unique_id():
			# Resolve from the sender's registered identity even while dead —
			# otherwise a dead client could post as anyone / read-leak team chat.
			if main._players_by_id.has(sender) and is_instance_valid(main._players_by_id[sender]):
				author = str(main._players_by_id[sender].display_name)
				sender_team = int(main._players_by_id[sender].team)
			elif main._peer_team_by_id.has(sender):
				author = str(main._peer_names.get(sender, "Player %d" % sender))
				sender_team = int(main._peer_team_by_id[sender])
			else:
				return
	# Team chat is filtered locally so opponents don't see it. Global chat is
	# visible to everyone. Route through the HUD's chat feed.
	if scope == "team" and is_instance_valid(main.player) and int(main.player.team) != sender_team:
		return
	if Net.smoke_chat_log:
		print("SMOKE-CHAT %s: %s" % [author, msg])
	if main.hud != null and main.hud.has_method("post_chat"):
		main.hud.post_chat(author, msg, scope == "team")


func _tick_pings(delta: float) -> void:
	if not Net.is_networked() or not Net.is_host():
		return
	main._ping_t -= delta
	if main._ping_t > 0.0:
		return
	main._ping_t = 2.0
	var enet := main.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var out := {}
	if is_instance_valid(main.player):
		out[str(main.player.display_name)] = 0
	for pid in main._peer_names.keys():
		var pc := enet.get_peer(int(pid))
		if pc != null:
			out[str(main._peer_names[pid])] = int(pc.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	bcast("net_pings", [out], true)


func net_pings(table: Dictionary) -> void:
	main.peer_pings = table


# #266: the round trip to each peer, measured end to end with tiny probes
# (RPC to RPC, so it includes frame delays and works over the WebSocket relay
# too). The host rewinds a player's shots by this (host_hits.gd). An echo can
# only answer a probe the host actually sent, and on ENet the figure is capped
# near ENet's own round-trip time, so holding echoes back can't buy much rewind.
var _rtt: Dictionary = {}        # peer -> smoothed ms
var _rtt_sent: Dictionary = {}   # peer -> recent probe stamps
var _rtt_t := 0.0
var _hh_log_ms := 0
var _medic := false
var _medic_tag := ""   # --smoke-medic=TAG: only names with that clan tag
const RTT_PROBE_SECS := 0.5


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--smoke-medic" or a.begins_with("--smoke-medic="):
			_medic = true
			_medic_tag = a.substr(14).to_upper() if a.begins_with("--smoke-medic=") else ""


func _tick_rtt(delta: float) -> void:
	if not Net.is_networked() or not Net.is_host():
		return
	# Release-gate only (--smoke-medic, tools/hosthits_test.gd): keep remote
	# humans alive with ordinary medikits so a long hit-registration run
	# isn't broken up by deaths.
	if _medic:
		for p in HostHits.remote_humans():
			if is_instance_valid(p) and not bool(p.dead) and float(p.health) < 60.0 \
					and (_medic_tag == "" or str(p.display_name).contains("«%s»" % _medic_tag)):
				p.apply_kit("medkit")
				HostHits.count("medic")
			# (and grenade throwers in grenades: a kit once they are out)
			if is_instance_valid(p) and not bool(p.dead) and int(p.grenades) <= 0 \
					and Time.get_ticks_msec() - int(p.get_meta("smoke_kit_ms", -100000)) > 2000:
				p.set_meta("smoke_kit_ms", Time.get_ticks_msec())
				p.apply_kit("grenades")
				HostHits.count("kits")
	_rtt_t -= delta
	if _rtt_t > 0.0:
		return
	_rtt_t = RTT_PROBE_SECS
	var now := Time.get_ticks_msec()
	# Test / ops visibility: what the host decided and refused (host_hits.gd).
	if now - _hh_log_ms >= 5000 and OS.get_cmdline_user_args().has("--hosthits-log"):
		_hh_log_ms = now
		var rt: PackedStringArray = []
		for p in _rtt.keys():
			rt.append("%d:%d" % [int(p), peer_rtt_ms(int(p))])
		print("HOSTHITS %s rtt=[%s]" % [HostHits.summary(), ",".join(rt)])
	for pid in ready_peer_ids():
		if int(pid) == main.multiplayer.get_unique_id() or not main.multiplayer.get_peers().has(int(pid)):
			continue
		var sent: Array = _rtt_sent.get(int(pid), [])
		sent.append(now)
		if sent.size() > 8:
			sent.pop_front()
		_rtt_sent[int(pid)] = sent
		main.rpc_id(int(pid), "net_rtt_probe", now)


func net_rtt_probe(stamp: int) -> void:
	if Net.is_host() or main.multiplayer.get_remote_sender_id() != 1:
		return
	main.rpc_id(1, "net_rtt_echo", stamp)
	# #266: also a host-clock stamp for our shots' view (relayed soldier states
	# carry one too, but a soldier in a vehicle seat sends none).
	HostHits.note_view(stamp)


func net_rtt_echo(stamp: int) -> void:
	if not Net.is_host():
		return
	var pid := main.multiplayer.get_remote_sender_id()
	var sent: Array = _rtt_sent.get(pid, [])
	var at := sent.find(stamp)
	if at < 0:
		return
	_rtt_sent[pid] = sent.slice(at + 1)
	var sample := Time.get_ticks_msec() - stamp
	if sample < 0 or sample > 3000:
		return
	_rtt[pid] = float(sample) if not _rtt.has(pid) else lerpf(float(_rtt[pid]), float(sample), 0.2)


## Host: round trip to `pid` in ms (0 if unknown).
func peer_rtt_ms(pid: int) -> int:
	var app := int(round(float(_rtt.get(pid, -1.0))))
	var enet_rtt := -1
	var mp = main.multiplayer.multiplayer_peer
	# (Only a connected remote peer has one: the host itself — a bot's or
	# the host player's "peer" — or a peer that just left has none.)
	if mp is ENetMultiplayerPeer and pid != main.multiplayer.get_unique_id() and main.multiplayer.get_peers().has(pid):
		var pc := (mp as ENetMultiplayerPeer).get_peer(pid)
		if pc != null:
			enet_rtt = int(pc.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	if app < 0:
		return maxi(0, enet_rtt)
	if enet_rtt >= 0:
		return mini(app, enet_rtt + 80)
	return app


# Friends list: remember the people you play with online (newest first, 40
# kept, favourites never dropped). Saved at most once a minute.
func _tick_recent_players(delta: float) -> void:
	if not Net.is_networked():
		return
	_recent_t -= delta
	if _recent_t > 0.0:
		return
	_recent_t = 20.0
	var me := Settings.display_name()
	var now := int(Time.get_unix_time_from_system())
	var seen: Array = []
	for pid in main._players_by_id.keys():
		var p = main._players_by_id[pid]
		if is_instance_valid(p) and str(p.display_name) != me:
			seen.append(str(p.display_name))
	if seen.is_empty():
		return
	main.remember_players(seen, now)
	Settings.save()


func _broadcast_match_state() -> void:
	if not Net.is_host():
		return
	for pid in main._ready_peers.keys():
		main.rpc_id(int(pid), "net_match_state", main.scores, main.time_left, main.round_active, main.winner_team, main.winner_end_t, main.winner_note, main._gg_levels, main._gg_kills)


func net_match_state(new_scores: Dictionary, tl: float, active: bool, winner: int, we: float, note: String = "", gg_ranks: Dictionary = {}, gg_kills: Dictionary = {}) -> void:
	main.scores = new_scores.duplicate(true)
	main.time_left = tl
	main.round_active = active
	main.winner_team = winner
	main.winner_end_t = we
	main.winner_note = note
	# #91 / #97: mirror GG ladder + kills so the scoreboard reads live on the
	# client and joining peers see the correct rung without waiting for the
	# next kill event. Empty dicts (non-GG modes) are a no-op.
	if not gg_ranks.is_empty():
		main._gg_levels = gg_ranks.duplicate(true)
	main._gg_kills = gg_kills.duplicate(true)


func _broadcast_mode_state() -> void:
	if not Net.is_host():
		return
	if main._ready_peers.is_empty():
		return
	var mode: int = Settings.game_mode
	# Only bundle state that's relevant to the current mode — reduces payload
	# for DM/TDM/CTF etc. where none of this applies.
	var payload: Dictionary = {}
	if mode == Settings.MODE_DOM:
		var dom: Array = []
		for a in main._dom_points:
			if not is_instance_valid(a):
				dom.append([0, 0.0, 0])
				continue
			dom.append([int(a.get_meta("owner_team", 0)), float(a.get_meta("progress", 0.0)), int(a.get_meta("cap_team", 0))])
		payload["dom"] = dom
	elif mode == Settings.MODE_PM:
		var pm: Array = []
		for p in main.get_tree().get_nodes_in_group("point_pickup"):
			if is_instance_valid(p):
				pm.append(p.get_meta("spawn_pos", p.global_position))
		payload["pm"] = pm
	elif mode == Settings.MODE_BR:
		payload["br"] = {"c": main._br_zone_center, "r": main._br_zone_radius}
	elif mode == Settings.MODE_BOMB and main._bomb.active():
		payload["bomb"] = main._bomb.net_payload(false)
	elif mode == Settings.MODE_ZOMBIE and main._zombie.active():
		payload["zombie"] = main._zombie.net_payload(false)
	if payload.is_empty():
		return
	for pid in main._ready_peers.keys():
		main.rpc_id(int(pid), "net_mode_state", payload)


func net_mode_state(payload: Dictionary) -> void:
	# Client-side apply of host-authoritative mode state. Runs on client only —
	# host mutates these directly in its own ticks and short-circuits its net_
	# broadcast for itself.
	if not Net.is_networked() or Net.is_host():
		return
	if payload.has("dom"):
		var dom: Array = payload["dom"]
		for i in mini(dom.size(), main._dom_points.size()):
			var a = main._dom_points[i]
			if not is_instance_valid(a):
				continue
			var entry: Array = dom[i]
			a.set_meta("owner_team", int(entry[0]))
			a.set_meta("progress", float(entry[1]))
			a.set_meta("cap_team", int(entry[2]))
	if payload.has("pm"):
		var alive: Array = payload["pm"]
		var alive_set: Dictionary = {}
		for pos in alive:
			alive_set[str(pos)] = true
		var have_set: Dictionary = {}
		for p in main.get_tree().get_nodes_in_group("point_pickup"):
			if not is_instance_valid(p):
				continue
			var key: String = str(p.get_meta("spawn_pos", p.global_position))
			if not alive_set.has(key):
				p.queue_free()
			else:
				have_set[key] = true
		# Spawn any pickup we don't have locally (host respawned it after cooldown).
		for pos in alive:
			if not have_set.has(str(pos)):
				main._modes._spawn_point_pickup(pos)
	if payload.has("bomb") and typeof(payload["bomb"]) == TYPE_DICTIONARY:
		main._bomb.apply_payload(payload["bomb"])
	if payload.has("zombie") and typeof(payload["zombie"]) == TYPE_DICTIONARY:
		main._zombie.apply_payload(payload["zombie"])
	if payload.has("br"):
		var br: Dictionary = payload["br"]
		main._br_zone_center = br.get("c", main._br_zone_center)
		main._br_zone_radius = float(br.get("r", main._br_zone_radius))


func _broadcast_flag_state() -> void:
	# Each flag: {pos, carrier peer_id (0 = none)}. Only sent to acked peers.
	var arr: Array = []
	for f in main.flags:
		if not is_instance_valid(f):
			arr.append({"pos": Vector2.ZERO, "carrier": 0})
			continue
		var cid := 0
		var carrier: Variant = f.get_meta("carrier") if f.has_meta("carrier") else null
		if is_instance_valid(carrier):
			var nm := String(carrier.name)
			if nm.begins_with("Player_"):
				cid = int(nm.substr(7))
			elif int(carrier.get("bot_id")) > 0:
				# Bots ride as negative ids so clients can attach the flag to the
				# bot replica (smooth carried visual) instead of an 8 Hz dot.
				cid = -int(carrier.get("bot_id"))
		arr.append({"pos": f.position, "carrier": cid})
	for pid in main._ready_peers.keys():
		main.rpc_id(int(pid), "net_flag_state", arr)


func net_flag_state(arr: Array) -> void:
	for i in arr.size():
		if i >= main.flags.size():
			break
		var f = main.flags[i]
		if not is_instance_valid(f):
			continue
		var entry: Dictionary = arr[i]
		f.position = entry.get("pos", f.position)
		var cid := int(entry.get("carrier", 0))
		if cid > 0 and main._players_by_id.has(cid):
			var p = main._players_by_id[cid]
			if is_instance_valid(p):
				f.set_meta("carrier", p)
			else:
				f.set_meta("carrier", null)
		elif cid < 0 and main._bots_by_id.has(-cid) and is_instance_valid(main._bots_by_id[-cid]):
			f.set_meta("carrier", main._bots_by_id[-cid])
		else:
			f.set_meta("carrier", null)
