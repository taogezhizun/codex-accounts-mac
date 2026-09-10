#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ARCH="${ARCH:-$(uname -m)}"
APP="$ROOT/dist/Codex Accounts.app"
swift build -c release --arch "$ARCH" \
  -Xswiftc -gnone \
  -Xswiftc -file-prefix-map -Xswiftc "$ROOT=/source/codex-accounts-mac"
BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/CodexAccounts" "$APP/Contents/MacOS/CodexAccounts"
/usr/bin/strip -S "$APP/Contents/MacOS/CodexAccounts"
cp resources/Info.plist "$APP/Contents/Info.plist"
/usr/bin/swift scripts/make-icon.swift "$ROOT/dist"
/usr/bin/iconutil -c icns "$ROOT/dist/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
# The distributed binary must not embed the builder's home directory.
if /usr/bin/strings "$APP/Contents/MacOS/CodexAccounts" | /usr/bin/grep -Eq '/Users/[^/]+/|/home/[^/]+/'; then
  echo 'Privacy check failed: a user-home path is embedded in the binary.' >&2
  exit 1
fi
/usr/bin/ditto --norsrc --noextattr -c -k --keepParent "$APP" "$ROOT/dist/Codex-Accounts-macOS-$ARCH.zip"
printf 'Built: %s\n' "$APP"
