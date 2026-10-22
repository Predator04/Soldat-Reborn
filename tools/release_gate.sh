#!/usr/bin/env bash
# Soldat Reborn release gate — the "is this shippable?" run.
#   tools/release_gate.sh [--quick] [--out DIR]
# Stages (any FAIL makes the exit code non-zero):
#   A static   map audit (0 problems), nav graph per map, version strings agree
#   B boot     main / menu / map editor scenes load with zero script errors
#   C net      dedicated server + client smoke (CTF + DM), listen-host smoke,
#              zero RPC/node errors on either side; dedboot = dedicated boot
#              from a never-imported checkout + busy-port failure (#278)
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
# Load-robust + isolated (#293), so several gates can share one machine:
#   - every Godot launch gets this run's own user-data dir (XDG_DATA_HOME =
#     $OUT/.userdata-<pid>-<time>, fresh settings / controls each launch,
#     removed at exit; GATE_KEEP_USERDATA=1 keeps it) and its own LAN
#     discovery port (TRACERFALL_LAN_PORT); game / master ports are picked
#     free (bind test) instead of at random.
#   - LOAD = (1-min loadavg + 1) / CPUs at the start, re-read before each
#     step (never below the start value), clamped to [1, 4]: every timeout
#     and wait-style step scales by it (T), and tests get it as GATE_LOAD for
#     their own wall-clock deadlines (tools/gate_load.gd). Measured limits
#     (perf, stall, respawn timing ...) never scale.
# SERVER_DIR=<master-server dir> (default ../server/master-server; a dir that
# holds master-server/ works too; from a git worktree the default is also
# looked up beside the main checkout).
# Piecewise runs (each piece fits a short shell budget; summary accumulates):
#   --only "A B"   run just these stages      --modes "0 1 2"  subset for D
#   --net "ctf dm host"  subset for C          --sweep FROM:TO  map range for E
#   --keep         append to an existing summary instead of starting fresh
#   --final        only print the verdict for the accumulated summary
set -uo pipefail
cd "$(dirname "$0")/.."
G="${GODOT_BIN:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}"
QUICK=0; OUT="build/gate"; ONLY="A B N C D R F E"; MODESEL="0 1 2 3 4 5 6 7 8 9"
NETSEL="ctf dm dedboot selfcheck two trust drop fill ranked friends news featured respawn killcam drive heli plane rejoin relay host listen lan soak m3 m7 m9 m2"; SWEEP=""; FSEL=""; KEEP=0; FINAL=0; MSWEEP=""; MVERDICT=0
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

# ── Load factor, free ports, master server (#293) ──────────────────────────
NPROC=$(nproc 2>/dev/null || echo 2)
_load_now() { awk -v n="$NPROC" '{f = ($1 + 1) / n; if (f < 1) f = 1; if (f > 4) f = 4; printf "%.2f", f}' /proc/loadavg 2>/dev/null || echo 1; }
LOAD0=$(_load_now)
# Current factor: the load right now, never below the start value, <= 4.
load_f() { awk -v a="$LOAD0" -v b="$(_load_now)" 'BEGIN {printf "%.2f", (b > a ? b : a)}'; }
# T SECS -> SECS scaled by the load (timeouts and waits only, never a limit).
T() { awk -v t="$1" -v f="$(load_f)" 'BEGIN {printf "%d", t * f + 0.999}'; }
# wait_log FILE REGEX SECS: poll until the line shows up (SECS scaled).
wait_log() {
  local n; n=$(( $(T "$3") * 2 ))
  for ((_w = 0; _w < n; _w++)); do grep -qE "$2" "$1" 2>/dev/null && return 0; sleep 0.5; done
  return 1
}
# wait_ready LOG: a dedicated server is listening AND has loaded its match
# (the clients used to start after a fixed "sleep 4", too short under load).
wait_ready() { wait_log "$1" "listening on port|DEDICATED-START-FAILED" 30 && wait_log "$1" "Dedicated match ready|DEDICATED-START-FAILED" 40; }
# wait_http PORT SECS: a local HTTP server (master / fake GitHub) answers
# (any status) — a fixed "sleep 1" lost the menu news fetch under load.
wait_http() {
  local n; n=$(( $(T "$2") * 4 ))
  for ((_w = 0; _w < n; _w++)); do curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$1/" && return 0; sleep 0.25; done
  return 1
}
# freeport udp|tcp: a free game port whose query port (+1) is free too / a
# free TCP port (random ports used to collide with another gate's servers).
freeport() {
  python3 -c '
import random, socket, sys
def free(p, kind):
    s = socket.socket(socket.AF_INET, kind)
    try:
        s.bind(("0.0.0.0", p))
        return True
    except OSError:
        return False
    finally:
        s.close()
for _ in range(500):
    if sys.argv[1] == "udp":
        p = random.randrange(20000, 29990)
        if free(p, socket.SOCK_DGRAM) and free(p + 1, socket.SOCK_DGRAM):
            break
    else:
        p = random.randrange(12000, 19990)
        if free(p, socket.SOCK_STREAM):
            break
print(p)' "$1"
}
# Master server checkout: SERVER_DIR (the master-server dir, or a dir that
# holds master-server/), else ../server/master-server, else (git worktree)
# the same path beside the main checkout.
_srv_dir() {
  local c cands=()
  if [ -n "${SERVER_DIR:-}" ]; then cands=("$SERVER_DIR" "$SERVER_DIR/master-server")
  else
    cands=(../server/master-server)
    local common; common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    [ -n "$common" ] && cands+=("$(dirname "$common")/../server/master-server")
  fi
  for c in "${cands[@]}"; do [ -x "$c/dist/soldat-master-linux-amd64" ] && { (cd "$c" && pwd -P); return; }; done
  echo "${cands[0]}"
}
SRV=$(_srv_dir)
RB="$SRV/dist/soldat-master-linux-amd64"
need_master() { [ -x "$RB" ] && return 0; fail "C net $1: master server binary missing ($RB) — set SERVER_DIR"; return 1; }

echo "== Release gate $(date -Is)  godot=$G  load=x$LOAD0 ($(cut -d' ' -f1 /proc/loadavg 2>/dev/null) on $NPROC CPUs)  server=$SRV" | tee -a "$SUM"
# Refresh Godot's global class cache first: a checkout pulled after a commit
# that adds a `class_name` script fails to parse every user of that class
# until it is re-imported (the cache lives in .godot/, which isn't in git).
"$G" --headless --import > "$OUT/import.log" 2>&1 || true

# Hermetic + isolated runs (#293): this gate run has its own user-data dir
# (parallel gates used to share ~/.local/share/godot/app_userdata/Soldat Reborn
# and delete / list each other's replays, settings and maps) and its own LAN
# discovery port (they heard each other's servers, and the second listener
# could not bind). Every Godot launch also starts from default settings /
# controls (tests toggle mods, bot counts, loadouts and some of them save).
# The machine's own user files are never touched.
RUN_ID="$$-$(date +%s)"
GATE_DATA="$(cd "$OUT" && pwd)/.userdata-$RUN_ID"
mkdir -p "$GATE_DATA"
UD="$GATE_DATA/godot/app_userdata/Soldat Reborn"
export XDG_DATA_HOME="$GATE_DATA"
export TRACERFALL_LAN_PORT; TRACERFALL_LAN_PORT=$(freeport udp)
export GATE_LOAD="$LOAD0"
gate_cleanup() { [ "${GATE_KEEP_USERDATA:-0}" = 1 ] || rm -rf "$GATE_DATA"; }
trap gate_cleanup EXIT
trap "exit 143" TERM INT
REAL_G="$G"; G="$OUT/.godot_fresh.sh"
cat > "$G" <<EOF
#!/bin/bash
# release_gate.sh launcher (#293): fresh settings, this run's user dir + LAN
# port, GATE_LOAD = the load factor right now (never below the gate's start).
rm -f "$UD/settings.cfg" "$UD/controls.cfg"
export XDG_DATA_HOME="$GATE_DATA" TRACERFALL_LAN_PORT="$TRACERFALL_LAN_PORT"
f=\$(awk -v n="$NPROC" -v a="$LOAD0" '{f = (\$1 + 1) / n; if (f < a) f = a; if (f < 1) f = 1; if (f > 4) f = 4; printf "%.2f", f}' /proc/loadavg 2>/dev/null)
export GATE_LOAD="\${f:-$LOAD0}"
exec "$REAL_G" "\$@"
EOF
chmod +x "$G"
info "isolation: user data $GATE_DATA, LAN discovery port $TRACERFALL_LAN_PORT"

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
# #224 itch.io upload script: butler command lines (fake butler), skips cleanly without a key / target.
il=$(python3 tools/itch/push.py --self-test 2>&1 | tail -1)
if echo "$il" | grep -q "ITCH-SELFTEST ok"; then pass "A itch push: ${il#ITCH-SELFTEST ok }"; else fail "A itch push self-test: $il"; fi

