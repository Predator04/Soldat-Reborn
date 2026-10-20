#!/usr/bin/env bash
# Gameplay trailer (#263): render every beat with Godot's Movie Maker, render
# the title cards, then cut / mix / encode with ffmpeg (tools/trailer_edit.py).
#
#   tools/make_trailer.sh                    # everything (~1-1.5 h on software GL)
#   tools/make_trailer.sh --beats "hd ctf"   # re-render only these beats
#   tools/make_trailer.sh --edit-only        # re-cut from the existing renders
#   tools/make_trailer.sh --url itch.io/...  # the URL on the end cards
#
# Outputs: build/trailer/tracerfall-trailer.mp4 (16:9 1920x1080 60 fps),
# build/trailer/tracerfall-trailer-vertical.mp4 (9:16 1080x1920, 30 s),
# build/trailer/shotlist.txt, docs/screenshots/trailer-*.jpg, docs/media/cover-630x500.png.
# Raw renders + logs: build/trailer/raw/.
#
# Needs: xvfb-run + Mesa (software GL is fine: Movie Maker renders every frame
# at a fixed 60 fps however slow the machine), ffmpeg (or
# `pip install --break-system-packages imageio-ffmpeg`), python3 + Pillow.
# One Godot at a time; each beat starts from a fresh user:// folder.
set -euo pipefail
cd "$(dirname "$0")/.."
G="${GODOT:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}"
OUT=build/trailer
RAW=$OUT/raw
ALL="open jets boom multi hd buggy tank heli plane ctf maker levels end"
BEATS="$ALL"
EDIT_ONLY=0
CARDS=1
URL="github.com/Predator04/Tracerfall"
EDIT_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --beats) BEATS="$2"; CARDS=0; shift;;
    --cards) CARDS=1;;
    --edit-only) EDIT_ONLY=1;;
    --url) URL="$2"; CARDS=1; shift;;
    --preview|--plan|--no-vertical|--no-art) EDIT_ARGS+=("$1");;
    -h|--help) sed -n '2,20p' "$0"; exit 0;;
    *) echo "unknown option $1"; exit 2;;
  esac
  shift
done
mkdir -p "$RAW"
# build/ is inside the Godot project: without this the editor / --import would
# import every card frame and still as a texture.
touch "$OUT/.gdignore"

# Movie Maker records at the project's window size: a temporary override.cfg
# asks for 1920x1080 and high MJPEG quality. Always removed again.
cleanup() { rm -f override.cfg; }
trap cleanup EXIT INT TERM

godot_run() {  # log, args...
  local log="$1"; shift
  rm -rf "$RAW/xdg"; mkdir -p "$RAW/xdg"
  XDG_DATA_HOME="$PWD/$RAW/xdg" timeout 5400 xvfb-run -a -s "-screen 0 1920x1080x24" \
    "$G" --rendering-driver opengl3 --resolution 1920x1080 "$@" > "$log" 2>&1
}

if [ $EDIT_ONLY = 0 ]; then
  printf '[display]\nwindow/size/window_width_override=1920\nwindow/size/window_height_override=1080\n[editor]\nmovie_writer/mjpeg_quality=0.93\n' > override.cfg
  if [ $CARDS = 1 ]; then
    echo "== title cards"
    rm -rf "$RAW/cards"
    godot_run "$RAW/cards.log" --fixed-fps 60 -s tools/trailer.gd -- --cards --out="$RAW/cards" --url="$URL"
    grep -h "TRAILER card" "$RAW/cards.log" || { echo "card render failed (see $RAW/cards.log)"; exit 1; }
  fi
  for b in $BEATS; do
    echo "== beat $b  $(date +%T)"
    rm -f "$RAW/$b".avi "$RAW/$b".json "$RAW/$b"_still_*.png
    godot_run "$RAW/$b.log" --fixed-fps 60 --write-movie "$RAW/$b.avi" \
      -s tools/trailer.gd -- --beat="$b" --out="$RAW" --no-perf-guard
    grep -h "TRAILER done\|TRAILER render" "$RAW/$b.log" || true
    if ! grep -q "TRAILER done beat=$b why=done" "$RAW/$b.log"; then echo "beat $b failed (see $RAW/$b.log)"; exit 1; fi
    if grep -qE "SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Invalid get" "$RAW/$b.log"; then
      echo "beat $b: script errors (see $RAW/$b.log)"; exit 1
    fi
  done
  cleanup
fi

echo "== edit  $(date +%T)"
python3 tools/trailer_edit.py --raw "$RAW" --out "$OUT" --url "$URL" "${EDIT_ARGS[@]}"
ls -la "$OUT"/*.mp4 2>/dev/null || true
