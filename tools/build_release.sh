#!/usr/bin/env bash
# Export Windows .exe + signed Android .apk (+ the standalone server
# downloads, #320) into build/.
#   tools/build_release.sh [win|android|server|all]   (default all)
# server: build/TracerfallServer-windows.zip + TracerfallServer-linux.tar.gz
# (+ .sig each) from the stripped "Windows Server" / "Linux Server" presets.
# A platform whose export template isn't installed is skipped with a SKIP
# line — it never fails the release.
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

if [ "$WHAT" = all ] || [ "$WHAT" = server ]; then
  # #320: standalone dedicated server: stripped export (no textures / music)
  # + start scripts, service install, updater, server.cfg.example, HOSTING.md.
  VER="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot | tr -d '\r')"
  GV="$("$G" --version 2>/dev/null | tr -d '\r' | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.([a-z]+[0-9]*)\..*/\1.\3/')"
  TPLDIR=""
  for base in "${XDG_DATA_HOME:-$HOME/.local/share}/godot" "$(cygpath "${APPDATA:-}" 2>/dev/null)/Godot" "$HOME/Library/Application Support/Godot"; do
    if [ -d "$base/export_templates/$GV" ]; then TPLDIR="$base/export_templates/$GV"; break; fi
  done
  KIT=tools/server_kit
  for plat in linux windows; do
    if [ "$plat" = linux ]; then
      PRESET="Linux Server"; BIN=TracerfallServer.x86_64; TPL=linux_release.x86_64; ARC=TracerfallServer-linux.tar.gz
      FILES="start-server.sh install-service.sh tracerfall-server.service update-server.sh update_server.py server.cfg.example"
    else
      PRESET="Windows Server"; BIN=TracerfallServer.exe; TPL=windows_release_x86_64.exe; ARC=TracerfallServer-windows.zip
      FILES="start-server.bat run-service.bat install-service.bat uninstall-service.bat update-server.bat update_server.py server.cfg.example"
    fi
    rm -f "build/$ARC" "build/$ARC.sig"
    if [ -z "$TPLDIR" ] || [ ! -f "$TPLDIR/$TPL" ]; then
      echo "SKIP server $plat: export template $TPL not found in ${TPLDIR:-<Godot data>/export_templates/$GV} — install the $GV export templates (Godot editor: Editor > Manage Export Templates) to build $ARC"
      continue
    fi
    ST="build/server/$plat/TracerfallServer"
    rm -rf "build/server/$plat"; mkdir -p "$ST"
    "$G" --headless --export-release "$PRESET" "$ST/$BIN" > "build/server/export_$plat.log" 2>&1 || true
    if [ ! -f "$ST/$BIN" ] || [ ! -f "$ST/TracerfallServer.pck" ]; then
      echo "SKIP server $plat: export failed — see build/server/export_$plat.log"
      continue
    fi
    for f in $FILES; do cp "$KIT/$f" "$ST/$f"; done
    cp docs/HOSTING.md "$ST/HOSTING.md"
    cp LICENSE.md "$ST/LICENSE.md"
    printf '%s\n' "$VER" > "$ST/VERSION.txt"
    # Line endings for the target OS (a Windows checkout may hand us CRLF scripts).
    if [ "$plat" = linux ]; then
      sed -i 's/\r$//' "$ST"/*.sh "$ST"/*.py "$ST"/*.service "$ST"/*.md "$ST"/server.cfg.example "$ST/VERSION.txt"
      chmod +x "$ST/$BIN" "$ST"/*.sh "$ST"/*.py
    else
      sed -i 's/\r*$/\r/' "$ST"/*.bat "$ST"/*.md "$ST"/server.cfg.example "$ST/VERSION.txt"
    fi
    "$G" --headless -s tools/pack_server.gd -- --src="$ST" --out="build/$ARC" 2>&1 | grep -E "PACK-" || true
    if [ ! -f "build/$ARC" ]; then
      echo "SKIP server $plat: packing failed"
      continue
    fi
    # Signed like the game exe (#237): update_server.py refuses unsigned archives.
    if [ -f "$KEYDIR/update-sign-key.pem" ]; then
      openssl dgst -sha256 -sign "$KEYDIR/update-sign-key.pem" -out "build/$ARC.sig" "build/$ARC"
    else
      echo "WARNING: $KEYDIR/update-sign-key.pem missing — build/$ARC is unsigned (servers will not auto-update to it)" >&2
    fi
    ls -la "build/$ARC" "build/$ARC.sig" 2>/dev/null || true
  done
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