fi

# The tracked class list (.godot/global_script_class_cache.cfg) must match what
# the import just regenerated, or a non-importing checkout breaks (#275).
if has A; then
  if git diff --quiet -- .godot/global_script_class_cache.cfg 2>/dev/null; then pass "A class cache committed and current"; else fail "A .godot/global_script_class_cache.cfg changed on import — commit it (a class_name was added/removed)"; fi
fi

# ── B boot ──────────────────────────────────────────────────────────────────
has B && for sc in main menu map_editor; do
  timeout $(T 90) "$G" --headless --quit-after 700 "res://scenes/$sc.tscn" > "$OUT/boot_$sc.log" 2>&1
  n=$(errs "$OUT/boot_$sc.log")
  if [ "$n" = "0" ]; then pass "B boot $sc.tscn"; else fail "B boot $sc.tscn: $n error lines"; fi
done

# ── N nav reachability ──────────────────────────────────────────────────────
NAV_KNOWN_BROKEN=""   # every CTF route works; add a map name here only with a reason
if has N; then
  timeout $(T 330) "$G" --headless -s tools/nav_check.gd > "$OUT/navcheck.log" 2>&1
  line=$(grep -m1 NAVCHECK "$OUT/navcheck.log")
  unknown=$(grep '^map' "$OUT/navcheck.log" | awk '{print $3}' | grep -vwE "${NAV_KNOWN_BROKEN:+$(echo $NAV_KNOWN_BROKEN | tr ' ' '|')}${NAV_KNOWN_BROKEN:-^$}" | tr '\n' ' ')
  if [ -n "$line" ] && [ -z "$unknown" ] && [ "$(errs "$OUT/navcheck.log")" = "0" ]; then pass "N nav routes: $line (known: $NAV_KNOWN_BROKEN)"; else fail "N nav routes: ${line:-no result} new broken: $unknown"; fi
  # #287: the same audit with every graph built in-game (scripts/nav_builder.gd),
  # as custom / Maker / shared maps get them — must match the bake.
  timeout $(T 900) "$G" --headless -s tools/nav_check.gd -- --runtime > "$OUT/navcheck_runtime.log" 2>&1
  line=$(grep -m1 NAVCHECK "$OUT/navcheck_runtime.log")
  bad=$(grep '^map' "$OUT/navcheck_runtime.log" | awk '{print $3}' | tr '\n' ' ')
  if [ -n "$line" ] && [ -z "$bad" ] && [ "$(errs "$OUT/navcheck_runtime.log")" = "0" ]; then pass "N runtime nav routes: $line"; else fail "N runtime nav routes: ${line:-no result} broken: $bad"; fi
fi

# ── C net ───────────────────────────────────────────────────────────────────
netcase() { # label map mode [extra client flags]
  local L="$1" port=$(freeport udp)
  timeout $(T 95) "$G" --headless -- --dedicated --port $port --map "$2" --mode "$3" > "$OUT/net_${L}_server.log" 2>&1 &
  local spid=$!
  # Wait for the server to actually listen (boot time varies with CPU load).
  wait_ready "$OUT/net_${L}_server.log"
  sleep 1
  timeout $(T 70) "$G" --headless -- --smoke-botfire --port $port ${4:-} > "$OUT/net_${L}_client.log" 2>&1
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  local line; line=$(grep -m1 SMOKE-BOTFIRE "$OUT/net_${L}_client.log")
  local ce se; ce=$(errs "$OUT/net_${L}_client.log"); se=$(errs "$OUT/net_${L}_server.log")
  local shots; shots=$(echo "$line" | sed -n 's/.*bot_shots_seen=\([0-9]*\).*/\1/p')
  local gm; gm=$(echo "$line" | sed -n 's/.* gm=\([0-9]*\).*/\1/p')
  # An honest client must never trip the host's trust checks (trust_guard.gd).
  local tr; tr=$(grep -c "^TRUST " "$OUT/net_${L}_server.log" 2>/dev/null || true)
  if [ -n "$line" ] && [ "${shots:-0}" -gt 0 ] && [ "$ce" = "0" ] && [ "$se" = "0" ] && [ "${gm:-$3}" = "$3" ] && [ "${tr:-0}" = "0" ]; then
    pass "C net $L: $line"
  else
    fail "C net $L: '${line:-no SMOKE line}' client_errs=$ce server_errs=$se trust_lines=${tr:-0}"
  fi
}
# A modified client against a dedicated host: the host's trust checks must
# catch it (trust_guard.gd). trustcase KIND MAP MODE SECS EXPECT_REGEX
trustcase() {
  local K="$1" port=$(freeport udp)
  timeout $(T $(( $4 + 50 ))) "$G" --headless -- --dedicated --port $port --map "$2" --mode "$3" > "$OUT/net_trust_${K}_server.log" 2>&1 &
  local spid=$!
  wait_ready "$OUT/net_trust_${K}_server.log"
  sleep 1
  # Godmode stands still where the bots are (no autopilot) so the host's hit
  # detection keeps landing shots on it; the others run the autopilot.
  local auto="--smoke-auto"; [ "$K" = "godmode" ] && auto=""
  timeout $(T $(( $4 + 40 ))) "$G" --headless -- --smoke-botfire --port $port $auto --smoke-secs=$4 --smoke-cheat=$K > "$OUT/net_trust_${K}_client.log" 2>&1
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  # The cheater is force-killed / kicked mid-stream, so the engine may report
  # packets from it addressed to a body that is already gone (or a peer that
  # is already disconnected). Those dropped-packet lines are expected here and
  # only here; honest-client cases still count every error.
  local DROP='Node not found: "Main/Player_|Failed to get cached node from peer|Invalid packet received. Requested node was not found|Unable to send packet on channel'
  local e; e=$(( $(grep -E "$ERR_RE" "$OUT/net_trust_${K}_server.log" 2>/dev/null | grep -cvE "$DROP" || true) + $(grep -E "$ERR_RE" "$OUT/net_trust_${K}_client.log" 2>/dev/null | grep -cvE "$DROP" || true) ))
  local hit; hit=$(grep -m1 -E "$5" "$OUT/net_trust_${K}_server.log")
  if [ -n "$hit" ] && [ "$e" = "0" ]; then pass "C net trust $K: $hit"; else fail "C net trust $K: expected /$5/ errors=$e — $(grep -m3 '^TRUST' "$OUT/net_trust_${K}_server.log" | tr '\n' ' ')"; fi
}
if has C; then
case " $NETSEL " in *" ctf "*) netcase ctf_arena 18 2;; esac
case " $NETSEL " in *" dm "*) netcase dm_ascent 0 0;; esac
# Opt-in per-mode cases: --net "m3 m7" = dedicated server on map 19 in mode N.
for tok in $NETSEL; do case "$tok" in m[0-9]) netcase "mode${tok#m}" 19 "${tok#m}" --smoke-auto;; esac; done
case " $NETSEL " in *" dedboot "*)
  # #278 #285 #289 #290: dedicated server boot the way a supervisor / the
  # external self-check sees it. (1) This (imported) checkout: the first line
  # is "Dedicated server starting", "listening on port" follows within 20 s,
  # and no error line at all while it loads the match (menu.tscn is skipped
  # on a server). (2) A second server on a busy port must exit 1 within
  # seconds and say why on stdout. (3) A clean, NEVER-imported checkout of
  # HEAD (git archive: tracked files only, incl. the class cache — what a
  # pull-and-run checker has) must still START and say so; its match then
  # can't load unimported assets (preload parse errors), so those are only
  # counted: a checker must run --import after every pull.
  port=$(freeport udp); t0=$(date +%s)
  timeout $(T 60) "$G" --headless -- --dedicated --port $port --mode ctf > "$OUT/net_dedboot_server.log" 2>&1 &
  spid=$!
  wait_log "$OUT/net_dedboot_server.log" "listening on port" 30
  secs=$(( $(date +%s) - t0 ))
  wait_log "$OUT/net_dedboot_server.log" "Dedicated match ready" 40   # no error while the match loads
  timeout $(T 20) "$G" --headless -- --dedicated --port $port --mode ctf > "$OUT/net_dedboot_busy.log" 2>&1
  brc=$?
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  first=$(grep -v -e '^Godot Engine' -e '^$' "$OUT/net_dedboot_server.log" | head -1)
  se=$(errs "$OUT/net_dedboot_server.log")
  if echo "$first" | grep -q "^Dedicated server starting: " && grep -q "listening on port $port" "$OUT/net_dedboot_server.log" \
      && [ "$secs" -le "$(T 20)" ] && [ "$se" = "0" ]; then
    pass "C net dedicated boot: listening after ${secs}s, no errors ($(echo "$first" | cut -c1-60))"
  else
    fail "C net dedicated boot: first='$first' '$(grep -m1 -E 'listening|DEDICATED-START' "$OUT/net_dedboot_server.log")' after ${secs}s errors=$se"
  fi
  if [ "$brc" = "1" ] && grep -q "^DEDICATED-START-FAILED .*port $port" "$OUT/net_dedboot_busy.log" && ! grep -q "listening on port" "$OUT/net_dedboot_busy.log"; then
    pass "C net dedicated on a busy port fails fast and says so: $(grep -m1 '^DEDICATED-START-FAILED' "$OUT/net_dedboot_busy.log" | cut -c1-110)"
  else
    fail "C net dedicated on a busy port: rc=$brc '$(grep -m1 -E 'DEDICATED-START|listening' "$OUT/net_dedboot_busy.log")'"
  fi
  FT="$OUT/dedboot_tree"; rm -rf "$FT"; mkdir -p "$FT"
  git archive HEAD | tar -x -C "$FT"
  port=$(freeport udp); t0=$(date +%s)
  timeout $(T 40) "$G" --headless --path "$FT" -- --dedicated --port $port --mode ctf > "$OUT/net_dedboot_fresh.log" 2>&1 &
  spid=$!
  wait_log "$OUT/net_dedboot_fresh.log" "listening on port" 30
  secs=$(( $(date +%s) - t0 ))
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  rm -rf "$FT"
  pe=$(grep -c "Parse Error" "$OUT/net_dedboot_fresh.log" || true)
  if grep -q "listening on port $port" "$OUT/net_dedboot_fresh.log" && [ "$secs" -le "$(T 20)" ]; then
    pass "C net dedicated boot from a never-imported checkout: listening after ${secs}s (unimported-asset parse errors: $pe; checkers must --import)"
  else
    fail "C net dedicated boot from a never-imported checkout: no listening line after ${secs}s ($(grep -m1 -E 'SCRIPT ERROR|ERROR' "$OUT/net_dedboot_fresh.log"))"
  fi
