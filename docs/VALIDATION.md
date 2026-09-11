# Validation

## Automated / isolated

The test suite exercises stable identity across token rotation; separate users in one workspace; invalid and mixed API-key credentials; missing and multiple quota buckets; private permissions; symlink refusal; exclusive instance locks; backup ordering; shutdown-time token rotation; refused termination; failed backup; failed relaunch; concurrent credential changes; guarded restoration; wrong-directory refusal; and a previously absent credential file.

The opt-in CLI smoke test starts the actual locally installed Codex binary with an empty private home, verifies initialization, signed-out account state and file-storage config, then shuts down and removes the isolated directory. It does not log in, switch the desktop or query a real account's quota.

The release script verifies its ad-hoc signature and scans executable strings for builder home paths. UI checks use synthetic demo data only. Intel and older macOS versions still need real-device testing.

## Manual acceptance before daily use

Use two of your own accounts and pause work in every client sharing the credential directory.

1. Save the currently logged-in account A; add B through the OpenAI browser flow. Confirm the desktop still shows A.
2. Explicitly refresh B's quota. Confirm displayed values are plausible and stale/unknown states are labeled correctly.
3. Switch A → B. Confirm the desktop closes normally, reopens, and its account screen shows B. Only then confirm success in the utility.
4. Use recovery. Confirm the desktop returns to A. Then test a normal B → A switch.
5. Verify preferences and existing local tasks remain usable; restart the utility during a pending confirmation and confirm recovery is still available.

Do not claim real-account end-to-end validation based on unit tests or a demo screenshot. Record only client versions and anonymized outcomes; keep real email addresses, tokens, home paths and private workspace details out of this repository.

## 0.2 UI verification

Checked synthetic light, dark, empty-account and pending-confirmation windows on Apple Silicon. Checked the menu panel target confirmation, pause-task checkbox and cancellation. The demo final action remains disabled even after confirmation. Presentation tests cover email masking without data mutation, case-insensitive trimmed search, current-account ordering with more than five accounts, quota freshness, switch eligibility and future timestamps. The 30-test local run included the actual CLI in an empty isolated home; all passed. This does not replace the real-account acceptance above.

## 0.2.1 quota labels

Regression coverage checks official display names, missing/opaque labels, all-window preservation, old cache decoding without refresh, dotted bucket IDs, the legacy response, and the minimum remaining Codex window used in summaries. Demo quota fixtures are synthetic and do not reproduce account usage screenshots. Real account login and switching acceptance remains unchanged.

Verified the default collapsed state, recognized display names, unknown group expansion and raw-ID information popover using the isolated quota demo. All 35 local tests passed, including the opt-in signed-out CLI test. No live account was accessed for UI verification.

## 0.3.0 updates and automatic refresh

43 local tests passed, including the signed-out real-CLI smoke test. New tests cover five-minute cadence, per-account backoff, wakeups, disabled/busy guards, new/removed accounts, manual cadence reset, demo inactivity, and release verification flags/public-key format. The settings UI was inspected with a separate demo bundle; no live account was loaded.

The standalone Sparkle integration fixture uses disposable apps and a temporary test signing key. A valid signed update replaced version 1 with version 2 and relaunched successfully. A modified archive was rejected before installation (4005); a modified signed feed was rejected (1000). Both rejection tests retained version 1. The fixture never opens the real utility or Codex desktop and never reads the production signing key. Real account periodic refresh and real-account upgrade continuity still require user acceptance.

The arm64 and x86_64 release archives and appcast feeds were signed with the production key held in the local macOS Keychain, then verified with Sparkle. The corresponding public key matches the key embedded in the app. No private key was exported or added to the repository.

## 0.3.0 DMG packaging and README

Both architecture-specific DMGs passed disk-image checksum verification, deep app code-signature verification, and a file-by-file plus symlink comparison against the already published signed ZIPs. The Applications link targets the standard system folder. Installer contents were scanned for local home paths; no additional runtime data was included. The Apple Silicon DMG was opened normally in Finder to verify the icon arrangement, Chinese instructions and Retina background rendering. The README screenshot uses a separate demo bundle with synthetic accounts only. This packaging change does not alter the app or extend the real-account validation claims above.
