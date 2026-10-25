# How we build AiBrainWorX Model Launcher

AiBrainWorX sets the product direction, chooses priorities and reviews the result.
This is an AI-assisted development project, with Codex playing a substantial
orchestration and implementation role.

## Codex: development orchestrator

Codex coordinates the work across launcher code, local model integrations,
profiles, memory, platform bridges, documentation and publishing. It inspects
source and logs, breaks larger problems into focused reviews, implements bounded
changes, runs checks and verifies results before preparing updates.

The October 25, 2026 review session recorded `gpt-6.1-sol` with `ultra`
reasoning: **GPT-6.1 Sol / Ultra**. This identifies that development session,
not a required model or configuration for launcher users.
[Official Codex model and reasoning guidance](https://learn.chatgpt.com/docs/agent-configuration/subagents#choosing-models-and-reasoning).

## Qwen: local coding collaborator

The installed local collaborator is
**ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF, IQ1_M**, served by
Strata. During this review it read selected launcher source and produced a
completed code review from 3,464 input tokens and 733 output tokens. Its reported
decode rate was 21.9 tokens/s on the RTX 3060 12 GB / Ryzen 5 5500 / 32 GB PC.
The request used temperature 0 and reasoning off. This is one observation,
not a quality score or sustained-speed guarantee.

Local model suggestions are proposals. Codex checks them against the actual code,
measures performance where possible and rejects unsupported diagnoses. For
example, testing whether an asynchronous task `IsCompleted` is not a blocking
wait; it must not be described as one merely because a model says so.

## Validation and runtime boundaries

- Inspect the current source and preserve the owner's work.
- Separate raw decode speed, prompt processing, first-token delay and UI latency.
- Compare automatic engine behavior with reversible request-local experiments.
- Run relevant tests and keep failures visible in the review.
- Review publishing changes for private paths and credentials.

Codex's development role does not make cloud inference part of the launcher's
local model path. Built-in chat and the local backends can run without Codex.
Strata is the inference engine; DeepSeek Harness and optional Codex CLI are
coding clients. Their identities must not be confused with the selected model.
OpenAI products remain external tools under their own terms; the repository's
MIT license covers AiBrainWorX's original code, not third-party services or models.

See the [October 25 performance review](reviews/2026-10-25-performance.md)
for findings, measurements and limits.
