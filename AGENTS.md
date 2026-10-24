# Repository instructions

Keep setup paths, credentials, session logs, model weights and game assets out of
Git. Actual installation paths belong in ignored `config.local.json`.

For commits made on the owner's behalf, use repository-local Git identity
`AiBrainWorX <28985302+AiBrainWorXdotCom@users.noreply.github.com>`. Verify author
and committer metadata before publishing. Prefer the Git CLI; connector commit
wrappers that omit author fields can expose an account's primary email. Do not
rewrite existing history without the owner's explicit authorization.

Use the focused checks in README for changed code. Do not claim a fresh-machine
installation or live Unreal acceptance test was performed unless it actually
was. The Unreal bridge provides inspection operations, not editor mutations.
