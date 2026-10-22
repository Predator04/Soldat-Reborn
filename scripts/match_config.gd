extends Node
## MatchConfig — host-authoritative match rules broadcast to every peer (#74).
##
## Before this, `mod_gravity` / `mod_jet` / `mod_damage` / `mod_speed` were
## read directly out of Settings on each peer, which meant a client could quietly
## run 2x damage or half-gravity while the host stayed on stock — visible desync.
##
## Now every physics/damage site goes through MatchConfig.mod_*(). On SP + Host
## the getters forward straight to Settings so single-player behaviour is
## unchanged. On Client the getters return whatever the host last broadcast
## via net_apply. The host publishes its snapshot on join + on any admin-menu
## change so late-joiners and mid-match tweaks propagate immediately.
##
## Also carries the new host_friendly_fire toggle (default OFF): when enabled,
## teammates take damage from bullets / grenades / rockets / melee.

# ── Client-side cache (populated by net_apply). Host + SP ignore these
# entirely; the getters short-circuit to Settings for them.
const GameLists = preload("res://scripts/game_lists.gd")

var _cfg_gravity: float = 1.0
var _cfg_jet: float = 1.0
var _cfg_damage: float = 1.0
var _cfg_speed: float = 1.0
var _cfg_friendly_fire: bool = false
var _cfg_bot_count: int = -1
var _cfg_bot_skill: int = 3
var _cfg_game_mode: int = 0
var _cfg_map_index: int = 0
var _cfg_weapon_bans: Array = []    # #256: names removed from the match
# #317: sub-modes + respawn delays follow the host (a dedicated server's
# server.cfg sets them; before, each client ran its own Settings sub-modes).
var _cfg_realistic := false
var _cfg_survival := false
var _cfg_advance := false
var _cfg_respawn := 2.0
var _cfg_respawn_inf := 5.0
var _broadcast_scheduled := false   # #245: debounced host_broadcast pending

# Host-only match knob: even in team modes, bullets/grenades/rockets/melee can
# damage teammates. Default OFF matches classic Soldat team play. Persisted for
# convenience across sessions so a host who likes FF doesn't have to re-toggle.
var host_friendly_fire: bool = false


func _ready() -> void:
	# host_friendly_fire is not part of Settings.gd itself (it's a host-authority
	# match knob, not a per-user preference), but we persist it in settings.cfg
	# so a host who likes FF doesn't have to re-toggle every session.
	var cf := ConfigFile.new()
	if cf.load(Settings.PATH) == OK:
		host_friendly_fire = bool(cf.get_value("match", "host_friendly_fire", false))


func save_host_ff() -> void:
	var cf := ConfigFile.new()
	# Read-modify-write so we don't clobber other Settings sections.
	cf.load(Settings.PATH)
	cf.set_value("match", "host_friendly_fire", host_friendly_fire)
	cf.save(Settings.PATH)


# ── Effective-value getters. Callers everywhere should use these, not the raw
# Settings.mod_* / Settings.friendly_fire_on / Settings.bot_* fields, so a
# joined client sees the host's values instead of its own local Settings.
func mod_gravity() -> float:
	return _cfg_gravity if Net.is_client() else float(Settings.mod_gravity)


func mod_jet() -> float:
	return _cfg_jet if Net.is_client() else float(Settings.mod_jet)


func mod_damage() -> float:
	return _cfg_damage if Net.is_client() else float(Settings.mod_damage)


func mod_speed() -> float:
	return _cfg_speed if Net.is_client() else float(Settings.mod_speed)


func friendly_fire_on() -> bool:
	if Net.is_client():
		return _cfg_friendly_fire
	# FFA modes (DM / RM / BR) always allow between-soldier damage — legacy behaviour.
	# Team modes only allow it when the host has flipped the toggle on.
	if Settings.friendly_fire_on():
		return true
	return host_friendly_fire


func bot_count() -> int:
	return _cfg_bot_count if Net.is_client() else int(Settings.bot_count)


## #317 sub-modes: the host's (SP / host read Settings; clients the snapshot).
## Same Gun Game / Bomb exemptions as Settings.survival / Settings.advance.
func realistic() -> bool:
	return _cfg_realistic if Net.is_client() else bool(Settings.realistic)


func survival() -> bool:
	if Net.is_client():
		return _cfg_survival and Settings.game_mode != Settings.MODE_GG and Settings.game_mode != Settings.MODE_BOMB
	return bool(Settings.survival)


