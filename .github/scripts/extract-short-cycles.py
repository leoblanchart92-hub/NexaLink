#!/usr/bin/env python3
"""Reassemble bounded logcat parts; reject missing, duplicate or invalid records."""
import json
import re
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:3])
expected = int(sys.argv[3]) if len(sys.argv) > 3 else 30
if expected < 1 or expected > 100: raise SystemExit('invalid expected cycle count')
parts = {}
errors = []
pattern = re.compile(r'^PART=(\d+):(\d+)/(\d+):(.*)$')
for line in source.read_text(errors='replace').splitlines():
    if not line.startswith('PART='): continue
    match = pattern.fullmatch(line)
    if not match:
        errors.append('malformed part'); continue
    cycle, index, total = map(int, match.group(1, 2, 3))
    if cycle >= expected or total < 1 or total > 100 or index >= total:
        errors.append('invalid part index'); continue
    previous_total, chunks = parts.setdefault(cycle, (total, {}))
    if previous_total != total or index in chunks:
        errors.append(f'duplicate or inconsistent part for cycle {cycle}'); continue
    chunks[index] = match.group(4)
records = []
for cycle, (total, chunks) in sorted(parts.items()):
    if len(chunks) != total:
        errors.append(f'missing part for cycle {cycle}'); continue
    text = ''.join(chunks[i] for i in range(total))
    try:
        record = json.loads(text)
        if not isinstance(record, dict) or record.get('cycle') != cycle:
            raise ValueError('cycle mismatch')
    except (ValueError, json.JSONDecodeError):
        errors.append(f'invalid JSON for cycle {cycle}'); continue
    records.append(json.dumps(record, separators=(',', ':')))
destination.write_text(''.join(row + '\n' for row in records))
if len(records) != expected:
    errors.append(f'expected {expected} complete records, found {len(records)}')
for error in errors: print(error, file=sys.stderr)
if errors: sys.exit(1)
