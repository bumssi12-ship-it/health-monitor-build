#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import sys

root = Path(__file__).resolve().parents[1]
manifest_path = root / "SOURCE_INTEGRITY.json"

if not manifest_path.exists():
    print("ERROR: SOURCE_INTEGRITY.json not found", file=sys.stderr)
    raise SystemExit(2)

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
errors = []

for entry in manifest.get("files", []):
    path = root / entry["path"]
    if not path.is_file():
        errors.append(f"missing: {entry['path']}")
        continue

    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual.lower() != entry["sha256"].lower():
        errors.append(f"hash mismatch: {entry['path']}")

if errors:
    for item in errors:
        print(f"ERROR: {item}", file=sys.stderr)
    raise SystemExit(1)

print(f"PASS: {len(manifest.get('files', []))} source/config files match SHA-256 manifest")
