extends Object
## Player customization catalog: every look a player can pick, all made by us
## (no player-supplied content). Some are free, the rest unlock with career
## level (Stats.level_for) or an achievement. Keys go into the cosmetics dict
## that every peer draws (gostek.gd / soldier_art.gd).

const SKIN_TONES := {
	"": Color(0.98, 0.82, 0.65), "fair": Color(1.0, 0.89, 0.78), "tan": Color(0.86, 0.67, 0.49),
	"brown": Color(0.65, 0.45, 0.31), "dark": Color(0.44, 0.3, 0.21),
}
# Trousers (the jacket keeps the team color so friend / foe still reads).
const PANTS := {
	"desert": Color(0.66, 0.58, 0.42), "woodland": Color(0.34, 0.41, 0.26), "urban": Color(0.43, 0.45, 0.48),
	"black": Color(0.17, 0.18, 0.2), "white": Color(0.8, 0.82, 0.85),
}
# Helmet / vest paint (also in gostek.gd FINISHES for drawing).
const FINISHES := {"desert": Color(0.78, 0.68, 0.46), "urban": Color(0.58, 0.6, 0.64),
	"night": Color(0.2, 0.22, 0.27), "gold": Color(1.0, 0.8, 0.28)}
# Weapon skins tint every gun you carry.
const WEAPON_SKINS := {
	"desert": Color(1.0, 0.86, 0.62), "woodland": Color(0.72, 0.86, 0.58), "carbon": Color(0.42, 0.43, 0.48),
	"arctic": Color(0.84, 0.93, 1.0), "crimson": Color(1.0, 0.55, 0.5), "gold": Color(1.0, 0.82, 0.32),
}

# kind -> key -> ["level", n] | ["ach", id]. Keys not listed are free.
const UNLOCKS := {
	"finish": {"desert": ["level", 5], "urban": ["level", 10], "night": ["level", 20], "gold": ["level", 35]},
	"vfinish": {"desert": ["level", 6], "urban": ["level", 12], "night": ["ach", "unstoppable"], "gold": ["ach", "champion"]},
	"pants": {"desert": ["level", 3], "woodland": ["level", 7], "urban": ["level", 14], "black": ["ach", "flag_runner"], "white": ["level", 25]},
	"wskin": {"desert": ["level", 2], "woodland": ["level", 8], "carbon": ["level", 15], "arctic": ["ach", "long_shot"],
		"crimson": ["ach", "massacre"], "gold": ["level", 40]},
}

# Rows of the CUSTOMIZE screen: [kind, label, [[key, name], ...]]
const ROWS := [
	["skin", "Skin tone", [["", "Default"], ["fair", "Fair"], ["tan", "Tan"], ["brown", "Brown"], ["dark", "Dark"]]],
	["head", "Head", [["helm", "Helmet"], ["kap", "Cap"], ["hair1", "Hair 1"], ["hair2", "Hair 2"], ["hair3", "Hair 3"], ["hair4", "Hair 4"], ["none", "Bald"]]],
	["finish", "Helmet paint", [["", "Standard"], ["desert", "Desert"], ["urban", "Urban"], ["night", "Night"], ["gold", "Gold"]]],
	["vest", "Vest", [["on", "On"], ["off", "Off"]]],
	["vfinish", "Vest paint", [["", "Standard"], ["desert", "Desert"], ["urban", "Urban"], ["night", "Night"], ["gold", "Gold"]]],
	["pants", "Trousers", [["", "Team color"], ["desert", "Desert"], ["woodland", "Woodland"], ["urban", "Urban"], ["black", "Black"], ["white", "White"]]],
	["chain", "Chain", [["none", "None"], ["silver", "Silver"], ["gold", "Gold"]]],
	["extras", "Extras", []],
	["wskin", "Weapon skin", [["", "Factory"], ["desert", "Desert"], ["woodland", "Woodland"], ["carbon", "Carbon"], ["arctic", "Arctic"], ["crimson", "Crimson"], ["gold", "Gold"]]],
]


static func _level() -> int:
	return Stats.level_for(Stats.xp())


static func is_unlocked(kind: String, key: String) -> bool:
	var rule = (UNLOCKS.get(kind, {}) as Dictionary).get(key)
	if rule == null:
		return true
	if str(rule[0]) == "level":
		return _level() >= int(rule[1])
	return Stats.unlocked.has(str(rule[1]))


static func lock_text(kind: String, key: String) -> String:
	var rule = (UNLOCKS.get(kind, {}) as Dictionary).get(key)
	if rule == null:
		return ""
	if str(rule[0]) == "level":
		return TranslationServer.translate("level %d") % int(rule[1])
	for a in Stats.ACHIEVEMENTS:
		if str(a[0]) == str(rule[1]):
			return TranslationServer.translate("achievement: %s") % TranslationServer.translate(str(a[1]))
	return "?"


static func allowed(kind: String, key: String) -> String:
	return key if is_unlocked(kind, key) else ""


## Everything still locked for you, for the "unlocked" toasts.
static func locked_list() -> Array:
	var out: Array = []
	for kind in UNLOCKS.keys():
		for key in (UNLOCKS[kind] as Dictionary).keys():
			if not is_unlocked(kind, key):
				out.append("%s:%s" % [kind, key])
	return out


static func item_name(kind: String, key: String) -> String:
	for row in ROWS:
		if row[0] == kind:
			for opt in row[2]:
				if opt[0] == key:
					return "%s: %s" % [TranslationServer.translate(row[1]), TranslationServer.translate(opt[1])]
	return key
