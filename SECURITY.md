# Security and local data

## Data boundary

This project is intended for a person's own authorized ChatGPT accounts. Credentials are never sent to a project-operated server. Update checks and package downloads connect to the public GitHub project, with Sparkle system profiling disabled. No account credentials are attached to update requests. Login and quota actions communicate with OpenAI through the locally installed official Codex executable. There is no analytics backend, credential export feature, automatic warmup, account selling or shared-account service.

Runtime data is outside the source repository:

| Data | Storage |
| --- | --- |
| Account snapshots and one recovery journal | macOS login Keychain, service `org.codexaccounts.local-vault.v1`, not synchronizable |
| Email, nickname, plan and cached quotas | `~/Library/Application Support/CodexAccounts/accounts.json`, mode 0600 |
| App selection and credential-directory selection | App preferences |
| Temporary browser login data | UUID directory in the app's private Application Support `Sessions` directory; removed after the operation and reaped on next launch after a crash |
| Active Codex credential | The selected `CODEX_HOME/auth.json`, mode 0600 when written |

Keychain access is limited by macOS's access-control behavior for the locally signed app. Ad-hoc rebuilds can trigger new access prompts. This does not protect against a fully compromised macOS user session, root, or a malicious executable approved by the user.

Account JWT payloads are decoded only to label and distinguish snapshots. They are **not** treated as verified cryptographic identity. Only successful authentication in the desktop app confirms the intended runtime identity.

## Switching and recovery

The app requires the user to pause work before requesting a normal desktop shutdown. It never force-kills the desktop app. It checks the Codex descendants of the running desktop process and waits for them to exit. It cannot discover every independently running CLI that shares the same credential directory.

After shutdown it re-reads the departing credentials, archives that fresh snapshot, and writes a durable Keychain recovery journal before changing the live file. New data is written to an exclusive 0600 temporary file, fsynced, and renamed in the same directory. Symlinks in the live credential path are rejected. A file re-read detects changes between backup and write. This narrows concurrency risk but is not a cross-process compare-and-swap guarantee; all clients sharing the directory should be idle.

A failed launch restores the prior file only while the file still equals the expected old or new bytes. Recovery rejects a different directory or unrelated account. The last recovery snapshot remains after confirmation. A pending journal blocks another switch until the user acknowledges or recovers the operation.

If the app crashes, reopen it to access the recovery journal. If the Keychain is inaccessible, the app stops credential changes; it does not fall back to a plaintext account store. Removing an account from the list does not delete the recovery journal or log the desktop out.

## Repository hygiene

All committed accounts, email addresses and quota values must be synthetic. Use `example.com` addresses. Do not commit screenshots of real account lists, authentication files, Keychain exports, local configuration, logs or debug dumps. `scripts/privacy-check.py` scans candidate tracked files; review images manually, since a text scanner cannot inspect their content. The build script removes debug information and rejects embedded user-home paths in the distributed executable.

Do not paste access tokens, refresh tokens or credential JSON into GitHub issues. Report a suspected vulnerability with a minimal synthetic reproduction and affected version. No real credential is needed to reproduce file handling or transaction-ordering bugs.

## Signed updates

Sparkle 2.9.6 verifies Ed25519 signatures on both the feed and archive, with validation before extraction. Only the public verification key is shipped in Info.plist. The publishing key remains in the maintainer’s macOS login Keychain under the dedicated Sparkle account `org.codexaccounts.updates`; publishing scripts do not export it or store it in CI. Public keys are safe to publish and cannot be used to sign new updates. Loss of the private key requires a carefully planned migration or manual installation for existing ad-hoc-signed users; do not casually rotate the embedded key.

These checks authenticate the project’s update channel; they do not provide Apple Developer ID signing or notarization. Installation remains user-confirmed. Keep the GitHub account and signing Mac secure. Upstream third-party copyright notices are preserved exactly; their public author information is distinct from private user information.
