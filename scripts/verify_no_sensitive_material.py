#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

forbidden_suffixes = {
    ".sqlite",
    ".sqlite3",
    ".db",
    ".p12",
    ".mobileprovision",
    ".cer",
    ".key",
}
forbidden_names = {".env"}
token_patterns = [
    re.compile(rb"gh[opsu]_[A-Za-z0-9_]{20,}"),
    re.compile(rb"github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(rb"sk-proj-[A-Za-z0-9_-]{20,}"),
    re.compile(rb"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
]

errors: list[str] = []

for path in ROOT.rglob("*"):
    if not path.is_file():
        continue

    rel = path.relative_to(ROOT)
    if any(
        part in {".git", ".build", "build", "__pycache__"}
        for part in rel.parts
    ):
        continue

    lower_name = path.name.lower()

    if path.suffix.lower() in forbidden_suffixes:
        errors.append(
            f"forbidden runtime/credential file: {rel}"
        )
        continue

    if lower_name in forbidden_names or lower_name.startswith(".env."):
        errors.append(
            f"forbidden environment file: {rel}"
        )
        continue

    try:
        if path.stat().st_size > 5 * 1024 * 1024:
            continue
        data = path.read_bytes()
    except OSError:
        continue

    for pattern in token_patterns:
        if pattern.search(data):
            errors.append(
                f"possible secret material: {rel}"
            )
            break

if errors:
    for error in sorted(set(errors)):
        print(f"ERROR: {error}", file=sys.stderr)
    raise SystemExit(1)

print(
    "PASS: no forbidden runtime files or common secret signatures found"
)
