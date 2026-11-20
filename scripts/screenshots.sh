#!/bin/zsh
# App Store screenshots from the Debug build on the screenshot fixtures (docs/SUBMISSION.md §6).
#
#   scripts/screenshots.sh <simulator udid> <out dir> [display id]
#
# iPhone: pass a booted simulator (the iPhone 18 Pro, or an 18 Pro Max for the 6.9-inch slot).
# iPhone Duo: open the Duo in Device Hub (Xcode ▸ Open Developer Tool ▸ Device Hub), set the pose there,
# then pass the display: `xcrun simctl io <udid> enumerate` lists them; the cover display is 1398 px wide,
# the open one 2007 px. Never boot the Duo with `simctl boot`: it comes up without displays.
#
# SHOT_LANG=es: Spanish (Mexico), with the screenshot world in Spanish; English otherwise.
#
# Build first: xcodebuild build -scheme masUNO -configuration Debug -destination 'generic/platform=iOS Simulator'
# and set APP below (or export it) to the built masUNO.app.
set -euo pipefail

UDID=${1:?simulator udid}
OUT=${2:?output directory}
DISPLAY_ID=${3:-}
APP=${APP:-build/Build/Products/Debug-iphonesimulator/masUNO.app}
BUNDLE=com.masuno.app
if [[ ${SHOT_LANG:-en} == es ]]; then LANG_ARGS=(-AppleLanguages "(es-MX)" -AppleLocale es_MX); else LANG_ARGS=(-AppleLanguages "(en)" -AppleLocale en_US); fi
SCREENS=(popup detail-open detail-in add-filled me chat onboarding-guidelines)

[[ -d $APP ]] || { echo "No app at $APP; build Debug for the simulator first" >&2; exit 1; }
mkdir -p "$OUT"

xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE"
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3

display_args=()
[[ -n $DISPLAY_ID ]] && display_args=(--display="$DISPLAY_ID" --mask=ignored)

for screen in $SCREENS; do
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -liveAuth NO -mockLocation YES -appearance light \
    -screenshots YES -screen "$screen" -appLanguage system "${LANG_ARGS[@]}" >/dev/null
  # The map and court art settle in a few seconds; a cold first launch on the Duo takes about ten.
  sleep "${SETTLE:-10}"
  png="$OUT/$screen.png"
  xcrun simctl io "$UDID" screenshot --type=png "${display_args[@]}" "$png" >/dev/null
  # App Store Connect rejects alpha channels: keep a flattened JPEG next to each capture.
  sips -s format jpeg -s formatOptions 95 "$png" --out "${png%.png}.jpg" >/dev/null
  echo "$screen → ${png%.png}.jpg ($(sips -g pixelWidth -g pixelHeight "$png" | awk '/pixel/{printf "%s ", $2}'))"
done

echo "Check each image: a display that's off still saves an all-black file."
