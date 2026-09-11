#!/usr/bin/env python3
"""Mount a DMG read-only and compare its app with the signed ZIP release."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('dmg', type=Path)
parser.add_argument('archive', type=Path)
args = parser.parse_args()

with tempfile.TemporaryDirectory(prefix='codex-installer-check-') as temporary:
    mount = Path(temporary) / 'volume'; mount.mkdir()
    subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(args.dmg)], check=True, stdout=subprocess.DEVNULL)
    try:
        app = mount / 'Codex Accounts.app'
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == 'org.codexaccounts.mac'
        assert 'CodexAccountsPreviewMode' not in info
        assert (mount / 'Applications').is_symlink()
        assert os.readlink(mount / 'Applications') == '/Applications'
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        actual = {}
        for path in app.rglob('*'):
            name = str(path.relative_to(mount))
            if path.is_symlink():
                actual[name] = ('link', os.readlink(path))
            elif path.is_file():
                actual[name] = ('file', hashlib.sha256(path.read_bytes()).hexdigest())
        expected = {}
        with zipfile.ZipFile(args.archive) as archive:
            for entry in archive.infolist():
                if entry.is_dir():
                    continue
                data = archive.read(entry)
                expected[entry.filename] = ('link', data.decode()) if stat.S_ISLNK(entry.external_attr >> 16) else ('file', hashlib.sha256(data).hexdigest())
        assert actual == expected, 'DMG app differs from signed ZIP app'
        allowed = {'Codex Accounts.app', 'Applications', '.DS_Store', '.VolumeIcon.icns', '.background.tiff', '.fseventsd', '.Trashes'}
        assert {p.name for p in mount.iterdir()} <= allowed, 'Unexpected installer content'
        for path in mount.rglob('*'):
            if path.is_symlink() or not path.is_file():
                continue
            data = path.read_bytes()
            for encoding in ('utf-8', 'utf-16le', 'utf-16be'):
                assert str(Path.home()) not in data.decode(encoding, errors='ignore'), 'Private home path in installer'
        print(f'PASS {args.dmg.name}: signed app matches ZIP; Applications link and privacy checks passed')
    finally:
        subprocess.run(['hdiutil', 'detach', str(mount)], check=True, stdout=subprocess.DEVNULL)
