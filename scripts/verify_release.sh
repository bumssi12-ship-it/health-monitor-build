#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Xcode =="
xcodebuild -version

echo "== plist =="
plutil -lint HealthMonitor/Info.plist
plutil -lint HealthMonitor/HealthMonitor.entitlements
plutil -lint HealthMonitorWatch/Info.plist
plutil -lint HealthMonitorWatch/HealthMonitorWatch.entitlements

echo "== iPhone target build =="
xcodebuild \
  -project HealthMonitor.xcodeproj \
  -target HealthMonitor \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "PASS: source/plist/iPhone target build"
