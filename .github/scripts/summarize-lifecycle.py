#!/usr/bin/env python3
"""Report observation, not a readiness or packet-location guarantee."""
import base64
import collections
import json
import sys
from pathlib import Path
rows=[]
malformed=0
for line in Path(sys.argv[1]).read_text(errors='replace').splitlines():
    try:
        r=json.loads(line)
        if not isinstance(r,dict): raise ValueError('not an object')
        rows.append(r)
    except (ValueError,json.JSONDecodeError): malformed+=1
complete=len(rows)==8 and {r.get('cycle') for r in rows}==set(range(8)) and malformed==0
errors=collections.Counter(e for r in rows for e in r.get('errors','').split(',') if e)
result={'label':sys.argv[2], 'requested':8, 'recorded':len(rows), 'malformed':malformed,
        'complete':complete,'errors':errors,
        'echoes':sum(r.get('firstProbe',{}).get('echo') is True for r in rows),
        'handshake_snapshot_positive':sum(r.get('latestHandshakeEpochMs',0)>0 for r in rows),
        'tun_established_event':'not exposed', 'socket_open_event':'not exposed',
        'protect_result':'not exposed', 'handshake':'snapshot, not event', 'examples':[]}
for failed in (False,True):
    r=next((r for r in rows if bool(r.get('errors'))==failed),None)
    if r is None: continue
    fields=('cycle','probeCycle','beginElapsedMs','stateBefore','serviceBefore','startCalledElapsedMs',
            'startReturnedElapsedMs','startReturnedState','serviceAfterStart','socketSnapshotAfterStart',
            'socketSnapshotElapsedMs','statisticsObservedElapsedMs','wgTxBytes','wgRxBytes',
            'latestHandshakeEpochMs','stopCalledElapsedMs','stopReturnedElapsedMs','stopReturnedState',
            'serviceAfterStop','socketSnapshotAfterStop','leaseReleased','errors')
    v={k:r.get(k) for k in fields}
    for name in ('before','networkAfterStart','firstProbe','after'):
        sample=r.get(name,{})
        v[name]={k:sample.get(k) for k in ('networkHandle','vpnReady','vpnGone','sent','echo','startedElapsedMs','sentElapsedMs','receivedElapsedMs','finishedElapsedMs','error')}
    result['examples'].append(v)
encoded=base64.b64encode(json.dumps(result,separators=(',',':')).encode()).decode()
# Keep concise annotations; full JSONL and logs remain in the diagnostics artifact.
if len(encoded)>3900:
    result['examples']=result['examples'][:1]
    encoded=base64.b64encode(json.dumps(result,separators=(',',':')).encode()).decode()
print(f'::notice title=PHASE83_LIFECYCLE_{sys.argv[2]}::{encoded}')
if not complete or errors: sys.exit(1)
