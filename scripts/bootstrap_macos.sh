#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: macOS is required for Xcode builds."
  exit 2
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: Xcode command line tools are not available."
  exit 3
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "ERROR: XcodeGen is missing and Homebrew is not installed."
    echo "Install XcodeGen 2.46.0+ and rerun this script."
    exit 4
  fi
fi

echo "== Xcode =="
xcodebuild -version

echo "== XcodeGen =="
xcodegen --version

echo "== Generate project =="
rm -rf HealthMonitor.xcodeproj
xcodegen generate

echo "== List targets/schemes =="
xcodebuild -project HealthMonitor.xcodeproj -list

echo "== Validate plists =="
plutil -lint HealthMonitor/Info.plist
plutil -lint HealthMonitor/HealthMonitor.entitlements
plutil -lint HealthMonitorWatch/Info.plist
plutil -lint HealthMonitorWatch/HealthMonitorWatch.entitlements

echo "== Build Watch target =="
xcodebuild \
  -project HealthMonitor.xcodeproj \
  -target HealthMonitorWatch \
  -configuration Debug \
  -sdk watchsimulator \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "== Build iPhone app target =="
xcodebuild \
  -project HealthMonitor.xcodeproj \
  -target HealthMonitor \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "== Build tests =="
xcodebuild \
  -project HealthMonitor.xcodeproj \
  -target HealthMonitorTests \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "PASS: generated project and all three targets compiled."