;; esac
case " $NETSEL " in *" selfcheck "*)
  # The unattended self-check the owner's machine runs every 6 h
  # (tools/selfcheck.py: import, dedicated server, --smoke-join, --smoke-botfire,
  # process-tree cleanup) must pass here too — no --pull, no GitHub.
  GATE_LOAD=$(load_f) timeout $(T 400) python3 tools/selfcheck.py --godot "$REAL_G" --out "$OUT/selfcheck" > "$OUT/net_selfcheck.log" 2>&1
  src=$?
  line=$(grep -m1 "^SELFCHECK " "$OUT/net_selfcheck.log")
  if [ "$src" = "0" ] && echo "$line" | grep -q "^SELFCHECK PASS "; then
    pass "C net selfcheck (tools/selfcheck.py): $line"
  else
    fail "C net selfcheck: exit=$src '${line:-no SELFCHECK line}' $(grep -v '^selfcheck: log' "$OUT/net_selfcheck.log" | head -1 | cut -c1-160)"
  fi
;; esac
case " $NETSEL " in *" two "*)
  # Two clients on one dedicated server: the second joins mid-match; every
  # body must keep its exact node name and no RPC may miss its node.
  port=$(freeport udp)
  timeout $(T 100) "$G" --headless -- --dedicated --port $port --map 19 --mode 2 > "$OUT/net_two_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_two_server.log"
  sleep 1
  timeout $(T 80) "$G" --headless -- --smoke-botfire --port $port --cos-head=kap --cos-skin=dark > "$OUT/net_two_c1.log" 2>&1 &
  c1=$!
  # The second client starts once the host has the first one (#293: a fixed
  # 3 s head start wasn't one under load); smoke windows scale with GATE_LOAD.
  wait_log "$OUT/net_two_server.log" "FILL humans=1" 40
  timeout $(T 70) "$G" --headless -- --smoke-join --port $port > "$OUT/net_two_c2.log" 2>&1
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
  port=$(freeport udp)
  timeout $(T 120) "$G" --headless -- --dedicated --fill=4 --port $port --map 19 --mode 2 > "$OUT/net_fill_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_fill_server.log"
  sleep 1
  # #293: event-driven — the second player starts once the host counts the
  # first, and the first stays long enough to outlast the second's whole run
  # (a fixed 6 s head start + 20 s stay left them never in together under
  # load); smoke windows scale with GATE_LOAD.
  timeout $(T 70) "$G" --headless -- --smoke-join --port $port --smoke-secs=30 > "$OUT/net_fill_c1.log" 2>&1 &
  c1=$!
  wait_log "$OUT/net_fill_server.log" "FILL humans=1" 40
  timeout $(T 30) "$G" --headless -- --smoke-join --port $port --smoke-secs=8 > "$OUT/net_fill_c2.log" 2>&1
  wait $c1 2>/dev/null
  wait_log "$OUT/net_fill_server.log" "FILL humans=0" 15
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
  if need_master "leaderboard"; then
  # Leaderboard: the host's ranked reporter -> master /report -> /leaderboard.
  rport=$(freeport tcp); rdir=$(mktemp -d)
  SOLDAT_DATA_DIR="$rdir" timeout $(T 150) "$RB" -port $rport > "$OUT/net_ranked_master.log" 2>&1 &
  rpid=$!; wait_http $rport 20
  timeout $(T 50) "$G" --headless -s tools/ranked_test.gd -- --master=http://127.0.0.1:$rport > "$OUT/net_ranked.log" 2>&1
  timeout $(T 60) "$G" --headless --fixed-fps 60 -s tools/online_panels_test.gd -- --master=http://127.0.0.1:$rport > "$OUT/net_panels.log" 2>&1
  pline=$(grep -m1 "PANELS-TEST" "$OUT/net_panels.log")
  if echo "$pline" | grep -q "PANELS-TEST ok" && [ "$(errs "$OUT/net_panels.log")" = "0" ]; then pass "C net leaderboard + map library screens: $pline"; else fail "C net leaderboard + map library screens: '${pline:-no result}' errors=$(errs "$OUT/net_panels.log")"; fi
  # End to end like the official server: dedicated + --register, a brand-new
  # player (no settings file yet) joins, dies, leaves -> on the leaderboard.
  port=$(freeport udp)
  timeout $(T 60) "$G" --headless -- --dedicated --port $port --map 19 --mode 2 --fill=2 --register http://127.0.0.1:$rport > "$OUT/net_ranked_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_ranked_server.log"
  sleep 1
  timeout $(T 40) "$G" --headless -- --smoke-join --port $port --smoke-secs=12 --smoke-die > "$OUT/net_ranked_client.log" 2>&1
  sleep 4; kill $spid 2>/dev/null; wait $spid 2>/dev/null
  board=$(curl -s "http://127.0.0.1:$rport/leaderboard")
  if echo "$board" | grep -q '"total":3' && grep -q "RANKED queued" "$OUT/net_ranked_server.log" && [ "$(errs "$OUT/net_ranked_server.log")" = "0" ]; then
    pass "C net leaderboard end to end (new player, real server): $(grep -m1 'RANKED queued' "$OUT/net_ranked_server.log" | cut -c1-90)"
  else
    fail "C net leaderboard end to end: board=$board $(grep -m1 RANKED "$OUT/net_ranked_server.log")"
  fi
  timeout $(T 60) "$G" --headless -s tools/matchmaking_test.gd -- --master=http://127.0.0.1:$rport > "$OUT/net_matchmaking.log" 2>&1
  mline=$(grep -m1 "MATCHMAKING-TEST" "$OUT/net_matchmaking.log")
  if echo "$mline" | grep -q "MATCHMAKING-TEST ok" && [ "$(errs "$OUT/net_matchmaking.log")" = "0" ]; then pass "C net skill matchmaking: $(echo "$mline" | cut -c1-120)"; else fail "C net skill matchmaking: '${mline:-no result}' errors=$(errs "$OUT/net_matchmaking.log")"; fi
  kill $rpid 2>/dev/null; wait $rpid 2>/dev/null
  line=$(grep -m1 "RANKED-TEST" "$OUT/net_ranked.log")
  if echo "$line" | grep -q "RANKED-TEST ok" && [ "$(errs "$OUT/net_ranked.log")" = "0" ]; then pass "C net leaderboard: $line"; else fail "C net leaderboard: '${line:-no result}' errors=$(errs "$OUT/net_ranked.log")"; fi
  fi
