extends Node
## Main's bots (#258 split of main.gd): the roster (Bots setting, --fill
## for dedicated servers, live bot-count changes), spawning + respawn, team
## auto-balance (#263), chatter and radio call-outs, and host -> client bot
## replication (#55: reliable spawn / despawn / die, 20 Hz state stream).
##
## Host / single player own every bot; clients only mirror them. The @rpc entry
## points stay on Main; _bots_by_id and the spawn tables stay on Main.

const Main = preload("res://scripts/main.gd")

var main: Main

var bot_scene := preload("res://scenes/bot.tscn")
var _bot_pending: Dictionary = {}    # bot name -> true while its respawn timer runs
var _next_bot_id: int = 1
const BOT_STATE_CHUNK_MAX := 8       # #102: max bot entries per net_bot_state packet — keeps under ENet MTU (1392 B).
var _fill_seq := 100
var _bot_team_by_name: Dictionary = {}   # bot name -> team (live or waiting to respawn)
# ── Bot chatter (host decides, everyone sees it in chat) ───────────────────
const BOT_KILL_LINES := ["Too easy.", "Next!", "Stay down.", "Get off my map!", "Nice try.",
	"Boom.", "Who's next?", "Sit.", "That's one.", "Should've jetted.", "gg ez", "Reload that."]
const BOT_DEATH_LINES := ["Lucky shot!", "I'll be back.", "Lag!", "Ugh...", "Not again!",
	"Respawning angry.", "Camper!", "Hax.", "You got lucky.", "Ow."]
var _bot_chat_cd: Dictionary = {}   # bot name -> msec of last line


func _spawn_bots() -> void:
	var spots: Array = main._map["bot_spawns"]
	# #67: bot_count -1 = "every spawn slot" (legacy). Otherwise cap to the setting.
	# We recycle spawn positions round-robin if the user asks for more bots than slots.
	if _bot_fill_active() and Settings.is_team_mode() and Settings.game_mode != Settings.MODE_INF and not spots.is_empty():
		_reconcile_fill_teams()
		return
	var desired: int = _desired_bot_count()
	if desired <= 0 or spots.is_empty():
		return
	for i in desired:
		_spawn_bot_at(i, desired)


# Bot fill (dedicated servers, --fill=N): keep the match at N soldiers, with
# bots stepping aside one-for-one as real players join and coming back when
# they leave. Otherwise the Bots setting decides.
func _bot_fill_active() -> bool:
	return Net.is_networked() and Net.is_host() and Net.is_dedicated and Net.fill_target > 0


func _desired_bot_count() -> int:
	if _bot_fill_active():
		return maxi(0, Net.fill_target - main._connected_peers.size())
	var spots: Array = main._map["bot_spawns"]
	return spots.size() if MatchConfig.bot_count() < 0 else MatchConfig.bot_count()


func _bot_carries_flag(b: Node) -> bool:
	for f in main.flags:
		if is_instance_valid(f) and f.has_meta("carrier") and f.get_meta("carrier") == b:
			return true
	return false


# Team-mode fill: each side is topped up to half the target with bots, so a
# side with more players gets fewer bots and the teams stay even.
func _reconcile_fill_teams() -> void:
	var per_side: int = int(ceil(Net.fill_target / 2.0))
	for t in [main.TEAM_BLUE, main.TEAM_RED]:
		var humans := 0
		for pid in main._connected_peers.keys():
			if int(main._peer_team_by_id.get(pid, -1)) == t:
				humans += 1
		var want: int = maxi(0, per_side - humans)
		var live_t: Array = _live_bots().filter(func(b): return int(b.team) == t)
		var pend_t: Array = _bot_pending.keys().filter(func(n): return int(_bot_team_by_name.get(n, -1)) == t)
		var have: int = live_t.size() + pend_t.size()
		while have < want:
			_fill_seq += 1
			var tl := main._team_spawn_list(t)
			var nm := ("Blue Bot %d" if t == main.TEAM_BLUE else "Red Bot %d") % _fill_seq
			_spawn_bot(tl[_fill_seq % tl.size()], t, nm, "AK-74")
			have += 1
		while have > want and not pend_t.is_empty():
			_bot_pending.erase(pend_t.pop_back())
			have -= 1
		while have > want and not live_t.is_empty():
			var rb: Node = null
			for i in range(live_t.size() - 1, -1, -1):
				if not _bot_carries_flag(live_t[i]):
					rb = live_t[i]
					break
			if rb == null:
				break
			live_t.erase(rb)
			_despawn_bot(rb)
			have -= 1


