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
ids = [r.get('cycle') for r in rows]
complete = len(rows) == 100 and set(ids) == set(range(100)) and parse_errors == 0
summary = {
    'label': label, 'requested': 100, 'recorded': len(rows), 'parse_errors': parse_errors, 'complete': complete,
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
                              closed=r.get('wireSocketsClosed')) for r in failures[:1]],
    'socket_v4_mark_available': sum(isinstance(r.get('wireSocketsBefore', {}).get('V4', {}).get('soMark'), int) for r in rows),
    'socket_v4_mark_bit17_set': sum(bool(r.get('wireSocketsBefore', {}).get('V4', {}).get('soMark', 0) & (1 << 17)) for r in rows),
}
encoded = base64.b64encode(json.dumps(summary, separators=(',', ':')).encode()).decode()
print(f'::notice title=PHASE81_CYCLES_{label}::{encoded}')

# Full per-cycle sanitized records remain in the uploaded artifact. Emit a
# compressed copy only when it fits in one notice (GitHub limits notices/step).
compressed = base64.b64encode(gzip.compress(path.read_bytes())).decode()
if len(compressed) <= 1800:
    print(f'::notice title=PHASE81_DATA_{label}_00::{compressed}')

if not complete:
    print(f'Incomplete or invalid cycle evidence for {label}', file=sys.stderr)
    sys.exit(1)
