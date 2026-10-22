extends Object
## GameInfo (v1.18) — one place for the player-facing text that explains
## modes and items: the menu mode pickers, the in-match mode banner, the
## pause menu, the H card, pickup toasts and the labels floating over items.
## Numbers here must match main.gd / player.gd (tools/label_test.gd checks
## the win targets against main.gd's constants).

# [title, one line on how to win, a little more detail]
## Display name of the game (#269). Internal identifiers keep the old name on
## purpose: project config/name (it decides where settings, stats and replays
## live — changing it would orphan every player's data), the Android package
## id, the update asset names (SoldatReborn.exe/.apk/.pck) and the repo URL.
const TITLE := "Tracerfall"
const TITLE_UPPER := "TRACERFALL"

## Online protocol. Builds with a different protocol (or game version) refuse
## each other at the join handshake with a readable reason instead of
## desyncing. 2 = host-decided hits (#266), 3 = Zombie mode (#314: mode 11,
## Main.net_zombie_sync). Bump whenever RPCs change meaning.
const NET_PROTOCOL := 3


## What a client sends (and the host compares) in the join handshake.
static func net_version() -> String:
	return "%s+net%d" % [str(ProjectSettings.get_setting("application/config/version", "")), NET_PROTOCOL]


## "1.37.0+net2" -> "1.37.0 (online protocol 2)"; a pre-#266 build sends the
## bare version (protocol 1).
static func pretty_net_version(v: String) -> String:
	if v == "":
		return "(old build)"
	var at := v.find("+net")
	if at < 0:
		return "%s (online protocol 1)" % v
	return "%s (online protocol %s)" % [v.left(at), v.substr(at + 4)]

## #223 Discord Rich Presence — the Discord application's id ("Application
## ID" on https://discord.com/developers/applications → your app → General
## Information; a long number, not a secret). Empty = the feature is off.
## TODO(owner): paste the id between the quotes, e.g. "1234567890123456789".
## See docs/discord/SETUP.md.
const DISCORD_APP_ID := ""

const MODES := [
	["DEATHMATCH", "Everyone for themselves. First to 50 kills wins.",
		"Every kill is a point. Round ends at 50 kills or when the 15-minute timer runs out."],
	["TEAMMATCH", "Blue vs red. First team to 120 kills wins.",
		"Kills score for your team. Friendly fire is off unless the host turns it on."],
	["CAPTURE THE FLAG", "Grab the enemy flag and carry it to your own. First to 3 captures wins.",
		"Your flag must be at home to capture. Touch your own dropped flag to send it back."],
	["INFILTRATION", "Red attacks, blue defends. Red scores by bringing the flag to blue's base — 3 wins.",
		"One flag. Blue returns it by touching it after a red carrier drops it."],
	["HOLD THE FLAG", "Keep the single flag. 1 point per second while your team carries it — 300 wins.",
		"Kills don't score. Kill the carrier to take it."],
	["RAMBOMATCH", "Grab the Rambo Bow. Only whoever holds the bow scores kills.",
		"The bow holder regenerates health fast. Kill them and take it."],
	["POINTMATCH", "Collect the gold diamonds — each is +1. First to 200 wins.",
		"Diamonds come back a few seconds after they're taken. Kills don't score."],
	["DOMINATION", "Stand on control points to take them. Each point you hold scores every second — 800 wins.",
		"Taking a point takes 4 seconds of standing on it. Kills don't score."],
	["BATTLE ROYALE", "Stay inside the shrinking ring and be the last one standing.",
		"Outside the ring you lose health every second. Turn on Survival for no respawns."],
	["GUN GAME", "Every kill moves you up to the next weapon. Get a knife kill on the last rung to win.",
		"16 rungs from pistol to knife. Weapon switching is locked to your rung."],
	["BOMB DEFUSAL", "Red attacks, blue defends: plant the bomb at site A or B, or stop it. First to 7 rounds wins.",
		"Hold Use 3 s in a site to plant; the bomb blows in 40 s unless a defender holds Use on it for 7 s. The dead respawn together every 10 s; sides swap at halftime."],
	["ZOMBIE", "Humans vs zombies: survive the 3:00 round clock or turn every human. First to 5 rounds wins.",
		"Zombies only claw and run faster; while they're few they shrug off hits. A human who dies rises as a zombie; zombies are back in 6 s."],
]

