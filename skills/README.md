# AiBrainWorX workflow skills

Original, portable instructions for an AI coding assistant. Made by AiBrainWorX;
MIT licensed under the repository's LICENSE. These are not Epic plugins and do
not contain Epic engine source, Marketplace assets, or private game content.

| Skill | Use it for |
| --- | --- |
| `awx-unreal-project-dev` | Plan and implement project/module changes with evidence and appropriate build checks. |
| `awx-unreal-source` | Trace descriptors, build rules, reflection, configuration and engine APIs. |
| `awx-unreal-research` | Research version-specific questions using Epic documentation and carefully labeled forum evidence. |
| `awx-unreal-mcp-check` | Diagnose this repository's optional read-only Unreal connection. |
| `awx-android-edge` | Inspect Android projects and plan very small on-device models. |
| `awx-blender-inspection` | Inspect Blender scenes through the optional read-only add-on. |
| `awx-offline-lora` | Preflight and manage explicitly enabled local tiny-text LoRA jobs. |
| `awx-model-dataset-review` | Review schemas, runtime support, rights and measured results. |

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

The launcher’s **Skills + templates** browser also links to pinned, source- and
license-reviewed repositories from Android, Hugging Face and community Blender
and Unreal authors. These are references, not automatically installed code or
security audits of every skill. Hugging Face cloud/Jobs skills are separate from
our local trainer and can require paid services; they are not enabled here.

Profile templates load instructions and optional bridge checkboxes. They do not
change model weights, choose private paths or enable training starts. The local
model needs the selected coding client's file/tool capabilities to follow a
workflow; small tool-free Chat models do not gain tools from Markdown alone.
