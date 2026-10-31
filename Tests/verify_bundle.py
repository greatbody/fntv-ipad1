"""Validate the old-device binary and package the exact checked app."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib
import json
import os
import plistlib
import struct
import subprocess

root = Path(__file__).resolve().parents[1]
app = root / 'build/Payload/FNTV.app'
binary = (app / 'FNTV').read_bytes()
magic, cpu, subtype, kind, ncmds, size, flags = struct.unpack_from('<7I', binary)
assert magic == 0xfeedface and cpu == 12 and subtype & 0xffffff == 9 and kind == 2, 'Expected ARMv7 executable'
offset = 28
commands = {}
for _ in range(ncmds):
    command, length = struct.unpack_from('<II', binary, offset)
    assert length >= 8 and offset + length <= len(binary)
    commands[command] = binary[offset:offset + length]
    offset += length
assert 0x5 in commands and 0x80000028 not in commands, 'iOS 5 requires legacy LC_UNIXTHREAD startup'
assert struct.unpack_from('<I', commands[0x25], 8)[0] == 0x50100, 'Expected iOS 5.1 deployment target'
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleExecutable'] == 'FNTV' and info['MinimumOSVersion'] == '5.1'
assert info['CFBundleIdentifier'] == 'ink.sunrui.fntv.ipad1', 'Keep the upgrade/session identity stable'
assert info['UIDeviceFamily'] == [2]
manifest = json.loads((root / 'Assets/manifest.json').read_text())
assert manifest and len({entry['file'] for entry in manifest}) == len(manifest)
assert {entry['file'] for entry in manifest} == {path.name for path in app.glob('*.png')}
for entry in manifest:
    path = app / entry['file']
    assert path.parent == app and path.suffix == '.png'
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack_from('>II', data, 16) == (entry['width'], entry['height'])
    assert hashlib.sha256(data).hexdigest() == entry['sha256'], f"Changed asset: {path.name}"
assert (app / 'poster-placeholder.png').is_file(), 'Poster fallback must be bundled'
assert (app / 'PROJECT-LICENSE.txt').read_bytes() == (root / 'LICENSE').read_bytes()
assert (app / 'ARTWORK-LICENSE.txt').read_bytes() == (root / 'Assets/LICENSE.txt').read_bytes()
diagnostics = os.environ.get('FNTV_DIAGNOSTICS', '0')
assert diagnostics in ('0', '1')
for marker in (b'.fntv-test-login.json', b'.fntv-player-smoke.json', b'FNTV-proxy-metrics.json', b'FNTV-selfcheck.json', b'FNTV_AUDIO_RELEASE'):
    assert (marker in binary) == (diagnostics == '1'), f"Diagnostic mode mismatch: {marker!r}"
assert (app / 'libwebp-LICENSE.txt').read_bytes() == (root / 'Assets/libwebp-LICENSE.txt').read_bytes()
assert not any(path.suffix == '.json' for path in app.rglob('*')), 'No runtime or credential JSON belongs in the IPA'
imports = subprocess.check_output(['xcrun', 'dyld_info', '-imports', str(app / 'FNTV')], text=True)
for name in ['NSMutableURLRequest', 'NSURLConnection']:
    assert f'_OBJC_CLASS_$_{name}  (from Foundation)' in imports, f'{name} must bind to Foundation on iOS 5'
with ZipFile(root / 'build/FNTV.ipa', 'w', ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        if path.is_file():
            archive.write(path, path.relative_to(root / 'build'))
print('PASS: ARMv7, iOS 5.1, legacy startup, Foundation networking bindings, plist, original asset hashes/licences, diagnostic mode; build/FNTV.ipa')
