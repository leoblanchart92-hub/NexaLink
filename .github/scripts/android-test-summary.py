#!/usr/bin/env python3
"""Emit only test names/counts/statuses, no log contents or credentials."""
from pathlib import Path
import base64
import json
import re

root = Path('test-diagnostics')
result = {}
for directory in sorted(p for p in root.glob('*') if p.is_dir()):
    status_file = directory / 'exit-status.txt'
    if not status_file.exists():
        continue
    tests = []
    for path in sorted(directory.glob('tests-*.log')):
        text = path.read_text(errors='replace')
        tests.append({
            'started': len(re.findall(r'\bstarted: ', text)),
            'finished': len(re.findall(r'\bfinished: ', text)),
            'assumptions': len(re.findall(r'assumption failed:', text)),
            'owner_loss_started': 'started: ownerServiceStartsAndStopsOnActualCellularLossWhenAvailable' in text,
            'owner_loss_skipped': 'assumption failed: ownerServiceStartsAndStopsOnActualCellularLossWhenAvailable' in text,
        })
    result[directory.name] = {'exit': status_file.read_text().strip(), 'attempts': tests}
channel = root / 'flutter-channel-status.txt'
result['flutter-channel-exit'] = channel.read_text().strip() if channel.exists() else 'not-recorded'
data = json.dumps(result, separators=(',', ':')).encode()
for i in range(0, len(data), 2400):
    encoded = base64.b64encode(data[i:i + 2400]).decode()
    print(f'::notice title=ANDROID_PHASE7_SUMMARY_{i // 2400:02d}::{encoded}')
