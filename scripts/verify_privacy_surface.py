#!/usr/bin/env python3
from pathlib import Path
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def source_text(folder: str) -> str:
    return "\n".join(
        p.read_text(encoding="utf-8", errors="ignore")
        for p in (ROOT / folder).rglob("*.swift")
    )

ios_text = source_text("HealthMonitor") + "\n" + source_text("Shared")
watch_text = source_text("HealthMonitorWatch") + "\n" + source_text("Shared")

ios_manifest_path = ROOT / "HealthMonitor" / "PrivacyInfo.xcprivacy"

if not ios_manifest_path.exists():
    print("ERROR: iOS privacy manifest missing", file=sys.stderr)
    raise SystemExit(1)

ios_manifest = plistlib.loads(ios_manifest_path.read_bytes())
ios_api_entries = ios_manifest.get("NSPrivacyAccessedAPITypes", [])

def reasons_for(category: str) -> set[str]:
    reasons: set[str] = set()
    for item in ios_api_entries:
        if item.get("NSPrivacyAccessedAPIType") == category:
            reasons.update(item.get("NSPrivacyAccessedAPITypeReasons", []))
    return reasons

errors: list[str] = []

uses_defaults = (
    "UserDefaults" in ios_text
    or "@AppStorage" in ios_text
)
if uses_defaults and "CA92.1" not in reasons_for(
    "NSPrivacyAccessedAPICategoryUserDefaults"
):
    errors.append(
        "iOS uses UserDefaults/@AppStorage but CA92.1 is not declared"
    )

# Keep this list intentionally conservative. attributesOfItem is included
# because it exposes size/metadata and maps to the C617.1 approved reason.
file_metadata_patterns = [
    r"\battributesOfItem\s*\(",
    r"\bcontentModificationDate\b",
    r"\bcreationDateKey\b",
    r"\bfileModificationDate\b",
]
uses_file_metadata = any(
    re.search(pattern, ios_text)
    for pattern in file_metadata_patterns
)
if uses_file_metadata and "C617.1" not in reasons_for(
    "NSPrivacyAccessedAPICategoryFileTimestamp"
):
    errors.append(
        "iOS accesses app-container file metadata but C617.1 is not declared"
    )

watch_required_patterns = [
    r"\bUserDefaults\b",
    r"@AppStorage\b",
    r"\battributesOfItem\s*\(",
    r"\bsystemUptime\b",
    r"\bvolumeAvailableCapacity",
]
if any(re.search(pattern, watch_text) for pattern in watch_required_patterns):
    if not (ROOT / "HealthMonitorWatch" / "PrivacyInfo.xcprivacy").exists():
        errors.append(
            "watchOS source uses a required-reason API but Watch PrivacyInfo.xcprivacy is absent"
        )

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)

print("PASS: privacy required-reason surface matches bundled manifests")
