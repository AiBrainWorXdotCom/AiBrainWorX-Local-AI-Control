# AiBrainWorX Local AI Control

**Portable local AI, with a clear Start button.** Download, extract and run the Windows launcher from your chosen folder. Choose a coding workspace, save your own instructions and model settings, and optionally connect Unreal inspection tools.

**v0.3.0-alpha.1 Â· Portable source package.** No fixed installation folder or registry registration is required for the launcher. Python, Node, Strata and model files are separate dependencies; run **Setup.cmd on each PC**. This is not a standalone executable or a bundled model download.

**Performance is workload-dependent.** A fresh audit on our RTX 3060 12 GB / Ryzen 5 5500 / 32 GB PC measured **17.4 decode tokens/s on the first short request**, then **30.9 and 36.7** on identical cached repeats. A different earlier request showed **11.8**. These are separate observations, not a sustained-speed promise. [Method and complete results](docs/performance.md).

![AiBrainWorX Local AI Control](media/aibrainworx-local-ai-control.png)

Made by **AiBrainWorX** Â· Original code: **MIT** Â· [Website](https://aibrainworx.com) Â· [GitHub](https://github.com/AiBrainWorXdotCom)

## Start here â€” no Git commands required

1. [Download the ZIP](https://github.com/AiBrainWorXdotCom/AiBrainWorX-Local-AI-Control/archive/refs/heads/main.zip), then extract it into a permanent folder. You can also use **Code â†’ Download ZIP**.
2. Read [model license notes](MODEL-LICENSES.md), then double-click **Setup.cmd**.
3. Setup checks prerequisites, offers installation through official sources, and reuses an existing Strata installation when selected.
4. Choose a working folder. Unreal is optional; an ordinary coding folder works too.
5. Open **Launch.cmd**, click **Start model**, and wait for Ready. Choose **DeepSeek Harness (browser)**, then **Start â†’ Open chat**.

The workspace dropdown also offers **Codex CLI (optional)**. Choose it and click **Open CLI** to open a prepared local profile in a terminal. Both clients use the same Strata server; you can use either one. Switching clients does not stop a running service. Choose model weights during Setup; customize instructions and request settings through **Settings**.

## Your settings, before launch

- **Saved profiles:** name a project, choose its folder and optional Unreal Python folder, then Save or Save as new.
- **Custom instructions:** start with General Coder, Unreal Developer or Code Reviewer, edit the text, and enable its checkbox.
- **Sampling sliders:** optionally override temperature and top-p. Leave the checkbox off to retain client/model defaults.
- **Output limit:** set a maximum of 64â€“8192 tokens per request. A client may request fewer tokens, and reasoning can consume the output budget.
- **Live readings:** see generation speed, CPU usage, VRAM and RAM from Strata's metrics. Idle shows the last completed request separately.
- **Diagnostics:** check installed clients, the model and optional Unreal connection without generating a reply. The copyable report excludes personal paths and prompts.

![Instructions, sampling sliders and saved launch profiles](media/aibrainworx-launch-settings.png)

These settings apply to new requests through a small local service on port **8082**, which forwards to Strata on **8081**. Existing client instructions and tools remain in place. Settings do not change model weights, context size or the client's permissions. See the [profiles guide](docs/launch-profiles.md).

**Updating an existing installation:** if Harness is already running, finish its current turn, then use Stop â†’ Start once to use the new managed profile. Each profile has its own client home; existing global history is preserved. Stop Harness before switching project profiles. The launcher never interrupts your current assistant automatically.

## Moving the launcher

Keep the extracted source folder together. After moving it on the same PC, client bridge paths are regenerated at launch. On another PC, run Setup again to select that computer's installed runtimes, project and model. Do not share `config.local.json`, prompts, logs or client homes. Heavy model data can stay in its own location, including a suitable external drive; drive speed affects loading and inference.

Large model downloads require an explicit `DOWNLOAD` confirmation. The tested Qwen Coder files are approximately 58.4 GB, plus prepared data and other runtime files. The guided Strata option can select another supported model. Model weights are downloaded by Strata; none are stored in this repository.

Setup uses Windows Package Manager for missing Git, Python or Node when you approve. Agent packages come from the official npm packages. Existing installers may display their own prompts. The launcher does not install drivers or change machine-wide PowerShell execution policy. The `.cmd` entry points use a process-only execution-policy setting to run these local scripts.

## What is included

- A branded portable control panel with detected hardware and live utilization.
- Independent model and Harness start/stop controls.
- Saved launch profiles and isolated client configuration, leaving global defaults unchanged.
- Five optional Unreal inspection tools: project status, actors, actor details, selection and asset search.
- Four original [Unreal skills](skills/README.md) for development, source investigation, Epic research and MCP diagnostics.
- A [setup tutorial](docs/tutorial.md), screenshots, architecture graphics and a [rebuildable captioned walkthrough](media/VIDEO.md).
- MIT-licensed integration source and contract tests.

Harness is the agent interface; the configured model can be Qwen. You do not need to download a DeepSeek model to use this setup.

## Hardware and current support

This release targets **Windows**, using source-based Strata installations. Our tested machine has an **RTX 3060 with 12 GB VRAM, Ryzen 5 5500 and 32 GB RAM**. Those specifications describe our build; they are not a promise that every model fits every PC.

The launcher reads your hardware. Strata's hardware check and setup choose an appropriate backend/model. NVIDIA VRAM is queried through `nvidia-smi`; other adapters fall back to their reported name without guessing VRAM from Windows' limited `AdapterRAM` field.

The model does not fit entirely in 12 GB VRAM. It also uses system RAM and SSD-backed files. We observed about 20â€“25 generated tokens/sec on short probes and around 13 tokens/sec under severe memory pressure with Unreal open. These are observations from one PC, not guaranteed performance. A probe also returned a wrong answer: review outputs and run tests.

Keep one active agent at a time on memory-constrained machines. Stop inference when you need to free the GPU. Heavy concurrent Unreal/model workloads are not validated as a smooth experience on our 32 GB machine.

## Settings and privacy

See [SECURITY.md](SECURITY.md) for security and privacy details.

`config.local.json` contains your actual installation paths and is ignored by Git. Runtime data and logs go into your local application-data folder. The first-run setup uses a dedicated Harness home so it can prepare its own profile without replacing your existing Harness history or credentials.

This alpha expects Strata on `127.0.0.1:8081`, the launch settings service on `127.0.0.1:8082`, and Harness on `127.0.0.1:3080`. All bind to loopback. The model-control preset expects no Strata API key. A conflicting port blocks another start instead of killing its owner.

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
- Saved-profile persistence, instruction injection, request limits, isolation and incremental streaming have contract tests. A managed Harness profile also booted on a separate test port without interrupting the active session.
- Model generation and earlier Codex project-status tool calls were validated.
- A complete fresh-machine bootstrap with new model downloads has **not** been tested end to end.
- Live actor/asset/selection inspection still needs a separate open-editor acceptance pass.
- The application-only media captures render the real WinForms controls with live service status. The walkthrough adds explanatory graphics; it does not simulate successful editor mutations.
- Local voice-over installation is planned separately and is not part of this release.

For contributors:

```powershell
python bridge/test_unreal_mcp.py
python Tests/test_control_runtime.py
python Tests/check_public_files.py
powershell -NoProfile -File Tests/Check-Scripts.ps1
powershell -NoProfile -File Tests/Check-ClientLaunch.ps1
powershell -NoProfile -File Setup.ps1 -Plan
```

## Licenses

Our original launcher and bridge code use [MIT](LICENSE). Strata, Qwen, Codex, Harness and Unreal retain their own terms. See [third-party notices](THIRD_PARTY_NOTICES.md) and [model license notes](MODEL-LICENSES.md). This project is independent and is not an official product or endorsement from those vendors.
