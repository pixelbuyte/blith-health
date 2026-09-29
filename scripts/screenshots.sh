#!/usr/bin/env bash
# Boots a small and a large iPhone simulator, installs the Debug build and captures key
# screens in light and dark mode using sample data (launch arguments, see LaunchOptions.swift).
set -euo pipefail

ROOT="${CM_BUILD_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
APP="$ROOT/build/dd/Build/Products/Debug-iphonesimulator/Blith.app"
OUT="$ROOT/build/screenshots"
BUNDLE="com.blith.health"
mkdir -p "$OUT"
[ -d "$APP" ] || { echo "App not found at $APP"; exit 1; }

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
rs=[r for r in json.load(sys.stdin)["runtimes"] if r.get("platform")=="iOS" and r.get("isAvailable")]
print(sorted(rs,key=lambda r:[int(x) for x in r["version"].split(".")])[-1]["identifier"])')
echo "Runtime: $RUNTIME"

pick_type() { # $1 = python predicate on name
  xcrun simctl list devicetypes -j | python3 -c "
import json,sys
names=[d for d in json.load(sys.stdin)['devicetypes'] if d['name'].startswith('iPhone')]
m=[d for d in names if $1]
print((m or names)[-1]['identifier'])"
}
SMALL=$(pick_type "('SE' in d['name'] or d['name'].endswith('e')) ")
LARGE=$(pick_type "'Pro Max' in d['name']")

shoot() { # udid label args...
  local udid="$1" label="$2"; shift 2
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BUNDLE" "$@" >/dev/null
  sleep 7
  xcrun simctl io "$udid" screenshot "$OUT/$label.png" >/dev/null 2>&1
  echo "  $label"
}

for TYPE in "$SMALL" "$LARGE"; do
  NAME=$(echo "$TYPE" | sed 's/.*SimDeviceType\.//')
  UDID=$(xcrun simctl create "shot-$NAME" "$TYPE" "$RUNTIME")
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$UDID" "$APP"
  echo "$NAME ($UDID)"
  DEMO=(-BlithDemo balanced -BlithAIConsent NO)
  for MODE in light dark; do
    xcrun simctl ui "$UDID" appearance "$MODE"
    shoot "$UDID" "$NAME-$MODE-1-today" "${DEMO[@]}" -BlithTab today
    shoot "$UDID" "$NAME-$MODE-2-walk" "${DEMO[@]}" -BlithTab walk -BlithPeriod month
    shoot "$UDID" "$NAME-$MODE-3-ask" "${DEMO[@]}" -BlithTab ask -BlithAskScript YES
    if [ "$MODE" = light ]; then
      shoot "$UDID" "$NAME-$MODE-4-insight" "${DEMO[@]}" -BlithSheet insight
      shoot "$UDID" "$NAME-$MODE-5-sleep" "${DEMO[@]}" -BlithSheet sleep
      shoot "$UDID" "$NAME-$MODE-6-weight" "${DEMO[@]}" -BlithSheet weight
      shoot "$UDID" "$NAME-$MODE-7-walk-day" "${DEMO[@]}" -BlithTab walk -BlithPeriod day
      shoot "$UDID" "$NAME-$MODE-8-newuser" -BlithDemo newUser -BlithTab today
      shoot "$UDID" "$NAME-$MODE-9-onboarding" -BlithResetOnboarding YES
    fi
  done
  xcrun simctl shutdown "$UDID" || true
  xcrun simctl delete "$UDID" || true
done
ls -1 "$OUT"
