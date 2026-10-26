# Changelog

## 0.4.0-alpha.5

- Keep Python installation per-user and omit the optional shared `py.exe` launcher, avoiding its elevation/repair conflict on another Windows account.
- Preserve winget's installer/hash checks and defaults; no Windows policy changes or automatic elevation.
- Explain installer error 1625 separately and test the ordinary-user installer arguments and policy-blocked recovery.

## 0.4.0-alpha.4

- Fix first-run setup accepting the Windows Python Store placeholder as a real interpreter.
- Verify 64-bit Python 3.10+, SQLite and venv; discover Python through PATH, the Python launcher, registered installs and per-user folders.
- Recheck prerequisites after installation and keep package-manager output out of saved executable paths.
- Four numbered setup stages, readable recovery messages, a first-run guide and a read-only prerequisite check.
- Windows PowerShell 5.1 regression fixtures for missing/invalid prerequisites and install recovery; no test installs or model downloads.

## 0.4.0-alpha.3

- Full-prompt output budgeting, native Strata counting, bounded text continuation
  and truthful terminal SSE events; tools/structured output retain client control.
- Stable built-in chat sessions, saved local transcripts and bounded context
  handoffs, independent of explicit project memory.
- Read-only component Update Center, model provenance tracking and source reviews.
- External user-plugin folders, API-v1 chat hooks and explicit source approval.
- Preview-first customization migration, three-way conflicts and candidate backups.
- No model, Harness, skill or plugin automatically installed or upgraded.

## 0.4.0-alpha.1

- Expanded library: 56 model profiles, 36 text suggestions and six dataset guides.
- Tiny Gemma, TTS, ASR, vision, embedding and video references with explicit runtime/license notes.
- Experimental offline tiny-text LoRA jobs, preflight, opt-in starts, progress and cooperative stop.
- Profile-scoped training and original workflow-reading MCP tools for coding clients.
- Optional Android project/ADB inventory and Blender main-thread inspection bridges.
- Thirteen workflow templates, eight original skills and four reviewed upstream references.
- In-Chat local video preview through the optional Windows Media Player component.
- Ko-fi support links; no payment credentials, downloads or automatic training.

## 0.3.0-alpha.1

- Rebranded as AiBrainWorX Model Launcher, with a desktop sidebar and brand icon.
- Per-profile connections for Strata, Ollama, LM Studio and local compatible servers.
- External-only setup, model discovery and explicit context/reasoning declarations.
- Tool-free streamed local chat and creative, adventure and learning presets.
- Original local SQLite project memory, bounded opt-in recall and handoff export.
- Manual GitHub update checks, with accurate unavailable and prerelease states.
- 33 model suggestions with offline summaries and links to AiBrainWorX profiles.
- Source-reviewed site profiles separate publisher claims from our local tests.
- Fresh varied-prompt performance results; no sustained-speed guarantee.
- Backend, credential, memory, updater and chat contracts plus live Strata smoke test.

## 0.2.0-alpha.1

- Saved project profiles, editable instruction presets and a custom prompt box.
- Optional temperature/top-p sliders and a per-request output limit.
- Loopback settings gateway with separate endpoints and client homes per profile.
- Live generation speed, CPU, VRAM and RAM readings, with an explicit idle state.
- Connection diagnostics and a privacy-conscious copyable report.
- Portable startup validation and stronger moving/setup guidance.
- Profile, streaming, request transformation and client-launch contract checks.

This is an alpha source package. No GitHub release or tag is created by changing
the version file. Models and third-party runtimes are installed separately.
