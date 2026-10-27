# Setup progress, private captures and isolated acceptance

Run `Get-Help .\Setup.ps1 -Detailed` for options. Search `HELP:` in `Setup.ps1`,
`app/Setup-Prerequisites.ps1` and `app/setup_progress.py` for the dependency,
consent, path, configuration and error boundaries.

Strata's actual transfer output supplies each percentage. The display wrapper adds
an ASCII bar to that reported value and keeps the reported byte counts. Percentages
belong to one transfer at a time, including engine files and model shards; there
is no invented overall installation percentage. If an upstream transfer has no
total size, the display shows bytes and a rotating activity character with
`total unknown`, without a percentage. Hashing, extracting and building may have
text-only status. Git uses its native `--progress`, npm uses `--progress=true`,
and Windows Package Manager keeps its own progress output.

The wrapper runs the selected official `setup.py` using `runpy` with Strata's
private `.venv` interpreter and unbuffered output. It preserves stdin prompts and
the real exit code. It also captures descendant output. It does not replace
Strata's download implementation, certificates, signatures, hashes, resume files,
model terms or choices. Setup creates that private venv using the verified Python
interpreter; it does not invoke Strata's global-Python bootstrap fallback.

For a public console capture, start Setup with `-PublicOutput`. Known home,
source, runtime and workspace roots, project names and absolute child-output
paths are masked before display. Typed answers are hidden to avoid terminal echo
exposing private values. The real local settings, private logs and model configs
still contain the real paths and must stay out of shared screenshots or source
control. Capture the setup console only; desktop titles, Explorer, another app,
or an unrelated terminal prompt are outside the console filter. Review a capture
before publishing it. The wrapper never writes a raw public transcript itself.

For an isolated test, prepare a separate empty parent with `source`, `runtime`,
`workspace` and `logs` directories. Put a clean source copy in `source`; do not
copy `config.local.json`, credentials, model weights or old runtime state. Then
run from that source copy:

```powershell
.\Setup.ps1 -RuntimeRoot C:\InstallTest\runtime -WorkspaceRoot C:\InstallTest\workspace -GatewayPort 18082 -HarnessPort 13080 -PublicOutput
```

Use actual dedicated absolute paths on the test machine. Runtime and workspace
must be separate. Isolated setup uses the runtime's Strata directory and refuses
an external Strata folder. It reuses working Python/Node/Git installations but
fails with guidance if a prerequisite is missing; it never offers a global
prerequisite installation. Its config is still written to the separate source
copy. `-RuntimeRoot` alone cannot protect a production source copy's config.

Choose unused, distinct `-GatewayPort` and `-HarnessPort` values from 1 to 65535
for a separate test launch. Their normal defaults remain 8082 and 3080, and the
selected model server uses its own API port. Setup saves these service ports and
does not start either service. A path-isolated install still shares normal
service ports unless separate values are supplied; Setup prints a reminder.

An acceptance run may reuse existing model weight files through an independently
prepared model configuration in the isolated Strata folder. Keep those shared
weight files read-only and do not run the production Strata installer. Label this
as **fresh clients/runtime with existing weights reused**. It is not evidence of
a fresh 58 GB model download or a fresh-machine prerequisite installation. Never
use test-fixture output as a tutorial download screenshot.

Read-only checks create no requested directories, write no settings, download
nothing and start no servers:

```powershell
.\Setup.ps1 -Plan -RuntimeRoot C:\InstallTest\runtime -WorkspaceRoot C:\InstallTest\workspace -GatewayPort 18082 -HarnessPort 13080 -PublicOutput
.\Setup.ps1 -CheckPrerequisites -RuntimeRoot C:\InstallTest\runtime -WorkspaceRoot C:\InstallTest\workspace -GatewayPort 18082 -HarnessPort 13080 -PublicOutput
python -m unittest discover -s tests -p test_setup_progress.py
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Check-SetupIsolation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Check-SetupPrerequisites.ps1
```

The Python fixtures test real stdout/stderr handling, exact reported percentages,
unknown sizes, privacy, interactive stdin and failed exit propagation without any
network access. They do not establish live download or full installation success.
