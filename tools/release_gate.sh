#!/usr/bin/env bash
# Soldat Reborn release gate — the "is this shippable?" run.
#   tools/release_gate.sh [--quick] [--out DIR]
# Stages (any FAIL makes the exit code non-zero):
#   A static   map audit (0 problems), nav graph per map, version strings agree
#   B boot     main / menu / map editor scenes load with zero script errors
#   C net      dedicated server + client smoke (CTF + DM), listen-host smoke,
#              zero RPC/node errors on either side
#   D modes    every game mode (DM..GG) on 3 maps with bots-vs-bots: kills,
#              objective scoring where the mode has one, no script errors
#   R rules    Realistic / Survival / Advance toggles (autopilot, menu path)
#   F features scripted SP run: gestures, all weapon slots, nades, throw,
#              extreme mods, live bot-count changes, vote, GIF recorder, /kill
#   N nav      every map in CTF: each team can path spawn -> enemy flag -> home
#              (known exceptions allowed: NAV_KNOWN_BROKEN)
#   E sweep    every map in CTF: grabs / captures / falls / anti-stuck frees
#   C extra: --net "m0 m3 m9" runs a dedicated server + autopiloted client per mode
#   M modes    (opt-in: --only M --msweep MODE:FROM:TO, then --only M --mode-verdict)
#              every map in INF / HTF / DOM: errors, falls, objective activity
# --quick skips E (CI-sized). Logs + summary land in build/gate/ (or --out).
# Piecewise runs (each piece fits a short shell budget; summary accumulates):
#   --only "A B"   run just these stages      --modes "0 1 2"  subset for D
#   --net "ctf dm host"  subset for C          --sweep FROM:TO  map range for E
#   --keep         append to an existing summary instead of starting fresh
#   --final        only print the verdict for the accumulated summary
set -uo pipefail
cd "$(dirname "$0")/.."
G="${GODOT_BIN:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}"
QUICK=0; OUT="build/gate"; ONLY="A B N C D R F E"; MODESEL="0 1 2 3 4 5 6 7 8 9"
NETSEL="ctf dm two fill ranked friends respawn killcam drive rejoin relay host listen lan soak m3 m7 m9"; SWEEP=""; FSEL=""; KEEP=0; FINAL=0; MSWEEP=""; MVERDICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1;; --out) OUT="$2"; shift;; --only) ONLY="$2"; shift;;
    --modes) MODESEL="$2"; shift;; --net) NETSEL="$2"; shift;; --ftests) FSEL="$2"; shift;;
    --sweep) SWEEP="$2"; shift;;
    --msweep) MSWEEP="$2"; shift;; --mode-verdict) MVERDICT=1;; --keep) KEEP=1;; --final) FINAL=1;;
  esac; shift
done
mkdir -p "$OUT"
fon() { [ -z "$FSEL" ] || [[ " $FSEL " == *" $1 "* ]]; }
SUM="$OUT/summary.txt"; [ $KEEP = 1 ] || [ $FINAL = 1 ] || : > "$SUM"
FAILS=0
has() { case " $ONLY " in *" $1 "*) return 0;; esac; return 1; }
if [ $FINAL = 1 ]; then
  n=$(grep -c '^FAIL' "$SUM"); p=$(grep -c '^PASS' "$SUM")
  echo "== $( [ "$n" = 0 ] && echo 'GATE PASSED' || echo "GATE FAILED ($n)" )  pass=$p  $(date -Is)" | tee -a "$SUM"
  exit "$n"
fi
ERR_RE='FEATURE-FAIL|No multiplayer peer is assigned|SCRIPT ERROR|Parse Error|Cannot load|Identifier not found|Invalid call|Cannot infer|Node not found|Invalid packet|Failed to get path|previously freed|Invalid access|Invalid get|Invalid set|Invalid assignment|Nonexistent function|out of bounds|Lambda capture|while flushing queries'
pass() { echo "PASS  $1" | tee -a "$SUM"; }
fail() { echo "FAIL  $1" | tee -a "$SUM"; FAILS=$((FAILS+1)); }
info() { echo "INFO  $1" | tee -a "$SUM"; }
errs() { grep -cE "$ERR_RE" "$1" 2>/dev/null || true; }

echo "== Release gate $(date -Is)  godot=$G" | tee -a "$SUM"

# Hermetic runs: every Godot launch starts from default settings / controls
# (tests toggle mods, bot counts, loadouts and some of them save), and this
# machine's own files are restored when the gate exits.
UD="${GODOT_USER_DIR:-$HOME/.local/share/godot/app_userdata/Soldat Reborn}"
BAK="$OUT/.userbak"; mkdir -p "$BAK"
for f in settings.cfg controls.cfg; do [ -f "$UD/$f" ] && cp "$UD/$f" "$BAK/$f"; done
restore_user() { for f in settings.cfg controls.cfg; do rm -f "$UD/$f"; [ -f "$BAK/$f" ] && cp "$BAK/$f" "$UD/$f"; done; rm -rf "$BAK"; }
trap restore_user EXIT
trap "exit 143" TERM INT
REAL_G="$G"; G="$OUT/.godot_fresh.sh"
printf '#!/bin/bash\nrm -f "%s/settings.cfg" "%s/controls.cfg"\nexec "%s" "$@"\n' "$UD" "$UD" "$REAL_G" > "$G"; chmod +x "$G"

