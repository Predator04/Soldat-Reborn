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
mkdir -p build

if [ "$WHAT" = all ] || [ "$WHAT" = win ]; then
  [ -f build/SoldatReborn.exe ] && mv -f build/SoldatReborn.exe build/SoldatReborn.old.exe
  "$G" --headless --export-release "Windows Desktop" build/SoldatReborn.exe >/dev/null 2>&1
  ls -la build/SoldatReborn.exe
fi

if [ "$WHAT" = all ] || [ "$WHAT" = android ]; then
  SDK="$HOME/fakesdk"
  mkdir -p "$SDK/platform-tools" "$SDK/build-tools/34.0.0" "$SDK/platforms/android-34"
  printf '#!/bin/sh\nexit 0\n' > "$SDK/platform-tools/adb"
  printf '#!/bin/sh\nexit 0\n' > "$SDK/build-tools/34.0.0/apksigner"
  chmod +x "$SDK/platform-tools/adb" "$SDK/build-tools/34.0.0/apksigner"
  ES="$HOME/.config/godot/editor_settings-4.7.tres"
  JAVA_HOME_GUESS="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  python3 - "$ES" "$SDK" "$JAVA_HOME_GUESS" <<'PY'
import re, sys
f, sdk, jh = sys.argv[1:4]
s = open(f).read()
for k, v in (("export/android/android_sdk_path", sdk), ("export/android/java_sdk_path", jh)):
    line = '%s = "%s"' % (k, v)
    s = re.sub(re.escape(k) + r' = .*', line, s) if k + " =" in s else s.replace("[resource]\n", "[resource]\n" + line + "\n", 1)
open(f, "w").write(s)
PY
  cp export_presets.cfg /tmp/export_presets.bak
  trap 'cp /tmp/export_presets.bak export_presets.cfg' EXIT
  sed -i 's/^package\/signed=true/package\/signed=false/' export_presets.cfg
  "$G" --headless --export-release "Android" /tmp/SoldatReborn.apk >/dev/null 2>&1
  cp /tmp/export_presets.bak export_presets.cfg
  PW="$(sed -n 's/^password: //p' "$KEYDIR/KEYSTORE_INFO.txt")"
  java -jar "$UBER" -a /tmp/SoldatReborn.apk --ks "$KEYDIR/soldat-reborn.keystore" --ksAlias soldatreborn \
    --ksPass "$PW" --ksKeyPass "$PW" --overwrite 2>&1 | grep -E "verified|Successfully|ERROR" || true
  [ -f build/SoldatReborn.apk ] && mv -f build/SoldatReborn.apk build/SoldatReborn.old.apk
  cp /tmp/SoldatReborn.apk build/SoldatReborn.apk
  ls -la build/SoldatReborn.apk
fi