func advance() -> bool:
	if Net.is_client():
		return _cfg_advance and Settings.game_mode != Settings.MODE_GG
	return bool(Settings.advance)


## Respawn delay in seconds (`inf_attacker` = Infiltration's red team).
## Defaults 2 / 5; a dedicated server's server.cfg can change them (#317).
func respawn_secs(inf_attacker: bool) -> float:
	if Net.is_client():
		return _cfg_respawn_inf if inf_attacker else _cfg_respawn
	if inf_attacker:
		return float(Net.rule("respawn_time_inf_attackers", 5.0))
	return float(Net.rule("respawn_time", 2.0))


func bot_skill() -> int:
	return _cfg_bot_skill if Net.is_client() else int(Settings.bot_skill)


## #256: is this weapon banned for the match? (Host/SP reads Settings live so
## the panel takes effect immediately; clients read the broadcast snapshot.
## Gun Game's rung and Rambo's bow are match OBJECTIVES — callers exempt them.)
func weapon_banned(wname: String) -> bool:
	if wname == "":
		return false
	var bans: Array = _cfg_weapon_bans if Net.is_client() else (Settings.weapon_bans as Array)
	return bans.has(wname)


# ── Broadcast pipeline. Host wraps up its Settings snapshot + host_friendly_fire
# into a Dictionary and RPCs it out; every remote peer applies to its cache.
func to_dict() -> Dictionary:
	return {
		"gravity": float(Settings.mod_gravity),
		"jet": float(Settings.mod_jet),
		"damage": float(Settings.mod_damage),
		"speed": float(Settings.mod_speed),
		"ff": friendly_fire_on(),
		"bot_count": int(Settings.bot_count),
		"bot_skill": int(Settings.bot_skill),
		"game_mode": int(Settings.game_mode),
		"map_index": int(Settings.map_index),
		"bans": (Settings.weapon_bans as Array).duplicate(),
		"realistic": bool(Settings.realistic),
		"survival": bool(Settings.survival_pref),
		"advance": bool(Settings.advance_pref),
		"respawn": respawn_secs(false),
		"respawn_inf": respawn_secs(true),
	}


func apply_dict(d: Dictionary) -> void:
	_cfg_gravity = float(d.get("gravity", 1.0))
	_cfg_jet = float(d.get("jet", 1.0))
	_cfg_damage = float(d.get("damage", 1.0))
	_cfg_speed = float(d.get("speed", 1.0))
	_cfg_friendly_fire = bool(d.get("ff", false))
	_cfg_bot_count = int(d.get("bot_count", -1))
	_cfg_bot_skill = int(d.get("bot_skill", 3))
	_cfg_game_mode = int(d.get("game_mode", 0))
	_cfg_map_index = int(d.get("map_index", 0))
	# #256: only real names survive (a hostile host packet can't smuggle junk).
	var bans: Array = []
	var bl = d.get("bans", [])
	if typeof(bl) == TYPE_ARRAY:
		for nm in bl:
			if typeof(nm) == TYPE_STRING and GameLists.WEAPON_NAMES.has(nm) and not bans.has(nm):
				bans.append(nm)
	_cfg_weapon_bans = bans
	_cfg_realistic = bool(d.get("realistic", false))
	_cfg_survival = bool(d.get("survival", false))
	_cfg_advance = bool(d.get("advance", false))
	_cfg_respawn = clampf(float(d.get("respawn", 2.0)), 0.0, 60.0)
	_cfg_respawn_inf = clampf(float(d.get("respawn_inf", 5.0)), 0.0, 60.0)


func host_broadcast() -> void:
	# Push the current host snapshot to every connected peer. #245: sliders
	# call this at drag-tick rate — coalesce bursts into one reliable RPC half
	# a second after the last change so a dragged slider doesn't spam every
	# client's reliable channel.
	if not Net.is_host():
		return
	if multiplayer.multiplayer_peer == null:
		return
	if _broadcast_scheduled:
		return
	_broadcast_scheduled = true
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		_broadcast_scheduled = false
		if is_inside_tree() and Net.is_host() and multiplayer.multiplayer_peer != null:
			rpc("net_apply", to_dict()))


@rpc("authority", "reliable")
func net_apply(cfg: Dictionary) -> void:
	apply_dict(cfg)
