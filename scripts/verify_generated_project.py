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

phase = re.search(
    r"Embed Watch Content\s+\*/\s*=\s*\{(?P<body>.*?)\n\s*\};",
    text,
    re.S,
)

if not phase:
    errors.append("Embed Watch Content phase missing")
else:
    body = phase.group("body")
    if not re.search(r'dstSubfolderSpec\s*=\s*13;', body):
        errors.append("Embed Watch Content does not use PlugIns dstSubfolderSpec=13")
    if not re.search(r'dstPath\s*=\s*"";', body):
        errors.append("Embed Watch Content dstPath is not empty")

if "HealthMonitorWatch" not in text:
    errors.append("HealthMonitorWatch target missing")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)

print("PASS: generated Xcode project structure and Watch embed destination verified")