# Fill removal (FFA / INF): newest bot first, never the flag carrier.
func _fill_pick_removal(live: Array) -> Node:
	for i in range(live.size() - 1, -1, -1):
		if not _bot_carries_flag(live[i]):
			return live[i]
	return null


## #256: the classic bot loadout (last bot brings the LAW), falling through
## the primary roster when the pick is banned for the match.
func _bot_loadout(want_law: bool) -> String:
	var tbl: Array = main.player.get("weapons") if main.player != null and is_instance_valid(main.player) else []
	var want := "LAW" if want_law else "AK-74"
	if not MatchConfig.weapon_banned(want):
		return want
	if not tbl.is_empty():
		for w in tbl:
			if not MatchConfig.weapon_banned(str(w["name"])):
				return str(w["name"])
	return "AK-74"


func _spawn_bot_at(i: int, desired: int) -> void:
	var spots: Array = main._map["bot_spawns"]
	var slot: Vector2 = spots[i % spots.size()]
	var loadout := _bot_loadout(i == desired - 1)
	var mode: int = Settings.game_mode
	if Settings.is_team_mode():
		if mode == Settings.MODE_INF:
			# INF: bots are attackers (RED). Player defends solo on BLUE.
			var rl := main._team_spawn_list(main.TEAM_RED)
			_spawn_bot(rl[i % rl.size()], main.TEAM_RED, "Red Bot %d" % (i + 1), loadout)
		else:
			# TDM/CTF/HTF/PM: split bots BLUE/RED evenly, each at its own base.
			var on_blue: bool = i < desired / 2
			var t: int = main.TEAM_BLUE if on_blue else main.TEAM_RED
			var nm := "Blue Bot %d" % (i + 1) if on_blue else "Red Bot %d" % (i + 1)
			var tl := main._team_spawn_list(t)
			_spawn_bot(tl[i % tl.size()], t, nm, loadout)
	else:
		# DM/RM/GG/BR: every bot is its own team (FFA_BOT_TEAM_BASE + i), so bots
		# fight each other as well as humans. Ids sit far above peer ids (humans
		# use team = peer_id in MP FFA, 0 in single-player).
		_spawn_bot(slot, main.FFA_BOT_TEAM_BASE + i, "Bot %d" % (i + 1), loadout)


# Reconcile the live bot count to MatchConfig.bot_count() — called when the host
# tweaks the bot-count slider mid-match so new bots appear / extras vanish without
# a full restart. Host/SP only; clients get spawn/despawn pushed via RPC.
func _reconcile_bots() -> void:
	if Net.is_networked() and not Net.is_host():
		return
	var spots: Array = main._map["bot_spawns"]
	if spots.is_empty():
		return
	if _bot_fill_active() and Settings.is_team_mode() and Settings.game_mode != Settings.MODE_INF:
		_reconcile_fill_teams()
		_log_fill.call_deferred()
		return
	var desired: int = _desired_bot_count()
	var live: Array = _live_bots()
	# Dead bots waiting on their respawn timer count too — otherwise lowering
	# then raising the slider mid-fight spawned extras AND the pending respawns.
	var have: int = live.size() + _bot_pending.size()
	var diff: int = desired - have
	if diff > 0:
		for i in range(have, desired):
			_spawn_bot_at(i, desired)
	elif diff < 0:
		var excess: int = -diff
		for k in _bot_pending.keys():
			if excess <= 0:
				break
			_bot_pending.erase(k)
			excess -= 1
		if _bot_fill_active():
			while excess > 0 and not live.is_empty():
				var rb: Node = _fill_pick_removal(live)
				if rb == null:
					break
				live.erase(rb)
				_despawn_bot(rb)
				excess -= 1
		else:
			for i in range(maxi(0, live.size() - excess), live.size()):
				_despawn_bot(live[i])
	if _bot_fill_active():
		_log_fill.call_deferred()


