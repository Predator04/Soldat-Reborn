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
#   N nav      every map in CTF: each team can path spawn -> enemy flag -> home
#              (known exceptions allowed: NAV_KNOWN_BROKEN)
#   E sweep    every map in CTF: grabs / captures / falls / anti-stuck frees
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
QUICK=0; OUT="build/gate"; ONLY="A B N C D R E"; MODESEL="0 1 2 3 4 5 6 7 8 9"
NETSEL="ctf dm two respawn host"; SWEEP=""; KEEP=0; FINAL=0; MSWEEP=""; MVERDICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1;; --out) OUT="$2"; shift;; --only) ONLY="$2"; shift;;
    --modes) MODESEL="$2"; shift;; --net) NETSEL="$2"; shift;;
    --sweep) SWEEP="$2"; shift;;
    --msweep) MSWEEP="$2"; shift;; --mode-verdict) MVERDICT=1;; --keep) KEEP=1;; --final) FINAL=1;;
  esac; shift
done
mkdir -p "$OUT"
SUM="$OUT/summary.txt"; [ $KEEP = 1 ] || [ $FINAL = 1 ] || : > "$SUM"
FAILS=0
has() { case " $ONLY " in *" $1 "*) return 0;; esac; return 1; }
if [ $FINAL = 1 ]; then
  n=$(grep -c '^FAIL' "$SUM"); p=$(grep -c '^PASS' "$SUM")
  echo "== $( [ "$n" = 0 ] && echo 'GATE PASSED' || echo "GATE FAILED ($n)" )  pass=$p  $(date -Is)" | tee -a "$SUM"
  exit "$n"
fi
ERR_RE='No multiplayer peer is assigned|SCRIPT ERROR|Parse Error|Cannot load|Identifier not found|Invalid call|Cannot infer|Node not found|Invalid packet|Failed to get path|previously freed|Invalid access|Invalid get|Invalid set|Invalid assignment|Nonexistent function|out of bounds'
pass() { echo "PASS  $1" | tee -a "$SUM"; }
fail() { echo "FAIL  $1" | tee -a "$SUM"; FAILS=$((FAILS+1)); }
info() { echo "INFO  $1" | tee -a "$SUM"; }
errs() { grep -cE "$ERR_RE" "$1" 2>/dev/null || true; }

echo "== Release gate $(date -Is)  godot=$G" | tee -a "$SUM"

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
if grep -q 'include_filter="\*.poa, \*.json"' export_presets.cfg && [ "$(grep -c 'include_filter="\*.poa, \*.json"' export_presets.cfg)" -ge 2 ]; then pass "A exports ship map JSON (Windows + Android)"; else fail "A export include_filter missing *.json"; fi

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
netcase() { # label map mode
  local L="$1" port=$((7700 + RANDOM % 200))
  timeout 95 "$G" --headless -- --dedicated --port $port --map "$2" --mode "$3" > "$OUT/net_${L}_server.log" 2>&1 &
  local spid=$!
  # Wait for the server to actually listen (boot time varies with CPU load).
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_${L}_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 4
  timeout 70 "$G" --headless -- --smoke-botfire --port $port > "$OUT/net_${L}_client.log" 2>&1
  wait $spid 2>/dev/null
  local line; line=$(grep -m1 SMOKE-BOTFIRE "$OUT/net_${L}_client.log")
  local ce se; ce=$(errs "$OUT/net_${L}_client.log"); se=$(errs "$OUT/net_${L}_server.log")
  local shots; shots=$(echo "$line" | sed -n 's/.*bot_shots_seen=\([0-9]*\).*/\1/p')
  if [ -n "$line" ] && [ "${shots:-0}" -gt 0 ] && [ "$ce" = "0" ] && [ "$se" = "0" ]; then
    pass "C net $L: $line"
  else
    fail "C net $L: '${line:-no SMOKE line}' client_errs=$ce server_errs=$se"
  fi
}
if has C; then
case " $NETSEL " in *" ctf "*) netcase ctf_arena 18 2;; esac
case " $NETSEL " in *" dm "*) netcase dm_ascent 0 0;; esac
case " $NETSEL " in *" two "*)
  # Two clients on one dedicated server: the second joins mid-match; every
  # body must keep its exact node name and no RPC may miss its node.
  port=$((7700 + RANDOM % 200))
  timeout 100 "$G" --headless -- --dedicated --port $port --map 19 --mode 2 > "$OUT/net_two_server.log" 2>&1 &
  spid=$!
  for _ in $(seq 1 40); do grep -q "listening on port" "$OUT/net_two_server.log" 2>/dev/null && break; sleep 0.5; done
  sleep 3
  timeout 80 "$G" --headless -- --smoke-botfire --port $port > "$OUT/net_two_c1.log" 2>&1 &
  c1=$!
  sleep 3
  timeout 70 "$G" --headless -- --smoke-join --port $port > "$OUT/net_two_c2.log" 2>&1
  wait $c1 2>/dev/null; wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_two_server.log") + $(errs "$OUT/net_two_c1.log") + $(errs "$OUT/net_two_c2.log") ))
  names=$(grep -m1 "SMOKE-JOIN-PLAYERS" "$OUT/net_two_c2.log")
  if grep -q "players=2" "$OUT/net_two_c2.log" && [ "$e" = "0" ] && ! echo "$names" | grep -q "@"; then
    pass "C net two clients: $names errors=0"
  else
    fail "C net two clients: '$(grep -m1 SMOKE-JOIN "$OUT/net_two_c2.log")' $names errors=$e"
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
  if grep -q "SMOKE-DIE sent" "$OUT/net_respawn_client.log" && grep -q "SMOKE-JOIN-LOCAL alive=true" "$OUT/net_respawn_client.log" \
      && ! grep -m1 "SMOKE-JOIN-PLAYERS" "$OUT/net_respawn_client.log" | grep -q "@" && [ "$e" = "0" ]; then
    pass "C net client death + respawn: $(grep -m1 SMOKE-JOIN-PLAYERS "$OUT/net_respawn_client.log")"
  else
    fail "C net client death + respawn: $(grep -hE 'SMOKE-(DIE|JOIN-LOCAL|JOIN-PLAYERS)' "$OUT/net_respawn_client.log" | tr '\n' ' ') errors=$e"
  fi
;; esac
case " $NETSEL " in *" host "*)
timeout 60 "$G" --headless -- --smoke-host > "$OUT/net_host.log" 2>&1
if grep -q "SMOKE-HOST" "$OUT/net_host.log" && [ "$(errs "$OUT/net_host.log")" = "0" ]; then pass "C net listen host: $(grep -m1 SMOKE-HOST "$OUT/net_host.log")"; else fail "C net listen host ($(errs "$OUT/net_host.log") errors)"; fi
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