# ── A static ────────────────────────────────────────────────────────────────
NMAPS=$(ls assets/maps/*.json | wc -l)
if has A; then
python3 tools/map_audit.py > "$OUT/audit.log" 2>&1
if grep -q "^0 / " "$OUT/audit.log"; then pass "A map audit: $(tail -1 "$OUT/audit.log")"; else fail "A map audit: $(tail -1 "$OUT/audit.log")"; fi
NMAPS=$(ls assets/maps/*.json | wc -l); NNAV=$(ls assets/nav/*.json | wc -l)
if [ "$NNAV" -ge $((NMAPS + 3)) ]; then pass "A nav graphs: $NNAV for $NMAPS classic + 3 built-in maps"; else fail "A nav graphs: $NNAV nav files for $NMAPS+3 maps"; fi
V=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
AV=$(sed -n 's/^version\/name="\(.*\)"/\1/p' export_presets.cfg)
WV=$(sed -n 's/^application\/file_version="\(.*\)"/\1/p' export_presets.cfg)
CV=$(grep -m1 -oE '^## \[[0-9.]+\]' CHANGELOG.md | tr -d '#[] ')
if [ "$V" = "$AV" ] && [ "$WV" = "$V.0" ] && [ "$CV" = "$V" ]; then pass "A versions agree: $V (android $AV, windows $WV, changelog $CV)"; else fail "A versions: project=$V android=$AV windows=$WV changelog=$CV"; fi
if [ "$(grep -c 'include_filter="\*.poa, \*.json' export_presets.cfg)" -ge 2 ]; then pass "A exports ship map JSON (Windows + Android)"; else fail "A export include_filter missing *.json"; fi

fi

# ── B boot ──────────────────────────────────────────────────────────────────
has B && for sc in main menu map_editor; do
  timeout 90 "$G" --headless --quit-after 700 "res://scenes/$sc.tscn" > "$OUT/boot_$sc.log" 2>&1
  n=$(errs "$OUT/boot_$sc.log")
  if [ "$n" = "0" ]; then pass "B boot $sc.tscn"; else fail "B boot $sc.tscn: $n error lines"; fi
done

# ── N nav reachability ──────────────────────────────────────────────────────
NAV_KNOWN_BROKEN=""   # every CTF route works; add a map name here only with a reason
if has N; then
  timeout 175 "$G" --headless -s tools/nav_check.gd > "$OUT/navcheck.log" 2>&1
  line=$(grep -m1 NAVCHECK "$OUT/navcheck.log")
  unknown=$(grep '^map' "$OUT/navcheck.log" | awk '{print $3}' | grep -vwE "${NAV_KNOWN_BROKEN:+$(echo $NAV_KNOWN_BROKEN | tr ' ' '|')}${NAV_KNOWN_BROKEN:-^$}" | tr '\n' ' ')
  if [ -n "$line" ] && [ -z "$unknown" ] && [ "$(errs "$OUT/navcheck.log")" = "0" ]; then pass "N nav routes: $line (known: $NAV_KNOWN_BROKEN)"; else fail "N nav routes: ${line:-no result} new broken: $unknown"; fi
fi

# ── C net ───────────────────────────────────────────────────────────────────
netcase() { # label map mode [extra client flags]
  local L="$1" port=$((7700 + RANDOM % 200))
  timeout 95 "$G" --headless -- --dedicated --port $port --map "$2" --mode "$3" > "$OUT/net_${L}_server.log" 2>&1 &
  local spid=$!
  # Wait for the server to actually listen (boot time varies with CPU load).
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_${L}_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 4
  timeout 70 "$G" --headless -- --smoke-botfire --port $port ${4:-} > "$OUT/net_${L}_client.log" 2>&1
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  local line; line=$(grep -m1 SMOKE-BOTFIRE "$OUT/net_${L}_client.log")
  local ce se; ce=$(errs "$OUT/net_${L}_client.log"); se=$(errs "$OUT/net_${L}_server.log")
  local shots; shots=$(echo "$line" | sed -n 's/.*bot_shots_seen=\([0-9]*\).*/\1/p')
  local gm; gm=$(echo "$line" | sed -n 's/.* gm=\([0-9]*\).*/\1/p')
  if [ -n "$line" ] && [ "${shots:-0}" -gt 0 ] && [ "$ce" = "0" ] && [ "$se" = "0" ] && [ "${gm:-$3}" = "$3" ]; then
    pass "C net $L: $line"
  else
    fail "C net $L: '${line:-no SMOKE line}' client_errs=$ce server_errs=$se"
  fi
}
if has C; then
case " $NETSEL " in *" ctf "*) netcase ctf_arena 18 2;; esac
case " $NETSEL " in *" dm "*) netcase dm_ascent 0 0;; esac
# Opt-in per-mode cases: --net "m3 m7" = dedicated server on map 19 in mode N.
for tok in $NETSEL; do case "$tok" in m[0-9]) netcase "mode${tok#m}" 19 "${tok#m}" --smoke-auto;; esac; done
case " $NETSEL " in *" two "*)
  # Two clients on one dedicated server: the second joins mid-match; every
  # body must keep its exact node name and no RPC may miss its node.
  port=$((7700 + RANDOM % 200))
  timeout 100 "$G" --headless -- --dedicated --port $port --map 19 --mode 2 > "$OUT/net_two_server.log" 2>&1 &
  spid=$!
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_two_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 3
  timeout 80 "$G" --headless -- --smoke-botfire --port $port --cos-head=kap --cos-skin=dark > "$OUT/net_two_c1.log" 2>&1 &
  c1=$!
  sleep 3
  timeout 70 "$G" --headless -- --smoke-join --port $port > "$OUT/net_two_c2.log" 2>&1
  wait $c1 2>/dev/null; wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_two_server.log") + $(errs "$OUT/net_two_c1.log") + $(errs "$OUT/net_two_c2.log") ))
  names=$(grep -m1 "SMOKE-JOIN-PLAYERS" "$OUT/net_two_c2.log")
  heads=$(grep -m1 "SMOKE-JOIN-HEADS" "$OUT/net_two_c2.log")
  if grep -q "players=2" "$OUT/net_two_c2.log" && [ "$e" = "0" ] && ! echo "$names" | grep -q "@" && echo "$heads" | grep -q '"kap/dark"' && grep -qE "SMOKE-JOIN-BOTLOOK keys=(9|1[0-9])" "$OUT/net_two_c2.log"; then
    pass "C net two clients: $names $heads errors=0"
  else
    fail "C net two clients: '$(grep -m1 SMOKE-JOIN "$OUT/net_two_c2.log")' $names $heads errors=$e"
  fi