# kind -> [label, what it does]
const ITEMS := {
	"predator": ["PREDATOR", "See-through to enemies and 35% faster for 30 s. Firing breaks it."],
	"berserker": ["BERSERKER", "Knife only: every stab is a one-hit kill, 15% faster, for 30 s."],
	"vest": ["BULLETPROOF VEST", "You take half damage for 30 s."],
	"cluster": ["CLUSTER GRENADES", "Your grenades split into bomblets for 30 s."],
	"medkit": ["MEDIKIT", "Heals you to full. Left alone if you're already at full health."],
	"grenades": ["GRENADE KIT", "Refills you to 3 grenades."],
	"point": ["+1 POINT", "Pointmatch: worth one point to your team."],
	"m2": ["M2 MACHINE GUN", "Mounted heavy gun — press F next to it to use it."],
	"tank": ["TANK", "Heavy armor, two seats: F to get in. Slow, shrugs off bullets; the turret lobs explosive shells (aim high for range). Bring a LAW, M79 or grenades to kill one."],
	"heli": ["HELICOPTER", "Two seats: F to get in. Pilot: W lift, S down, A/D fly, click fires two rockets (every 3 s). Door gunner fires the MG. Bullets do half damage; explosives bring it down."],
	"plane": ["PLANE", "One seat: F to get in, F again bails out. W / S throttle, A / D (or the mouse) pitch the nose; it can't hover — too slow and it stalls. Click fires the nose gun, the grenade key drops a bomb (every 3.5 s). Take off down a runway; hard impacts wreck it."],
	"buggy": ["BUGGY", "Two seats: F to get in. Driver: A/D drive. Gunner (or a driver alone) fires the mounted gun. Runs people over; blows up when wrecked."],
}

# weapon -> short role line (pickup labels / toasts)
const WEAPONS := {
	"Deagles": "Dual heavy pistols — hard-hitting, semi-auto.",
	"MP5": "SMG — very fast fire, low damage.",
	"AK-74": "Assault rifle — all-rounder.",
	"Steyr AUG": "Assault rifle — accurate, fast fire.",
	"Spas-12": "Shotgun — 8 pellets, deadly up close.",
	"Ruger 77": "Hunting rifle — accurate, slow, big hits.",
	"M79": "Grenade launcher — lobbed explosive shells.",
	"Barrett": "Sniper — winds up, then one huge shot per click.",
	"Minimi": "Light machine gun — 50-round belt.",
	"Minigun": "Spins up, then shreds. 100 rounds.",
	"Flamethrower": "Short-range fire cone.",
	"Rambo Bow": "Silent bow: one arrow kills. Arrows sag, so aim high at range.",
	"USSOCOM": "Sidearm pistol.",
	"Knife": "Melee — stab, or throw it with F.",
	"Chainsaw": "Melee — continuous damage up close.",
	"LAW": "Rocket launcher — slow rocket, big blast.",
}


static func mode_title(i: int) -> String:
	return str(MODES[clampi(i, 0, MODES.size() - 1)][0])


static func mode_goal(i: int) -> String:
	return str(MODES[clampi(i, 0, MODES.size() - 1)][1])


static func mode_detail(i: int) -> String:
	return str(MODES[clampi(i, 0, MODES.size() - 1)][2])


static func item_label(kind: String) -> String:
	return str((ITEMS.get(kind, [kind.to_upper(), ""]) as Array)[0])


static func item_desc(kind: String) -> String:
	return str((ITEMS.get(kind, ["", ""]) as Array)[1])


# Few-word reminder shown next to the bonus countdown.
const SHORT := {
	"predator": "see-through · faster · firing breaks it",
	"berserker": "knife one-hit kills",
	"vest": "half damage",
	"cluster": "cluster grenades",
}


static func item_short(kind: String) -> String:
	return TranslationServer.translate(str(SHORT.get(kind, "")))


static func weapon_desc(wname: String) -> String:
	return str(WEAPONS.get(wname, ""))


# Sub-mode text shared by the menu tooltips and the pause menu.
const SUBMODES := {
	"realistic": "Realistic: headshots kill in one hit, no jet boots, no ammo / fuel readouts.",
	"survival": "Survival: no respawns — wait until one side is wiped out.",
	"advance": "Advance: start with a knife and unlock better guns as you score kills.",
}
