# Performance review — October 25, 2026

Reviewed application commit: `a9d0acb`. This is a review, not a claim that the
findings below have been fixed. Codex orchestrated focused source reviews and
measurements; the installed Qwen Coder also reviewed selected source.

## Findings

1. **P2 — Recurring status work competes with inference and blocks token display.**
   [Desktop.ps1](../../app/Desktop.ps1#L289) synchronously checks Harness status
   during its approximately three-second overview refresh. That check performs
   CIM process scans and a socket check on the UI thread that also drains chat
   output. Separately, [status polling](../../app/Desktop.ps1#L294) starts fresh
   PowerShell and Python processes through [Control.ps1](../../app/Control.ps1#L22)
   and [Strata-Control.ps1](../../app/Strata-Control.ps1#L7). Use background,
   cached status with less-frequent ownership reconciliation. The raw decode
   benefit has not been measured; UI stalls and process churn are code findings.

2. **P2 — Memory retrieval adds unrelated notes and changes the reusable prefix.**
   [Recall](../../app/project_memory.py#L108) ranks notes but does not exclude
   zero-relevance unpinned records. A synthetic test returned 4,096 characters
   for an unrelated query. Query-dependent ordering is inserted into the first
   system prompt by [request transformation](../../app/control_core.py#L245).
   Keep pinned notes stable and require relevance for other notes. This affects
   prompt work and cache reuse, not a proven raw decoder gain. Memory was off in
   the active profile during these speed tests.

3. **P2 — Speed telemetry can label active prompt reading as idle.**
   [Desktop.ps1](../../app/Desktop.ps1#L306) recognizes `generating` but falls back
   to an old “Idle | Last decode rate” during Strata's `reading` state. Metric
   results also lack the profile/model/revision guards used by lifecycle results.
   Show reading, generating and idle separately, and discard stale samples.

4. **P2 — Chat's context guard does not budget the final transformed request.**
   [local_chat.py](../../app/local_chat.py#L15) uses a character heuristic before
   injected instructions and memory, without accounting for the output budget.
   Token-dense code can pass that guard and exceed backend context. Budget the
   final request and reserve output space; label estimates honestly until a
   compatible tokenizer is available.

5. **P2 — Shutdown reported incomplete before a subsequent stopped snapshot.**
   The live stop command returned “1 model process(es) are still running.”
   GPU allocation had already fallen to approximately 1.3 GiB; the following
   verified snapshot showed stopped and no matching engine process remained.
   [Survivor checking](../../app/Model-Lifecycle.ps1#L58) needs further real-process
   investigation. The exact cause is unresolved; do not assume all stop failures
   are harmless. The test engine ended stopped, with 21.58 GiB RAM free.

## Measurements

Exact source: ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF, **IQ1_M**.
Hardware: RTX 3060 12 GB, Ryzen 5 5500, 32 GB RAM. Sequential direct Strata
requests, temperature 0, reasoning off. No other applications were closed.

| Workload | Reported decode tokens/s | Conditions |
| --- | ---: | --- |
| First three varied probes after loading | 13.7 / 15.7 / 17.3 | 192 output tokens, zero cached input |
| Separate identical-prompt sequence | 20.6 / 38.1 / 37.1 | 128 output tokens; 0 / 35 / 35 cached input |
| Completed Qwen source review | 21.9 | 3,464 input, 733 output, zero cached input |
| Later automatic-routing probes | 24.8 / 25.5 / 25.0 | Warm engine, changed prompt prefixes, zero cached input |

The completed review took 42.46 seconds end to end. Engine prompt processing was
8.895 seconds, and first engine token was 8.945 seconds. These are different
measurements from decode speed.

Request-local CPU/GPU split experiments reached 40.5 tokens/s on a cached short
repeat. Fixed splits did not win consistently across tasks. Expert-cache warming,
trial order and differing generated text remain confounders even with zero
cached input tokens. No fixed split was promoted into saved settings.

Available RAM fell to approximately 0.12 GiB during several trials, with
substantial disk reads. Memory pressure is an important constraint to measure;
these observations do not isolate one cause of every speed change. MTP, expert
caching, int8 KV and resident experts were already enabled. No hard launcher-side
20 tokens/s limit was found.

Most short probes stopped at their output cap. They measure short throughput,
not completed-task quality or a sustained-speed guarantee. Qwen's review was
also checked manually: unsupported suggestions were not applied automatically.
[Numeric observations](../benchmarks/2026-10-25-review.json).

## Validation and scope

38 application Python tests and 10 Unreal bridge tests passed. PowerShell syntax
and mocked lifecycle checks passed. These tests do not cover all UI timing or
real shutdown behavior. No fresh-machine install, live Unreal acceptance,
Ollama/LM Studio generation, or long agent-quality benchmark was performed.
Application code and saved engine settings were unchanged by this review.
