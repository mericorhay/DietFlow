#!/usr/bin/env bash
# Screenshots of every main screen from a Debug build, in several languages and appearances,
# printed into the CI log as small base64 JPEGs between SHOT-BEGIN/SHOT-END markers, so they can
# be looked at without downloading artifacts. The app opens each state from launch arguments
# (DietFlow/DebugLaunch.swift) on in-memory sample data.
#
#   scripts/ci-screenshots.sh <simulator udid> <path to DietFlow.app> [core|all|onboarding]
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
# white launch screen) is retaken for up to about 35 seconds before it is reported: a CI simulator
# has been seen to take 28 seconds over one launch.
shot() {
  local name="$1"
  shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep 3
  capture "$name"
  local tries=0
  while [ "$(stat -f%z "$OUT/$name.jpg")" -lt 7000 ] && [ "$tries" -lt 10 ]; do
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

# The first-launch introduction on its own: every page, and four moments of the last page's animation.
if [ "$SET" = "onboarding" ]; then
  ONBOARDING=(-DebugSeed onboarding)
  shot onboarding-plan-en "${EN[@]}" "${ONBOARDING[@]}" -DebugOnboardingPage 0
  shot onboarding-day-tr "${TR[@]}" "${ONBOARDING[@]}" -DebugOnboardingPage 1
  shot onboarding-setup-tr "${TR[@]}" "${ONBOARDING[@]}" -DebugOnboardingPage 2
  shot onboarding-setup-blue-es "${ES[@]}" "${ONBOARDING[@]}" -DebugOnboardingPage 2 -DebugWidgetLook blue.bold
  shot onboarding-add-hold-tr "${TR[@]}" "${ONBOARDING[@]}" -DebugOnboardingPage 3 -DebugOnboardingTime 1.3
  shot onboarding-add-edit-en "${EN[@]}" "${ONBOARDING[@]}" -DebugOnboardingPage 3 -DebugOnboardingTime 2.5
  shot onboarding-add-land-tr "${TR[@]}" "${ONBOARDING[@]}" -DebugOnboardingPage 3 -DebugOnboardingTime 3.4 -DebugWidgetLook green.soft
  shot onboarding-add-done-es "${ES[@]}" "${ONBOARDING[@]}" -DebugOnboardingPage 3 -DebugOnboardingTime 6.2 -DebugWidgetLook blue.bold
  appearance dark
  shot onboarding-add-done-dark-tr "${TR[@]}" "${ONBOARDING[@]}" -DebugOnboardingPage 3 -DebugOnboardingTime 6.2
  shot onboarding-setup-dark-en "${EN[@]}" "${ONBOARDING[@]}" -DebugOnboardingPage 2 -DebugWidgetLook purple.dark
  appearance light
  exit 0
fi

shot today-now-en "${EN[@]}" "${NOW[@]}"
shot plan-en "${EN[@]}" "${SAMPLE[@]}" -DebugTab plan
shot meal-now-tr "${TR[@]}" "${NOW[@]}" -DebugMeal next
# Cook mode on the canned recipe: the overview, the grill step with its timer, the closing page.
shot cook-overview-tr "${TR[@]}" "${NOW[@]}" -DebugCook next
shot cook-step-en "${EN[@]}" "${NOW[@]}" -DebugCook next -DebugCookStep 3
shot cook-done-es "${ES[@]}" "${NOW[@]}" -DebugCook next -DebugCookStep 7
shot widgets-en "${EN[@]}" "${SAMPLE[@]}" -DebugTab widgets
shot widgets-today-large-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget today.large
shot widgets-today-medium-en "${EN[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget today.medium
shot widgets-progress-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget progress.small -DebugWidgetLook blue.bold
shot widgets-lock-circle-en "${EN[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget progress.lockCircle
shot settings-tr "${TR[@]}" "${SAMPLE[@]}" -DebugSheet settings
shot import-tr "${TR[@]}" "${SAMPLE[@]}" -DebugSheet import
shot onboarding-setup-tr "${TR[@]}" -DebugSeed onboarding -DebugOnboardingPage 2
shot onboarding-add-tr "${TR[@]}" -DebugSeed onboarding -DebugOnboardingPage 3 -DebugOnboardingTime 6.2
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
shot empty-tr "${TR[@]}" -DebugSeed empty
shot empty-plan-es "${ES[@]}" -DebugSeed empty -DebugTab plan
shot write-tr "${TR[@]}" -DebugSeed empty -DebugSheet write
shot organize-en "${EN[@]}" -DebugSeed empty -DebugSheet organize
shot privacy-links-en "${EN[@]}" "${SAMPLE[@]}" -DebugSheet settings
shot cook-consent-en "${EN[@]}" "${NOW[@]}" -DebugCook next -DebugCookConsent ask
# Room for longer languages and right-to-left scripts: Xcode's pseudolanguages.
shot today-long "${EN[@]}" "${SAMPLE[@]}" -NSDoubleLocalizedStrings YES
shot today-rtl "${EN[@]}" "${SAMPLE[@]}" -AppleTextDirection YES -NSForceRightToLeftWritingDirection YES

appearance dark
shot today-now-tr-dark "${TR[@]}" "${NOW[@]}"
shot widgets-now-es-dark "${ES[@]}" "${NOW[@]}" -DebugTab widgets
shot cook-step-tr-dark "${TR[@]}" "${NOW[@]}" -DebugCook next -DebugCookStep 2
shot meal-now-tr-dark "${TR[@]}" "${NOW[@]}" -DebugMeal next
appearance light

textSize accessibility-large
sleep 3
shot today-large-text "${EN[@]}" "${NOW[@]}"
shot plan-large-text "${EN[@]}" "${SAMPLE[@]}" -DebugTab plan
shot meal-large-text "${EN[@]}" "${NOW[@]}" -DebugMeal next
shot cook-step-large-text "${EN[@]}" "${NOW[@]}" -DebugCook next -DebugCookStep 3
textSize large
