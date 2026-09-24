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
#   E sweep    every map in CTF: grabs / captures / falls / anti-stuck frees
# --quick skips E (CI-sized). Logs + summary land in build/gate/ (or --out).
# Piecewise runs (each piece fits a short shell budget; summary accumulates):
#   --only "A B"   run just these stages      --modes "0 1 2"  subset for D
#   --net "ctf dm host"  subset for C          --sweep FROM:TO  map range for E
#   --keep         append to an existing summary instead of starting fresh
#   --final        only print the verdict for the accumulated summary
set -uo pipefail
cd "$(dirname "$0")/.."
G="${GODOT_BIN:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}"
QUICK=0; OUT="build/gate"; ONLY="A B C D E"; MODESEL="0 1 2 3 4 5 6 7 8 9"
NETSEL="ctf dm host"; SWEEP=""; KEEP=0; FINAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1;; --out) OUT="$2"; shift;; --only) ONLY="$2"; shift;;
    --modes) MODESEL="$2"; shift;; --net) NETSEL="$2"; shift;;
    --sweep) SWEEP="$2"; shift;; --keep) KEEP=1;; --final) FINAL=1;;
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
ERR_RE='SCRIPT ERROR|Parse Error|Cannot load|Identifier not found|Invalid call|Cannot infer|Node not found|Invalid packet|Failed to get path|previously freed|Invalid access|Invalid get|Invalid set|Invalid assignment|Nonexistent function|out of bounds'
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
  timeout 170 "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=$secs --from=19 --to=21 --mode=$m > "$f" 2>&1
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

if [ $KEEP = 0 ]; then
  echo "== $( [ $FAILS = 0 ] && echo 'GATE PASSED' || echo "GATE FAILED ($FAILS)" )  $(date -Is)" | tee -a "$SUM"
fi
exit $FAILS
