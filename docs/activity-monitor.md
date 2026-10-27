# Activity, service indicators and optional monitoring

The Windows workspace has more room and labeled model/Harness status lights.
The native Linux browser workspace has the same service indicators and an
Activity page. A status color always has a text label; an unavailable backend
is not shown as running. Closing the launcher does not stop its model.

## Enable the resource monitor

1. Open **User plugins** (from Activity or Updates).
2. Copy the included `examples/plugins/resource-monitor` folder into your private
   **state folder / plugins** directory. Keep the folder name `resource-monitor`.
3. Refresh, read the source and declared `read_system` capability, then enable it
   only if you trust it to run with your account permissions.
4. Open **Activity**. Light samples run about every five seconds while this page
   is visible. They reuse supplied Strata telemetry; no model request is generated.
5. Press **Refresh processes** for one read-only CPU/RAM process snapshot. GPU
   process memory requires the separate checkbox and a supported driver.

Process snapshots are deliberately explicit. The monitor does not continuously
enumerate other applications, kill processes, change priorities or tune inference.
It returns process names, PIDs, CPU percentage and memory, without command lines,
executable paths, environment variables or window titles. CPU percentages use a
whole-machine scale. Missing measurements remain unavailable, including GPU
process allocation on unsupported Windows drivers.

The process table is a snapshot; light polls preserve it for the same reviewed
plugin source. Strata CPU/RAM/decode readings are live only when the launcher
already has that telemetry. Other connectors can show unavailable model metrics;
the explicit process snapshot still works. The Linux UI currently has no Strata
metrics poller, so it does not invent decode/first-token measurements.

## Enable, disable, remove and restore without a restart

Disable takes effect on the next hook/sample and invalidates in-flight results.
Removing an extension archives its source inside the private state directory.
Restore brings the source back **disabled**, requiring another explicit enable.
Plugin data remains in `plugin-data/<id>` independently of source and app updates.
Editing plugin code invalidates its fingerprint approval. An app update does not
silently approve changed code or execute incompatible API versions.

The additive API-1 `monitor.sample` hook returns bounded plain JSON panels; it
does not execute HTML or UI code. The host limits a monitor invocation to five
seconds. Plugins remain trusted local programs, **not an operating-system
sandbox**. See [the plugin contract](user-plugins.md) and the included example.

## Update progress

**Check everything** reports actual completed source-check jobs as `X/Y` and a
progress bar. It checks the launcher, Strata, Harness, skills, tracked model
sources and user-plugin release sources. An unknown source or network failure
stays **Needs review / Could not check**. A completed check does not mean all
components are current. This is check progress, not a download/install percentage;
checking never installs updates or overwrites customizations.

Windows install transfer progress is explained in [install-progress.md](install-progress.md).
Read the [validation record](validation/2026-10-26-activity.md) for measured
overhead, installation scope and remaining limits.