;; esac
case " $NETSEL " in *" m2 "*)
  # M2 turret mount/dismount over the real client->host RPC path (#235/#254
  # regression): the mount used to recurse the host to death, the dismount
  # used to leave the host's turret occupied. SMOKE-M2 drives both packets
  # and asserts the end state came back through the host.
  port=$(freeport udp)
  timeout $(T 45) "$G" --headless -- --dedicated --port $port --map abel --mode 0 > "$OUT/net_m2_host.log" 2>&1 &
  m2pid=$!
  wait_ready "$OUT/net_m2_host.log"
  sleep 1
  timeout $(T 30) "$G" --headless -- --smoke-m2 --port $port --smoke-secs=10 > "$OUT/net_m2.log" 2>&1
  kill $m2pid 2>/dev/null; wait $m2pid 2>/dev/null
  line=$(grep -m1 "SMOKE-M2" "$OUT/net_m2.log")
  m2he=$(errs "$OUT/net_m2_host.log"); m2ce=$(errs "$OUT/net_m2.log")
  if echo "$line" | grep -q "SMOKE-M2 ok" && [ "$m2he" = "0" ] && [ "$m2ce" = "0" ]; then
    pass "C net m2 turret: $line"
  else
    fail "C net m2 turret: '${line:-no result}' host_errs=$m2he client_errs=$m2ce"
  fi
;; esac
case " $NETSEL " in *" friends "*)
  if need_master "clan tag + friends"; then
  # Clan tag + friends: a tagged player shows up by name in the master's game
  # list, and another player who meets them has them on their recent list.
  fport=$(freeport tcp); port=$(freeport udp)
  SOLDAT_DATA_DIR="$(mktemp -d)" timeout $(T 80) "$RB" -port $fport > "$OUT/net_friends_master.log" 2>&1 &
  fpid=$!; wait_http $fport 20
  timeout $(T 75) "$G" --headless -- --dedicated --port $port --map 19 --mode 2 --fill=2 --register http://127.0.0.1:$fport > "$OUT/net_friends_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_friends_server.log"
  sleep 1
  timeout $(T 50) "$G" --headless -- --smoke-join --port $port --smoke-secs=30 --clan=abc > "$OUT/net_friends_c1.log" 2>&1 &
  c1=$!
  sleep 6
  timeout $(T 40) "$G" --headless -- --smoke-join --port $port --smoke-secs=14 > "$OUT/net_friends_c2.log" 2>&1
  sleep 1; list=$(curl -s "http://127.0.0.1:$fport/list")
  wait $c1 2>/dev/null; kill $spid $fpid 2>/dev/null; wait $spid $fpid 2>/dev/null
  rec=$(grep -m1 "SMOKE-RECENT" "$OUT/net_friends_c2.log")
  e=$(( $(errs "$OUT/net_friends_server.log") + $(errs "$OUT/net_friends_c1.log") + $(errs "$OUT/net_friends_c2.log") ))
  if echo "$list" | grep -q '«ABC» Player' && echo "$rec" | grep -q '«ABC» Player' && [ "$e" = "0" ]; then
    pass "C net clan tag + friends: listed $(echo "$list" | grep -o '"names":\[[^]]*\]') | $rec"
  else
    fail "C net clan tag + friends: list=$(echo "$list" | head -c 300) recent='$rec' errors=$e"
  fi
  fi
;; esac
case " $NETSEL " in *" news "*)
  if need_master "menu news line"; then
  # #261 menu news line (+ #264 featured fallback) against a real master
  # serving news.json: shown under the version button, x hides it for good,
  # a new message shows again, expired / missing / unreachable show nothing.
  nport=$(freeport tcp); ndir=$(mktemp -d)
  SOLDAT_DATA_DIR="$ndir" SOLDAT_FEATURED_FILE="$ndir/featured.json" timeout $(T 100) "$RB" -port $nport > "$OUT/net_news_master.log" 2>&1 &
  npid=$!; wait_http $nport 20
  timeout $(T 90) "$G" --headless -s tools/news_test.gd -- --menu-news --master=http://127.0.0.1:$nport --news-file="$ndir/news.json" --featured-file="$ndir/featured.json" > "$OUT/net_news.log" 2>&1
  kill $npid 2>/dev/null; wait $npid 2>/dev/null; rm -rf "$ndir"
  line=$(grep -m1 "NEWS-TEST" "$OUT/net_news.log")
  if echo "$line" | grep -q "NEWS-TEST ok" && [ "$(errs "$OUT/net_news.log")" = "0" ]; then pass "C net menu news line (#261): $(echo "$line" | cut -c1-140)"; else fail "C net menu news line: '${line:-no result}' errors=$(errs "$OUT/net_news.log")"; fi
  fi
;; esac
case " $NETSEL " in *" featured "*)
  # #264 weekly featured server: the deploy script turns featured.json into
  # the unit's ExecStart; the dedicated server starts in that mode / map with
  # the bans; a bad entry falls back to the defaults with a log line.
  FT="$SRV/deploy/featured_test.sh"
  line=$(bash "$FT" 2>&1 | tail -3 | tr '\n' ' ')
  if echo "$line" | grep -q "FEATURED-SCRIPT-TEST ok"; then pass "C net featured: deploy ExecStart generator + weekly rotation"; else fail "C net featured script: $line"; fi
  port=$(freeport udp)
  timeout $(T 40) "$G" --headless -- --dedicated --port $port --mode ctf --mode rm --map Voland "--bans=Minigun,steyr aug,Nope" > "$OUT/net_featured_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_featured_server.log"
  sleep 1
  timeout $(T 20) "$G" --headless -- --smoke-query --port $port > "$OUT/net_featured_query.log" 2>&1
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  q=$(grep -m1 SMOKE-QUERY "$OUT/net_featured_query.log")
  e=$(( $(errs "$OUT/net_featured_server.log") + $(errs "$OUT/net_featured_query.log") ))
  if echo "$q" | grep -q "map=Voland mode=Rambomatch" && grep -q "weapon bans: Minigun, Steyr AUG" "$OUT/net_featured_server.log" && grep -q "unknown weapon 'Nope'" "$OUT/net_featured_server.log" && [ "$e" = "0" ]; then
    pass "C net featured server: $q | $(grep -m1 'weapon bans' "$OUT/net_featured_server.log")"
  else
    fail "C net featured server: '${q:-no query}' $(grep -m1 'weapon bans' "$OUT/net_featured_server.log") errors=$e"
  fi
  port=$(freeport udp)
  timeout $(T 30) "$G" --headless -- --dedicated --port $port --mode ctf --mode bogusmode --map Nowhere --bans= > "$OUT/net_featured_bad.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_featured_bad.log"
  sleep 1; kill $spid 2>/dev/null; wait $spid 2>/dev/null
  if grep -q "unknown mode 'bogusmode', keeping Capture the Flag" "$OUT/net_featured_bad.log" && grep -q "unknown map 'Nowhere'" "$OUT/net_featured_bad.log" \
      && grep -q "listening on port $port, map=.* mode=Capture the Flag" "$OUT/net_featured_bad.log" && [ "$(errs "$OUT/net_featured_bad.log")" = "0" ]; then
    pass "C net featured bad entry falls back: $(grep -m1 'listening on port' "$OUT/net_featured_bad.log")"
  else
    fail "C net featured bad entry: $(grep -hE 'Dedicated|listening' "$OUT/net_featured_bad.log" | tr '\n' ' ') errors=$(errs "$OUT/net_featured_bad.log")"
  fi
