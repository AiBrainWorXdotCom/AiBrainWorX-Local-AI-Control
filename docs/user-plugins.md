# User plugins and customization migration

Plugins live in the launcher's private **state folder / plugins**, outside the
application/update folder. Replacing app source therefore does not replace plugins.
No migration or update check installs or enables one automatically.

The first plugin interface is `apiVersion: 1`, with `chat.before_send` and
`chat.after_reply` JSON hooks for built-in chat, plus the additive `monitor.sample` hook for bounded Activity panels. Python and Node entries run as
local programs only after explicit approval of their source fingerprint and
declared capabilities. Source edits require fresh approval. An unsupported API
version leaves files intact and disables execution. This versioned contract needs
compatibility tests before a future host API change.

Plugins are **trusted local code, not sandboxed code**. A subprocess has the same
OS account permissions as the app. Capability declarations explain consent; they
do not enforce operating-system isolation. Dependencies also need separate review.
Timeouts and response-size checks do not make hostile code safe to run.

Voice capture/playback can be declared for review, but the current host does not
provide microphone, speech or persistent audio hooks. Activity panels are plain validated data, not executable UI. No voice plugin or
voice model is installed by this change. Adding voice to the actual Harness UI
also needs its supported extension interface; a built-in-chat plugin does not
magically patch an external client.

## Try the small MIT example

Copy `examples/plugins/reply-counter` into the user plugin folder opened by
**Updates → User plugins → Open plugin folder**. Refresh, inspect its source and
capabilities, then explicitly enable it. This example only counts reply/character
totals in its private data directory; it stores no chat text. It is not a voice demo.

Plugins receive JSON on stdin and return `{"apiVersion":1,"data":{...}}` on
stdout. Use `AIBRAINWORX_PLUGIN_DATA` for settings/data, outside the reviewed
source folder. Changing settings there does not invalidate source approval.
Keep model weights, recordings and dependencies outside the small reviewed source
folder. Chat hook timeout is three seconds; monitor sampling has a five-second bound. Persistent audio requires a future
host interface rather than loading a large speech model inside a hook.

## Existing direct modifications

`migrate-customizations.py --source OLD --target NEW` previews a transfer into a
separate extracted update folder. `--baseline ORIGINAL-SHIPPED-HASHES.json` enables
three-way comparison of vendor files. If local and upstream both changed a file,
the script flags a conflict. It does not guess a merge. `--apply` is an explicit
additional step and refuses conflicts or files changed after preview. Replaced
candidate files have target-side backups. The original installation and running
services are never modified by the script.

Without a shipped baseline, only recognized customization directories and local
config can be planned; vendor edits remain unverified. Secrets, databases, binary
models and large voice assets are not automatically transferred. Existing external
state remains referenced by local configuration; live SQLite databases are not
copied during use. Private plans and backups must stay out of Git.


## Activity and hot lifecycle controls

See [Activity monitoring](activity-monitor.md) for the opt-in read-only monitor. Disable, remove-to-archive and restore work without restarting the app or model. Restored code stays disabled; private plugin data survives app source replacement.
