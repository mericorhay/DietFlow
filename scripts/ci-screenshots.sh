#!/usr/bin/env bash
# Screenshots of every main screen from a Debug build, in several languages and appearances,
# printed into the CI log as small base64 JPEGs between SHOT-BEGIN/SHOT-END markers, so they can
# be looked at without downloading artifacts. The app opens each state from launch arguments
# (DietFlow/DebugLaunch.swift) on in-memory sample data.
#
#   scripts/ci-screenshots.sh <simulator udid> <path to DietFlow.app>
set -euo pipefail

UDID="$1"
APP="$2"
BUNDLE="com.orhay.dietflow"
OUT="${RUNNER_TEMP:-/tmp}/screenshots"
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"

appearance() { xcrun simctl ui "$UDID" appearance "$1" >/dev/null 2>&1 || true; }
textSize() { xcrun simctl ui "$UDID" content_size "$1" >/dev/null 2>&1 || true; }

# shot <name> <launch arguments…>
shot() {
  local name="$1"
  shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
  sips -Z 560 "$OUT/$name.png" --out "$OUT/$name-small.png" >/dev/null
  sips -s format jpeg -s formatOptions 50 "$OUT/$name-small.png" --out "$OUT/$name.jpg" >/dev/null
  echo "SHOT-BEGIN $name"
  base64 -i "$OUT/$name.jpg" | fold -w 4000
  echo "SHOT-END $name"
}

EN=(-AppleLanguages "(en)" -AppleLocale en_US)
TR=(-AppleLanguages "(tr)" -AppleLocale tr_TR)
ES=(-AppleLanguages "(es)" -AppleLocale es_ES)
SAMPLE=(-DebugSeed sample)

appearance light
textSize large
shot today-en "${EN[@]}" "${SAMPLE[@]}"
shot plan-en "${EN[@]}" "${SAMPLE[@]}" -DebugTab plan
shot meal-en "${EN[@]}" "${SAMPLE[@]}" -DebugMeal next
shot widgets-en "${EN[@]}" "${SAMPLE[@]}" -DebugTab widgets
shot settings-tr "${TR[@]}" "${SAMPLE[@]}" -DebugSheet settings
shot newmeal-es "${ES[@]}" "${SAMPLE[@]}" -DebugSheet newMeal
shot import-tr "${TR[@]}" "${SAMPLE[@]}" -DebugSheet import
shot empty-en "${EN[@]}" -DebugSeed empty
shot onboarding-last-tr "${TR[@]}" -DebugSeed onboarding -DebugOnboardingPage 2
# Room for longer languages and right-to-left scripts: Xcode's pseudolanguages.
shot today-long "${EN[@]}" "${SAMPLE[@]}" -NSDoubleLocalizedStrings YES
shot today-rtl "${EN[@]}" "${SAMPLE[@]}" -AppleTextDirection YES -NSForceRightToLeftWritingDirection YES

appearance dark
shot today-tr-dark "${TR[@]}" "${SAMPLE[@]}"
appearance light

textSize accessibility-large
shot today-large-text "${EN[@]}" "${SAMPLE[@]}"
textSize large
