#!/usr/bin/env python3
"""Report all outcomes while retaining individual sanitized records as an artifact."""
import base64
import collections
import gzip
import json
import sys
from pathlib import Path

path, label = Path(sys.argv[1]), sys.argv[2]
rows = []
parse_errors = 0
for line in path.read_text(errors='replace').splitlines():
    try:
        rows.append(json.loads(line))
    except json.JSONDecodeError:
        parse_errors += 1
counts = collections.Counter()
for r in rows:
    for error in filter(None, r.get('errors', '').split(',')):
        counts[error] += 1

def counters(s):
    result = {}
    for field in s.split(','):
        if '=' in field:
            k, v = field.split('=', 1)
            if v.isdigit():
                result[k] = int(v)
    return result

def delta(r, name):
    before, after = counters(r.get('tunBefore', '')), counters(r.get('tunAfter', ''))
    return after[name] - before[name] if name in before and name in after else None

failures = [r for r in rows if r.get('errors')]
summary = {
    'label': label, 'requested': 100, 'recorded': len(rows), 'parse_errors': parse_errors,
    'passed': len(rows) - len(failures), 'failed': len(failures), 'errors': counts,
    'by_mode': {mode: {'count': len([r for r in rows if r.get('mode') == mode]),
                       'failed': len([r for r in failures if r.get('mode') == mode])}
                for mode in ('reused', 'fresh')},
    'failure_tun_tx_positive': sum((delta(r, 'tx_packets') or 0) > 0 for r in failures),
    'failure_tun_tx_zero': sum(delta(r, 'tx_packets') == 0 for r in failures),
    'failure_tun_tx_unavailable': sum(delta(r, 'tx_packets') is None for r in failures),
    'bound_diagnostic_echo_after_failure': sum(r.get('boundDiagnostic', {}).get('echo', False) for r in failures),
    'failure_examples': [dict(cycle=r.get('cycle'), errors=r.get('errors'),
                              probe=r.get('probe'), tunBefore=r.get('tunBefore'), tunAfter=r.get('tunAfter'),
                              wgTx=r.get('wgTxBytes'), wgRx=r.get('wgRxBytes'),
                              bound=r.get('boundDiagnostic'), sockets=r.get('wireSocketsBefore'),
                              closed=r.get('wireSocketsClosed')) for r in failures[:2]],
}
encoded = base64.b64encode(json.dumps(summary, separators=(',', ':')).encode()).decode()
print(f'::notice title=PHASE81_CYCLES_{label}::{encoded}')

# Compact, sanitized per-cycle records in annotations as well as the artifact;
# this keeps partial evidence accessible if a job times out. Never output keys.
compressed = base64.b64encode(gzip.compress(path.read_bytes())).decode()
chunks = [compressed[i:i + 1800] for i in range(0, len(compressed), 1800)]
if len(chunks) <= 30:
    for i, chunk in enumerate(chunks):
        print(f'::notice title=PHASE81_DATA_{label}_{i:02d}::{chunk}')
else:
    print(f'::warning title=PHASE81_DATA::{label}: records exceed annotation limit; use artifact')