func _log_fill() -> void:
	await main.get_tree().process_frame
	var c := {main.TEAM_BLUE: 0, main.TEAM_RED: 0}
	for pid in main._connected_peers.keys():
		var pt: int = int(main._peer_team_by_id.get(pid, -1))
		if c.has(pt):
			c[pt] += 1
	for b in _live_bots():
		if c.has(int(b.team)):
			c[int(b.team)] += 1
	for n in _bot_pending.keys():
		var bt: int = int(_bot_team_by_name.get(n, -1))
		if c.has(bt):
			c[bt] += 1
	print("FILL humans=%d bots=%d blue=%d red=%d" % [main._connected_peers.size(), _live_bots().size() + _bot_pending.size(), int(c[main.TEAM_BLUE]), int(c[main.TEAM_RED])])


func _live_bots() -> Array:
	var out: Array = []
	for n in main.get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(n) and n.get("loadout") != null and not bool(n.get("dead")):
			out.append(n)
	return out


func _despawn_bot(b: Node) -> void:
	var bid: int = int(b.get("bot_id"))
	if Net.is_networked() and Net.is_host() and bid > 0:
		main.bcast("net_bot_despawn", [bid], false)
		main._bots_by_id.erase(bid)
	if is_instance_valid(b):
		b.queue_free()


## #263: move bots from the bigger team to the smaller until they're within
## one, picking the lowest-scoring movers (least disruptive). Humans are never
## moved. Host/SP only; clients see the result through the bot state mirror.
func _balance_teams() -> void:
	if not (not Net.is_networked() or Net.is_host()):
		return
	for _guard in 16:
		var counts := {main.TEAM_BLUE: 0, main.TEAM_RED: 0}
		var bots := {main.TEAM_BLUE: [], main.TEAM_RED: []}
		for sld in main.get_tree().get_nodes_in_group("soldier"):
			if not is_instance_valid(sld):
				continue
			var t: int = int(sld.get("team"))
			if not counts.has(t):
				continue
			counts[t] += 1
			if sld.get("bot_id") != null and not bool(sld.get("dead")):
				bots[t].append(sld)
		var diff: int = counts[main.TEAM_BLUE] - counts[main.TEAM_RED]
		if absi(diff) <= 1:
			return
		var from_t: int = main.TEAM_BLUE if diff > 0 else main.TEAM_RED
		var to_t: int = main.TEAM_RED if diff > 0 else main.TEAM_BLUE
		if bots[from_t].is_empty():
			return   # imbalance is all-human — respect their choices
		# Least-disruptive mover: fewest kills this match (K from player_stats).
		var mover = bots[from_t][0]
		var best_score := INF
		for b in bots[from_t]:
			var st: Dictionary = main.player_stats.get(str(b.get("display_name")), {})
			var sc: float = float(st.get("k", 0))
			if sc < best_score:
				best_score = sc
				mover = b
		mover.set("team", to_t)
		mover.set("color", main.bot_color_for_team(to_t))
		# Respawn at the new team's base so the mover isn't behind enemy lines.
		var tl: Array = main._team_spawn_list(to_t)
		if not tl.is_empty():
			(mover as Node2D).global_position = main._safe_spawn_near(tl[0], to_t)
		main.hud.post_chat("HOST", "%s switched to %s to balance the teams." % [
			str(mover.get("display_name")), "BLUE" if to_t == main.TEAM_BLUE else "RED"], false)


