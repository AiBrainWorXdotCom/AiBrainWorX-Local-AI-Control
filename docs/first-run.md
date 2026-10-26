# First-time Windows setup

The GitHub ZIP contains the **launcher source**, not a complete Python/Node/model
installation. Extract it before running. Repeat setup for each Windows user or PC;
tools installed only for another user may not be available to the current user.

## 1. Download and extract

1. [Download the current ZIP](https://github.com/AiBrainWorXdotCom/AiBrainWorX-Local-AI-Control/archive/refs/heads/main.zip).
2. Right-click the ZIP in File Explorer and choose **Extract All**.
3. Open the extracted folder that contains `Setup.cmd`, `Launch.cmd` and `README.md`.
4. Double-click **Setup.cmd**. Keep its window open while it works. Follow any
   official installer dialogs it opens. You do not need to open GitHub in a
   special app or sign in to download the ZIP.

## 2. Prerequisites: what to answer

Step 1 checks the tools that run the launcher and coding clients:

| Tool | Why it is needed | If setup offers installation |
| --- | --- | --- |
| 64-bit Python 3.10+ | Launcher services, SQLite memory and model integration | Type `y` for Python 3.12, or install manually below |
| Node.js LTS with npm | DeepSeek Harness and the optional Codex CLI | Type `y` for Node.js LTS |
| Git | Download Strata source, only when you select Strata | Type `y` if needed; you do not need to learn Git commands |

An offer ends in `[y/N]`: type `y` and press Enter to install. Pressing Enter
without typing means **No**. Package-manager prompts/installer dialogs remain
visible; setup does not silently accept license agreements or change credentials.
Model terms are separate from the launcher's MIT license.

### “Python was not found” / Microsoft Store shortcut

Windows can include a `python.exe` shortcut even when Python is not installed.
Versions before **0.4.0-alpha.4** could mistake that shortcut for Python. Download
the current ZIP and rerun setup. The repaired installer runs a bounded Python
probe and rejects the shortcut, old/32-bit versions and missing SQLite/venv.
It can find a real registered/per-user interpreter without changing PATH or
disabling Windows' app execution aliases.

If Windows Package Manager is unavailable, you decline installation or it fails:

1. Install a **64-bit** Python version from the [official Python downloads](https://www.python.org/downloads/windows/). Python 3.12 is the setup's preferred install target. Include **pip** and **venv**; selecting **Add Python to PATH** is helpful.
2. Install [Node.js LTS](https://nodejs.org/) with npm and the installer PATH option.
3. Close the failed setup window and double-click `Setup.cmd` again.

Or run these commands in PowerShell if `winget` is installed:

```powershell
winget install --exact --id Python.Python.3.12 --source winget --architecture x64 --scope user
winget install --exact --id OpenJS.NodeJS.LTS --source winget
```

Git is needed only for Strata:

```powershell
winget install --exact --id Git.Git --source winget
```

No Microsoft account is required for the python.org installation. New PATH
settings may require reopening setup. If `winget` fails, use the official manual
installers rather than repeatedly running the old ZIP.

## 3. Choose a backend and model

Step 2 asks which model server to use. Pick one:

- **1 — Strata:** setup can reuse an installation or download the pinned official
  Strata source. Follow the hardware check. Choose the tested Coder preset or
  guided selection; review model terms and disk needs, then type `DOWNLOAD` only
  if you want that model download. Loading/downloading can take time.
- **2 — Ollama:** install Ollama separately, download a model in Ollama and start
  it. Default API: `http://127.0.0.1:11434/v1`.
- **3 — LM Studio:** install/load a model in LM Studio and turn on its local
  server. Default API: `http://127.0.0.1:1234/v1`.
- **4 — Compatible server:** start your installed llama.cpp/llama-swap server and
  enter its actual loopback API and exact model ID.

The large Strata IQ1_M Coder test used an RTX 3060 **12 GB**, **32 GB RAM** and an
SSD. Allow roughly **120 GB free** for that preset's approximately 58.4 GB
download, prepared data and working space. Smaller/other models have different
requirements. The launcher does not make every listed model fit every GPU.
For another backend, this setup does not download its app or model for you.

## 4. Finish and open your workspace

Step 3 offers the official Harness/Codex client packages in this app's runtime.
Step 4 asks for a working project folder; an empty folder is fine. Unreal Engine
is optional. Wait for **Setup complete** before opening `Launch.cmd`.

1. On **Overview**, click **Start model** for Strata; wait for green **Running**.
   Other backends are controlled in their own app. First loading may take minutes.
2. Use **Chat** for a simple message. A green server badge is not a completed
   generation test; a reply confirms the configured model is responding.
3. For coding, choose **DeepSeek Harness**, click **Start**, wait for readiness,
   then **Open chat**. Codex CLI is another client, not a requirement to use Harness.

If a step fails, read its final message, fix that prerequisite and rerun setup.
Existing model files/downloads are retained. Do not share `config.local.json`,
private logs or client histories when asking for help.

## Check prerequisites without installing anything

Open PowerShell in the extracted project folder and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -CheckPrerequisites
```

This checks real Python, Node and npm. Exit code `0` means these checks passed;
`2` means a prerequisite is missing/non-working. It does not install packages,
download weights, create config or start a model. Git is checked later if Strata
is selected. A plan-only explanation is also available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Plan
```

The prerequisite regression suite uses local fixture executables to reproduce
first-run errors. It does not represent a full clean-PC installation or a model
download. See [verification](../README.md#verification) for reproducible checks.

Sources: [Python's Windows installation guide](https://docs.python.org/3.12/using/windows.html),
[Microsoft's Python setup guide](https://learn.microsoft.com/en-us/windows/dev-environment/python),
[Windows Package Manager installation options](https://learn.microsoft.com/en-us/windows/package-manager/winget/install).