;; esac
case " $NETSEL " in *" fill "*)
  # Bot fill: a --fill=4 server keeps 4 soldiers; bots step aside as two
  # players join and come back when they leave. Teams stay even.
  port=$((7700 + RANDOM % 200))
  timeout 90 "$G" --headless -- --dedicated --fill=4 --port $port --map 19 --mode 2 > "$OUT/net_fill_server.log" 2>&1 &
  spid=$!
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_fill_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 3
  timeout 40 "$G" --headless -- --smoke-join --port $port --smoke-secs=20 > "$OUT/net_fill_c1.log" 2>&1 &
  c1=$!
  sleep 6
  timeout 30 "$G" --headless -- --smoke-join --port $port --smoke-secs=8 > "$OUT/net_fill_c2.log" 2>&1
  wait $c1 2>/dev/null
  for _ in $(seq 1 30); do grep -q "FILL humans=0" "$OUT/net_fill_server.log" && break; sleep 0.5; done
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_fill_server.log") + $(errs "$OUT/net_fill_c1.log") + $(errs "$OUT/net_fill_c2.log") ))
  seq=$(grep -o "FILL humans=[0-9]* bots=[0-9]* blue=[0-9]* red=[0-9]*" "$OUT/net_fill_server.log" | sed 's/FILL //' | tr '\n' ';')
  if echo "$seq" | grep -q "humans=2 bots=2 blue=2 red=2" && echo "$seq" | grep -q "humans=0 bots=4" && [ "$e" = "0" ]; then
    pass "C net bot fill: $seq"
  else
    fail "C net bot fill: '$seq' errors=$e"
  fi
;; esac
case " $NETSEL " in *" ranked "*)
  # Leaderboard: the host's ranked reporter -> master /report -> /leaderboard.
  RB="../server/master-server/dist/soldat-master-linux-amd64"
  rport=$((8300 + RANDOM % 400)); rdir=$(mktemp -d)
  SOLDAT_DATA_DIR="$rdir" timeout 150 "$RB" -port $rport > "$OUT/net_ranked_master.log" 2>&1 &
  rpid=$!; sleep 1
  timeout 50 "$G" --headless -s tools/ranked_test.gd -- --master=http://127.0.0.1:$rport > "$OUT/net_ranked.log" 2>&1
  timeout 60 "$G" --headless --fixed-fps 60 -s tools/online_panels_test.gd -- --master=http://127.0.0.1:$rport > "$OUT/net_panels.log" 2>&1
  pline=$(grep -m1 "PANELS-TEST" "$OUT/net_panels.log")
  if echo "$pline" | grep -q "PANELS-TEST ok" && [ "$(errs "$OUT/net_panels.log")" = "0" ]; then pass "C net leaderboard + map library screens: $pline"; else fail "C net leaderboard + map library screens: '${pline:-no result}' errors=$(errs "$OUT/net_panels.log")"; fi
  # End to end like the official server: dedicated + --register, a brand-new
  # player (no settings file yet) joins, dies, leaves -> on the leaderboard.
  port=$((7700 + RANDOM % 200))
  timeout 60 "$G" --headless -- --dedicated --port $port --map 19 --mode 2 --fill=2 --register http://127.0.0.1:$rport > "$OUT/net_ranked_server.log" 2>&1 &
  spid=$!
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_ranked_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 2
  timeout 40 "$G" --headless -- --smoke-join --port $port --smoke-secs=12 --smoke-die > "$OUT/net_ranked_client.log" 2>&1
  sleep 4; kill $spid 2>/dev/null; wait $spid 2>/dev/null
  board=$(curl -s "http://127.0.0.1:$rport/leaderboard")
  if echo "$board" | grep -q '"total":3' && grep -q "RANKED queued" "$OUT/net_ranked_server.log" && [ "$(errs "$OUT/net_ranked_server.log")" = "0" ]; then
    pass "C net leaderboard end to end (new player, real server): $(grep -m1 'RANKED queued' "$OUT/net_ranked_server.log" | cut -c1-90)"
  else
    fail "C net leaderboard end to end: board=$board $(grep -m1 RANKED "$OUT/net_ranked_server.log")"
  fi
  timeout 60 "$G" --headless -s tools/matchmaking_test.gd -- --master=http://127.0.0.1:$rport > "$OUT/net_matchmaking.log" 2>&1
  mline=$(grep -m1 "MATCHMAKING-TEST" "$OUT/net_matchmaking.log")
  if echo "$mline" | grep -q "MATCHMAKING-TEST ok" && [ "$(errs "$OUT/net_matchmaking.log")" = "0" ]; then pass "C net skill matchmaking: $(echo "$mline" | cut -c1-120)"; else fail "C net skill matchmaking: '${mline:-no result}' errors=$(errs "$OUT/net_matchmaking.log")"; fi
  kill $rpid 2>/dev/null; wait $rpid 2>/dev/null
  line=$(grep -m1 "RANKED-TEST" "$OUT/net_ranked.log")
  if echo "$line" | grep -q "RANKED-TEST ok" && [ "$(errs "$OUT/net_ranked.log")" = "0" ]; then pass "C net leaderboard: $line"; else fail "C net leaderboard: '${line:-no result}' errors=$(errs "$OUT/net_ranked.log")"; fi
