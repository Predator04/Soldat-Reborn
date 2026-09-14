#!/usr/bin/env bash
# Soldat-Reborn compile check — run after any .gd edit (PostToolUse hook).
# Full headless boot is the ONLY reliable check here: `--headless --import` is a
# no-op on a warm cache (doesn't recompile), and `--check-only --script` false-
# positives on autoload identifiers (Settings/Net/MatchConfig not loaded). The
# boot loads autoloads + main.tscn, so it catches real parse/compile errors.
# Clean run = zero output (silent success). Errors print to stderr so Claude
# sees them and self-corrects on the next turn. ~11s per run.
set -uo pipefail
# Resolve the Godot binary: explicit env override, then PATH, then William's WSL install.
GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  GODOT="$(command -v godot 2>/dev/null || true)"
fi
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  GODOT="/home/predator04/godot/Godot_v4.7.2-stable_linux.x86_64"
fi
[ -x "$GODOT" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-/mnt/c/Users/Admin/Desktop/soldat reborn/game}" 2>/dev/null || exit 0
errs="$("$GODOT" --headless --quit-after 700 res://scenes/main.tscn 2>&1 | grep -iE 'SCRIPT ERROR|Parse Error|Cannot load|Identifier not found|Invalid call|Cannot infer')"
if [ -n "$errs" ]; then
  printf '%s\n' "$errs" >&2
  exit 1
fi
exit 0
