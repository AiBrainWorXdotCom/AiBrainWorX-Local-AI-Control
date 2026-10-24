"""Scan Git-tracked source without echoing possible secret values.

This small guard catches common accidents. It does not replace a security review
or a dedicated secret-scanning service. Run with --staged before committing.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RULES = {
    "private-key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "github-token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b"),
    "provider-key": re.compile(r"\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{24,}\b"),
    "aws-access-key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "personal-windows-path": re.compile(r"[A-Za-z]:[\\/](?:Users|Documents and Settings)[\\/](?!Public[\\/]|Default[\\/])[^\s'\"/\\]+", re.I),
    "personal-unix-path": re.compile(r"/(?:home|Users)/[A-Za-z0-9_.-]+/"),
    "credential-url": re.compile(r"https?://[^/\s:@]+:[^/\s@]+@|[?&#](?:access_token|api_key|auth_token)=[A-Za-z0-9_.-]{16,}", re.I),
}
PRIVATE_NAMES = {"auth.json", "cookies.txt", "config.local.json"}
PRIVATE_SUFFIXES = {".pem", ".key", ".pfx", ".p12", ".gguf", ".uasset", ".umap", ".sqlite", ".sqlite3", ".bak"}


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def main():
    staged = "--staged" in sys.argv[1:]
    paths = git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z") if staged else git("ls-files", "-z")
    failures = []
    checked = 0
    for raw in paths.split(b"\0"):
        if not raw:
            continue
        name = raw.decode("utf-8")
        path = Path(name)
        if path.name.lower() in PRIVATE_NAMES or path.suffix.lower() in PRIVATE_SUFFIXES or ".local." in path.name.lower():
            failures.append((name, 0, "private-file"))
            continue
        data = git("show", ":" + name) if staged else (ROOT / name).read_bytes()
        checked += 1
        if b"\0" in data:
            continue  # Media is visually reviewed separately.
        try:
            content = data.decode("utf-8-sig")
        except UnicodeDecodeError:
            continue
        for number, line in enumerate(content.splitlines(), 1):
            for label, pattern in RULES.items():
                if pattern.search(line):
                    failures.append((name, number, label))
    for name, number, label in failures:
        print(f"BLOCKED {name}:{number}: {label} (value suppressed)")
    if failures:
        return 1
    print(f"PASS: {checked} Git-tracked files checked; no configured credential/path patterns found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