;; esac
case " $NETSEL " in *" friends "*)
  # Clan tag + friends: a tagged player shows up by name in the master's game
  # list, and another player who meets them has them on their recent list.
  RB="../server/master-server/dist/soldat-master-linux-amd64"
  fport=$((8300 + RANDOM % 400)); port=$((7700 + RANDOM % 200))
  SOLDAT_DATA_DIR="$(mktemp -d)" timeout 80 "$RB" -port $fport > "$OUT/net_friends_master.log" 2>&1 &
  fpid=$!; sleep 1
  timeout 75 "$G" --headless -- --dedicated --port $port --map 19 --mode 2 --fill=2 --register http://127.0.0.1:$fport > "$OUT/net_friends_server.log" 2>&1 &
  spid=$!
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_friends_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 2
  timeout 50 "$G" --headless -- --smoke-join --port $port --smoke-secs=30 --clan=abc > "$OUT/net_friends_c1.log" 2>&1 &
  c1=$!
  sleep 6
  timeout 40 "$G" --headless -- --smoke-join --port $port --smoke-secs=14 > "$OUT/net_friends_c2.log" 2>&1
  sleep 1; list=$(curl -s "http://127.0.0.1:$fport/list")
  wait $c1 2>/dev/null; kill $spid $fpid 2>/dev/null; wait $spid $fpid 2>/dev/null
  rec=$(grep -m1 "SMOKE-RECENT" "$OUT/net_friends_c2.log")
  e=$(( $(errs "$OUT/net_friends_server.log") + $(errs "$OUT/net_friends_c1.log") + $(errs "$OUT/net_friends_c2.log") ))
  if echo "$list" | grep -q '«ABC» Player' && echo "$rec" | grep -q '«ABC» Player' && [ "$e" = "0" ]; then
    pass "C net clan tag + friends: listed $(echo "$list" | grep -o '"names":\[[^]]*\]') | $rec"
  else
    fail "C net clan tag + friends: list=$(echo "$list" | head -c 300) recent='$rec' errors=$e"
  fi
;; esac
case " $NETSEL " in *" relay "*)
  # Host and client both go through the WebSocket relay on the master server.
  RB="../server/master-server/dist/soldat-master-linux-amd64"
  if [ -x "$RB" ]; then
    rport=$((8300 + RANDOM % 400))
    SOLDAT_DATA_DIR="$(mktemp -d)" timeout 70 "$RB" -port $rport > "$OUT/net_relay_server.log" 2>&1 &
    rpid=$!; sleep 1
    cf="$OUT/relay_code.txt"; rm -f "$cf"
    timeout 60 "$G" --headless -- --smoke-host --relay-host=http://127.0.0.1:$rport --code-file="$cf" --smoke-secs=28 > "$OUT/net_relay_host.log" 2>&1 &
    hpid=$!
    for _ in $(seq 1 40); do [ -s "$cf" ] && break; sleep 0.5; done
    sleep 3
    timeout 40 "$G" --headless -- --smoke-join --relay-join=http://127.0.0.1:$rport --code-file="$cf" --smoke-secs=12 > "$OUT/net_relay_client.log" 2>&1
    wait $hpid 2>/dev/null; kill $rpid 2>/dev/null; wait $rpid 2>/dev/null
    e=$(( $(errs "$OUT/net_relay_host.log") + $(errs "$OUT/net_relay_client.log") ))
    line=$(grep -m1 "SMOKE-JOIN " "$OUT/net_relay_client.log")
    if echo "$line" | grep -q "players=2" && [ "$e" = "0" ]; then pass "C net relay: code $(cat "$cf" 2>/dev/null) | $line"; else fail "C net relay: '${line:-no result}' errors=$e"; fi
  else
    fail "C net relay: relay binary missing ($RB)"
  fi
;; esac
case " $NETSEL " in *" rejoin "*)
  # A client drops hard; the menu's REJOIN countdown brings it back under the
  # same name and team (the host retires the stale connection).
  port=$((7700 + RANDOM % 200))
  timeout 60 "$G" --headless -- --dedicated --port $port --map 2 --mode 2 > "$OUT/net_rejoin_server.log" 2>&1 &
  spid=$!
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_rejoin_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 3
  timeout 45 "$G" --headless -- --smoke-rejoin --port $port > "$OUT/net_rejoin_client.log" 2>&1
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_rejoin_server.log") + $(errs "$OUT/net_rejoin_client.log") ))
  line=$(grep "SMOKE-REJOIN" "$OUT/net_rejoin_client.log" | tail -1)
  if echo "$line" | grep -q "SMOKE-REJOIN ok" && [ "$e" = "0" ]; then pass "C net rejoin: $line"; else fail "C net rejoin: '${line:-no result}' errors=$e"; fi
