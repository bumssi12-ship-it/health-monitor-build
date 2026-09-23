#!/usr/bin/env python3
from pathlib import Path
import sys

project = Path("HealthMonitor.xcodeproj/project.pbxproj")
if not project.is_file():
    print("ERROR: generated project.pbxproj not found", file=sys.stderr)
    raise SystemExit(1)

text = project.read_text(encoding="utf-8")
errors = []

if "PrivacyInfo.xcprivacy" not in text:
    errors.append("PrivacyInfo.xcprivacy missing from generated project")

marker = "/* Embed Watch Content */ = {"
count = text.count(marker)

if count != 1:
    errors.append(
        f"Expected exactly one Embed Watch Content copy phase, found {count}"
    )
else:
    start = text.index(marker)
    end = text.find("\n\t\t};", start)

    if end == -1:
        errors.append("Embed Watch Content phase terminator not found")
    else:
        body = text[start:end]

        if "isa = PBXCopyFilesBuildPhase;" not in body:
            errors.append("Embed Watch Content is not a PBXCopyFilesBuildPhase")

        if "dstSubfolderSpec = 13;" not in body:
            errors.append(
                "Embed Watch Content does not use PlugIns dstSubfolderSpec=13"
            )

        if 'dstPath = "";' not in body:
            errors.append("Embed Watch Content dstPath is not empty")

        if "HealthMonitorWatch.app in Embed Watch Content" not in body:
            errors.append("Watch app is not present in Embed Watch Content phase")

if "HealthMonitorWatch" not in text:
    errors.append("HealthMonitorWatch target missing")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)

print(
    "PASS: generated Xcode project structure and Watch embed destination verified"
)