;; esac
case " $NETSEL " in *" relay "*)
  # Host and client both go through the WebSocket relay on the master server.
  if [ -x "$RB" ]; then
    rport=$(freeport tcp)
    SOLDAT_DATA_DIR="$(mktemp -d)" timeout $(T 100) "$RB" -port $rport > "$OUT/net_relay_server.log" 2>&1 &
    rpid=$!; wait_http $rport 20
    cf="$OUT/relay_code.txt"; rm -f "$cf"
    # #293: the client retries an unreachable relay (up to 6 tries, 2 s
    # apart, SMOKE-RELAY-FAIL lines), so both windows leave room for that.
    timeout $(T 80) "$G" --headless -- --smoke-host --relay-host=http://127.0.0.1:$rport --code-file="$cf" --smoke-secs=40 > "$OUT/net_relay_host.log" 2>&1 &
    hpid=$!
    for ((_w = 0; _w < $(T 20) * 2; _w++)); do [ -s "$cf" ] && break; sleep 0.5; done
    sleep 3
    timeout $(T 60) "$G" --headless -- --smoke-join --relay-join=http://127.0.0.1:$rport --code-file="$cf" --smoke-secs=26 > "$OUT/net_relay_client.log" 2>&1
    # Diagnostics for a failed join: does the master still answer a relay upgrade?
    probe=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" "http://127.0.0.1:$rport/relay")
    wait $hpid 2>/dev/null; kill $rpid 2>/dev/null; wait $rpid 2>/dev/null
    e=$(( $(errs "$OUT/net_relay_host.log") + $(errs "$OUT/net_relay_client.log") ))
    line=$(grep -m1 "SMOKE-JOIN " "$OUT/net_relay_client.log")
    if echo "$line" | grep -q "players=2" && [ "$e" = "0" ]; then pass "C net relay: code $(cat "$cf" 2>/dev/null) | $line"; else fail "C net relay: '${line:-no result}' errors=$e relay_probe=$probe $(grep -h SMOKE-RELAY-FAIL "$OUT/net_relay_client.log" | tail -2 | tr '\n' ' ')"; fi
  else
    fail "C net relay: relay binary missing ($RB) — set SERVER_DIR"
  fi
;; esac
case " $NETSEL " in *" rejoin "*)
  # A client drops hard; the menu's REJOIN countdown brings it back under the
  # same name and team (the host retires the stale connection).
  port=$(freeport udp)
  timeout $(T 60) "$G" --headless -- --dedicated --port $port --map 2 --mode 2 > "$OUT/net_rejoin_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_rejoin_server.log"
  sleep 1
  timeout $(T 45) "$G" --headless -- --smoke-rejoin --port $port > "$OUT/net_rejoin_client.log" 2>&1
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_rejoin_server.log") + $(errs "$OUT/net_rejoin_client.log") ))
  line=$(grep "SMOKE-REJOIN" "$OUT/net_rejoin_client.log" | tail -1)
  if echo "$line" | grep -q "SMOKE-REJOIN ok" && [ "$e" = "0" ]; then pass "C net rejoin: $line"; else fail "C net rejoin: '${line:-no result}' errors=$e"; fi
;; esac
case " $NETSEL " in *" drive "*)
  # A client gets into a buggy (the host grants the seat) and drives it.
  port=$(freeport udp)
  timeout $(T 60) "$G" --headless -- --dedicated --port $port --map 2 --mode 0 > "$OUT/net_drive_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_drive_server.log"
  sleep 1
  timeout $(T 40) "$G" --headless -- --smoke-join --port $port --smoke-secs=12 --smoke-drive > "$OUT/net_drive_client.log" 2>&1
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
case " $NETSEL " in *" heli "*)
  # #277: a client gets into a helicopter (the host grants the seat), spins it
  # up, climbs, flies sideways, lands and gets out; the host must have seen it
  # move (once out, the host simulates it and streams its own position back:
  # host_dist ~0 and host_rx > 0) and an honest pilot trips no trust check
  # (the client teleports to the pad inside the spawn grace; checked below with
  # every other case). Industrial (55), --fill=1: no bots once we're in.
  port=$(freeport udp)
  timeout $(T 75) "$G" --headless -- --dedicated --port $port --map 55 --mode 0 --fill=1 > "$OUT/net_heli_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_heli_server.log"
  sleep 1
  timeout $(T 50) "$G" --headless -- --smoke-join --port $port --smoke-secs=16 --smoke-heli > "$OUT/net_heli_client.log" 2>&1
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_heli_server.log") + $(errs "$OUT/net_heli_client.log") ))
  line=$(grep -m1 "SMOKE-HELI " "$OUT/net_heli_client.log")
  cl=$(echo "$line" | sed -n 's/.*climbed=\(-\?[0-9]*\).*/\1/p')
  mv=$(echo "$line" | sed -n 's/.* moved=\(-\?[0-9]*\).*/\1/p')
  hd=$(echo "$line" | sed -n 's/.*host_dist=\([0-9]*\).*/\1/p')
  rx=$(echo "$line" | sed -n 's/.*host_rx=\([0-9]*\).*/\1/p')
  tr=$(grep -c "^TRUST " "$OUT/net_heli_server.log" 2>/dev/null || true)
  if echo "$line" | grep -q "seat=0" && echo "$line" | grep -q "out=true" && [ "${cl:-0}" -gt 150 ] && [ "${mv:-0}" -gt 300 ] \
      && [ "${hd:-999}" -lt 80 ] && [ "${rx:-0}" -gt 5 ] && [ "$e" = "0" ] && [ "${tr:-0}" = "0" ]; then
    pass "C net heli: $line"
  else
    fail "C net heli: '${line:-no result}' errors=$e trust_lines=${tr:-0}"
  fi
;; esac
case " $NETSEL " in *" plane "*)
  # #291: a client gets into a plane on a classic runway (the host grants the
  # seat), takes off with real input (throttle + nose up), climbs, fires the
  # gun and drops a bomb (relayed by the host), bails out; then the host
  # simulates the empty plane and the client's replica must move smoothly
  # (jerk = frames far off the streamed velocity, turn = biggest per-frame
  # heading step). Honest pilot: no trust lines (checked with every case).
  # Industrial (55, two runways), --fill=1: no bots once we're in.
  port=$(freeport udp)
  timeout $(T 75) "$G" --headless -- --dedicated --port $port --map 55 --mode 0 --fill=1 > "$OUT/net_plane_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_plane_server.log"
  sleep 1
  timeout $(T 50) "$G" --headless -- --smoke-join --port $port --smoke-secs=18 --smoke-plane > "$OUT/net_plane_client.log" 2>&1
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_plane_server.log") + $(errs "$OUT/net_plane_client.log") ))
  fly=$(grep -m1 "SMOKE-PLANE-FLY " "$OUT/net_plane_client.log")
  line=$(grep -m1 "SMOKE-PLANE seat" "$OUT/net_plane_client.log")
  cl=$(echo "$fly" | sed -n 's/.*climbed=\(-\?[0-9]*\).*/\1/p')
  mv=$(echo "$fly" | sed -n 's/.* moved=\([0-9]*\).*/\1/p')
  bo=$(echo "$fly" | sed -n 's/.*bombs=\([0-9]*\).*/\1/p')
  ht=$(echo "$fly" | sed -n 's/.*heat=\([0-9.]*\).*/\1/p')
  rx=$(echo "$line" | sed -n 's/.*host_rx=\([0-9]*\).*/\1/p')
  rmv=$(echo "$line" | sed -n 's/.*moved_replica=\([0-9]*\).*/\1/p')
  jk=$(echo "$line" | sed -n 's/.*jerk=\([0-9]*\).*/\1/p')
  if echo "$fly" | grep -q "seat=0" && echo "$line" | grep -q "out=true" && [ "${cl:-0}" -gt 150 ] && [ "${mv:-0}" -gt 600 ] \
      && [ "${bo:-0}" -ge 1 ] && [ "${ht:-0}" != "0.00" ] && [ "${rx:-0}" -gt 10 ] && [ "${rmv:-0}" -gt 200 ] && [ "${jk:-99}" -le 2 ] && [ "$e" = "0" ]; then
    pass "C net plane: $fly | $line"
  else
    fail "C net plane: '${fly:-no flight}' '${line:-no result}' errors=$e"
  fi
