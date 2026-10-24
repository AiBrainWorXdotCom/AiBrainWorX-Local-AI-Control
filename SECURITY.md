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

The request-settings service also binds only to loopback, on port 8082. It
checks Host/Origin, accepts a fixed set of model API routes and rejects oversized
requests. It is not an authenticated boundary against other software on this PC.
It does not log requests or prompts. Custom instructions are stored as plain text
in your local runtime profile file: never put passwords or API keys in prompts.
Project profiles have separate client homes and fixed model URLs, preserving the
profile chosen by an existing client when another profile is selected.

The Unreal bridge exposes five fixed inspection operations. It has no arbitrary
Python-execution tool and cannot edit or save maps. Unreal's own remote-execution
feature is powerful: keep its network configuration restricted to this PC.
Coding clients may still modify files through their separate tools. Review their
permissions and proposed changes before using them on important projects.

Model connections accept HTTP on literal loopback or localhost only. The gateway
rejects itself as a target, strips incoming credentials and supplies only the
selected API-key environment variable. Set that variable before starting it.
A local server can itself proxy a cloud service: select local weights and review
its settings. Ollama inventory discovery excludes advertised cloud models.

Project memory is an unencrypted local SQLite database under StateRoot/memory.
It records only notes you save, with previous revisions on changes. Archive is
not deletion. Inclusion in model requests is opt-in and bounded, but enabled
notes are sent to the chosen loopback model server. Do not store secrets there.
Built-in chat history stays in process memory; the selected backend may keep its
own logs. Exported handoffs can contain user-written paths or private notes.

Update checks contact public GitHub release/version endpoints only on request.
They never install code, change files or restart the application. Model-guide
buttons open public pages when clicked; weights are not automatically fetched.

Automated checks have read-only repository permissions, pinned action revisions,
and no repository secrets. `Tests/check_public_files.py` checks common credential
and personal-path patterns without echoing suspected values. It is a lightweight
guard, not a guarantee that every possible secret is detected.

If you discover an exposed credential, revoke it at its provider first. Removing
a file does not remove it from Git history. Report vulnerabilities privately to
the repository owner using GitHub's private reporting option when available;
never put credentials in issues, screenshots, or pull requests.
