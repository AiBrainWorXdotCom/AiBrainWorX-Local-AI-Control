# Experimental long-context extension

DeepSeek Harness can optionally use [Billion-Context](https://github.com/ranxianglei/billion-context)
and its [acp-kernel](https://github.com/ranxianglei/acp-kernel) to compress older
conversation context. The extension is third-party local code with the same user
account permissions as Harness; it is not sandboxed. Review its license, code and
network behavior before using it. Its license includes additional attribution terms.

In the Windows launcher, open **Activity → User plugins → Context extension**.
The manager installs a pinned package into the selected Harness profile only.
Stop Harness before installing, enabling or disabling it. Start Harness again
afterward. Disabling removes the bundle from that profile and preserves the package
and separately stored session data. The manager keeps metadata backups under the
profile directory. Existing project memory is a separate feature.

The plugin can store conversation data locally, potentially without encryption,
and may keep additional data in its own default data directory. It may contact external services
for update checks and other features. The launcher sets the extension's documented
switches to turn off its automatic updates, critical-advisory checks, release-note
checks, and SQLite helper download for the Harness process. Those switches do not
guarantee the extension is offline. Because advisory checks are disabled, check
upstream security notices and review updates manually. The extension changes the
Harness compaction behavior.
Do not assume that every provider is routed through its proxy; check its status
and logs before relying on compression. No data is automatically deleted when
the extension is disabled. Review the upstream documentation for storage and
removal options.

Compression does not enlarge the model's context window or guarantee that details
survive a summary. It also does not remove a single-response output limit. The
extension adds its own instructions and tools to model requests, which consume
context and may add latency. Test it against your model and workload; keep copies
of important work. The launcher passes the selected profile's configured window
to the extension, but the model server's real limit remains authoritative.

The upstream project documents native Harness integration, including known cases
where some transports may bypass the proxy. The launcher uses the native bundle;
it does not claim that those cases are resolved. For troubleshooting, see the
upstream [Harness integration guide](https://github.com/ranxianglei/billion-context/blob/master/CLIENTS.md#dsh-deepseek-harness).
