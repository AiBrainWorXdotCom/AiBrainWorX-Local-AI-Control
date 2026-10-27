# Optional resource monitor example

This Python standard-library example declares the additive `monitor.sample` hook
in plugin API 1. It is trusted local code running with your account permissions;
capabilities describe consent and do not create an operating-system sandbox.
It is disabled until you review the source and explicitly accept that risk.
There is no automatic installation and no process control or termination action.

Copy this entire `resource-monitor` folder into `StateRoot/plugins/`, review it
in User plugins, and enable it. Installation-specific paths belong in your local
configuration. Disable or remove its folder at any time without restarting the
launcher, model or Harness. Restoring identical source restores its prior
approval; edited source requires fresh approval. `StateRoot/plugins/`,
`plugin-approvals.local.json` and `plugin-data/` remain separate from app source
so replacing the app during an update preserves plugins and their data.
The manager's Remove action first disables the plugin and moves only its source
to `StateRoot/plugin-archive/`. Restore returns that source disabled; review and
explicitly enable it again. Removal and restoration preserve persistent data.

The host sends `{apiVersion: 1, hook: "monitor.sample", context: {...}}` and
expects `{apiVersion: 1, panel: {...}}`. Context contains only `backend`, a
numeric subset of existing `modelMetrics`, `inspectProcesses` and
`includeGpuProcesses`. It contains no chat, prompts, project or model paths.
The plugin receives its own persistent data directory through
`AIBRAINWORX_PLUGIN_DATA`; it does not use it. The host strips unrelated app
environment variables. Trusted code can still access files with your account.

Automatic light samples only display already supplied model telemetry. The
example never makes a model HTTP request, including when telemetry is missing.
Strata hardware, live decode rate and latest request timing are reused when
available. Missing CPU, RAM, GPU and timing measurements remain null (display
as N/A), rather than being presented as zero.

Only an explicit `inspectProcesses: true` request reads processes. Windows uses
a hidden PowerShell child with a 3.2 second bound to read fixed CIM performance
fields. Linux reads `/proc` process names, CPU ticks and resident memory over a
short sample. CPU percentage is a share of total machine capacity. Both return
at most 20 processes, ordered by resident memory. Neither reads command lines,
full executable paths, environment or window titles. Restricted or exited
processes are skipped. GPU process allocations additionally require
`includeGpuProcesses: true` and a working local NVIDIA utility; unsupported
GPUs, drivers and absent per-process measurements remain null. A host sample
has a five second limit; chat hooks retain their three second limit.

Panels are bounded JSON data rendered as plain text. `metrics` accepts at most
12 `{label, value, unit?, state?}` entries; `services` at most 8
`{name, state, detail?}` entries; `processes` at most 20
`{pid, name, cpuPercent, memoryBytes, gpuMemoryBytes?}` entries, plus an optional
500 character `note`. CPU is 0 to 100; memory is nonnegative bytes or null.
Metrics accept a finite number, short text or null. Names and other text have
small length limits; process names use a basename alphabet without arguments.
Paths, markup, controls, extra schema fields and executable UI are rejected.
States are `ok`, `warning`, `error`, `unknown`, `unavailable`, `running`,
`stopped`, `idle`, `generating` or `available`.

The host rechecks source fingerprints and approval before and after each
subprocess. Disabling, editing or removing a monitor during collection discards
its in-flight output. Plugin failures return a fixed, sanitized error for that
plugin and do not stop other monitors.
