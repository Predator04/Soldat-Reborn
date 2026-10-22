extends Node
## New-player protection (#315), Main helper `_catchup`, decided by the host.
## A human who dies STREAK_MIN times in a row without scoring a kill takes
## less damage (BASE_CUT, +STEP_CUT per further death, capped at MAX_CUT =
## 20 % less = 25 % more effective health) until they score one. Damage on a
## remote human is the host's ledger (#266 `player.host_damage`), so the cut
## is applied there and the owner just sees smaller hits in `net_hit`; the
## host's own body / bots take it in `take_damage`. The owner gets a toast
## through `Main.net_catchup(pct)` when it starts or grows.
##
## Never for bots (only `bots_too`, set by the measuring tool), never in Gun
## Game (a race up a weapon ladder), never in single player (bot difficulty
## covers that; `force_sp` is for the measuring tool). Self-inflicted damage
## is never reduced. Switch: host setting `Settings.catchup` ("Catch-up for
## new players" on the Host screen, default on) / server.cfg `catchup`.

const STREAK_MIN := 3     # deaths in a row without a kill before it starts
const BASE_CUT := 0.10    # damage taken -10 % at STREAK_MIN deaths
const STEP_CUT := 0.05    # -5 % more per further death
const MAX_CUT := 0.20     # cap: -20 % = +25 % effective health

static var bots_too := false   # dev: bots count too (tools/catchup_watch.gd)
static var force_sp := false   # dev: on in single player when Settings.catchup

var main: Node
var streak := {}          # display name -> deaths in a row without a kill
var reduced_hits := 0     # damage events cut (tests / watch tool)
var reduced_dmg := 0.0    # damage removed in total
var _log := false         # --catchup-log: one CATCHUP-HIT line per cut hit (gate)


func _ready() -> void:
	_log = "--catchup-log" in OS.get_cmdline_user_args()


func enabled() -> bool:
	if Settings.game_mode == Settings.MODE_GG:
		return false
	if Net.is_networked():
		return Net.is_host() and bool(Net.rule("catchup", Settings.catchup))
	return force_sp and Settings.catchup


static func cut_for_streak(n: int) -> float:
	if n < STREAK_MIN:
		return 0.0
	return minf(MAX_CUT, BASE_CUT + STEP_CUT * float(n - STREAK_MIN))


func _eligible(s: Node) -> bool:
	return s != null and (s.get("bot_id") == null or bots_too)


## Fraction of incoming damage removed for soldier `s` right now.
func cut_for(s: Node) -> float:
	if not _eligible(s) or not enabled():
		return 0.0
	return cut_for_streak(int(streak.get(str(s.get("display_name")), 0)))


## The damage `s` actually takes from `amount` (the hit paths call this).
func scale(s: Node, amount: float, killer: String) -> float:
	if amount <= 0.0 or killer == str(s.get("display_name")):
		return amount
	var c := cut_for(s)
	if c <= 0.0:
		return amount
	reduced_hits += 1
	reduced_dmg += amount * c
	if _log:
		print("CATCHUP-HIT %s %.1f -> %.1f (-%d%%) by %s" % [str(s.get("display_name")), amount, amount * (1.0 - c), roundi(c * 100.0), killer])
	return amount * (1.0 - c)


## Kill feed hook (every peer calls Main._on_kill_scored; only the host keeps
## the ledger). victim_team < 0 = an objective line, not a death.
func on_kill(killer: String, victim: String, killer_team: int, victim_team: int) -> void:
	if victim_team < 0 or (Net.is_networked() and not Net.is_host()):
		return
	if killer != "" and killer != victim and (not Settings.is_team_mode() or killer_team != victim_team):
		streak[killer] = 0
	var n := int(streak.get(victim, 0)) + 1
	streak[victim] = n
	if enabled() and cut_for_streak(n) > cut_for_streak(n - 1):
		_tell(victim, roundi(cut_for_streak(n) * 100.0))


## Host: a human got a body (match_net._accept_client). Gate hook
## --smoke-catchup-streak=N starts every joiner N deaths in.
func on_join(pid: int, who: String) -> void:
	var n := Net._smoke_arg("--smoke-catchup-streak")
	if n == "" or not enabled():
		return
	streak[who] = int(n)
	if cut_for_streak(int(n)) > 0.0:
		print("CATCHUP seeded %s streak=%d (peer %d)" % [who, int(n), pid])
		_tell(who, roundi(cut_for_streak(int(n)) * 100.0))


func _tell(who: String, pct: int) -> void:
	var p = main.get("player")
	if p != null and is_instance_valid(p) and str(p.get("display_name")) == who:
		show_note(pct)
		return
	if not Net.is_networked():
		return
	for pid in main._peer_names.keys():
		if str(main._peer_names[pid]) == who and main.multiplayer.get_peers().has(int(pid)):
			main.rpc_id(int(pid), "net_catchup", pct)
			print("CATCHUP %s -%d%%" % [who, pct])
			return


## Owner side: the host says our catch-up level (percent less damage).
func show_note(pct: int) -> void:
	var hud = main.get("hud")
	print("CATCHUP note -%d%%" % pct)
	if pct <= 0 or hud == null or not is_instance_valid(hud) or not hud.has_method("toast"):
		return
	hud.toast(TranslationServer.translate("CATCH-UP"),
		TranslationServer.translate("you take %d%% less damage until you score a kill") % pct, Color(0.55, 0.85, 1.0))
