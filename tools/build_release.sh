#!/usr/bin/env bash
# Export Windows .exe + signed Android .apk into build/.
#   tools/build_release.sh [win|android|all]   (default all)
# Needs: Godot 4.7.2 + export templates in ~/.local/share/godot/export_templates/4.7.2.stable
# Android without a full SDK: Godot only needs *paths* to exist for an UNSIGNED
# export (we point it at a stub SDK), then uber-apk-signer zipaligns + signs
# v2/v3 with the project keystore kept OUTSIDE the repo:
#   ../keys/soldat-reborn.keystore  (+ ../keys/KEYSTORE_INFO.txt for alias/password)
# Keep that keystore backed up: phones only accept updates signed with it.
set -euo pipefail
cd "$(dirname "$0")/.."
G="${GODOT_BIN:-$HOME/godot/Godot_v4.7.2-stable_linux.x86_64}"
WHAT="${1:-all}"
KEYDIR="$(cd .. && pwd)/keys"
UBER="${UBER_APK_SIGNER:-$HOME/tools/uber.jar}"
mkdir -p build build/old
# Git Bash: Windows Godot can't write MSYS /tmp — use a path both understand.
TMPX="$(cygpath -m "${TMPDIR:-/tmp}" 2>/dev/null || echo /tmp)"

# Move a previous build to build/old/SoldatReborn-<time>.<ext> (unique name, so
# a copy that's still running is never overwritten); drop copies over a day old.
retire() {
  [ -f "$1" ] || return 0
  mv "$1" "build/old/SoldatReborn-$(date +%Y%m%d-%H%M%S).$2"
  find build/old -name "SoldatReborn-*.$2" -mmin +1440 -delete 2>/dev/null || true
}

if [ "$WHAT" = all ] || [ "$WHAT" = win ]; then
  # Never overwrite an exe in place: if the game is running from it, the new
  # build replaces the pack under the running process and it can no longer
  # load scenes ("Cannot open file res://scenes/main.tscn" on Start Hosting).
  # Rename the current build out of the way (allowed while it runs), export to
  # a temp file, then move the new one in.
  retire build/SoldatReborn.exe exe
  "$G" --headless --export-release "Windows Desktop" "$TMPX/SoldatReborn.exe" >/dev/null 2>&1
  mv "${TMPDIR:-/tmp}/SoldatReborn.exe" build/SoldatReborn.exe
  # Game pack alone, for the headless dedicated server (official server pulls
  # it from the GitHub release and runs it with the Linux Godot binary).
  rm -f build/SoldatReborn.pck
  "$G" --headless --export-pack "Windows Desktop" "$TMPX/SoldatReborn.pck" >/dev/null 2>&1
  mv "${TMPDIR:-/tmp}/SoldatReborn.pck" build/SoldatReborn.pck
  # #237: sign the exe so the self-updater can prove the download genuine
  # (keys/update-sign-key.pem; the matching public key is compiled into the
  # game). A release without this .sig is refused by every updated client.
  if [ ! -f "$KEYDIR/update-sign-key.pem" ]; then
    echo "MISSING $KEYDIR/update-sign-key.pem — cannot sign the update (see keys/UPDATE_SIGNING.md)" >&2
    exit 1
  fi
  openssl dgst -sha256 -sign "$KEYDIR/update-sign-key.pem" \
    -out build/SoldatReborn.exe.sig build/SoldatReborn.exe
  sync; ls -la build/SoldatReborn.exe build/SoldatReborn.exe.sig build/SoldatReborn.pck
fi

if [ "$WHAT" = all ] || [ "$WHAT" = android ]; then
  SDK="$HOME/fakesdk"
  mkdir -p "$SDK/platform-tools" "$SDK/build-tools/34.0.0" "$SDK/platforms/android-34"
  printf '#!/bin/sh\nexit 0\n' > "$SDK/platform-tools/adb"
  printf '#!/bin/sh\nexit 0\n' > "$SDK/build-tools/34.0.0/apksigner"
  chmod +x "$SDK/platform-tools/adb" "$SDK/build-tools/34.0.0/apksigner"
  # Editor settings live in different places per OS (Linux vs Windows).
  ES="$HOME/.config/godot/editor_settings-4.7.tres"
  if [ ! -f "$ES" ] && [ -n "$APPDATA" ]; then
    ES="$(cygpath "$APPDATA")/Godot/editor_settings-4.7.tres"
  fi
  JAVA_HOME_GUESS="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  # Git Bash: hand Godot Windows-style paths (cygpath -m), else the native ones.
  SDK_ES="$(cygpath -m "$SDK" 2>/dev/null || echo "$SDK")"
  JH_ES="$(cygpath -m "$JAVA_HOME_GUESS" 2>/dev/null || echo "$JAVA_HOME_GUESS")"
  # Point Godot at the stub SDK + this machine's Java (plain sed: no Python
  # needed — a broken Windows python3 alias stopped the 1.35 release here).
  for kv in "export/android/android_sdk_path|$SDK_ES" "export/android/java_sdk_path|$JH_ES"; do
    k="${kv%%|*}"; v="${kv#*|}"
    if grep -q "^$k = " "$ES"; then
      sed -i "s#^$k = .*#$k = \"$v\"#" "$ES"
    else
      sed -i "s#^\[resource\]\$#[resource]\n$k = \"$v\"#" "$ES"
    fi
  done
  cp export_presets.cfg /tmp/export_presets.bak
  trap 'cp /tmp/export_presets.bak export_presets.cfg' EXIT
  sed -i 's/^package\/signed=true/package\/signed=false/' export_presets.cfg
  # The preset's debug-keystore path may point at another machine's home
  # (e.g. /home/... from the Linux box) — rewrite it to this machine's.
  DBGKS="$(cygpath "$APPDATA" 2>/dev/null)/Godot/keystores/debug.keystore"
  if [ ! -f "$DBGKS" ]; then
    DBGKS="$HOME/.local/share/godot/keystores/debug.keystore"
  fi
  if [ -f "$DBGKS" ]; then
    sed -i "s|^keystore/debug=.*|keystore/debug=\"$(cygpath -m "$DBGKS" 2>/dev/null || echo "$DBGKS")\"|" export_presets.cfg
  fi
  "$G" --headless --export-release "Android" "$TMPX/SoldatReborn.apk" >/dev/null 2>&1
  cp /tmp/export_presets.bak export_presets.cfg
  PW="$(sed -n 's/^password: //p' "$KEYDIR/KEYSTORE_INFO.txt")"
  java -jar "$UBER" -a "$TMPX/SoldatReborn.apk" --ks "$KEYDIR/soldat-reborn.keystore" --ksAlias soldatreborn \
    --ksPass "$PW" --ksKeyPass "$PW" --overwrite 2>&1 | grep -E "verified|Successfully|ERROR" || true
  retire build/SoldatReborn.apk apk
  cp "${TMPDIR:-/tmp}/SoldatReborn.apk" build/SoldatReborn.apk
  sync; ls -la build/SoldatReborn.apk
fi
