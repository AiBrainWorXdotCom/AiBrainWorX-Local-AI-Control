# AiBrainWorX Unreal skills

Original, portable instructions for an AI coding assistant. Made by AiBrainWorX;
MIT licensed under the repository's LICENSE. These are not Epic plugins and do
not contain Epic engine source, Marketplace assets, or private game content.

| Skill | Use it for |
| --- | --- |
| `awx-unreal-project-dev` | Plan and implement project/module changes with evidence and appropriate build checks. |
| `awx-unreal-source` | Trace descriptors, build rules, reflection, configuration and engine APIs. |
| `awx-unreal-research` | Research version-specific questions using Epic documentation and carefully labeled forum evidence. |
| `awx-unreal-mcp-check` | Diagnose this repository's optional read-only Unreal connection. |

The intended starting point is UE 5.8, but each workflow checks the installed
engine instead of assuming APIs are identical across versions. The skill text
has been reviewed for portability; it is not an engine compatibility certificate.

For Codex, copy the desired skill folder into your user skills directory,
normally `%USERPROFILE%/.codex/skills/`, then start a new session. Keep `SKILL.md`
inside its named folder. Invoke it by name, for example `$awx-unreal-mcp-check`.
Do not overwrite another skill without comparing it first.

Other assistants may accept the same Markdown as project instructions, but their
skill discovery and installation mechanisms differ. Installing these files does
not install Unreal, enable plugins, register an MCP server, or grant new tools.
Follow the tutorial for the actual connection setup.
