#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${ARCH:-$(uname -m)}"
OUT="${OUTPUT_DIR:-$ROOT/dist}"
APP="$OUT/Codex Accounts.app"
DMG="$OUT/Codex-Accounts-macOS-$ARCH.dmg"
PYTHON="${PACKAGING_PYTHON:-$ROOT/dist/packaging-venv/bin/python}"
[[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || { echo 'Unsupported architecture' >&2; exit 1; }
[[ -x "$PYTHON" ]] || { echo 'Create dist/packaging-venv and install scripts/dmg-requirements.txt first.' >&2; exit 1; }
[[ ! -e "$DMG" ]] || { echo 'Refusing to overwrite an existing installer.' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$APP"
"$PYTHON" - "$APP" "$ARCH" <<'PY'
import pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1]); arch = sys.argv[2]
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'org.codexaccounts.mac'
assert 'CodexAccountsPreviewMode' not in info
assert info['SUFeedURL'].endswith('/' + arch + '.xml')
assert arch in subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/CodexAccounts')], text=True).split()
PY
/usr/bin/swift "$ROOT/scripts/make-dmg-background.swift" "$OUT/installer-background.tiff"
"$PYTHON" -m dmgbuild -s "$ROOT/scripts/dmg-settings.py" \
  -D "app=$APP" -D "background=$OUT/installer-background.tiff" \
  'Codex Accounts' "$DMG"
/usr/bin/hdiutil verify "$DMG"
printf 'Built installer: %s\n' "$DMG"
