# AiBrainWorX Local AI Control

**Local AI, with a clear Start button.** A Windows launcher for Strata and your choice of coding workspace, with optional Unreal inspection tools.

**Measured on our PC: about 20–25 generated tokens/second on short probes**, using an RTX 3060 12 GB, Ryzen 5 5500, 32 GB RAM and SSD-backed data. Read the [public tutorial](https://aibrainworx.com/qwen-38-coder-12gb-gpu-ryzen5-strata-codex-unreal/). Heavy memory pressure reduced one live reading to roughly 13 tokens/second; these are observations, not a performance guarantee.

![AiBrainWorX Local AI Control](media/aibrainworx-local-ai-control.png)

Made by **AiBrainWorX** · Original code: **MIT** · [Website](https://aibrainworx.com) · [GitHub](https://github.com/AiBrainWorXdotCom)

## Start here — no Git commands required

1. [Download the ZIP](https://github.com/AiBrainWorXdotCom/AiBrainWorX-Local-AI-Control/archive/refs/heads/main.zip), then extract it into a permanent folder. You can also use **Code → Download ZIP**.
2. Read [model license notes](MODEL-LICENSES.md), then double-click **Setup.cmd**.
3. Setup checks prerequisites, offers installation through official sources, and reuses an existing Strata installation when selected.
4. Choose a working folder. Unreal is optional; an ordinary coding folder works too.
5. Open **Launch.cmd**, click **Start model**, and wait for Ready. Choose **DeepSeek Harness (browser)**, then **Start → Open chat**.

The workspace dropdown also offers **Codex CLI (optional)**. Choose it and click **Open CLI** to open the prepared local profile in a terminal. Both clients use the same Strata server; you can use either one. The Harness Start/Stop buttons are disabled when the terminal client is selected. Switching clients does not stop an already running service. Model selection happens during Setup; model tuning controls are planned for a later version.

Large model downloads require an explicit `DOWNLOAD` confirmation. The tested Qwen Coder files are approximately 58.4 GB, plus prepared data and other runtime files. The guided Strata option can select another supported model. Model weights are downloaded by Strata; none are stored in this repository.

Setup uses Windows Package Manager for missing Git, Python or Node when you approve. Agent packages come from the official npm packages. Existing installers may display their own prompts. The launcher does not install drivers or change machine-wide PowerShell execution policy. The `.cmd` entry points use a process-only execution-policy setting to run these local scripts.

## What is included

- A branded control panel with detected CPU, GPU and RAM labels.
- Independent model and Harness start/stop controls.
- A named Codex local-provider profile, leaving the normal default profile unchanged.
- Five optional Unreal inspection tools: project status, actors, actor details, selection and asset search.
- Four original [Unreal skills](skills/README.md) for development, source investigation, Epic research and MCP diagnostics.
- A [setup tutorial](docs/tutorial.md), screenshots, architecture graphics and a [rebuildable captioned walkthrough](media/VIDEO.md).
- MIT-licensed integration source and contract tests.

Harness is the agent interface; the configured model can be Qwen. You do not need to download a DeepSeek model to use this setup.

## Hardware and current support

This release targets **Windows**, using source-based Strata installations. Our tested machine has an **RTX 3060 with 12 GB VRAM, Ryzen 5 5500 and 32 GB RAM**. Those specifications describe our build; they are not a promise that every model fits every PC.

The launcher reads your hardware. Strata's hardware check and setup choose an appropriate backend/model. NVIDIA VRAM is queried through `nvidia-smi`; other adapters fall back to their reported name without guessing VRAM from Windows' limited `AdapterRAM` field.

The model does not fit entirely in 12 GB VRAM. It also uses system RAM and SSD-backed files. We observed about 20–25 generated tokens/sec on short probes and around 13 tokens/sec under severe memory pressure with Unreal open. These are observations from one PC, not guaranteed performance. A probe also returned a wrong answer: review outputs and run tests.

Keep one active agent at a time on memory-constrained machines. Stop inference when you need to free the GPU. Heavy concurrent Unreal/model workloads are not validated as a smooth experience on our 32 GB machine.

## Settings and privacy

See [SECURITY.md](SECURITY.md) for security and privacy details.

`config.local.json` contains your actual installation paths and is ignored by Git. Runtime data and logs go into your local application-data folder. The first-run setup uses a dedicated Harness home so it can prepare its own profile without replacing your existing Harness history or credentials.

Version 1 expects the model API on `127.0.0.1:8081`, and Harness on `127.0.0.1:3080`. Both services bind to loopback. The current model-control preset expects no Strata API key. A conflicting port blocks another start instead of killing its owner.

Harness prints a process sign-in URL into its private log. **Open chat** uses that URL. Do not publish the URL or your local configuration. Screenshots and video in this release contain application-only captures and explanatory graphics.

Local inference does not make every possible tool offline. Online plugins and searches depend on the client's configuration. Model and package installation need internet access.

## Optional Unreal connection

Install Unreal separately through Epic. Enable Python Editor Script Plugin and Editor Scripting Utilities, and configure loopback Python remote execution. Setup can connect one `.uproject` at the selected working-folder root.

Supply the installed engine folder containing `remote_execution.py`, normally under its PythonScriptPlugin directory. Open the intended project to inspect its live editor. The bridge cannot open, modify or save a map. Source-code edits use the coding client's ordinary tools; binary Unreal assets require supported editor operations.

The first diagnostic prompt:

> Use the Unreal project-status tool and report whether the editor is connected. Do not change files.

## Validation and limitations

- The portable Unreal bridge's ten contract tests pass.
- PowerShell parsing, the no-download setup plan, hardware detection and existing-install status checks were exercised.
- Harness lifecycle and duplicate-start handling were tested on our installation.
- Model generation and earlier Codex project-status tool calls were validated.
- A complete fresh-machine bootstrap with new model downloads has **not** been tested end to end.
- Live actor/asset/selection inspection still needs a separate open-editor acceptance pass.
- The application-only media captures render the real WinForms controls with live service status. The walkthrough adds explanatory graphics; it does not simulate successful editor mutations.
- Local voice-over installation is planned separately and is not part of this release.

For contributors:

```powershell
python bridge/test_unreal_mcp.py
powershell -NoProfile -File Tests/Check-Scripts.ps1
powershell -NoProfile -File Setup.ps1 -Plan
```

## Licenses

Our original launcher and bridge code use [MIT](LICENSE). Strata, Qwen, Codex, Harness and Unreal retain their own terms. See [third-party notices](THIRD_PARTY_NOTICES.md) and [model license notes](MODEL-LICENSES.md). This project is independent and is not an official product or endorsement from those vendors.
