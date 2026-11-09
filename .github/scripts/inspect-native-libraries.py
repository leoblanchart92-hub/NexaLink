#!/usr/bin/env python3
"""Record static native ABI/build metadata, not runtime data or keys."""
from pathlib import Path
import subprocess
import tempfile
import zipfile

apk = Path('build/app/outputs/flutter-apk/app-release.apk')
out = Path('test-diagnostics/native-abi-metadata.txt')
out.parent.mkdir(parents=True, exist_ok=True)
lines = []
with zipfile.ZipFile(apk) as archive, tempfile.TemporaryDirectory() as tmp:
    for abi in ('x86', 'x86_64', 'arm64-v8a', 'armeabi-v7a'):
        exported = {}
        for library in ('libgojni.so', 'libwg-go.so'):
            name = f'lib/{abi}/{library}'
            path = Path(tmp) / library
            path.write_bytes(archive.read(name))
            lines.append(f'=== {abi}/{library} ===')
            for command in (['readelf', '-h', str(path)], ['go', 'version', '-m', str(path)]):
                result = subprocess.run(command, capture_output=True, text=True)
                lines.append(f'{command[0]} exit={result.returncode}\n{result.stdout}{result.stderr}')
            result = subprocess.run(['readelf', '--dyn-syms', '--wide', str(path)], capture_output=True, text=True, check=True)
            symbols = set()
            for row in result.stdout.splitlines():
                cols = row.split()
                if len(cols) >= 8 and cols[4] in ('GLOBAL', 'WEAK') and cols[6] != 'UND':
                    symbols.add(cols[7].split('@', 1)[0])
            exported[library] = symbols
            lines.append(f'defined dynamic symbols: {len(symbols)}')
        shared = sorted(exported['libgojni.so'] & exported['libwg-go.so'])
        lines.append(f'shared defined dynamic symbols ({len(shared)}): {", ".join(shared)}')
out.write_text('\n'.join(lines) + '\n')
print(f'Native ABI/build metadata recorded in {out}; no execution is implied.')
