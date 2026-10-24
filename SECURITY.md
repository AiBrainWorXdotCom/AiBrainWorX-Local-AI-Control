# Security and privacy

This is a public repository for the original AiBrainWorX launcher, integration
code and skills. The MIT license applies to that original work. Third-party
models and tools retain their own licenses; model weights are not distributed.

Local paths belong in ignored `config.local.json`. Model weights, credentials,
session data, logs, game assets, and raw desktop recordings are excluded. The
included images show only the launcher and original explanatory graphics.

The model and Harness bind to loopback. This launcher does not open firewall
ports or configure a public tunnel. Other processes on the same computer may
still reach local services. Keep Harness sign-in URLs and logs private.

The Unreal bridge exposes five fixed inspection operations. It has no arbitrary
Python-execution tool and cannot edit or save maps. Unreal's own remote-execution
feature is powerful: keep its network configuration restricted to this PC.
Coding clients may still modify files through their separate tools. Review their
permissions and proposed changes before using them on important projects.

Automated checks have read-only repository permissions, pinned action revisions,
and no repository secrets. `Tests/check_public_files.py` checks common credential
and personal-path patterns without echoing suspected values. It is a lightweight
guard, not a guarantee that every possible secret is detected.

If you discover an exposed credential, revoke it at its provider first. Removing
a file does not remove it from Git history. Report vulnerabilities privately to
the repository owner using GitHub's private reporting option when available;
never put credentials in issues, screenshots, or pull requests.