;; esac
case " $NETSEL " in *" respawn "*)
  # A client kills itself at 4 s (DM, few bots near spawn): it must come back
  # as the exact same node name with no RPC errors anywhere.
  port=$(freeport udp)
  timeout $(T 60) "$G" --headless -- --dedicated --port $port --map 0 --mode 0 > "$OUT/net_respawn_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_respawn_server.log"
  sleep 1
  timeout $(T 40) "$G" --headless -- --smoke-join --port $port --smoke-secs=12 --smoke-die > "$OUT/net_respawn_client.log" 2>&1
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
case " $NETSEL " in *" trust "*)
  trustcase teleport 18 2 60 "^TRUST kick: "
  trustcase credit 18 2 20 "^TRUST kill credit stripped: Nobody_Fake"
  trustcase godmode 18 0 90 "^TRUST forced death: .*ignored damage"
;; esac
case " $NETSEL " in *" drop "*)
  # Drop the power-up (#303): the host (--smoke-bonus) gives both clients a
  # Predator; the dropper forges a drop for the watcher's soldier (ignored),
  # then drops its own with the drop_powerup key. Host + watcher must see it
  # end (with time left, so not the 30 s expiry); the watcher keeps its own.
  port=$(freeport udp)
  timeout $(T 110) "$G" --headless -- --dedicated --fill=1 --smoke-bonus=predator --port $port --map 0 --mode 0 > "$OUT/net_drop_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_drop_server.log"
  sleep 1
  timeout $(T 80) "$G" --headless -- --smoke-join --port $port --smoke-secs=34 --smoke-drop=dropper > "$OUT/net_drop_c1.log" 2>&1 &
  c1=$!
  wait_log "$OUT/net_drop_server.log" "FILL humans=1" 40
  timeout $(T 70) "$G" --headless -- --smoke-join --port $port --smoke-secs=26 --smoke-drop=watcher > "$OUT/net_drop_c2.log" 2>&1
  wait $c1 2>/dev/null; kill $spid 2>/dev/null; wait $spid 2>/dev/null
  e=$(( $(errs "$OUT/net_drop_server.log") + $(errs "$OUT/net_drop_c1.log") + $(errs "$OUT/net_drop_c2.log") ))
  hd=$(grep -m1 "^DROP-POWERUP peer .* dropped predator (host replica now '')" "$OUT/net_drop_server.log")
  hf=$(grep -m1 "^DROP-POWERUP ignored: peer" "$OUT/net_drop_server.log")
  nd=$(grep -c "^DROP-POWERUP peer" "$OUT/net_drop_server.log" || true)
  fr=$(grep -m1 "SMOKE-DROP forged-result other_kind=predator" "$OUT/net_drop_c1.log")
  dr=$(grep -m1 "SMOKE-DROP dropped .*toast='PREDATOR dropped' other_kind=predator" "$OUT/net_drop_c1.log")
  we=$(grep -m1 "SMOKE-DROP-WATCH ended" "$OUT/net_drop_c2.log")
  wl=$(echo "$we" | sed -n 's/.*left=\([0-9.]*\).*/\1/p')
  if [ -n "$hd" ] && [ -n "$hf" ] && [ "${nd:-0}" = "1" ] && [ -n "$fr" ] && [ -n "$dr" ] && echo "$we" | grep -q "own=predator" \
      && [ -n "$wl" ] && awk "BEGIN{exit !($wl >= 5)}" && [ "$e" = "0" ]; then
    pass "C net drop power-up: $hd | forged ignored | $we"
  else
    fail "C net drop power-up: host='$hd' forged='$hf' drops=$nd c1='$(grep -h 'SMOKE-DROP' "$OUT/net_drop_c1.log" | tr '\n' ' ')' c2='$we' errors=$e"
  fi
;; esac
case " $NETSEL " in *" killcam "*)
  # A bot "kills" the client: its kill cam rewind plays (~4.3 s) and the host
  # holds the respawn until the client says it's done; a self-kill (case
  # "respawn") must still come back on the normal 2 s timer.
  port=$(freeport udp)
  timeout $(T 60) "$G" --headless -- --dedicated --port $port --map 0 --mode 0 > "$OUT/net_killcam_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_killcam_server.log"
  sleep 1
  timeout $(T 40) "$G" --headless -- --smoke-join --port $port --smoke-secs=14 --smoke-die --smoke-die-by-bot > "$OUT/net_killcam_client.log" 2>&1
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
timeout $(T 60) "$G" --headless -- --smoke-host > "$OUT/net_host.log" 2>&1
if grep -q "SMOKE-HOST" "$OUT/net_host.log" && [ "$(errs "$OUT/net_host.log")" = "0" ]; then pass "C net listen host: $(grep -m1 SMOKE-HOST "$OUT/net_host.log")"; else fail "C net listen host ($(errs "$OUT/net_host.log") errors)"; fi
;; esac
case " $NETSEL " in *" listen "*)
  # Listen host (a player hosting from the menu) + an autopiloted client.
  port=$(freeport udp)
  timeout $(T 60) "$G" --headless -- --smoke-host --port $port --smoke-secs=32 > "$OUT/net_listen_host.log" 2>&1 &
  hpid=$!
  sleep 7
  timeout $(T 45) "$G" --headless -- --smoke-join --port $port --smoke-secs=18 --smoke-auto > "$OUT/net_listen_client.log" 2>&1
  wait $hpid 2>/dev/null
  hl=$(grep -m1 SMOKE-HOST "$OUT/net_listen_host.log"); cl=$(grep -m1 '^SMOKE-JOIN ' "$OUT/net_listen_client.log")
  he=$(errs "$OUT/net_listen_host.log"); ce=$(errs "$OUT/net_listen_client.log")
  if echo "$cl" | grep -q "players=2" && [ "$he" = "0" ] && [ "$ce" = "0" ]; then pass "C net listen host + client: $hl | $cl"; else fail "C net listen host + client: '$hl' '$cl' host_errs=$he client_errs=$ce"; fi
;; esac
case " $NETSEL " in *" soak "*)
  # Two autopiloted clients (second joins late) on a CTF server for ~50 s.
  line=$(GODOT_BIN="$G" SOAK_PORT=$(freeport udp) timeout $(T 140) bash tools/mp_soak.sh 2 18 "$OUT/soak" 2>&1 | grep "^SOAK")
  if echo "$line" | grep -q "errors=0"; then pass "C net soak: $line"; else fail "C net soak: '${line:-no SOAK line}' (logs in $OUT/soak)"; fi
;; esac
case " $NETSEL " in *" lan "*)
  # LAN discovery: a dedicated host's beacon must show up in a listener.
  port=$(freeport udp)
  timeout $(T 50) "$G" --headless -- --dedicated --port $port --map 12 --mode 7 > "$OUT/net_lan_server.log" 2>&1 &
  spid=$!
  wait_ready "$OUT/net_lan_server.log"
  sleep 1   # the host is still loading the match right after it starts listening
  timeout $(T 20) "$G" --headless -- --smoke-lan > "$OUT/net_lan_client.log" 2>&1
  timeout $(T 20) "$G" --headless -- --smoke-query --port $port > "$OUT/net_query_client.log" 2>&1
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
  line=$(grep -m1 SMOKE-LAN "$OUT/net_lan_client.log")
  if echo "$line" | grep -q ":$port " && [ "$(errs "$OUT/net_lan_client.log")" = "0" ]; then pass "C net LAN discovery: $line"; else fail "C net LAN discovery: '${line:-no SMOKE-LAN}'"; fi
  line=$(grep -m1 SMOKE-QUERY "$OUT/net_query_client.log")
  if echo "$line" | grep -Eq "ping=[0-9]+ players=0/8" && [ "$(errs "$OUT/net_query_client.log")" = "0" ]; then pass "C net server query (ping): $line"; else fail "C net server query: '${line:-no SMOKE-QUERY}'"; fi