;; esac
case " $NETSEL " in *" drive "*)
  # A client gets into a buggy (the host grants the seat) and drives it.
  port=$((7700 + RANDOM % 200))
  timeout 60 "$G" --headless -- --dedicated --port $port --map 2 --mode 0 > "$OUT/net_drive_server.log" 2>&1 &
  spid=$!
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_drive_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 3
  timeout 40 "$G" --headless -- --smoke-join --port $port --smoke-secs=12 --smoke-drive > "$OUT/net_drive_client.log" 2>&1
  wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_drive_server.log") + $(errs "$OUT/net_drive_client.log") ))
  line=$(grep -m1 "SMOKE-DRIVE" "$OUT/net_drive_client.log")
  mv=$(echo "$line" | sed -n 's/.*moved=\(-\?[0-9]*\).*/\1/p')
  if echo "$line" | grep -q "seat=0" && [ "${mv:-0}" -gt 150 ] && [ "$e" = "0" ]; then
    pass "C net buggy: $line"
  else
    fail "C net buggy: '${line:-no result}' errors=$e"
  fi
;; esac
case " $NETSEL " in *" respawn "*)
  # A client kills itself at 4 s (DM, few bots near spawn): it must come back
  # as the exact same node name with no RPC errors anywhere.
  port=$((7700 + RANDOM % 200))
  timeout 60 "$G" --headless -- --dedicated --port $port --map 0 --mode 0 > "$OUT/net_respawn_server.log" 2>&1 &
  spid=$!
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_respawn_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 3
  timeout 40 "$G" --headless -- --smoke-join --port $port --smoke-secs=12 --smoke-die > "$OUT/net_respawn_client.log" 2>&1
  wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_respawn_server.log") + $(errs "$OUT/net_respawn_client.log") ))
  after=$(grep -m1 -o "SMOKE-RESPAWNED.*after=[0-9.]*" "$OUT/net_respawn_client.log" | grep -o "after=[0-9.]*" | cut -d= -f2)
  if grep -q "SMOKE-DIE sent" "$OUT/net_respawn_client.log" && grep -q "SMOKE-RESPAWNED name=Player_" "$OUT/net_respawn_client.log" \
      && [ -n "$after" ] && awk "BEGIN{exit !($after <= 3.2)}" \
      && ! grep -m1 "SMOKE-JOIN-PLAYERS" "$OUT/net_respawn_client.log" | grep -q "@" && [ "$e" = "0" ]; then
    pass "C net client death + respawn: $(grep -m1 SMOKE-RESPAWNED "$OUT/net_respawn_client.log")"
  else
    fail "C net client death + respawn: $(grep -hE 'SMOKE-(DIE|RESPAWNED|JOIN-LOCAL|JOIN-PLAYERS)' "$OUT/net_respawn_client.log" | tr '\n' ' ') errors=$e"
  fi
;; esac
case " $NETSEL " in *" killcam "*)
  # A bot "kills" the client: its kill cam rewind plays (~4.3 s) and the host
  # holds the respawn until the client says it's done; a self-kill (case
  # "respawn") must still come back on the normal 2 s timer.
  port=$((7700 + RANDOM % 200))
  timeout 60 "$G" --headless -- --dedicated --port $port --map 0 --mode 0 > "$OUT/net_killcam_server.log" 2>&1 &
  spid=$!
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_killcam_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 3
  timeout 40 "$G" --headless -- --smoke-join --port $port --smoke-secs=14 --smoke-die --smoke-die-by-bot > "$OUT/net_killcam_client.log" 2>&1
  wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_killcam_server.log") + $(errs "$OUT/net_killcam_client.log") ))
  after=$(grep -m1 -o "SMOKE-RESPAWNED.*after=[0-9.]*" "$OUT/net_killcam_client.log" | grep -o "after=[0-9.]*" | cut -d= -f2)
  if grep "SMOKE-DIE sent" "$OUT/net_killcam_client.log" | grep -v "killer=Player_" | grep -q "rewind=true"; [ $? = 0 ] && grep -q "SMOKE-DIE sent" "$OUT/net_killcam_client.log" && grep -q "KILLCAM-REWIND end skipped=false" "$OUT/net_killcam_client.log" \
      && [ -n "$after" ] && awk "BEGIN{exit !($after >= 3.6 && $after <= 6.0)}" && [ "$e" = "0" ]; then
    pass "C net kill cam rewind holds the respawn: respawned after ${after}s"
  else
    fail "C net kill cam: $(grep -hE 'SMOKE-(DIE|RESPAWNED)|KILLCAM-REWIND' "$OUT/net_killcam_client.log" | tr '\n' ' ') errors=$e"
  fi
;; esac
case " $NETSEL " in *" host "*)
timeout 60 "$G" --headless -- --smoke-host > "$OUT/net_host.log" 2>&1
if grep -q "SMOKE-HOST" "$OUT/net_host.log" && [ "$(errs "$OUT/net_host.log")" = "0" ]; then pass "C net listen host: $(grep -m1 SMOKE-HOST "$OUT/net_host.log")"; else fail "C net listen host ($(errs "$OUT/net_host.log") errors)"; fi
;; esac
case " $NETSEL " in *" listen "*)
  # Listen host (a player hosting from the menu) + an autopiloted client.
  port=$((7700 + RANDOM % 200))
  timeout 60 "$G" --headless -- --smoke-host --port $port --smoke-secs=32 > "$OUT/net_listen_host.log" 2>&1 &
  hpid=$!
  sleep 7
  timeout 45 "$G" --headless -- --smoke-join --port $port --smoke-secs=18 --smoke-auto > "$OUT/net_listen_client.log" 2>&1
  wait $hpid 2>/dev/null
  hl=$(grep -m1 SMOKE-HOST "$OUT/net_listen_host.log"); cl=$(grep -m1 '^SMOKE-JOIN ' "$OUT/net_listen_client.log")
  he=$(errs "$OUT/net_listen_host.log"); ce=$(errs "$OUT/net_listen_client.log")
  if echo "$cl" | grep -q "players=2" && [ "$he" = "0" ] && [ "$ce" = "0" ]; then pass "C net listen host + client: $hl | $cl"; else fail "C net listen host + client: '$hl' '$cl' host_errs=$he client_errs=$ce"; fi