func _spawn_bot(pos: Vector2, team: int, bname: String, loadout: String = "AK-74") -> void:
	if not main.is_inside_tree():
		return
	# Clients never spawn bots directly — the host owns bot lifecycle and pushes
	# spawn/despawn via net_spawn_bot / net_despawn_bot RPCs (issue #55).
	if Net.is_networked() and not Net.is_host():
		return
	var b := bot_scene.instantiate()
	_bot_team_by_name[bname] = team
	b.position = main._safe_spawn_near(pos, team)
	b.team = team
	b.display_name = bname
	b.loadout = loadout
	# Colorize per team so friend/foe reads at a glance (FFA bots get a hue each).
	b.color = main.bot_color_for_team(team)
	# Assign a stable id + set host as authority so the bot's own is_multiplayer_authority()
	# check gates AI to peer 1. Clients skip _physics_process AI (see bot.gd).
	var assigned_id: int = 0
	if Net.is_networked() and Net.is_host():
		assigned_id = _next_bot_id
		_next_bot_id += 1
		b.bot_id = assigned_id
		b.name = "Bot_%d" % assigned_id
		b.set_multiplayer_authority(1)
	# Gun Game: bots share the players' ladder — restore the persisted rung so
	# a bot that climbed pre-death re-spawns holding the same rung's weapon.
	if Settings.game_mode == Settings.MODE_GG:
		b.gg_level = main._modes._gg_get(bname)
	# Bots respawn on the same slot so the match can accumulate score.
	# Survival gates this — the next spawn only happens on _reset_round.
	b.died.connect(func() -> void:
		if assigned_id > 0:
			main._bots_by_id.erase(assigned_id)
		# Survival: _reset_round respawns everyone — a death on the winner
		# screen used to schedule an extra body that appeared after the reset.
		if Settings.survival:
			return
		var delay: float = main._respawn_delay_for_team(team)
		_bot_pending[bname] = true
		main.get_tree().create_timer(delay).timeout.connect(func() -> void:
			# Guard against the outer Main being torn down (scene change / quit)
			# during the respawn window — the SceneTreeTimer keeps firing.
			if not main.is_inside_tree():
				return
			# Cancelled by _reconcile_bots (slider lowered while dead).
			if not _bot_pending.has(bname):
				return
			_bot_pending.erase(bname)
			_spawn_bot(_bot_respawn_pos(pos, team), team, bname, loadout)))
	main.add_child(b)
	# Reassert authority after add_child so children added in _ready inherit it.
	if Net.is_networked() and Net.is_host():
		b.set_multiplayer_authority(1, true)
		main._bots_by_id[assigned_id] = b
		# Notify every peer whose main.tscn is loaded so they spawn a replica.
		# We gate on _connected_peers (populated in net_client_ready) instead of
		# _ready_peers (populated on net_spawn_ack) so bots spawned in the gap
		# between the client's "ready" and its ack still reach the joining peer
		# — otherwise those bots would be permanently invisible to it (#84).
		# _connected_peers may be empty on the first bot batch (dedicated boot) —
		# that's fine, joiners get all live bots mirrored in net_client_ready below.
		for pid in main._connected_peers.keys():
			main.rpc_id(int(pid), "net_spawn_bot", assigned_id, b.position, team, bname, loadout, b.cosmetics)


# Respawn somewhere on the bot's own side (team modes) or any spawn point
# (FFA), preferring spots away from enemies, instead of always the same slot.
func _bot_respawn_pos(slot: Vector2, team: int) -> Vector2:
	if Settings.is_team_mode():
		if Settings.game_mode == Settings.MODE_INF and team == main.TEAM_RED:
			return main._pick_spawn_away(main._team_spawn_list(main.TEAM_RED), team)
		return main._team_spawn_pick(team)
	var bs: Array = main._map.get("bot_spawns", [])
	return main._pick_spawn_away(bs, team) if not bs.is_empty() else slot


func _is_bot_name(n: String) -> bool:
	for b in _live_bots():
		if str(b.get("display_name")) == n:
			return true
	for b in main._bots_by_id.values():
		if is_instance_valid(b) and str(b.get("display_name")) == n:
			return true
	return n.begins_with("Bot ") or n.begins_with("Red Bot") or n.begins_with("Blue Bot")


func _maybe_bot_chatter(killer: String, victim: String) -> void:
	if not Settings.bot_chatter or killer == "" or killer == victim:
		return
	var speaker := ""
	var lines: Array = []
	# Mostly react to humans: bots trash-talk the player they killed and
	# complain when a player gets them; bot-vs-bot stays quieter.
	var human_involved: bool = not _is_bot_name(killer) or not _is_bot_name(victim)
	var chance := 0.35 if human_involved else 0.06
	if randf() > chance:
		return
	if _is_bot_name(killer) and (randf() < 0.6 or not _is_bot_name(victim)):
		speaker = killer
		lines = BOT_KILL_LINES
	elif _is_bot_name(victim):
		speaker = victim
		lines = BOT_DEATH_LINES
	if speaker == "":
		return
	var now := Time.get_ticks_msec()
	if now - int(_bot_chat_cd.get(speaker, -100000)) < 12000:
		return
	_bot_chat_cd[speaker] = now
	var msg: String = str(lines[randi() % lines.size()])
	net_bot_chat(speaker, msg)
	if Net.is_networked() and main.multiplayer.has_multiplayer_peer():
		for pid in main._ready_peers.keys():
			main.rpc_id(int(pid), "net_bot_chat", speaker, msg)