;; esac
fi
# Honest clients must never trip the host's trust checks (trust_guard.gd) in
# ANY online case (the per-netcase check covers only netcase()); the trust
# cases themselves play modified clients and are excluded.
if has C; then
  # (net_drive is excluded: its harness teleports the client next to the buggy,
  # which the host rightly logs once — one move is not a strike.)
  tl=$(grep -l "^TRUST " "$OUT"/net_*server*.log 2>/dev/null | grep -v -e "/net_trust_" -e "/net_drive_" | tr '\n' ' ')
  dl=$(grep -c "^TRUST forced\|^TRUST kick" "$OUT"/net_drive_server.log 2>/dev/null || true)
  [ "${dl:-0}" = "0" ] || tl="$tl net_drive(forced/kick)"
  if [ -z "$tl" ]; then pass "C trust checks quiet for honest clients (all online cases)"; else fail "C TRUST lines from honest clients in: $tl"; fi
fi

# ── D modes ─────────────────────────────────────────────────────────────────
MODES=(DM TDM CTF INF HTF RM PM DOM BR GG)
has D && for m in $MODESEL; do
  f="$OUT/mode_$m.log"
  # Objective modes get longer rounds: a CTF run home takes 30-60 s.
  secs=60; case $m in 2|3|4|6|7) secs=120;; esac
  # --autopilot: the human player is driven with random input so player.gd
  # (jet, weapons, nades, stances, throwing) runs in every mode too.
  timeout $(T 170) "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=$secs --from=19 --to=21 --mode=$m --autopilot --sp > "$f" 2>&1
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
    timeout $(T 60) "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=40 --from=19 --to=19 --mode=1 --sp --autopilot $fl > "$f" 2>&1
    n=$(errs "$f"); k=$(grep '^map' "$f" | sed -n 's/.*kills=\([0-9]*\).*/\1/p')
    if [ "$n" = "0" ] && [ "${k:-0}" -gt 0 ]; then pass "R rules ${fl#--}: kills=$k"; else fail "R rules ${fl#--}: kills=${k:-none} errors=$n"; fi
  done
  # Death screen clears on the next life (timed respawn and Survival round reset).
  for fl in "" "--survival"; do
    f="$OUT/respawn${fl:-_timed}.log"
    timeout $(T 90) "$G" --headless --fixed-fps 60 -s tools/respawn_test.gd -- --mode=2 $fl > "$f" 2>&1
    line=$(grep -m1 RESPAWN-TEST "$f")
    if echo "$line" | grep -q "RESPAWN-TEST ok" && [ "$(errs "$f")" = "0" ]; then pass "R respawn: $line"; else fail "R respawn: '${line:-no result}' errors=$(errs "$f")"; fi
  done
fi

# ── F feature exercise ───────────────────────────────────────────────────────
if has F && fon features; then
  for spec in "19 1" "11 2" "7 7"; do
    set -- $spec
    f="$OUT/feature_$1_$2.log"
    timeout $(T 60) "$G" --headless --fixed-fps 60 -s tools/feature_test.gd -- --map=$1 --mode=$2 > "$f" 2>&1
    n=$(( $(errs "$f") + $(grep -c 'ERROR: Parameter' "$f") ))
    if grep -q "FEATURE-TEST done" "$f" && [ "$n" = "0" ]; then pass "F features map $1 mode $2"; else fail "F features map $1 mode $2: $(grep -c 'FEATURE-TEST done' "$f") done, errors=$n"; fi
  done
fi