;; esac
case " $NETSEL " in *" soak "*)
  # Two autopiloted clients (second joins late) on a CTF server for ~50 s.
  line=$(GODOT_BIN="$G" timeout 110 bash tools/mp_soak.sh 2 18 "$OUT/soak" 2>&1 | grep '^SOAK')
  if echo "$line" | grep -q "errors=0"; then pass "C net soak: $line"; else fail "C net soak: '${line:-no SOAK line}' (logs in $OUT/soak)"; fi
;; esac
case " $NETSEL " in *" lan "*)
  # LAN discovery: a dedicated host's beacon must show up in a listener.
  port=$((7700 + RANDOM % 200))
  timeout 50 "$G" --headless -- --dedicated --port $port --map 12 --mode 7 > "$OUT/net_lan_server.log" 2>&1 &
  spid=$!
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_lan_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 4   # the host is still loading the match right after it starts listening
  timeout 20 "$G" --headless -- --smoke-lan > "$OUT/net_lan_client.log" 2>&1
  timeout 20 "$G" --headless -- --smoke-query --port $port > "$OUT/net_query_client.log" 2>&1
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  line=$(grep -m1 SMOKE-LAN "$OUT/net_lan_client.log")
  if echo "$line" | grep -q ":$port " && [ "$(errs "$OUT/net_lan_client.log")" = "0" ]; then pass "C net LAN discovery: $line"; else fail "C net LAN discovery: '${line:-no SMOKE-LAN}'"; fi
  line=$(grep -m1 SMOKE-QUERY "$OUT/net_query_client.log")
  if echo "$line" | grep -Eq "ping=[0-9]+ players=0/8" && [ "$(errs "$OUT/net_query_client.log")" = "0" ]; then pass "C net server query (ping): $line"; else fail "C net server query: '${line:-no SMOKE-QUERY}'"; fi
;; esac
fi

# ── D modes ─────────────────────────────────────────────────────────────────
MODES=(DM TDM CTF INF HTF RM PM DOM BR GG)
has D && for m in $MODESEL; do
  f="$OUT/mode_$m.log"
  # Objective modes get longer rounds: a CTF run home takes 30-60 s.
  secs=60; case $m in 2|3|4|6|7) secs=120;; esac
  # --autopilot: the human player is driven with random input so player.gd
  # (jet, weapons, nades, stances, throwing) runs in every mode too.
  timeout 170 "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=$secs --from=19 --to=21 --mode=$m --autopilot --sp > "$f" 2>&1
  n=$(errs "$f"); maps=$(grep -c '^map' "$f")
  kills=$(grep '^map' "$f" | sed -n 's/.*kills=\([0-9]*\).*/\1/p' | paste -sd+ | bc)
  caps=$(grep '^map' "$f" | sed -n 's/.*caps=\([0-9]*\).*/\1/p' | paste -sd+ | bc)
  fell=$(grep '^map' "$f" | sed -n 's/.*fell=\([0-9]*\).*/\1/p' | paste -sd+ | bc)
  ok=1; why=""
  [ "$maps" = "3" ] || { ok=0; why="$why maps=$maps/3"; }
  [ "$n" = "0" ] || { ok=0; why="$why errors=$n"; }
  [ "${kills:-0}" -gt 0 ] || { ok=0; why="$why no-kills"; }
  case $m in 2|6|7) [ "${caps:-0}" -gt 0 ] || { ok=0; why="$why no-objective-score"; };; esac
  msg="D mode ${MODES[$m]}: kills=${kills:-0} objective=${caps:-0} fell=${fell:-0}"
  if [ $ok = 1 ]; then pass "$msg"; else fail "$msg —$why"; fi
done
# Bots vs bots in FFA: several distinct bot teams must have scored.
if has D && [ -f "$OUT/mode_0.log" ] && case " $MODESEL " in *" 0 "*) true;; *) false;; esac; then
fteams=$(grep '^map' "$OUT/mode_0.log" | grep -oE '10[0-9][0-9]: [1-9]' | wc -l)
if [ "$fteams" -ge 3 ]; then pass "D bots-vs-bots FFA: $fteams bot score entries > 0"; else fail "D bots-vs-bots FFA: only $fteams bot teams scored"; fi
fi

