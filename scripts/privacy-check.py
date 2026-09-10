#!/usr/bin/env python3
"""Check source candidates without printing the matched sensitive values."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
paths = subprocess.check_output(
    ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root
).decode().split("\0")
patterns = {
    "absolute user-home path": re.compile(r"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
    "OpenAI-style secret": re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}\b"),
    "GitHub-style token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
    "JWT-like credential": re.compile(r"\beyJ[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\b"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
}
email = re.compile(r"\b[A-Za-z0-9_.+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b")
failures = []
count = 0
for name in sorted(set(filter(None, paths))):
    path = root / name
    if not path.is_file():
        continue
    if path.name in {"auth.json", ".env", "accounts.json"} or path.suffix in {".log", ".enc", ".keychain", ".keychain-db"}:
        failures.append((name, "runtime/private file"))
    data = path.read_bytes()
    if b"\0" in data:
        if path.suffix not in {".png", ".jpg", ".jpeg", ".icns"}:
            failures.append((name, "unexpected binary"))
        continue
    count += 1
    text = data.decode("utf-8", errors="replace")
    for label, pattern in patterns.items():
        if pattern.search(text):
            failures.append((name, label))
    if any(m.group(1).lower() not in {"example.com", "example.org", "users.noreply.github.com"} for m in email.finditer(text)):
        failures.append((name, "non-example email"))
for name, label in failures:
    print(f"FAIL {name}: {label}", file=sys.stderr)
if failures:
    sys.exit(1)
print(f"Privacy scan passed: {count} text files; no detected private paths, emails or token patterns. Review any images separately.")
