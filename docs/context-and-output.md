# Context and output limits

Original AiBrainWorX code, MIT. Shared by the separate Linux work and the focused
Windows 0.4.0-alpha.3 fix. This is a control-plane change, not a model upgrade.

- Count AFTER user instructions, optional project memory and reasoning settings.
- Use the running server's per-slot context, bounded by the profile's declaration.
- Output allowance is the minimum of client cap, profile cap, 4096 per pass,
  remaining 12288 total allowance, and context minus prompt minus 256 tokens.
- No `len(text)//4` estimate. Strata uses its installed frontend and tokenizer in
  a persistent helper; the running template hash must match. Text, tools and
  stateless Responses are rendered using the installed adapters. No engine loads.
- llama.cpp Chat Completions uses `/apply-template`, `/tokenize` and `/props`.
- Missing counting support fails explicitly. Ollama/LM Studio retain their existing
  transport and cap behavior; exact preflight adapters have not been validated.
- Two EXTRA text continuations means three requests total. Continuation requires
  2048 tokens of room after the reserve, available total allowance, no repeated
  preview, and a completed upstream pass with `finish_reason: length`.
- Structured output, tool calls, reasoning streams, multimodal output and Responses
  are not concatenated. Their client owns the next step.
- Each visible SSE response has one stable ID, a final truthful finish reason and
  one `[DONE]`. Content arriving in a finish chunk is preserved. Client disconnect
  closes the upstream iterator. Missing terminal events are errors, not success.
- Requests are also bounded by a time and byte ceiling. Usage is reported only
  when complete backend measurements are available; stream chunks are not tokens.

## Built-in chat handoffs

The visible conversation ID stays stable. Full user/assistant turns are saved in
the private state folder's `conversations.sqlite3`. When the working prompt needs
space, a bounded model-generated handoff replaces older turns in the NEXT model
request, keeping the newest messages. The transcript is never deleted. Summary
failure keeps the previous state. No 32K context reload is performed automatically.

Project memory remains in its separate existing database. The memory checkbox
still decides whether its notes are included. A handoff is labeled unverified
conversation data; it is never inserted as a verified saved fact or a system rule.
There is no exact-recall guarantee after summarization. Oversized single turns can
still require splitting. Summarizing incurs a local model request and can pause
the next reply. Agent/tool transcripts are not summarized behind their client's back.

Continuation uses a normal conversational request. Raw assistant prefill requires
a validated backend-specific adapter. It is not assumed to repair a split identifier,
Markdown fence, malformed JSON or incorrect code. Tests and code review still apply.

## Acceptance recorded October 25, 2026

52 unit/HTTP/profile tests passed in Ubuntu 24.04 WSL2. A separate live staged
gateway used the already-running Strata/Qwen model: a normal answer stopped
naturally; an 8-token forced cutoff made two extra passes, allocated 24 tokens
total and ended with `length` plus one `[DONE]`. Stateless Responses and tool
schemas were counted without tool execution. No model restart, downloads,
profile switches or backend configuration changes were performed for these probes.
These are acceptance checks, not throughput or coding-quality benchmarks.