# ── R rule toggles ───────────────────────────────────────────────────────────
if has R; then
  for fl in "--realistic" "--survival" "--advance"; do
    f="$OUT/rules${fl}.log"
    timeout 60 "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=40 --from=19 --to=19 --mode=1 --sp --autopilot $fl > "$f" 2>&1
    n=$(errs "$f"); k=$(grep '^map' "$f" | sed -n 's/.*kills=\([0-9]*\).*/\1/p')
    if [ "$n" = "0" ] && [ "${k:-0}" -gt 0 ]; then pass "R rules ${fl#--}: kills=$k"; else fail "R rules ${fl#--}: kills=${k:-none} errors=$n"; fi
  done
  # Death screen clears on the next life (timed respawn and Survival round reset).
  for fl in "" "--survival"; do
    f="$OUT/respawn${fl:-_timed}.log"
    timeout 90 "$G" --headless --fixed-fps 60 -s tools/respawn_test.gd -- --mode=2 $fl > "$f" 2>&1
    line=$(grep -m1 RESPAWN-TEST "$f")
    if echo "$line" | grep -q "RESPAWN-TEST ok" && [ "$(errs "$f")" = "0" ]; then pass "R respawn: $line"; else fail "R respawn: '${line:-no result}' errors=$(errs "$f")"; fi
  done
fi

# ── F feature exercise ───────────────────────────────────────────────────────
if has F && fon features; then
  for spec in "19 1" "11 2" "7 7"; do
    set -- $spec
    f="$OUT/feature_$1_$2.log"
    timeout 60 "$G" --headless --fixed-fps 60 -s tools/feature_test.gd -- --map=$1 --mode=$2 > "$f" 2>&1
    n=$(( $(errs "$f") + $(grep -c 'ERROR: Parameter' "$f") ))
    if grep -q "FEATURE-TEST done" "$f" && [ "$n" = "0" ]; then pass "F features map $1 mode $2"; else fail "F features map $1 mode $2: $(grep -c 'FEATURE-TEST done' "$f") done, errors=$n"; fi
  done
fi

if has F && fon editor; then
  f="$OUT/editor.log"
  timeout 60 "$G" --headless --fixed-fps 60 -s tools/editor_test.gd > "$f" 2>&1
  if grep -q "EDITOR-TEST roundtrip ok" "$f" && grep -q "EDITOR-TEST undo ok" "$f" && grep -q "EDITOR-TEST playtest ok.*player=true" "$f" && [ "$(errs "$f")" = "0" ]; then
    pass "F map editor: place-all / save / reload / move / delete / undo / generate / play-test"
  else
    fail "F map editor: $(grep -h 'EDITOR-TEST' "$f" | tr '\n' ' ') errors=$(errs "$f")"
  fi
fi
# F tests run one after another; pass --ftests "grenade weapons ..." to run a
# subset (each device call has a time limit), with --keep to append.
ft() {  # key script timeout TAG label
  fon "$1" || return 0
  local f="$OUT/$1.log"
  timeout "$3" "$G" --headless --fixed-fps 60 -s "tools/$2" ${6:+-- $6} > "$f" 2>&1
  local line
  line=$(grep "$4" "$f" | tail -1)
  if echo "$line" | grep -q "$4 ok" && [ "$(errs "$f")" = "0" ]; then pass "F $5: $(echo "$line" | cut -c1-110)"; else fail "F $5: '${line:-no result}' errors=$(errs "$f")"; fi
}
if has F; then
  ft grenade grenade_test.gd 90 GRENADE-TEST "grenade cooking"
  ft training training_test.gd 90 TRAINING-TEST "training"
  ft fire fire_test.gd 100 FIRE-TEST "every primary fires"
  ft weapons weapon_test.gd 175 WEAPON-TEST "every weapon hits (player + bots)"
  ft labels label_test.gd 100 LABEL-TEST "labels / explanations"
  ft kits kit_test.gd 100 KIT-TEST "medikits / grenade kits"
  ft radio radio_test.gd 170 RADIO-TEST "team radio"
  ft vehicles vehicle_test.gd 100 VEHICLE-TEST "buggy: enter / drive / run over / gun / exit / wreck / respawn"
  ft botdrive vehicle_drive_test.gd 100 DRIVE-TEST "bots drive buggies to far-off goals"
  ft step vehicle_step_test.gd 90 STEP-TEST "buggy: no hop, rolls up a curb, stopped by a wall"
  ft teamspawn team_spawn_test.gd 90 TEAMSPAWN-TEST "team modes: each side spawns by its own flag on every map"
  ft perf perf_test.gd 90 PERF-TEST "performance: 16 bots on Abel CTF, frame time and hitches"
  ft crew vehicle_crew_test.gd 100 CREW-TEST "buggy crew: solo-fire slowdown / bot gunner boards, shoots, leaves"
  ft tank tank_test.gd 100 TANK-TEST "tank: drive / lobbed shell / armor / wreck / respawn / wide-map spawns"
  ft joincode join_code_test.gd 60 JOINCODE-TEST "join codes: round trip, typos, garbage, host shows its code"
  ft replay replay_test.gd 150 REPLAY-TEST "replays: record, save on leave, list, play back in place, seek, exit restores"
  ft tags label_overlap_test.gd 120 LABELS-TEST "pickup name tags never overlap (#185)"
  ft friends friends_test.gd 60 FRIENDS-TEST "friends list: order, online + join, stars, cap"
  ft unlock unlock_test.gd 60 UNLOCK-TEST "unlock in play: toast, equip live, kept on respawn"
  ft customize customize_test.gd 60 CUSTOMIZE-TEST "customization: locks, unlocks, network, screens"
  ft mapvote mapvote_test.gd 60 MAPVOTE-TEST "end-of-round map vote"
  ft pad pad_test.gd 60 PAD-TEST "gamepad: radio (L3 + D-pad), limbo loadout (D-pad)"
  ft gfx gfx_test.gd 60 GFX-TEST "graphics presets: terrain depth / grass / post FX / bloom / lights / shadows / caps, live switch"
  ft killcam killcam_test.gd 60 KILLCAM-TEST "kill cam: rewind w/ slow-mo, respawn waits, skip, live follow"
  ft lagcomp lagcomp_test.gd 60 LAGCOMP-TEST "lag compensation: hits where the shooter saw you, capped"
  ft quickplay quickplay_test.gd 60 QUICKPLAY-TEST "quick play: no game online -> bot match"
  ft name name_test.gd 60 NAME-TEST "name required before Training / online, easy rename"
  if fon updater; then
    # Fake GitHub: a releases/latest JSON one version ahead + a 1 MB "exe".
    ud="$OUT/updsrv"; mkdir -p "$ud"; head -c 1048576 /dev/urandom > "$ud/SoldatReborn.exe"
    uport=$((8100 + RANDOM % 400))
    printf '{"tag_name":"v99.0.0","body":"test","html_url":"x","assets":[{"name":"SoldatReborn.exe","size":1048576,"browser_download_url":"http://127.0.0.1:%d/SoldatReborn.exe"}]}' $uport > "$ud/latest.json"
    python3 -m http.server $uport --bind 127.0.0.1 --directory "$ud" > /dev/null 2>&1 &
    upid=$!; sleep 1
  fi
  ft updater updater_test.gd 60 UPDATER-TEST "auto-updater: version compare, release check, download + size check, swap script" "--update-url=http://127.0.0.1:${uport:-1}/latest.json"
  ft achievements achievement_test.gd 60 ACH-TEST "achievements: unlock once, counters, multi-kill, streak, wins"
  if fon updater; then kill $upid 2>/dev/null; wait $upid 2>/dev/null; fi
  ft sound sound_test.gd 100 SOUND-TEST "sound wiring"
