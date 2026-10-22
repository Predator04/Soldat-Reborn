extends RefCounted
## Zombie mode (#314) — the per-soldier rules any script can ask (static, no
## state; preload it). In mode 11 the RED team (2) is always the zombies and
## BLUE (1) the humans, so "is this soldier a zombie?" is its team, which every
## peer already has for every body (net_spawn_player / net_spawn_bot).
##
## Zombies: claws only (the Knife through the normal melee path, shown as
## "claws"), no weapon / grenade / power-up pickups, no grenades, no vehicles
## or M2s, run SPEED_MUL faster and take damage_taken() of every hit (applied
## in HostHits.damage, so every damage path agrees, host-decided as always).

const MODE := 11
const TEAM_HUMAN := 1
const TEAM_ZOMBIE := 2
const SPEED_MUL := 1.1        # run / air caps
const DAMAGE_TAKEN_LONE := 0.55  # x every hit while the zombies are few (~180 HP) ...
const DAMAGE_TAKEN_HORDE := 1.3  # ... up to this once nearly everyone is a zombie (~77 HP)
const CLAW_DAMAGE := 26.0      # per swing (Knife 55): four to turn a healthy human
const SPAWN_SHIELD := 0.5      # s of spawn protection (soldiers get 3 s)
const CLAW_WEAPON := "Knife"   # player.gd SECONDARY_WEAPONS entry the claws use
const CLAW_SLOT := 1           # its secondary index


## The mode, read without naming the Settings autoload (tests preload this
## before autoloads exist).
static func on() -> bool:
	var ml := Engine.get_main_loop() as SceneTree
	var st: Node = ml.root.get_node_or_null("Settings") if ml != null else null
	return st != null and int(st.get("game_mode")) == MODE


static func is_zombie(s: Variant) -> bool:
	if s == null or not is_instance_valid(s) or not on():
		return false
	var t: Variant = (s as Object).get("team")
	return t != null and int(t) == TEAM_ZOMBIE


## x a zombie takes of every hit when `share` of the living soldiers are
## zombies: a lone zombie is tough, a horde is fragile (the last humans can
## still fight their way through it).
static func damage_taken(share: float) -> float:
	return lerpf(DAMAGE_TAKEN_LONE, DAMAGE_TAKEN_HORDE, clampf(share, 0.0, 1.0))


## Damage a zombie actually takes from a hit of `amount` (kill zones / the
## kill line call take_damage(9999) directly and stay lethal). The share comes
## from the host's match_zombie (Main is the soldier's parent).
static func scaled_damage(s: Node, amount: float) -> float:
	if not is_zombie(s):
		return amount
	var m: Node = s.get_parent()
	var z: Variant = m.get("_zombie") if m != null else null
	var share: float = float(z.zombie_share) if z != null else 0.0
	return amount * damage_taken(share)
