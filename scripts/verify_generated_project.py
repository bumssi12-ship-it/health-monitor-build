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
positions = []
offset = 0

while True:
    index = text.find(marker, offset)
    if index == -1:
        break
    positions.append(index)
    offset = index + len(marker)

if len(positions) != 1:
    errors.append(
        f"Expected exactly one Embed Watch Content copy phase, found {len(positions)}"
    )
else:
    marker_start = positions[0]
    open_brace = text.find("{", marker_start)

    if open_brace == -1:
        errors.append("Embed Watch Content opening brace not found")
    else:
        depth = 0
        close_brace = None

        for index in range(open_brace, len(text)):
            char = text[index]

            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    close_brace = index
                    break

        if close_brace is None:
            errors.append("Embed Watch Content closing brace not found")
        else:
            body = text[marker_start : close_brace + 1]

            required_fragments = {
                "PBXCopyFilesBuildPhase":
                    "isa = PBXCopyFilesBuildPhase;",
                "PlugIns destination":
                    "dstSubfolderSpec = 13;",
                "empty destination path":
                    'dstPath = "";',
                "Watch app build file":
                    "HealthMonitorWatch.app in Embed Watch Content",
            }

            for label, fragment in required_fragments.items():
                if fragment not in body:
                    errors.append(
                        f"Embed Watch Content missing {label}: {fragment}"
                    )

            if not errors:
                print("Verified Embed Watch Content phase:")
                for line in body.splitlines():
                    stripped = line.strip()
                    if (
                        stripped.startswith("dstPath =")
                        or stripped.startswith("dstSubfolderSpec =")
                        or "HealthMonitorWatch.app in Embed Watch Content" in stripped
                    ):
                        print(f"  {stripped}")

if "HealthMonitorWatch" not in text:
    errors.append("HealthMonitorWatch target missing")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)

print(
    "PASS: generated Xcode project structure and Watch embed destination verified"
)
