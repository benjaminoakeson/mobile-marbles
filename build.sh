#!/usr/bin/env bash
# Export the Android APK and, with -i, install and launch it on the attached device.
set -euo pipefail

cd "$(dirname "$0")"

GODOT="${GODOT:-$HOME/Desktop/Godot_v4.7.1-stable_linux.x86_64}"
APK="build/android/MobileMarbles.apk"

[ -x "$GODOT" ] || { echo "Godot not found at $GODOT (set GODOT=...)" >&2; exit 1; }

mkdir -p build/android
"$GODOT" --headless --path . --export-debug Android "$APK"
[ -f "$APK" ] || { echo "export produced no APK" >&2; exit 1; }
echo "built $APK ($(du -h "$APK" | cut -f1))"

if [ "${1:-}" = "-i" ]; then
	adb get-state >/dev/null 2>&1 || { echo "no device attached (adb devices)" >&2; exit 1; }
	adb install -r "$APK"
	adb shell monkey -p com.oakeson.mobilemarbles -c android.intent.category.LAUNCHER 1
fi
