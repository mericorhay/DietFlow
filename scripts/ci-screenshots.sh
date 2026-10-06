#!/usr/bin/env bash
# Screenshots of every main screen from a Debug build, in several languages and appearances,
# printed into the CI log as small base64 JPEGs between SHOT-BEGIN/SHOT-END markers, so they can
# be looked at without downloading artifacts. The app opens each state from launch arguments
# (DietFlow/DebugLaunch.swift) on in-memory sample data.
#
#   scripts/ci-screenshots.sh <simulator udid> <path to DietFlow.app> [core|all]
#
# Each shot is a cold launch on a CI simulator, about half a minute. "core" (the default) is the
# seven screens that show whether a change broke something; "all" adds the languages, dark mode,
# large text and the pseudolanguages, and takes around nine minutes.
set -euo pipefail

UDID="$1"
APP="$2"
SET="${3:-core}"
BUNDLE="com.orhay.dietflow"
OUT="${RUNNER_TEMP:-/tmp}/screenshots"
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"

appearance() { xcrun simctl ui "$UDID" appearance "$1" >/dev/null 2>&1 || true; }
textSize() { xcrun simctl ui "$UDID" content_size "$1" >/dev/null 2>&1 || true; }

capture() {
  local name="$1"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
  sips -Z 560 -s format jpeg -s formatOptions 50 "$OUT/$name.png" --out "$OUT/$name.jpg" >/dev/null
}

# shot <name> <launch arguments…>
# A first launch after a text-size change can take longer than usual, so a blank capture (the
# white launch screen) is retaken for up to about 20 seconds before it is reported.
shot() {
  local name="$1"
  shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep 3
  capture "$name"
  local tries=0
  while [ "$(stat -f%z "$OUT/$name.jpg")" -lt 7000 ] && [ "$tries" -lt 5 ]; do
    sleep 3
    capture "$name"
    tries=$((tries + 1))
  done
  if [ "$(stat -f%z "$OUT/$name.jpg")" -lt 7000 ]; then
    echo "NOTE $name still looks blank. Running: $(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -c "$BUNDLE" || true)"
    xcrun simctl spawn "$UDID" log show --last 1m --style compact --predicate 'process == "DietFlow"' 2>/dev/null | tail -25 || true
  fi
  echo "SHOT-BEGIN $name"
  base64 -i "$OUT/$name.jpg" | fold -w 4000
  echo "SHOT-END $name"
}

EN=(-AppleLanguages "(en)" -AppleLocale en_US)
TR=(-AppleLanguages "(tr)" -AppleLocale tr_TR)
ES=(-AppleLanguages "(es)" -AppleLocale es_ES)
SAMPLE=(-DebugSeed sample)
NOW=(-DebugSeed now)

appearance light
textSize large
shot today-now-en "${EN[@]}" "${NOW[@]}"
shot plan-en "${EN[@]}" "${SAMPLE[@]}" -DebugTab plan
shot meal-now-tr "${TR[@]}" "${NOW[@]}" -DebugMeal next
shot widgets-en "${EN[@]}" "${SAMPLE[@]}" -DebugTab widgets
shot settings-tr "${TR[@]}" "${SAMPLE[@]}" -DebugSheet settings
shot import-tr "${TR[@]}" "${SAMPLE[@]}" -DebugSheet import
shot onboarding-last-tr "${TR[@]}" -DebugSeed onboarding -DebugOnboardingPage 2
shot plus-intro-tr "${TR[@]}" -DebugSeed onboarding -DebugSheet plusIntro

if [ "$SET" != "all" ]; then
  exit 0
fi

shot widgets-now-en "${EN[@]}" "${NOW[@]}" -DebugTab widgets
shot today-en "${EN[@]}" "${SAMPLE[@]}"
shot meal-en "${EN[@]}" "${SAMPLE[@]}" -DebugMeal next
shot newmeal-es "${ES[@]}" "${SAMPLE[@]}" -DebugSheet newMeal
shot plus-en "${EN[@]}" "${SAMPLE[@]}" -DebugSheet plus
shot widgets-blue-bold-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidgetLook blue.bold
shot widgets-green-soft-en "${EN[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidgetLook green.soft
shot settings-plus-es "${ES[@]}" "${SAMPLE[@]}" -DebugSheet settings -DebugPlus trial
shot empty-en "${EN[@]}" -DebugSeed empty
# Room for longer languages and right-to-left scripts: Xcode's pseudolanguages.
shot today-long "${EN[@]}" "${SAMPLE[@]}" -NSDoubleLocalizedStrings YES
shot today-rtl "${EN[@]}" "${SAMPLE[@]}" -AppleTextDirection YES -NSForceRightToLeftWritingDirection YES

appearance dark
shot today-now-tr-dark "${TR[@]}" "${NOW[@]}"
shot widgets-now-es-dark "${ES[@]}" "${NOW[@]}" -DebugTab widgets
appearance light

textSize accessibility-large
sleep 3
shot today-large-text "${EN[@]}" "${NOW[@]}"
shot plan-large-text "${EN[@]}" "${SAMPLE[@]}" -DebugTab plan
shot meal-large-text "${EN[@]}" "${NOW[@]}" -DebugMeal next
textSize large
