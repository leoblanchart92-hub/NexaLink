#!/usr/bin/env python3
"""Audit resolved AAR or published sources; never dump WireGuard settings/keys."""
import base64
import hashlib
import io
import json
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

VERSION = '1.0.20230706'
TAG_COMMIT = '58789d6372e8948b87f5c47da7e5f2ad570eb531'
MAVEN = f'https://repo.maven.apache.org/maven2/com/wireguard/android/tunnel/{VERSION}/tunnel-{VERSION}'
sha = lambda b: hashlib.sha256(b).hexdigest()
out = Path('test-diagnostics'); out.mkdir(exist_ok=True)
mode = sys.argv[1]

def notice(label, value):
    print(f'::notice title={label}::{base64.b64encode(json.dumps(value,separators=(",", ":")).encode()).decode()}')

if mode == 'resolved':
    candidates = list((Path.home()/'.gradle/caches/modules-2/files-2.1/com.wireguard.android/tunnel'/VERSION).glob('**/*.aar'))
    hashes = {sha(p.read_bytes()) for p in candidates}
    if len(hashes) != 1: raise SystemExit(f'Expected exactly one resolved AAR hash; found {len(hashes)}')
    archive = zipfile.ZipFile(candidates[0]); classes = archive.read('classes.jar')
    with tempfile.TemporaryDirectory() as temp:
        jar = Path(temp)/'classes.jar'; jar.write_bytes(classes)
        outputs = []
        for classname in ('com.wireguard.android.backend.Backend', 'com.wireguard.android.backend.GoBackend',
                          'com.wireguard.android.backend.GoBackend$VpnService', 'com.wireguard.android.backend.Statistics',
                          'com.wireguard.android.backend.Tunnel'):
            p = subprocess.run(['javap', '-classpath', str(jar), '-c', '-p', '-s', classname], capture_output=True, text=True, check=True)
            outputs.append(f'==== {classname} ====\n{p.stdout}')
        disassembly = '\n'.join(outputs)
    (out/'wireguard-aar-javap.txt').write_text(disassembly)
    apk = zipfile.ZipFile('build/app/outputs/flutter-apk/app-release.apk')
    native = {}
    for abi in ('x86', 'x86_64', 'arm64-v8a', 'armeabi-v7a'):
        aar_data = archive.read(f'jni/{abi}/libwg-go.so')
        apk_data = apk.read(f'lib/{abi}/libwg-go.so')
        native[abi] = {'aar_sha256': sha(aar_data), 'apk_sha256': sha(apk_data), 'byte_identical': aar_data == apk_data}
    protect = re.findall(r'invokevirtual[^\n]*VpnService\.protect:\(I\)Z\s*\n\s*\d+:\s+pop', disassembly)
    summary = {'version': VERSION, 'aar_sha256': next(iter(hashes)), 'classes_jar_sha256': sha(classes),
               'protect_return_discarded_bytecode_count': len(protect), 'native': native,
               'note': 'Static fingerprints and disassembly, not reproducible-build or runtime proof.'}
    (out/'wireguard-resolved-aar.json').write_text(json.dumps(summary,indent=2)+'\n')
    notice('WIREGUARD_RESOLVED_AAR', summary)
elif mode == 'published':
    def download(url):
        with urllib.request.urlopen(url, timeout=60) as r: return r.read()
    aar = download(MAVEN+'.aar'); sources = download(MAVEN+'-sources.jar')
    tag = download(f'https://codeload.github.com/WireGuard/wireguard-android/tar.gz/{TAG_COMMIT}')
    srcjar = zipfile.ZipFile(io.BytesIO(sources)); tar = tarfile.open(fileobj=io.BytesIO(tag), mode='r:gz')
    files = ('GoBackend.java','Backend.java','Statistics.java','Tunnel.java')
    comparison = {}
    for name in files:
        suffix = 'com/wireguard/android/backend/'+name
        matches = [x for x in srcjar.namelist() if x.endswith(suffix)]
        members = [m for m in tar.getmembers() if m.isfile() and m.name.endswith('tunnel/src/main/java/'+suffix)]
        if len(matches)!=1 or len(members)!=1: raise SystemExit(f'Source missing or ambiguous: {name}')
        a=srcjar.read(matches[0]); b=tar.extractfile(members[0]).read()
        comparison[name] = {'sources_jar_sha256':sha(a),'tag_sha256':sha(b),'byte_identical':a==b}
    summary={'version':VERSION,'published_aar_sha256':sha(aar),'published_sources_sha256':sha(sources),
             'tag_commit':TAG_COMMIT,'source_comparison':comparison,
             'note':'Source-jar matches are not a reproducible binary build or proof of unexamined code.'}
    (out/'wireguard-published-provenance.json').write_text(json.dumps(summary,indent=2)+'\n')
    notice('WIREGUARD_PUBLISHED_PROVENANCE',summary)
    if not all(v['byte_identical'] for v in comparison.values()): sys.exit(1)
else:
    raise SystemExit('expected resolved or published')
