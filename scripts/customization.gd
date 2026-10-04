extends Object
## Player customization catalog: every look a player can pick, all made by us
## (no player-supplied content). Some are free, the rest unlock with career
## level (Stats.level_for) or an achievement. Keys go into the cosmetics dict
## that every peer draws (gostek.gd / soldier_art.gd).

const SKIN_TONES := {
	"": Color(0.98, 0.82, 0.65), "fair": Color(1.0, 0.9, 0.82), "tan": Color(0.82, 0.6, 0.42),
	"brown": Color(0.58, 0.38, 0.25), "dark": Color(0.36, 0.24, 0.17),
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
	# Values above 1 brighten: the gun sprites are mostly dark metal.
	"desert": Color(1.35, 1.12, 0.72), "woodland": Color(0.75, 1.0, 0.55), "carbon": Color(0.42, 0.43, 0.48),
	"arctic": Color(1.45, 1.55, 1.7), "crimson": Color(1.45, 0.5, 0.45), "gold": Color(1.75, 1.35, 0.45),
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


# Looked up at runtime (not the autoload identifier) so drawing code that
# preloads this catalog also compiles in tools that run before autoloads.
static func _stats() -> Node:
	var ml = Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null("Stats") if ml is SceneTree else null


static func _level() -> int:
	var st := _stats()
	return st.level_for(st.xp()) if st != null else 1


static func is_unlocked(kind: String, key: String) -> bool:
	var rule = (UNLOCKS.get(kind, {}) as Dictionary).get(key)
	if rule == null:
		return true
	if str(rule[0]) == "level":
		return _level() >= int(rule[1])
	var st := _stats()
	return st != null and st.unlocked.has(str(rule[1]))


static func lock_text(kind: String, key: String) -> String:
	var rule = (UNLOCKS.get(kind, {}) as Dictionary).get(key)
	if rule == null:
		return ""
	if str(rule[0]) == "level":
		return TranslationServer.translate("level %d") % int(rule[1])
	var st := _stats()
	for a in (st.ACHIEVEMENTS if st != null else []):
		if str(a[0]) == str(rule[1]):
			return TranslationServer.translate("achievement: %s") % TranslationServer.translate(str(a[1]))
	return "?"


## The key if it's a real catalog option you've unlocked, else the default.
static func allowed(kind: String, key: String) -> String:
	return key if is_option(kind, key) and is_unlocked(kind, key) else ""


static func is_option(kind: String, key: String) -> bool:
	for row in ROWS:
		if row[0] == kind:
			for opt in row[2]:
				if opt[0] == key:
					return true
	return false


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


## "Next unlock: Trousers: Desert at level 3" (lowest level still locked).
static func next_unlock_text() -> String:
	var best_lv := 9999
	var best := ""
	for kind in UNLOCKS.keys():
		for key in (UNLOCKS[kind] as Dictionary).keys():
			var rule = UNLOCKS[kind][key]
			if str(rule[0]) == "level" and not is_unlocked(kind, key) and int(rule[1]) < best_lv:
				best_lv = int(rule[1])
				best = item_name(kind, key)
	if best == "":
		return ""
	return TranslationServer.translate("Next unlock: %s at level %d") % [best, best_lv]
