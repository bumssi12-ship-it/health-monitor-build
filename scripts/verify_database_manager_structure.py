#!/usr/bin/env python3
from pathlib import Path
import re
import sys

path = Path("HealthMonitor/DatabaseManager.swift")
text = path.read_text(encoding="utf-8")

match = re.search(r"final\s+class\s+DatabaseManager\b[^{]*\{", text)
if not match:
    print("ERROR: DatabaseManager class declaration not found", file=sys.stderr)
    raise SystemExit(1)

start = match.end() - 1
depth = 0
end = None

# Lightweight brace matcher. SQL strings in this file do not contain braces.
for index in range(start, len(text)):
    char = text[index]
    if char == "{":
        depth += 1
    elif char == "}":
        depth -= 1
        if depth == 0:
            end = index
            break

if end is None:
    print("ERROR: DatabaseManager closing brace not found", file=sys.stderr)
    raise SystemExit(1)

inside = text[start:end + 1]
outside = text[end + 1:]

required_methods = [
    "initializeDatabase",
    "userVersion",
    "applyHealthKitChanges",
    "replaceDailyMetrics",
    "dailyMetricValue",
    "dailyMetricCoverageCount",
    "averageDailyMetric",
    "addSymptom",
    "addMedication",
    "addOrthostaticSession",
    "latestSample",
    "resetHealthCache",
    "latestValue",
    "recordedDayCount",
    "averageValue",
    "symptomCount",
    "recentSymptoms",
    "recentMedications",
    "recentOrthostaticSessions",
    "sleepSummary",
    "exportHealthSamples",
    "exportDailyMetrics",
    "quickCheck",
    "integrityCheck",
    "makeUserBackup",
    "importUserBackup",
    "reportText",
]

missing = []
escaped = []

for method in required_methods:
    if re.search(rf"\bfunc\s+{re.escape(method)}\b", inside) is None:
        missing.append(method)
    if re.search(rf"\bfunc\s+{re.escape(method)}\b", outside):
        escaped.append(method)

if missing:
    print("ERROR: required methods missing from DatabaseManager class:", ", ".join(missing), file=sys.stderr)

if escaped:
    print("ERROR: DatabaseManager methods found outside class:", ", ".join(escaped), file=sys.stderr)

if missing or escaped:
    raise SystemExit(1)

print(
    f"PASS: DatabaseManager class contains {len(required_methods)} required methods; none escaped class scope"
)
