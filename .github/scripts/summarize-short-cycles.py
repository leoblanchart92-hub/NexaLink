#!/usr/bin/env python3
"""Summarize test-only records; never turn missing records or failed probes into success."""
import base64
import collections
import json
import sys
from pathlib import Path

path, label = Path(sys.argv[1]), sys.argv[2]
rows, malformed = [], 0
for line in path.read_text(errors="replace").splitlines():
    try:
        row = json.loads(line)
        if not isinstance(row, dict): raise ValueError("not an object")
        rows.append(row)
    except (ValueError, json.JSONDecodeError):
        malformed += 1
ids = [r.get("cycle") for r in rows]
complete = len(rows) == 30 and set(ids) == set(range(30)) and malformed == 0
errors = collections.Counter(e for r in rows for e in r.get("errors", "").split(",") if e)
summary = {
    "label": label, "requested": 30, "recorded": len(rows), "malformed": malformed,
    "complete": complete, "errors": errors,
    "default_echo": sum(r.get("default", {}).get("echo") is True for r in rows),
    "bound_echo": sum(r.get("bound", {}).get("echo") is True for r in rows),
    "default_failed_bound_succeeded": sum(r.get("default", {}).get("echo") is False and r.get("bound", {}).get("echo") is True for r in rows),
    "orders": collections.Counter(r.get("order", "unavailable") for r in rows),
}
def notice(title, obj):
    data = json.dumps(obj, separators=(",", ":"), ensure_ascii=True).encode()
    print(f'::notice title={title}::{base64.b64encode(data).decode()}')
notice(f'PHASE82_SUMMARY_{label}', summary)
# Compact examples fit GitHub annotation limits; complete records remain in the artifact.
for kind, predicate in (("SUCCESS", lambda r: not r.get("errors")),
                        ("FAILURE", lambda r: bool(r.get("errors")))):
    row = next((r for r in rows if predicate(r)), None)
    if row is None: continue
    keys = ("uid", "pid", "thread", "localPort", "localPortAfterSend", "socketLocalOnCreate", "socketLocalAfterSend", "remote", "activeBefore", "activeAtCreate", "activeAtSend", "activeAfter", "networkEvents", "socketCreateElapsedMs", "sentElapsedMs", "finishedElapsedMs", "sent", "echo", "boundVpn", "error", "wgTxBefore", "wgRxBefore", "wgTxAfter", "wgRxAfter", "handshakeMillis")
    example = {k: row.get(k) for k in ("cycle", "mode", "order", "startElapsedMs", "vpnStartedElapsedMs", "stopState", "serviceAfterStop", "leaseReleased", "errors")}
    for name in ("default", "bound"):
        example[name] = {k: row.get(name, {}).get(k) for k in keys}
    notice(f'PHASE82_{kind}_{label}', example)
if not complete or errors:
    sys.exit(1)
