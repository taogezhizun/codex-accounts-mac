# Updates and refresh — 0.3.0

## User behavior

About credits the public maintainer account and links to the GitHub profile and project. No private name, email, account screenshot or developer-machine path is included.

Quota refresh runs on launch, then at five-minute per-account intervals. New accounts become due promptly, wakeups only refresh overdue accounts, and opening more windows does not create another timer. Failures retain cached values and back off through 10, 20, 40 and 60 minutes. A successful or manual refresh resets that account’s cadence. Automatic work is serialized with login and switching, pauses during pending desktop confirmation and Sparkle sessions, and can be disabled in Settings. The existing external-token protocol avoids rotating refresh tokens from two processes. Expired inactive accounts can still require sign-in.

This cadence and cache feedback were inspired by [OpenUsage’s refreshing documentation](https://github.com/robinebers/openusage/blob/main/docs/refreshing.md); the implementation is independent.

## Trust and distribution

[Sparkle](https://sparkle-project.org/documentation/) handles the native update dialog, download, verification, replacement and relaunch. A user starts with a one-time manual upgrade from 0.2.x and keeps the app in Applications. Subsequent releases update that same app. Architecture-specific feeds are hosted in this repository’s `appcast/` directory; archives are immutable versioned GitHub Release assets. EdDSA-signed feeds and archives are required, with archive verification before extraction. Automatic checking is enabled, automatic installation and system profiling are disabled.

The signing key was generated with Sparkle’s `generate_keys --account org.codexaccounts.updates`. Only the public key belongs in Info.plist. The private key stays in the login Keychain, not in source files, environment variables, logs or GitHub Actions. A maintainer may need to grant `sign_update` access through the macOS authentication dialog. Do not export a private key merely to avoid that dialog.

Ad-hoc app signing supports self-use without a paid Apple developer account. EdDSA updates do not replace Apple notarization. Sparkle’s complete license, including its dependencies’ notices, is retained in `docs/licenses/Sparkle.txt` and the distributed app.

## Release procedure

1. Update the display version and increment `CFBundleVersion` in `resources/Info.plist`; keep the public signing key unchanged. Run tests and the privacy scan.
2. Build both archives, using `ARCH=arm64 OUTPUT_DIR="$PWD/dist/v<VERSION>/arm64" scripts/build-app.sh` and `ARCH=x86_64 OUTPUT_DIR="$PWD/dist/v<VERSION>/x86_64" scripts/build-app.sh`. The script embeds the pinned Sparkle framework and chooses the matching feed.
3. Run `python3 scripts/prepare-release.py <VERSION>` on the signing Mac. It reads the key via Sparkle, signs archives and feeds, verifies signatures, and writes public feeds. No private key is exported.
4. Commit reviewed source and feeds, confirm CI, then publish a GitHub Release with tag `v<VERSION>` and the two exact archives from step 2. Never replace an asset under an existing published version; publish a higher build/version instead.
5. Check both public feed URLs and asset downloads. Run `python3 scripts/test-updater.py` for disposable-app tests of signed installation and rejection of modified archives/feeds when changing the updater. It uses a disposable test key and has no access to account credentials or the production signing key.

CI builds and tests without a publishing key. Release signing is local. Forks should change the maintainer links and feed URLs and generate their own signing key before distributing updates; never pretend to use the original publisher’s signing identity.
