#!/usr/bin/env python3
"""Synthetic SDK regression: source stays unchanged, repairs and cache are safe."""
from pathlib import Path
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / 'Tools/prepare-sdk.py'
CLASSES = '_NSURLRequest, _NSMutableURLRequest, _NSURLConnection, _NSHTTPURLResponse, _NSURLResponse, _NSCachedURLResponse'

def run(source, destination, ok=True):
    result = subprocess.run([sys.executable, str(SCRIPT), str(source), str(destination)], capture_output=True, text=True)
    assert (result.returncode == 0) == ok, result.stdout + result.stderr
    return result

with tempfile.TemporaryDirectory(prefix='fntv-sdk-test-') as tmp:
    root = Path(tmp)
    source = root / 'input.sdk'
    files = {
        'usr/lib/crt1.3.1.o': 'synthetic-crt',
        'usr/lib/libSystem.tbd': 'archs: [ armv7, arm64, i386, x86_64 ]\nre-exports: [ /usr/lib/system/liblaunch.dylib, /usr/lib/system/libc.dylib ]\nsymbols:            [ _read ]\n',
        'System/Library/Frameworks/Foundation.framework/Foundation.tbd': 'archs: [ armv7, i386 ]\nobjc-classes: [ _NSObject ]\n',
        'System/Library/Frameworks/CFNetwork.framework/CFNetwork.tbd': f'archs: [ armv7, x86_64 ]\nobjc-classes: [ {CLASSES}, _Other ]\n'
    }
    for relative, text in files.items():
        path = source / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    destination = root / 'prepared.sdk'
    run(source, destination)
    for relative, text in files.items():
        assert (source / relative).read_text() == text, 'Input SDK was changed'
    system = (destination / 'usr/lib/libSystem.tbd').read_text()
    assert 'liblaunch' not in system and 'i386' not in system and 'x86_64' not in system
    assert all(symbol in system for symbol in ('_memcmp', '_memcpy', '_memmove', '_memset'))
    for framework in ('Foundation', 'CFNetwork'):
        text = (destination / f'System/Library/Frameworks/{framework}.framework/{framework}.tbd').read_text()
        assert all((name in text) == (framework == 'Foundation') for name in CLASSES.split(', '))
    assert 'Using prepared build SDK' in run(source, destination).stdout
    run(source, source, ok=False)
    run(source, source / 'nested.sdk', ok=False)
    unfinished = root / 'unfinished.sdk'
    unfinished.mkdir()
    run(source, unfinished, ok=False)
    external = root / 'external.tbd'
    external.write_text('unchanged')
    (source / 'escape.tbd').symlink_to(external)
    run(source, root / 'unsafe.sdk', ok=False)
    assert external.read_text() == 'unchanged'
print('PASS: SDK repair, original preservation, idempotence, path and symlink guards')
