#!/usr/bin/env python3
from pathlib import Path
import plistlib
import sys

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []

project_text = (ROOT / "project.yml").read_text(encoding="utf-8")
xcconfig_text = (ROOT / "Config/BundleIds.xcconfig").read_text(encoding="utf-8")

required_project_fragments = [
    "minimumXcodeGenVersion: 2.46.0",
    "iOS: '17.0'",
    "watchOS: '10.0'",
    "postGenCommand: python3 scripts/patch_xcode26_watch_embed.py",
    "CODE_SIGN_STYLE: Automatic",
    "PRODUCT_BUNDLE_IDENTIFIER: $(HEALTHMONITOR_BUNDLE_ID)",
    "PRODUCT_BUNDLE_IDENTIFIER: $(HEALTHMONITOR_WATCH_BUNDLE_ID)",
    "HealthMonitor/PrivacyInfo.xcprivacy",
]
for fragment in required_project_fragments:
    if fragment not in project_text:
        errors.append(f"project.yml missing contract: {fragment}")

bundle_id = None
watch_bundle_expr = None
for raw_line in xcconfig_text.splitlines():
    line = raw_line.strip()
    if not line or line.startswith("//") or "=" not in line:
        continue
    key, value = [part.strip() for part in line.split("=", 1)]
    if key == "HEALTHMONITOR_BUNDLE_ID":
        bundle_id = value
    elif key == "HEALTHMONITOR_WATCH_BUNDLE_ID":
        watch_bundle_expr = value

if bundle_id != "com.bom.healthmonitor":
    errors.append(f"Unexpected iOS bundle identifier: {bundle_id!r}")

if watch_bundle_expr != "$(HEALTHMONITOR_BUNDLE_ID).watchapp":
    errors.append(
        f"Unexpected watch bundle identifier expression: {watch_bundle_expr!r}"
    )

ios_info = plistlib.loads((ROOT / "HealthMonitor/Info.plist").read_bytes())
watch_info = plistlib.loads((ROOT / "HealthMonitorWatch/Info.plist").read_bytes())
ios_entitlements = plistlib.loads(
    (ROOT / "HealthMonitor/HealthMonitor.entitlements").read_bytes()
)
watch_entitlements = plistlib.loads(
    (ROOT / "HealthMonitorWatch/HealthMonitorWatch.entitlements").read_bytes()
)
privacy = plistlib.loads(
    (ROOT / "HealthMonitor/PrivacyInfo.xcprivacy").read_bytes()
)

if not ios_info.get("NSHealthShareUsageDescription"):
    errors.append("iOS Info.plist missing NSHealthShareUsageDescription")
if not ios_info.get("NSFaceIDUsageDescription"):
    errors.append("iOS Info.plist missing NSFaceIDUsageDescription")

if not watch_info.get("NSHealthShareUsageDescription"):
    errors.append("watchOS Info.plist missing NSHealthShareUsageDescription")
if not watch_info.get("NSHealthUpdateUsageDescription"):
    errors.append("watchOS Info.plist missing NSHealthUpdateUsageDescription")
if watch_info.get("WKCompanionAppBundleIdentifier") != "$(HEALTHMONITOR_BUNDLE_ID)":
    errors.append("watchOS companion bundle identifier contract changed")
if "workout-processing" not in watch_info.get("WKBackgroundModes", []):
    errors.append("watchOS workout-processing background mode missing")

if ios_entitlements.get("com.apple.developer.healthkit") is not True:
    errors.append("iOS HealthKit entitlement missing")
if ios_entitlements.get("com.apple.developer.healthkit.background-delivery") is not True:
    errors.append("iOS HealthKit background-delivery entitlement missing")
if watch_entitlements.get("com.apple.developer.healthkit") is not True:
    errors.append("watchOS HealthKit entitlement missing")

if privacy.get("NSPrivacyTracking") is not False:
    errors.append("Privacy manifest must explicitly disable tracking")

user_defaults_reasons = set()
for item in privacy.get("NSPrivacyAccessedAPITypes", []):
    if item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults":
        user_defaults_reasons.update(item.get("NSPrivacyAccessedAPITypeReasons", []))

if "CA92.1" not in user_defaults_reasons:
    errors.append("Privacy manifest missing UserDefaults reason CA92.1")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)

print(
    "PASS: release contract, bundle identifiers, entitlements, "
    "usage strings and privacy manifest verified"
)
