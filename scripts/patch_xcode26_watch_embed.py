#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys

project = Path("HealthMonitor.xcodeproj/project.pbxproj")
if not project.exists():
    print("patch: project file not found", file=sys.stderr)
    sys.exit(1)

major = 0
try:
    output = subprocess.check_output(["xcodebuild", "-version"], text=True)
    match = re.search(r"Xcode\s+(\d+)", output)
    if match:
        major = int(match.group(1))
except Exception:
    pass

if major and major < 26:
    print(f"patch: Xcode {major}; legacy Watch embed path retained")
    sys.exit(0)

text = project.read_text(encoding="utf-8")
pattern = re.compile(
    r"(?P<head>[A-F0-9]{24}\s+/\*\s+Embed Watch Content\s+\*/\s*=\s*\{)"
    r"(?P<body>.*?)"
    r"(?P<tail>\n\s*\};)",
    re.S,
)

match = pattern.search(text)
if not match:
    print("patch: Embed Watch Content phase not found; inspect generated project", file=sys.stderr)
    sys.exit(2)

body = match.group("body")
patched = body
patched = re.sub(r'dstPath\s*=\s*"[^"]*";', 'dstPath = "";', patched)
patched = re.sub(r'dstSubfolderSpec\s*=\s*\d+;', 'dstSubfolderSpec = 13;', patched)

if patched == body:
    print("patch: Embed Watch Content already uses PlugIns destination")
else:
    text = text[:match.start("body")] + patched + text[match.end("body"):]
    project.write_text(text, encoding="utf-8")
    print("patch: Xcode 26+ Watch embedding changed to PlugIns (dstSubfolderSpec=13)")
