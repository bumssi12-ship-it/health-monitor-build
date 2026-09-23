#!/usr/bin/env python3
from pathlib import Path
import re
import sys

project = Path("HealthMonitor.xcodeproj/project.pbxproj")
if not project.is_file():
    print("ERROR: generated project.pbxproj not found", file=sys.stderr)
    raise SystemExit(1)

text = project.read_text(encoding="utf-8")
errors = []

if "PrivacyInfo.xcprivacy" not in text:
    errors.append("PrivacyInfo.xcprivacy missing from generated project")

# Match the exact PBXCopyFilesBuildPhase object named "Embed Watch Content".
# Do not match PBXBuildFile comments such as
# "HealthMonitorWatch.app in Embed Watch Content".
phase_pattern = re.compile(
    r"^[\\t ]*[A-F0-9]{24} /\\* Embed Watch Content \\*/ = \\{"
    r"(?P<body>.*?)"
    r"^[\\t ]*\\};",
    re.S | re.M,
)
phases = list(phase_pattern.finditer(text))

if len(phases) != 1:
    errors.append(
        f"Expected exactly one Embed Watch Content copy phase, found {len(phases)}"
    )
else:
    body = phases[0].group("body")

    if "isa = PBXCopyFilesBuildPhase;" not in body:
        errors.append("Embed Watch Content is not a PBXCopyFilesBuildPhase")

    if not re.search(r"dstSubfolderSpec\\s*=\\s*13;", body):
        errors.append(
            "Embed Watch Content does not use PlugIns dstSubfolderSpec=13"
        )

    if not re.search(r'dstPath\\s*=\\s*"";', body):
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
