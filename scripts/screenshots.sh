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

# Pick a small and a large iPhone among devices that exist for this runtime.
pick_device() { # $1 = small|large -> "udid|name"
  xcrun simctl list devices available -j | python3 -c "
import json,sys
devs=[d for d in json.load(sys.stdin)['devices'].get('$RUNTIME',[]) if d['name'].startswith('iPhone')]
small=[d for d in devs if 'SE' in d['name'] or d['name'].endswith('e') or 'mini' in d['name']]
large=[d for d in devs if 'Pro Max' in d['name'] or 'Plus' in d['name']]
pick=(small if '$1'=='small' else large) or devs
d=pick[-1] if '$1'=='small' else pick[0]
print(d['udid']+'|'+d['name'])"
}
SMALL=$(pick_device small)
LARGE=$(pick_device large)
echo "Devices: $SMALL / $LARGE"

shoot() { # udid label args...
  local udid="$1" label="$2"; shift 2
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BUNDLE" "$@" >/dev/null
  sleep 7
  xcrun simctl io "$udid" screenshot "$OUT/$label.png" >/dev/null 2>&1
  echo "  $label"
}

for DEV in "$SMALL" "$LARGE"; do
  UDID="${DEV%%|*}"
  NAME=$(echo "${DEV#*|}" | tr -cd '[:alnum:]')
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$UDID" "$APP"
  echo "$NAME ($UDID)"
  DEMO=(-BlithDemo balanced -BlithAIConsent NO -BlithClockHour 15.5)
  for MODE in light dark; do
    xcrun simctl ui "$UDID" appearance "$MODE"
    shoot "$UDID" "$NAME-$MODE-1-today" "${DEMO[@]}" -BlithTab today
    shoot "$UDID" "$NAME-$MODE-2-walk" "${DEMO[@]}" -BlithTab walk -BlithPeriod month -BlithWalkDaysAgo 40
    shoot "$UDID" "$NAME-$MODE-3-ask" "${DEMO[@]}" -BlithTab ask -BlithAskScript YES
    shoot "$UDID" "$NAME-$MODE-4-body" "${DEMO[@]}" -BlithTab body -BlithBodyFocus sample-ankle
    if [ "$MODE" = light ]; then
      shoot "$UDID" "$NAME-$MODE-5-body-front" "${DEMO[@]}" -BlithTab body
      shoot "$UDID" "$NAME-$MODE-6-insight" "${DEMO[@]}" -BlithSheet insight
      shoot "$UDID" "$NAME-$MODE-7-sleep" "${DEMO[@]}" -BlithSheet sleep
      shoot "$UDID" "$NAME-$MODE-8-achievements" "${DEMO[@]}" -BlithSheet achievements
      shoot "$UDID" "$NAME-$MODE-9-walk-day" "${DEMO[@]}" -BlithTab walk -BlithPeriod day
      shoot "$UDID" "$NAME-$MODE-10-newuser" -BlithDemo newUser -BlithClockHour 15.5 -BlithTab today
      shoot "$UDID" "$NAME-$MODE-11-onboarding" -BlithResetOnboarding YES
    fi
  done
  xcrun simctl shutdown "$UDID" || true
done
ls -1 "$OUT"
