extends Object
## GameLists — the single source of the map and mode name lists (#251).
## These were copy-pasted across menu.gd / net.gd / host_admin_panel.gd /
## replays_panel.gd; a missed edit silently desynced the host panel from the
## menu at the same index. Everyone preloads from here now.
##
## MAP_NAMES order is load-bearing: indices are persisted (settings,
## replays, dedicated --map) and slots 0-2 are pinned for compatibility.
## After adding maps run tools/build_nav.py + tools/make_thumbs.py.


const MAP_NAMES := [
	"Ascent", "Towers", "Pillars",
	"Nuubia", "Maya", "Aftermath", "Hormone", "Viet",
	"Scorpion", "Warehouse", "Baire", "Airpirates", "Bunker",
	"Abel", "Aero", "Amnesia", "April", "Arch",
	"Arena", "Arena2", "Arena3", "Argy", "Ash",
	"B2B", "Belltower", "BigFalls", "Biologic", "Blade",
	"Blox", "Boxed", "Bridge", "Cambodia", "Campeche",
	"Changeling", "Cobra", "CrackedBoot", "Crucifix", "Daybreak",
	"Death", "Desert", "DesertWind", "Division", "Dorothy",
	"Dropdown", "Dusk", "Equinox", "Erbium", "Factory",
	"Feast", "Flashback", "Flute", "Fortress", "Guardian",
	"HH", "IceBeam", "Industrial", "Island2k5", "Jungle",
	"Kampf", "Krab", "Lagrange", "Lanubya", "Laos",
	"Leaf", "Mayapan", "Messner", "MFM", "Moonshine",
	"Mossy", "Motheaten", "MrSnowman", "Muygen", "Niall",
	"Nuclear", "Outpost", "Prison", "Raspberry", "RatCave",
	"Rescue", "Rise", "Rok", "Rotten", "RR",
	"Rubik", "Ruins", "Run", "Shau", "Snakebite",
	"Star", "Steel", "Tower", "Triumph", "TropicCave",
	"Unlim", "Veoto", "Void", "Voland", "Vortex",
	"Warlock", "Wretch", "X", "Zajacz",
]

const MODE_NAMES := [
	"Deathmatch", "Teammatch", "Capture the Flag",
	"Infiltration", "Hold the Flag", "Rambomatch", "Pointmatch",
	"Domination", "Battle Royale", "Gun Game",
]

## #256: the full weapon roster in player.gd's table order (12 primaries,
## then 4 secondaries). Host weapon bans and their UI render in this order.
const WEAPON_NAMES := [
	"Deagles", "MP5", "AK-74", "Steyr AUG", "Spas-12", "Ruger 77",
	"M79", "Barrett", "Minimi", "Minigun", "Flamethrower", "Rambo Bow",
	"USSOCOM", "Knife", "Chainsaw", "LAW",
]
