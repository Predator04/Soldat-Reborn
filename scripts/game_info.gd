extends Object
## GameInfo (v1.18) — one place for the player-facing text that explains
## modes and items: the menu mode pickers, the in-match mode banner, the
## pause menu, the H card, pickup toasts and the labels floating over items.
## Numbers here must match main.gd / player.gd (tools/label_test.gd checks
## the win targets against main.gd's constants).

# [title, one line on how to win, a little more detail]
const MODES := [
	["DEATHMATCH", "Everyone for themselves. First to 20 kills wins.",
		"Every kill is a point. Round ends at 20 kills or when the 5-minute timer runs out."],
	["TEAMMATCH", "Blue vs red. First team to 20 kills wins.",
		"Kills score for your team. Friendly fire is off unless the host turns it on."],
	["CAPTURE THE FLAG", "Grab the enemy flag and carry it to your own. First to 3 captures wins.",
		"Your flag must be at home to capture. Touch your own dropped flag to send it back."],
	["INFILTRATION", "Red attacks, blue defends. Red scores by bringing the flag to blue's base — 3 wins.",
		"One flag. Blue returns it by touching it after a red carrier drops it."],
	["HOLD THE FLAG", "Keep the single flag. 1 point per second while your team carries it — 60 wins.",
		"Kills don't score. Kill the carrier to take it."],
	["RAMBOMATCH", "Grab the Rambo Bow. Only whoever holds the bow scores kills.",
		"The bow holder regenerates health fast. Kill them and take it."],
	["POINTMATCH", "Collect the gold diamonds — each is +1. First to 20 wins.",
		"Diamonds come back a few seconds after they're taken. Kills don't score."],
	["DOMINATION", "Stand on control points to take them. Each point you hold scores every second — 90 wins.",
		"Taking a point takes 4 seconds of standing on it. Kills don't score."],
	["BATTLE ROYALE", "Stay inside the shrinking ring and be the last one standing.",
		"Outside the ring you lose health every second. Turn on Survival for no respawns."],
	["GUN GAME", "Every kill moves you up to the next weapon. Get a knife kill on the last rung to win.",
		"16 rungs from pistol to knife. Weapon switching is locked to your rung."],
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
	"Rambo Bow": "Silent bow with sagging arrows.",
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
	return str(SHORT.get(kind, ""))


static func weapon_desc(wname: String) -> String:
	return str(WEAPONS.get(wname, ""))


# Sub-mode text shared by the menu tooltips and the pause menu.
const SUBMODES := {
	"realistic": "Realistic: headshots kill in one hit, no jet boots, no ammo / fuel readouts.",
	"survival": "Survival: no respawns — wait until one side is wiped out.",
	"advance": "Advance: start with a knife and unlock better guns as you score kills.",
}
