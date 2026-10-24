---
name: awx-unreal-mcp-check
description: Set up or diagnose AiBrainWorX Local AI Control's optional Unreal MCP bridge for Codex CLI or DeepSeek Harness. Use for connection and inspection-tool issues; the bridge cannot mutate assets or levels.
---

# Check the local Unreal MCP connection

Find the installed launcher repository, intended `.uproject`, Python executable,
and engine Python plugin folder containing `remote_execution.py`. Read the user's
ignored local configuration privately; do not print full personal paths or logs
into public reports. Verify the engine association rather than assuming UE 5.8.

Check that the project enables Python Editor Script Plugin and Editor Scripting
Utilities and that Python remote execution is restricted to the intended local
computer. The coding client launches `bridge/unreal_mcp.py` over stdio. Its
`UE_PROJECT_ROOT`, `UE_PROJECT_NAME`, and `UE_ENGINE_PYTHON` environment values
must match the actual installation. Keep model inference and editor connectivity
as separate diagnostics; a healthy Strata endpoint does not prove Unreal is open.

First call `unreal_project_status`. If the client has no tool, inspect its MCP
registration and subprocess startup. If the tool works but reports disconnected,
verify the intended editor, plugin configuration and engine Python module. This
bridge selects the matching local machine, project name and project root and
refuses ambiguous duplicate editors. Do not stop unrelated editor processes.

With the intended editor open, exercise a small actor query and asset query;
optionally select an actor manually and inspect the current selection. Record
what was actually verified. The bridge's contract tests can pass with Unreal
closed, so they do not replace an open-editor acceptance test.

The available tools are `unreal_project_status`, `unreal_list_actors`,
`unreal_inspect_actor`, `unreal_get_selection`, and `unreal_find_assets`. They
inspect only. Do not claim they opened, modified or saved a map, and do not add
an arbitrary execution tool to work around this boundary. Avoid exposing local
ports, authentication URLs, project files or screenshots to public services.
