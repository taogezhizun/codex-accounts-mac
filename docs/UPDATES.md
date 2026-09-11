# Updates and refresh — 0.4.0 (unreleased)

## User behavior

About credits the public maintainer account and links to the GitHub profile and project. No private name, email, account screenshot or developer-machine path is included.

Quota refresh runs only for the saved account matching the current Codex file login. It runs on launch and at five-minute intervals; wakeups refresh only if due. Other accounts keep their last cached values and cannot be refreshed manually until switched to and confirmed. The live identity is re-read on each tick and at asynchronous refresh boundaries, preventing an external login change from applying results to another account. Signed-out and unsaved logins produce no background requests. Failures back off through 10, 20, 40 and 60 minutes. Refresh remains paused during login, switching, pending confirmation and Sparkle updates.

Quota credentials come exclusively from the live auth file. In 0.4.0 saved accounts and recovery backups use a private, unencrypted local snapshot. Only explicit legacy migration queries the old Keychain; all subsequent credential operations use files. File-backed startup reads pending recovery and blocks new switches/refresh until resolved. Legacy users may defer migration and still refresh the current account. See [storage and migration](../SECURITY.md).

The status bar displays the lowest remaining Codex window for the current saved account, with a tooltip identifying its duration and timestamp. Unknown/pending is “—”; stale cache uses “~”. It reuses the existing state and scheduler. A settings toggle hides the number.

`AppUpdates` uses Sparkle 2.9.6 [gentle reminders](https://sparkle-project.org/documentation/gentle-reminders/). A verified scheduled discovery supplies the menu version row; clicking it focuses Sparkle's existing alert instead of starting a duplicate update flow. A passive reminder does not block account work. Opening the update dialog and installing remain mutually exclusive with account operations and migration. Closing/skipping, aborting or finishing the session clears its transient hint; restart does not restore a stale version string. Manual checks retain Sparkle's normal dialog.

The 0.3.1 attempt to suppress startup authorization with `kSecUseAuthenticationUIFail` was insufficient for the legacy file-based login Keychain. [Chromium documents the same backend limitation](https://chromium.googlesource.com/chromium/src/crypto/+/refs/heads/main/apple/scoped_keychain_user_interaction_allowed.cc). Version 0.3.2 removes the call instead of depending on a suppression flag. [OpenUsage also tries Codex login files before its Keychain fallback](https://github.com/robinebers/openusage/blob/main/Sources/OpenUsage/Providers/Codex/CodexProvider.swift); its fallback can still require authorization. No implementation code was copied.

This cadence and cache feedback were inspired by [OpenUsage’s refreshing documentation](https://github.com/robinebers/openusage/blob/main/docs/refreshing.md); the implementation is independent.

## Trust and distribution

[Sparkle](https://sparkle-project.org/documentation/) handles the native update dialog, download, verification, replacement and relaunch. A user starts with a one-time manual upgrade from 0.2.x and keeps the app in Applications. Subsequent releases update that same app. Architecture-specific feeds are hosted in this repository’s `appcast/` directory; archives are immutable versioned GitHub Release assets. EdDSA-signed feeds and archives are required, with archive verification before extraction. Automatic checking is enabled, automatic installation and system profiling are disabled.

The signing key was generated with Sparkle’s `generate_keys --account org.codexaccounts.updates`. Only the public key belongs in Info.plist. The private key stays in the login Keychain, not in source files, environment variables, logs or GitHub Actions. A maintainer may need to grant `sign_update` access through the macOS authentication dialog. Do not export a private key merely to avoid that dialog.

Ad-hoc app signing supports self-use without a paid Apple developer account. EdDSA updates do not replace Apple notarization. Sparkle’s complete license, including its dependencies’ notices, is retained in `docs/licenses/Sparkle.txt` and the distributed app.

## Commit attribution and privacy

Configure this repository's Git author with your public GitHub username and the GitHub-provided `noreply` address from your account's email settings. Use repository-local configuration so other projects keep their own author settings. Check both `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` before publishing; do not substitute a generic project identity or invent a shared `noreply` address. Never use a private personal or work email for public commits.

After pushing, verify that GitHub associates the commit with the intended account. Changing local author settings applies to future commits only; it does not reattribute historical commits. Preserve published release tags and history unless a separate history migration is explicitly agreed. See [GitHub's commit email guidance](https://docs.github.com/en/account-and-profile/how-tos/email-preferences/setting-your-commit-email-address).

## Release procedure

1. Update the display version and increment `CFBundleVersion` in `resources/Info.plist`; keep the public signing key unchanged. Run tests and the privacy scan.
2. Build both archives, using `ARCH=arm64 OUTPUT_DIR="$PWD/dist/v<VERSION>/arm64" scripts/build-app.sh` and `ARCH=x86_64 OUTPUT_DIR="$PWD/dist/v<VERSION>/x86_64" scripts/build-app.sh`. The script embeds the pinned Sparkle framework and chooses the matching feed.
3. Run `python3 scripts/prepare-release.py <VERSION>` on the signing Mac. It reads the key via Sparkle, signs archives and feeds, verifies signatures, and writes public feeds. No private key is exported.
4. Commit reviewed source and feeds, confirm CI, then publish a GitHub Release with tag `v<VERSION>` and the two exact archives from step 2. Never replace an asset under an existing published version; publish a higher build/version instead.
5. Check both public feed URLs and asset downloads. Run `python3 scripts/test-updater.py` for disposable-app tests of signed installation and rejection of modified archives/feeds when changing the updater. It uses a disposable test key and has no access to account credentials or the production signing key.

CI builds and tests without a publishing key. Release signing is local. Forks should change the maintainer links and feed URLs and generate their own signing key before distributing updates; never pretend to use the original publisher’s signing identity.

## DMG installers

Manual downloads use a DMG with a Chinese installation guide and an Applications shortcut. Sparkle continues to use the signed ZIP archives above. Both formats contain the identical app. DMG packaging does not re-sign the app or provide Apple notarization.

Set up the isolated packaging environment once (Python 3.10+):

```sh
python3 -m venv dist/packaging-venv
dist/packaging-venv/bin/pip install -r scripts/dmg-requirements.txt
```

After building a release, package and verify each architecture (replace the version when preparing a new release):

```sh
ARCH=arm64 OUTPUT_DIR="$PWD/dist/v0.4.0/arm64" scripts/build-dmg.sh
python3 scripts/verify-dmg.py dist/v0.4.0/arm64/Codex-Accounts-macOS-arm64.dmg dist/v0.4.0/arm64/Codex-Accounts-macOS-arm64.zip
```

Repeat with `x86_64`. Open the DMG normally in Finder to inspect the icon layout, arrow and installation text. The verifier mounts read-only, checks the app signature, compares every app file and symlink with the ZIP, and scans for private home paths. It never launches the packaged app.

Upload both DMGs alongside the ZIP assets. An additional installer format may be added to an existing release when it contains the exact previously published app; never replace an existing published asset. Keep the filenames `Codex-Accounts-macOS-arm64.dmg` and `Codex-Accounts-macOS-x86_64.dmg` stable for README's latest-release links. [dmgbuild](https://dmgbuild.readthedocs.io/) is a build-only dependency; its libraries are not bundled in the app.
