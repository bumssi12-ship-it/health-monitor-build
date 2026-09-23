#!/usr/bin/env python3
from pathlib import Path
import re
import sys

path = Path("HealthMonitor/DatabaseManager.swift")
text = path.read_text(encoding="utf-8")

required_fragments = [
    "if previousVersion < 5",
    'ALTER TABLE symptoms ADD COLUMN event_id TEXT;',
    'ALTER TABLE medications ADD COLUMN event_id TEXT;',
    'ALTER TABLE orthostatic_sessions ADD COLUMN event_id TEXT;',
    "SET event_id = 'local-' || lower(hex(randomblob(16)))",
    "if previousVersion < 4",
    "DELETE FROM health_samples WHERE type = 'step_count';",
    "setUserVersionUnsafe(5)",
    "idx_symptoms_event_id_unique",
    "idx_medications_event_id_unique",
    "idx_orthostatic_event_id_unique",
]

errors = []
for fragment in required_fragments:
    if fragment not in text:
        errors.append(f"missing migration contract: {fragment}")

if text.count("SET event_id = 'local-' || lower(hex(randomblob(16)))") != 3:
    errors.append("expected event_id backfill for exactly 3 user-event tables")

for table in ("symptoms", "medications", "orthostatic_sessions"):
    pattern = rf"CREATE UNIQUE INDEX IF NOT EXISTS .*?ON {table}\(event_id\)"
    if re.search(pattern, text, flags=re.S) is None:
        errors.append(f"missing unique event_id index for {table}")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)

print(
    "PASS: schema v5 migration contract, legacy step cleanup, "
    "event-id backfill and uniqueness guards verified"
)