func net_bot_chat(author: String, msg: String) -> void:
	if main.hud != null and main.hud.has_method("post_chat"):
		main.hud.post_chat(author, msg.left(80), false)


# A bot on the robbed team calls out the enemy flag carrier (host / SP only).
func _bot_radio_efc(robbed_team: int, carrier: Node) -> void:
	var callers: Array = []
	for b in main.get_tree().get_nodes_in_group("soldier"):
		if is_instance_valid(b) and b.get("bot_id") != null and b.get("dead") != true and int(b.get("team")) == robbed_team:
			callers.append(b)
	if callers.is_empty():
		return
	var bot_id: int = callers[randi() % callers.size()].get_instance_id()
	var carrier_id: int = carrier.get_instance_id()
	# Ids, not node captures: a lambda holding a node that's freed before the
	# timer fires logs "Lambda capture ... was freed".
	main.get_tree().create_timer(0.7).timeout.connect(func() -> void:
		var bot: Object = instance_from_id(bot_id)
		var carrier_n: Object = instance_from_id(carrier_id)
		if bot == null or carrier_n == null or not is_instance_valid(bot) or not is_instance_valid(carrier_n) or bot.get("dead") == true:
			return
		var code := "efc_" + main.radio_dir((carrier_n as Node2D).global_position)
		main.bcast("net_radio", [str(bot.get("display_name")), code, robbed_team], true))


func _broadcast_bot_state() -> void:
	if main._ready_peers.is_empty():
		return
	# #102: positional Array-of-Arrays instead of Dictionary-of-strings. Dropping
	# the 14 key strings per entry shrinks each bot from ~365 B → ~140 B, keeping
	# the unreliable_ordered packet under the ENet MTU (1392) for the common 4-8
	# bot case. Field order MUST match net_bot_state below.
	# Layout: [id, pos, vel, facing, jet, health, dead, loadout, ammo,
	#         reloading, muzzle_t, ceasefire, using_secondary, secondary_ammo]
	var arr: Array = []
	for bid in main._bots_by_id.keys():
		var b = main._bots_by_id[bid]
		if not is_instance_valid(b):
			continue
		arr.append([
			int(bid),
			b.position,
			b.velocity,
			float(b.facing),
			bool(b.jet_on),
			float(b.health),
			bool(b.dead),
			str(b.loadout),
			int(b.ammo),
			bool(b.reloading),
			float(b.muzzle_t),
			float(b.ceasefire_t),
			bool(b.using_secondary),
			int(b.secondary_ammo),
		])
	if arr.is_empty():
		return
	# Split across ticks if bot_count -1 (use every map spawn) yields more than
	# BOT_STATE_CHUNK_MAX bots — safeguards against a giant map pushing us back
	# over the MTU. 8/chunk × ~140 B ≈ 1120 B < 1392 B.
	for pid in main._ready_peers.keys():
		var i: int = 0
		while i < arr.size():
			var end: int = min(i + BOT_STATE_CHUNK_MAX, arr.size())
			main.rpc_id(int(pid), "net_bot_state", arr.slice(i, end))
			i = end


