extends RefCounted
## Zombie mode (#314) — the per-soldier rules any script can ask (static, no
## state; preload it). In mode 11 the RED team (2) is always the zombies and
## BLUE (1) the humans, so "is this soldier a zombie?" is its team, which every
## peer already has for every body (net_spawn_player / net_spawn_bot).
##
## Zombies: claws only (the Knife through the normal melee path, shown as
## "claws"), no weapon / grenade / power-up pickups, no grenades, no vehicles
## or M2s, run SPEED_MUL faster and take DAMAGE_TAKEN of every hit (applied
## in HostHits.damage, so every damage path agrees, host-decided as always).

const MODE := 11
const TEAM_HUMAN := 1
const TEAM_ZOMBIE := 2
const SPEED_MUL := 1.1        # run / air caps
const DAMAGE_TAKEN := 0.85     # x every hit = ~118 effective HP
const CLAW_DAMAGE := 40.0      # per swing (Knife 55): three to turn a healthy human
const SPAWN_SHIELD := 0.5      # s of spawn protection (soldiers get 3 s)
const CLAW_WEAPON := "Knife"   # player.gd SECONDARY_WEAPONS entry the claws use
const CLAW_SLOT := 1           # its secondary index


static func on() -> bool:
	return Settings.game_mode == MODE


static func is_zombie(s: Variant) -> bool:
	if Settings.game_mode != MODE or s == null or not is_instance_valid(s):
		return false
	var t: Variant = (s as Object).get("team")
	return t != null and int(t) == TEAM_ZOMBIE


## Damage a zombie actually takes from a hit of `amount` (kill zones / the
## kill line call take_damage(9999) directly and stay lethal).
static func scaled_damage(s: Node, amount: float) -> float:
	return amount * DAMAGE_TAKEN if is_zombie(s) else amount
