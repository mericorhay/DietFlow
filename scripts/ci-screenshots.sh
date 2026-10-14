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

# Small JPEGs keep the log short; the store set is printed at full size, since the artifact with
# the PNGs cannot always be fetched where the shots are turned into store images.
FULL_SIZE=0
capture() {
  local name="$1"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
  if [ "$FULL_SIZE" = 1 ]; then
    sips -s format jpeg -s formatOptions 80 "$OUT/$name.png" --out "$OUT/$name.jpg" >/dev/null
  else
    sips -Z 560 -s format jpeg -s formatOptions 50 "$OUT/$name.png" --out "$OUT/$name.jpg" >/dev/null
  fi
}

# shot <name> <launch arguments…>
# A first launch after a text-size change can take longer than usual, so a blank capture (the
# white launch screen) is retaken for up to about 35 seconds before it is reported: a CI simulator
# has been seen to take 28 seconds over one launch.
# Store shots are taken at half past twelve, whenever CI runs: the app is launched in the time zone
# where it is about then, and the status bar shows that zone's clock, so the clock and the meals
# on screen agree. Empty elsewhere: the runner's own zone, and the 9:41 status bar.
SHOT_TZ=""
midday_zone() {
  local offset=$(( 12 - 10#$(date -u +%H) ))
  [ "$offset" -lt -12 ] && offset=$((offset + 24))
  [ "$offset" -gt 14 ] && offset=$((offset - 24))
  # Etc/GMT names count the other way: Etc/GMT-3 is three hours ahead of UTC.
  if [ "$offset" -ge 0 ]; then echo "Etc/GMT-$offset"; else echo "Etc/GMT+$(( -offset ))"; fi
}

shot() {
  local name="$1"
  shift
  if [ -n "$SHOT_TZ" ]; then
    xcrun simctl status_bar "$UDID" override --time "$(TZ="$SHOT_TZ" date +%H:%M)" >/dev/null 2>&1 || true
    export SIMCTL_CHILD_TZ="$SHOT_TZ"
  fi
  # Cook mode writes its canned recipe and then moves to the step asked for; three seconds
  # caught it half way through that move.
  local wait=3
  case " $* " in *" -DebugCook "*) wait=7 ;; esac
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep "$wait"
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
DE=(-AppleLanguages "(de)" -AppleLocale de_DE)
FR=(-AppleLanguages "(fr)" -AppleLocale fr_FR)
# The widget in black and gold with the Classic font.
GOLD=(-DebugWidgetLook gold.dark.serif)
SAMPLE=(-DebugSeed sample)
NOW=(-DebugSeed now)

appearance light
textSize large

# Real app captures for localized store creatives; no personal data or network calls.
# Full size, and by default English and Turkish only, to keep the log in bounds:
# ASO_LOCALES="es de fr" runs the others.
if [ "$SET" = "aso" ]; then
  FULL_SIZE=1
  SHOT_TZ="$(midday_zone)"
  echo "Store shots in $SHOT_TZ, where it is $(TZ="$SHOT_TZ" date +%H:%M)"
  for locale in ${ASO_LOCALES:-en tr}; do
    case "$locale" in
      en) LANG_ARGS=("${EN[@]}") ;;
      tr) LANG_ARGS=("${TR[@]}") ;;
      es) LANG_ARGS=("${ES[@]}") ;;
      de) LANG_ARGS=("${DE[@]}") ;;
      fr) LANG_ARGS=("${FR[@]}") ;;
    esac
    shot "aso-$locale-today" "${LANG_ARGS[@]}" "${NOW[@]}"
    shot "aso-$locale-meal" "${LANG_ARGS[@]}" "${NOW[@]}" -DebugMeal next
    shot "aso-$locale-widget" "${LANG_ARGS[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.large "${GOLD[@]}"
    shot "aso-$locale-shifted" "${LANG_ARGS[@]}" -DebugSeed shifted
    shot "aso-$locale-late" "${LANG_ARGS[@]}" -DebugSeed late
    # The overview: the ingredients with their swaps.
    shot "aso-$locale-cook" "${LANG_ARGS[@]}" "${NOW[@]}" -DebugCook next
    shot "aso-$locale-import" "${LANG_ARGS[@]}" "${SAMPLE[@]}" -DebugSheet import
    shot "aso-$locale-write" "${LANG_ARGS[@]}" -DebugSeed empty -DebugSheet write
    shot "aso-$locale-plus" "${LANG_ARGS[@]}" "${SAMPLE[@]}" -DebugSheet plus
    shot "aso-$locale-consent" "${LANG_ARGS[@]}" "${NOW[@]}" -DebugCook next -DebugCookConsent ask
  done
  exit 0
fi

# Focused visual checks for meal actions and every Home Screen widget size.
if [ "$SET" = "widgets" ]; then
  shot today-now-tr "${TR[@]}" "${NOW[@]}"
  shot meal-now-tr "${TR[@]}" "${NOW[@]}" -DebugMeal next
  shot cook-done-tr "${TR[@]}" "${NOW[@]}" -DebugCook next -DebugCookStep 7
  shot widgets-small-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.small
  shot widgets-medium-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.medium
  shot widgets-large-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.large
  shot widgets-today-large-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget today.large
  shot widgets-gold-small-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.small "${GOLD[@]}"
  shot widgets-gold-medium-en "${EN[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.medium "${GOLD[@]}"
  shot widgets-gold-large-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.large "${GOLD[@]}"
  shot widgets-gold-today-de "${DE[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget today.large "${GOLD[@]}"
  shot widgets-gold-light-fr "${FR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.medium -DebugWidgetLook gold.system.serif
  appearance dark
  shot widgets-large-dark-en "${EN[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.large
  textSize extra-extra-extra-large
  shot widgets-large-text-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.large
  exit 0
fi

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
shot today-late-en "${EN[@]}" -DebugSeed late
shot today-shifted-tr "${TR[@]}" -DebugSeed shifted
shot plan-en "${EN[@]}" "${SAMPLE[@]}" -DebugTab plan
shot meal-now-tr "${TR[@]}" "${NOW[@]}" -DebugMeal next
# Cook mode on the canned recipe: the overview, the grill step with its timer, the closing page.
shot cook-overview-tr "${TR[@]}" "${NOW[@]}" -DebugCook next
shot cook-step-en "${EN[@]}" "${NOW[@]}" -DebugCook next -DebugCookStep 3
shot cook-done-es "${ES[@]}" "${NOW[@]}" -DebugCook next -DebugCookStep 7
shot widgets-en "${EN[@]}" "${SAMPLE[@]}" -DebugTab widgets
shot widgets-today-large-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget today.large
shot widgets-today-medium-en "${EN[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget today.medium
shot widgets-medium-en "${EN[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.medium
shot widgets-lock-rect-es "${ES[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.lockScreen
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
shot today-missed-es "${ES[@]}" -DebugSeed missed
shot widgets-lock-next-circle-tr "${TR[@]}" "${NOW[@]}" -DebugTab widgets -DebugWidget nextMeal.lockCircle
shot widgets-gallery-tr "${TR[@]}" -DebugSeed empty -DebugTab widgets -DebugWidget today.large
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
shot today-late-large-text "${EN[@]}" -DebugSeed late
shot cook-step-large-text "${EN[@]}" "${NOW[@]}" -DebugCook next -DebugCookStep 3
textSize large
