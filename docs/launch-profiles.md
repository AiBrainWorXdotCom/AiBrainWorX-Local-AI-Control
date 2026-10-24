# Launch profiles and model settings

Open **Settings** in the launcher before opening a coding client. Name the
profile, choose an existing project folder and optionally select the Unreal
engine folder containing `remote_execution.py`. The engine folder is unnecessary
for ordinary coding. Save updates the current profile; Save as new creates one.
Choose a saved profile from the main panel.

Load an instruction preset, edit it, and enable **Use custom instructions**.
These instructions are added to the client's existing system instructions on
each new model request. They do not replace the client's native tools, safety
instructions, project files or permission settings. Unchecking the box stops
adding them. The editor allows 8192 characters and treats braces literally.

Enable **Override temperature and top-p** to use the sliders. Temperature is
0–2; top-p is 0.01–1. A lower temperature often makes answers more consistent,
but correctness still needs tests. Leaving overrides off preserves the values
sent by the client or the model's defaults. Change one setting at a time when
comparing results.

**Maximum output tokens** is an upper limit of 64–8192 per model request. It
respects a smaller client request. Reasoning can count against this allowance;
raising it does not expand the 16k context used by this client preset or remove
another client-level turn budget. Context, cache, GPU layers and model weights
remain Strata settings. No model reload is needed for these request controls.

The tiny settings gateway starts automatically when starting the model or a
client. It listens on `127.0.0.1:8082`, forwards to Strata on `8081`, and handles
Chat Completions and Responses requests with incremental streaming. Each profile
uses a fixed `/profiles/<id>/v1` endpoint. Saving its prompt or sampling settings
affects subsequent requests, including requests in an existing chat; it does not
alter an in-flight generation.

Profiles live in `StateRoot/launch-profiles.local.json`, outside the source
folder. A previous copy is saved beside the file when editing. Each profile's
Harness and optional Codex configurations live under
`StateRoot/managed-clients/<id>/`. They are generated from this launcher's current
location, so moving the source folder regenerates the Unreal bridge path.
Global client settings and workspace `AGENTS.md` files are not overwritten.

Stop Harness before switching projects. If upgrading while an older Harness is
running, finish its active work and Stop → Start once. Its previous global
history remains in its original home; the new profile starts a separate home.
Existing terminal windows retain the profile they opened with. Close those
windows before moving the launcher or changing that profile's project folders.

**Diagnostics** checks local connections without sending a generation request.
The copied report excludes paths, instructions and credentials. If Unreal needs
attention, open the intended editor project and verify its Python plugins and
loopback remote-execution settings. A ready model does not prove an editor
connection.

**Portability means the launcher source can move.** On another Windows PC, run
Setup to detect or install its separate dependencies and select its local paths.
Never distribute your private config, client histories or prompts with the
source ZIP. Model files remain separately licensed and can require substantial
storage. A fresh-PC bootstrap has not been tested end to end.
