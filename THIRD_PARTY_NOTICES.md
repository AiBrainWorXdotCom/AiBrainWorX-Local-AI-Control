# Third-party projects

| Project | Published license / terms | Included here? |
| --- | --- | --- |
| [Strata](https://github.com/Niko1221/Strata) | [MIT](https://github.com/Niko1221/Strata/blob/v0.2.4/LICENSE); copyright Niko1221 and contributors | No; obtained separately by setup or reused. |
| [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) | [MIT](https://github.com/deepseek-ai/deepseek-harness/blob/master/LICENSE); copyright DeepSeek | No; official npm package. |
| [Codex CLI](https://github.com/openai/codex) | [Apache-2.0](https://github.com/openai/codex/blob/main/LICENSE) | No; official npm package. This does not include OpenAI's proprietary models or desktop application. |
| Qwen model weights and the ISTA-DASLab conversion | See [model license notes](MODEL-LICENSES.md) | No. |
| [Ollama](https://github.com/ollama/ollama) / [LM Studio](https://lmstudio.ai/) / [llama.cpp](https://github.com/ggml-org/llama.cpp) / [llama-swap](https://github.com/mostlygeek/llama-swap) | Respective project licenses and application terms | No; independently installed local servers. |
| Unreal Engine | Epic's applicable engine/license terms | No. The bridge imports the user's separately installed remote-execution module. |
| Python, Node, Git, FFmpeg and their dependencies | Their own upstream licenses | No runtime binaries bundled. FFmpeg is a media-build tool, not required to launch the application. |

The bridge, controller scripts, documentation and original infographic artwork are AiBrainWorX contributions. Interfaces and configuration examples refer to the upstream APIs. Retain required licenses and notices when independently redistributing upstream components or modified forks.

`app/model-details.json` contains original, concise editorial summaries plus
attributed factual metadata and reviewed upstream revision IDs, not mirrored
model cards or weights. The 33 launcher suggestions have MIT/Apache-2.0 source
metadata; research-only profiles may have custom licenses. Check exact artifacts.

AiBrainWorX Memory is original Python/SQLite code. REA (MIT) was used for a
selected-source private static research exercise. OpenHuman (GPL-3.0) code and
research copies are not incorporated or distributed. DeepInfer is documented
as a future server-engine possibility, not installed or bundled here.
