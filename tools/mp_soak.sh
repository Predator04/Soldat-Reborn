#!/bin/bash
# MP soak: dedicated server + two autopiloted clients (second joins 4 s late)
# for ~50 s in one mode; prints each log's error lines and the SMOKE result.
#   bash tools/mp_soak.sh MODE [MAP] [OUTDIR]     (run from game/)
# SOAK_PORT=N picks the game port (release_gate.sh passes a free one); under
# GATE_LOAD (#293) the clients' windows stretch (net.gd _smoke_secs), so the
# timeouts here stretch with them.
set -u
MODE="${1:-2}"; MAP="${2:-18}"; OUT="${3:-build/soak}"
G="${GODOT_BIN:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}"
mkdir -p "$OUT"; P=${SOAK_PORT:-$((7600 + RANDOM % 300))}
LF=$(awk -v f="${GATE_LOAD:-1}" 'BEGIN {if (f < 1) f = 1; if (f > 4) f = 4; print f}')
T() { awk -v t="$1" -v f="$LF" 'BEGIN {printf "%d", t * f + 0.999}'; }
ERR_RE='SCRIPT ERROR|Node not found|Invalid packet|Failed to get path|previously freed|Invalid access|Invalid get|Invalid set|Invalid call|No multiplayer peer|out of bounds'
timeout $(T 120) "$G" --headless -- --dedicated --port $P --map "$MAP" --mode "$MODE" > "$OUT/s$MODE.log" 2>&1 & S=$!
# Clients start once the match is loaded ("Dedicated match ready", #293).
for ((i = 0; i < $(T 40) * 2; i++)); do grep -qE "Dedicated match ready|DEDICATED-START-FAILED" "$OUT/s$MODE.log" 2>/dev/null && break; sleep 0.5; done
timeout $(T 100) "$G" --headless -- --smoke-join --port $P --smoke-secs=50 --smoke-auto > "$OUT/a$MODE.log" 2>&1 & A=$!
sleep 4
timeout $(T 95) "$G" --headless -- --smoke-join --port $P --smoke-secs=44 --smoke-auto > "$OUT/b$MODE.log" 2>&1
wait $A; kill $S 2>/dev/null; wait $S 2>/dev/null
bad=0
for f in s a b; do
  n=$(grep -cE "$ERR_RE" "$OUT/$f$MODE.log"); bad=$((bad + n))
  echo "$f: errors=$n $(grep -m1 '^SMOKE-JOIN ' "$OUT/$f$MODE.log" | cut -c1-90)"
  grep -E "$ERR_RE" "$OUT/$f$MODE.log" | sort | uniq -c | head -4
done
echo "SOAK mode=$MODE map=$MAP errors=$bad"