if has F && fon editor; then
  f="$OUT/editor.log"
  timeout $(T 60) "$G" --headless --fixed-fps 60 -s tools/editor_test.gd > "$f" 2>&1
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
  ft back back_button_test.gd 180 BACK-TEST "BACK rule (Android BACK / Esc / ui_cancel): top-most overlay first on every main-menu screen, editor (Maker sheets / popups, ADVANCED PUBLISH / LEVELS / load list), play-test (pause steps -> EDIT), match pause toggle, replay viewer; never leaves or quits under a dialog"
  ft maker maker_test.gd 120 MAKER-TEST "Maker mode (#286): place / merge / select / resize / undo / redo, hazards + pads, validation, save-load round trip, PLAY at the camera + EDIT back unchanged, pad launches, spikes kill, flat node count over 3 cycles"
  ft ppickup persistent_pickup_test.gd 120 PPICKUP-TEST "map weapon pickups persist + regenerate in place (#241/#254)"
  ft community community_test.gd 90 COMMUNITY-TEST "host weapon bans (#256) + host chat commands (#257)"
  ft vreset vehicle_reset_test.gd 90 VRESET-TEST "vehicles: idle respawn home, touch resets, occupied never teleports (#259)"
  ft wedge vehicle_wedge_test.gd 240 WEDGE-TEST "vehicles: wedged buggy / tank (Ascent slot, crewed + empty, tipped) goes home with the crew out, parked ones untouched, bot drivers see the end of the road (#302), no wedge in an Ascent bot match (#299)"
  ft move movement_test.gd 90 MOVE-TEST "movement tech: tap vs held jump height, prone air fast fall (#262)"
  ft balance balance_test.gd 90 BALANCE-TEST "auto team balance at round reset, bots only (#263)"
  ft training training_test.gd 90 TRAINING-TEST "training"
  ft course movement_course_test.gd 120 COURSE-TEST "movement course: tap/hold gaps, prone drop, bunny lane, best time, settings restored (#262)"
  ft fire fire_test.gd 100 FIRE-TEST "every primary fires"
  ft weapons weapon_test.gd 175 WEAPON-TEST "every weapon hits (player + bots)"
  ft labels label_test.gd 100 LABEL-TEST "labels / explanations"
  ft kits kit_test.gd 100 KIT-TEST "medikits / grenade kits"
  ft droppu drop_powerup_test.gd 110 DROP-POWERUP-TEST "drop the power-up (#303): every kind ends at once on the drop key (state restored, HUD pill gone, toast), nothing spawns, the box keeps its respawn timer, no-op with nothing active, touch DROP only while active, controls + strings"
  ft radio radio_test.gd 170 RADIO-TEST "team radio"
  ft vehicles vehicle_test.gd 100 VEHICLE-TEST "buggy: enter / drive / run over / gun / exit / wreck / respawn"
  ft botdrive vehicle_drive_test.gd 100 DRIVE-TEST "bots drive buggies to far-off goals"
  ft step vehicle_step_test.gd 90 STEP-TEST "buggy: no hop, rolls up a curb, stopped by a wall"
  ft teamspawn team_spawn_test.gd 90 TEAMSPAWN-TEST "team modes: each side spawns by its own flag on every map"
  ft perf perf_test.gd 90 PERF-TEST "performance: 16 bots on Abel CTF, frame time and hitches"
  ft crew vehicle_crew_test.gd 100 CREW-TEST "buggy crew: solo-fire slowdown / bot gunner boards, shoots, leaves"
  ft tank tank_test.gd 100 TANK-TEST "tank: drive / lobbed shell / armor / wreck / respawn / wide-map spawns"
  ft plane plane_test.gd 200 PLANE-TEST "plane (#291): map_io round trip / classic runways / F seats a hidden pilot / nose gun hits / take-off run (no lift below rotate speed) / level flight / loop / stall drops the nose + falls, throttle recovers / bomb (cooldown) hits a bot / soft vs hard touchdown by impact speed / nose-dive wreck kills the pilot / respawn / shot down ejects alive / exit / air spawn waits, launches, abandoned plane falls / bot pilot takes off + flies / Maker map: a bot boards and flies a plane"
  ft heli heli_test.gd 150 HELI-TEST "helicopter (#277): spin-up gate / climb / hover / fly / soft landing / rockets hit a bot / bullet 0.5x vs explosive / door gunner (human + bot) / spin-out crash kills pilot / respawn on pad / idle return / gentle wreck ejects crew / bot pilot takes off / big-map pads"
  ft vart vehicle_art_test.gd 200 VART-TEST "vehicle art (#276 / #291): every vehicle (buggy, tank, heli, plane) drawn pristine / crewed + firing / 4 damage levels / wreck / respawn at Low / Medium / High in both looks, pooled FX only on Medium+, no node growth, parked bodies unmoved"
  ft rtnav runtime_nav_test.gd 240 RTNAV-TEST "runtime bot nav (#287): maps without a bake get a graph built on a worker thread (no main-thread stall), CTF legs routable, bots travel on it (classic copy + generated map); Maker maps: no node on spikes / lava and no bot dies in them, bots board and drive the buggies (tanks / helis logged); jump pads: the graph routes over a big pad to an island flag and a blue attacker rides it there; merged lava basins (#296): same graph as separate shapes, no DOM stand-off inside each other; overhangs (#297): no climb link under a platform, no repeated underside hits"
  ft sart soldier_art_test.gd 60 SOLDIER-ART-TEST "Operator soldier art (#280/#281): every rig part in both facings with normal maps + mipmaps, layer mirrors, every head / vest / pose drawn, jet flame from the pack, classic setting wins; #306 team paint layers + coverage, team vs FFA colours, palettes, ally / enemy outlines, Low team-edge fallback, team markers"
  ft wart weapons_gfx_test.gd 60 WEAPONS-ART-TEST "HD weapon art (#284): every weapon + belt grenade at 6x its classic sprite with mipmaps + normal map, drawn HD in hand / slung / as a pickup, bullet spawn identical in both looks, drawn barrel scales with the 78% gun, classic asks for no HD"
  ft joincode join_code_test.gd 60 JOINCODE-TEST "join codes: round trip, typos, garbage, host shows its code"
  ft replay replay_test.gd 150 REPLAY-TEST "replays: record, save on leave, list, play back in place, seek, exit restores"
  ft tags label_overlap_test.gd 120 LABELS-TEST "pickup name tags never overlap (#185)"
  ft friends friends_test.gd 60 FRIENDS-TEST "friends list: order, online + join, stars, cap"
  ft unlock unlock_test.gd 60 UNLOCK-TEST "unlock in play: toast, equip live, kept on respawn"
  ft customize customize_test.gd 60 CUSTOMIZE-TEST "customization: locks, unlocks, network, screens"
  ft mapvote mapvote_test.gd 60 MAPVOTE-TEST "map vote only at the end of the match (#279): early round end keeps map + clock, last-2-min end votes"
  ft pad pad_test.gd 60 PAD-TEST "gamepad: radio (L3 + D-pad), limbo loadout (D-pad)"
  ft gfx gfx_test.gd 60 GFX-TEST "graphics presets: terrain depth / grass / post FX / bloom / lights / shadows / caps, live switch"
  ft atmos atmosphere_test.gd 60 ATMOS-TEST "graphics Phase A (#270): cinematic sky / parallax / ambient / post, pooled lights, rim light, live classic switch"
  ft terrain terrain_gfx_test.gd 120 TERRAIN-TEST "HD terrain (#283): every map resolves to a material + theme, mipmapped materials / edges, fill + AO + painted edges on 6 themed maps, classic nodes hidden / restored, flat node count on reload"
  ft fxpool fx_test.gd 120 FXPOOL-TEST "graphics Phase B (#271): pooled FX, flat node count, caps per quality, decal ring, Blood 0, hit-stop / shake toggles, sim identical FX on vs off"
  ft ui ui_test.gd 90 UI-TEST "graphics Phase C (#272): menu transitions + Reduce motion, button hover / press scale, D-pad focus, settings preview lifetime, no node growth over 3 passes of every screen, HUD vitals / strip / toast / death band / UI scale"
  ft trailer trailer.gd 120 TRAILER-TEST "trailer director (#263): staged bot beats pick their highlight (rocket in flight near a crowd, crewed helicopter airborne) and log kills / explosions while filming" "--smoke"
  ft levels levels_test.gd 90 LEVELS-TEST "level sharing (#288): Hot / New / Most played / Top liked order, search by title + share code, course-code box, like on / off, bookmark saved + listed (also offline), offline message, flat node count over open / close, editor Publish round trip + title filter, editor LEVELS overlay, PLAY -> bot match on the level + play counted (in-process fake level server)"
  ft featured featured_test.gd 480 FEATURED-TEST "featured levels (#295): all 8 bundled Maker levels load, recompile identically, validate clean for their modes, pass map_audit, runtime nav routes every CTF / DOM / HTF / INF / RM leg; LEVELS opens on FEATURED offline (8 cards, no server request), detail = modes + EDIT A COPY, PLAY / HOST ONLINE, EDIT A COPY -> unsaved Maker copy, Maker New map Start from Empty / Starter / featured, editor overlay edits in place; new strings translate (es / pt_BR / de / fr); short bot match per level: bots travel, objectives progress, pads / vehicles used, few hazard deaths"
  ft discord discord_test.gd 90 DISCORD-TEST "Discord Rich Presence (#223): desktop only (Android / headless / dedicated never start it), silent without an app id, handshake + SET_ACTIVITY for menu / LEVELS / CTF match / Maker editor over a fake pipe, PING/PONG, dedupe + throttle, toggle closes / reconnects, refused id stops, Linux Unix-socket transport"
  ft fxbench fx_bench.gd 90 FX-BENCH "graphics Phase B (#271): FX benchmark, 8 gibbings + minigun + 4 explosions, node count flat, FX ms / frame"
  ft killcam killcam_test.gd 60 KILLCAM-TEST "kill cam: rewind w/ slow-mo, respawn waits, skip, live follow"
  ft lagcomp lagcomp_test.gd 60 LAGCOMP-TEST "lag compensation: hits where the shooter saw you, capped"
  ft quickplay quickplay_test.gd 60 QUICKPLAY-TEST "quick play: no game online -> bot match"
  ft name name_test.gd 60 NAME-TEST "name required before Training / online, easy rename"
  if fon updater; then
    # Fake GitHub: a releases/latest JSON one version ahead + a 1 MB "exe",
    # signed with a throwaway key so the updater's #237 signature gate runs
    # for real (production releases are signed by ../keys/update-sign-key.pem).
    ud="$OUT/updsrv"; mkdir -p "$ud"; head -c 1048576 /dev/urandom > "$ud/SoldatReborn.exe"
    openssl genrsa -traditional -out "$ud/test-key.pem" 2048 2>/dev/null
    openssl rsa -in "$ud/test-key.pem" -pubout -out "$ud/test-key.pub.pem" 2>/dev/null
    openssl dgst -sha256 -sign "$ud/test-key.pem" -out "$ud/SoldatReborn.exe.sig" "$ud/SoldatReborn.exe"
    uport=$(freeport tcp)
    printf '{"tag_name":"v99.0.0","body":"test","html_url":"x","assets":[{"name":"SoldatReborn.exe","size":1048576,"browser_download_url":"http://127.0.0.1:%d/SoldatReborn.exe"},{"name":"SoldatReborn.exe.sig","size":256,"browser_download_url":"http://127.0.0.1:%d/SoldatReborn.exe.sig"}]}' $uport $uport > "$ud/latest.json"
    python3 -m http.server $uport --bind 127.0.0.1 --directory "$ud" > /dev/null 2>&1 &
    upid=$!; wait_http $uport 20
  fi
  ft updater updater_test.gd 60 UPDATER-TEST "auto-updater: version compare, release check, download + signature check, swap script" "--update-url=http://127.0.0.1:${uport:-1}/latest.json --update-pubkey=$OUT/updsrv/test-key.pub.pem"
  ft achievements achievement_test.gd 60 ACH-TEST "achievements: unlock once, counters, multi-kill, streak, wins"
  if fon updater; then kill $upid 2>/dev/null; wait $upid 2>/dev/null; fi
  ft sound sound_test.gd 100 SOUND-TEST "sound wiring"
fi

# ── E sweep ─────────────────────────────────────────────────────────────────
# movement_course.json is a Training-only micro-map, not in the rotation (#262)
total=$(( $(ls assets/maps/*.json | grep -vc '/movement_course\.json$') + 3 ))
if [ $QUICK = 0 ] && has E && [ -n "$SWEEP" ]; then
  # Piecewise: append one map range; the verdict comes from a later "--only E" run.
  timeout $(T 170) "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=30 --from=${SWEEP%%:*} --to=${SWEEP##*:} --mode=2 >> "$OUT/sweep.log" 2>&1
  info "E sweep chunk $SWEEP: $(grep -c '^map' "$OUT/sweep.log") maps logged so far"
elif [ $QUICK = 0 ] && has E; then
  if [ $KEEP = 0 ] || [ ! -s "$OUT/sweep.log" ]; then
    : > "$OUT/sweep.log"
    for from in $(seq 0 25 $((total - 1))); do
      to=$((from + 24))
      timeout $(T 400) "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=30 --from=$from --to=$to --mode=2 >> "$OUT/sweep.log" 2>&1
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
  timeout $(T 175) "$G" --headless --fixed-fps 60 -s tools/stuck_test.gd -- --secs=30 --from=$mf --to=$mt --mode=$mm >> "$OUT/msweep_$mm.log" 2>&1
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