fi

# ── E sweep ─────────────────────────────────────────────────────────────────
total=$((NMAPS + 3))
if [ $QUICK = 0 ] && has E && [ -n "$SWEEP" ]; then
  # Piecewise: append one map range; the verdict comes from a later "--only E" run.
  timeout 170 "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=30 --from=${SWEEP%%:*} --to=${SWEEP##*:} --mode=2 >> "$OUT/sweep.log" 2>&1
  info "E sweep chunk $SWEEP: $(grep -c '^map' "$OUT/sweep.log") maps logged so far"
elif [ $QUICK = 0 ] && has E; then
  if [ $KEEP = 0 ] || [ ! -s "$OUT/sweep.log" ]; then
    : > "$OUT/sweep.log"
    for from in $(seq 0 25 $((total - 1))); do
      to=$((from + 24))
      timeout 400 "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=30 --from=$from --to=$to --mode=2 >> "$OUT/sweep.log" 2>&1
    done
  fi
  n=$(errs "$OUT/sweep.log"); maps=$(grep -c '^map' "$OUT/sweep.log")
  sum() { grep '^map' "$OUT/sweep.log" | sed -n "s/.* $1=\([0-9]*\).*/\1/p" | paste -sd+ | bc; }
  grabs=$(sum grabs); caps=$(sum caps); kills=$(sum kills); fell=$(sum fell); unstuck=$(sum unstuck)
  zero=$(grep '^map' "$OUT/sweep.log" | grep -c 'kills=0 ')
  msg="E sweep CTF: maps=$maps/$total grabs=$grabs caps=$caps kills=$kills fell=$fell unstuck=$unstuck no-fight-maps=$zero errors=$n"
  if [ "$maps" = "$total" ] && [ "$n" = "0" ] && [ "${grabs:-0}" -ge 100 ] && [ "${caps:-0}" -ge 10 ] && [ "${fell:-0}" -le 25 ] && [ "${unstuck:-0}" -le 25 ]; then pass "$msg"; else fail "$msg"; fi
  info "E worst maps (fell/unstuck > 0):"
  grep '^map' "$OUT/sweep.log" | grep -vE 'unstuck=0 fell=0' | cut -c1-110 | tee -a "$SUM" >/dev/null
fi

# ── M all-map sweeps for other objective modes (opt-in) ─────────────────────
if has M && [ -n "$MSWEEP" ]; then
  IFS=: read -r mm mf mt <<< "$MSWEEP"
  timeout 175 "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=30 --from=$mf --to=$mt --mode=$mm >> "$OUT/msweep_$mm.log" 2>&1
  info "M sweep mode $mm chunk $mf:$mt: $(grep -c '^map' "$OUT/msweep_$mm.log") maps logged"
fi
if has M && [ $MVERDICT = 1 ]; then
  for f in "$OUT"/msweep_*.log; do
    [ -f "$f" ] || continue
    mm=$(basename "$f" .log | sed 's/msweep_//')
    n=$(errs "$f"); maps=$(grep -c '^map' "$f")
    s_() { grep '^map' "$f" | sed -n "s/.* $1=\([0-9]*\).*/\1/p" | paste -sd+ | bc; }
    msg="M mode ${MODES[$mm]:-$mm} all maps: maps=$maps grabs=$(s_ grabs) objective=$(s_ caps) kills=$(s_ kills) fell=$(s_ fell) errors=$n"
    if [ "$n" = "0" ] && [ "${maps:-0}" -ge $((NMAPS + 3)) ] && [ "$(s_ fell)" -le 25 ]; then pass "$msg"; else fail "$msg"; fi
  done
fi

if [ $KEEP = 0 ]; then
  echo "== $( [ $FAILS = 0 ] && echo 'GATE PASSED' || echo "GATE FAILED ($FAILS)" )  $(date -Is)" | tee -a "$SUM"
fi
exit $FAILS