func net_spawn_bot(bot_id: int, spawn_pos: Vector2, team: int, display_name: String, loadout: String, cosmetics: Dictionary) -> void:
	# Free any stale replica with the same id (bot respawn re-uses ids? no — we mint
	# a fresh id per spawn — but a peer that missed the despawn should still recover).
	if main._bots_by_id.has(bot_id):
		var old = main._bots_by_id[bot_id]
		if is_instance_valid(old):
			old.queue_free()
		main._bots_by_id.erase(bot_id)
	# Same exact-name rule as players (see net_spawn_player): a duplicate spawn
	# (mirror + broadcast) must not leave the live replica auto-renamed.
	var clash := main.get_node_or_null("Bot_%d" % bot_id)
	if clash != null:
		clash.name = "Bot_%d_gone_%d" % [bot_id, clash.get_instance_id()]
		if not clash.is_queued_for_deletion():
			clash.queue_free()
	var b := bot_scene.instantiate()
	b.name = "Bot_%d" % bot_id
	b.position = spawn_pos
	b.team = team
	b.display_name = display_name
	b.loadout = loadout
	b.bot_id = bot_id
	# Copy cosmetics so the client bot reads the same outfit as the host's — bot.gd's
	# _ready only randomises when cosmetics is empty (see bot.gd:89).
	if cosmetics != null and not cosmetics.is_empty():
		b.cosmetics = cosmetics.duplicate(true)
	b.color = main.bot_color_for_team(team)
	# Host (peer 1) owns the bot's AI + damage authority. Non-authority replicas
	# skip _physics_process and are driven by net_bot_state (see bot.gd guards).
	b.set_multiplayer_authority(1)
	# Gun Game: mirror the client's cached rung so the newly-spawned replica
	# reads the right weapon in-hand even before the first net_bot_state tick.
	if Settings.game_mode == Settings.MODE_GG:
		b.gg_level = main._modes._gg_get(display_name)
	main.add_child(b)
	b.set_multiplayer_authority(1, true)
	main._bots_by_id[bot_id] = b


func net_bot_despawn(bot_id: int) -> void:
	if not main._bots_by_id.has(bot_id):
		return
	var b = main._bots_by_id[bot_id]
	main._bots_by_id.erase(bot_id)
	if is_instance_valid(b):
		b.queue_free()


func net_bot_die(bot_id: int) -> void:
	if not main._bots_by_id.has(bot_id):
		return
	var b = main._bots_by_id[bot_id]
	main._bots_by_id.erase(bot_id)
	if is_instance_valid(b) and b.has_method("die_replica"):
		b.die_replica()
	elif is_instance_valid(b):
		b.queue_free()


func net_bot_state(arr: Array) -> void:
	# #102: entries are now positional Arrays (see _broadcast_bot_state).
	# Defend against malformed payloads — a corrupt / crafted packet used to
	# crash the client on the raw assignments (#86.1). Skip entries that aren't
	# 14-element arrays; guard each field so an incorrect type keeps the previous
	# value instead of forcing an invalid assignment.
	for entry in arr:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 14:
			continue
		var id: int = int(entry[0])
		if not main._bots_by_id.has(id):
			continue
		var b = main._bots_by_id[id]
		if not is_instance_valid(b):
			continue
		var pos_v: Variant = entry[1]
		var vel_v: Variant = entry[2]
		if typeof(vel_v) == TYPE_VECTOR2:
			b.velocity = vel_v
		if typeof(pos_v) == TYPE_VECTOR2:
			b.net_apply_pos(pos_v, b.velocity)
		var facing_v: Variant = entry[3]
		if typeof(facing_v) == TYPE_FLOAT or typeof(facing_v) == TYPE_INT:
			b.facing = float(facing_v)
		b.jet_on = bool(entry[4])
		var health_v: Variant = entry[5]
		if typeof(health_v) == TYPE_FLOAT or typeof(health_v) == TYPE_INT:
			b.health = float(health_v)
		b.dead = bool(entry[6])
		var loadout_v: Variant = entry[7]
		if typeof(loadout_v) == TYPE_STRING or typeof(loadout_v) == TYPE_STRING_NAME:
			b.loadout = String(loadout_v)
		var ammo_v: Variant = entry[8]
		if typeof(ammo_v) == TYPE_INT or typeof(ammo_v) == TYPE_FLOAT:
			b.ammo = int(ammo_v)
		b.reloading = bool(entry[9])
		var mz_v: Variant = entry[10]
		if typeof(mz_v) == TYPE_FLOAT or typeof(mz_v) == TYPE_INT:
			b.muzzle_t = float(mz_v)
		var cf_v: Variant = entry[11]
		if typeof(cf_v) == TYPE_FLOAT or typeof(cf_v) == TYPE_INT:
			b.ceasefire_t = float(cf_v)
		# #79: apply secondary state so the client-side replica draws the same
		# in-hand weapon as the host (physics-side ammo tracking is irrelevant
		# on the replica because _physics_process is authority-gated).
		b.using_secondary = bool(entry[12])
		var sa_v: Variant = entry[13]
		if typeof(sa_v) == TYPE_INT or typeof(sa_v) == TYPE_FLOAT:
			b.secondary_ammo = int(sa_v)
