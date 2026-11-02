#!/usr/bin/env bash
# Captures every screen of Plumb on the iPhone 17 Pro simulator in dark and light mode, using the
# app's debug-only launch flags (-screen, -appearance; see Plumb/App/DebugLaunch.swift).
# Output: fastlane/captures/<appearance>/<screen>.png (review only; store screenshots live in fastlane/screenshots/en-US)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$(cd "$ROOT/.." && pwd)/PlumbTestBuild/fastlane-shots"
OUT="$ROOT/fastlane/captures"
BUNDLE="com.plimb.Plumb"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"

UDID="$(xcrun simctl list devices available | grep -m1 "    $DEVICE_NAME (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "No simulator named '$DEVICE_NAME'"; exit 1; }

xcodebuild -project "$ROOT/Plumb.xcodeproj" -scheme Plumb -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$BUILD" build -quiet
APP="$BUILD/Build/Products/Debug-iphonesimulator/Plumb.app"

boot() { xcrun simctl list devices | grep -q "$UDID) (Booted)" || { xcrun simctl boot "$UDID" || true; xcrun simctl bootstatus "$UDID" -b >/dev/null; }; }
boot
xcrun simctl install "$UDID" "$APP"

SCREENS=(onboarding home tools projects history live level calibration surface angle protractor compass
  ruler ar room photo slope calculators converter convert.length convert.temperature shapes shape.square
  shape.circle settings paywall report project unavailable.motionUnavailable unavailable.cameraPermission)

for appearance in dark light; do
  mkdir -p "$OUT/$appearance"
  for s in "${SCREENS[@]}"; do
    boot
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE" -screen "$s" -appearance "$appearance" >/dev/null
    sleep 2.5
    xcrun simctl io "$UDID" screenshot "$OUT/$appearance/$s.png" >/dev/null 2>&1
    echo "captured $appearance/$s"
  done
done
echo "Screenshots in $OUT"
