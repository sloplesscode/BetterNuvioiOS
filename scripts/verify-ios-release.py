"""Verify the unsigned IPA and prepare matching latest/versioned release files."""
import hashlib
from pathlib import Path
import plistlib
import shutil
import struct
import zipfile

directory = Path('build/ios-ipa')
candidates = list(directory.glob('nuvio-*-enhanced-*.ipa'))
assert len(candidates) == 1, candidates
source = candidates[0]
with zipfile.ZipFile(source) as archive:
    assert archive.testzip() is None, 'Corrupt ZIP'
    names = set(archive.namelist())
    infos = [n for n in names if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
    assert len(infos) == 1, infos
    info = plistlib.loads(archive.read(infos[0]))
    app = infos[0].rsplit('/', 1)[0]
    for key in ('CFBundleIdentifier', 'CFBundleDisplayName', 'CFBundleExecutable', 'CFBundleShortVersionString', 'CFBundleVersion', 'MinimumOSVersion'):
        assert info.get(key), key
    executable = archive.read(f'{app}/{info["CFBundleExecutable"]}')
    assert len(executable) >= 32
    assert struct.unpack_from('<II', executable) == (0xfeedfacf, 0x100000c), 'Expected arm64 Mach-O'
    offset = 32
    for _ in range(struct.unpack_from('<I', executable, 16)[0]):
        command, size = struct.unpack_from('<II', executable, offset)
        assert size >= 8 and offset + size <= len(executable), 'Invalid load command'
        assert command != 0x1d, 'Unexpected code signature'
        offset += size
    assert not any('/_CodeSignature/' in n or n.endswith('/embedded.mobileprovision') for n in names), 'Expected unsigned bundle'
    assert any(n.startswith(app + '/') and n.endswith('subfont.ttf') for n in names), 'Missing subtitle font'
    version = info['CFBundleShortVersionString']
    assert version and all(c.isascii() and (c.isalnum() or c in '._-') for c in version)
    print({key: info[key] for key in ('CFBundleIdentifier', 'CFBundleDisplayName', 'CFBundleShortVersionString', 'CFBundleVersion', 'MinimumOSVersion')})
outputs = [directory / 'BetterNuvio.ipa', directory / f'BetterNuvio-{version}.ipa']
for output in outputs:
    shutil.copyfile(source, output)
hashes = [hashlib.sha256(path.read_bytes()).hexdigest() for path in outputs]
assert hashes[0] == hashes[1]
(directory / 'SHA256SUMS').write_text(''.join(f'{digest}  {path.name}\n' for path, digest in zip(outputs, hashes)))
print('Archive verified. UNSIGNED. Matching SHA-256:', hashes[0])
