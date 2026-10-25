# Measured performance, with the conditions attached

There is no single guaranteed tokens-per-second rate for this setup. Earlier
20–25 decode-token/s probes, a screenshot showing 11.8, and the audit below are
different observations. We have removed the fixed-rate marketing headline.

## Latest check: October 25, 2026, 08:29 Pacific

The already-loaded Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF **IQ1_M**, served through
Strata 0.1.48 on the same RTX 3060 12 GB / Ryzen 5 5500 / 32 GB PC, completed six
short coding requests. Temperature 0, reasoning off, sequential direct loopback;
no applications closed or saved engine settings changed.

| Request | Decode tokens/s | First engine token | Complete request | Cached input |
| --- | ---: | ---: | ---: | ---: |
| Python merge | 28.0 | 2.250 s | 6.521 s | 0 |
| TypeScript groupBy | 32.5 | 1.499 s | 5.665 s | 0 |
| SQL query | 28.1 | 1.691 s | 5.627 s | 0 |
| Python clamp | 35.5 | 1.570 s | 4.222 s | 0 |
| Identical clamp repeat | 40.5 | 0.140 s | 2.460 s | 54 |
| Identical clamp repeat | 41.0 | 0.201 s | 2.494 s | 54 |

All six ended normally, producing 95–136 tokens; none hit the 256/160 output caps.
The engine and expert cache were warm. Zero cached input means no prompt-token
reuse, not a cold engine. The three varied Python/TypeScript/SQL tasks had median
28.1; the fourth, shorter clamp task reached 35.5. Cache reuse, workload and trial
order remain distinct factors. No general speed improvement or task quality was
established by comparing these different samples with earlier runs.

![Completed short coding speed check](../media/aibrainworx-coding-speed-20261025.png)

[Full method and latency graphic](benchmarks/2026-10-25-coding-speed.md) ·
[Numeric observations](benchmarks/2026-10-25-coding-speed.json).

### Beyond the VRAM wall: what this establishes

The full model does not live in the 12 GB card. Strata combines GPU expert
caching with system-memory and file-backed tiers; see its
[technical documentation](https://github.com/Niko1221/Strata/blob/main/docs/DETAILS.md).
The exact compressed Coder variant is linked in the model source above.
IQ1_M is a format name, not a statement that every tensor uses exactly one bit.

The new requests were uncached at the prompt-token level, while the engine and
expert cache were already warm. Repeats reused 54 of 61 input tokens, leaving
seven to read; they did not completely bypass prefill. The observed 140/201 ms
first engine tokens are not a latency guarantee for a tool loop, a measurement
of launcher display latency, or a hosted-API comparison.

No application cleanup, fixed page-file size, new KV format or context-reset
policy was tested in this run. The existing configuration used a 16K context
and Strata's `--kv int8`. Do not copy another engine's cache flags blindly.
Microsoft's [page-file guidance](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/introduction-to-the-page-file)
explains commit-limit requirements; a universal 16 GB cap is not a measured
speed fix. Context resets can also discard reusable input.

Read the combined [setup and benchmark article](https://aibrainworx.com/qwen-38-coder-12gb-gpu-ryzen5-strata-codex-unreal/).

## Earlier October 25 review

The earlier [performance review](reviews/2026-10-25-performance.md) includes a
completed 733-output-token source review at 21.9 decode tokens/s and warm short
probes at 24.8–25.5. Its findings remain pending; this follow-up changes
documentation and graphics, not application code or engine settings.

## October 24, 2026 audit

Hardware: RTX 3060 12 GB, Ryzen 5 5500, approximately 32 GB RAM and SSD-backed
model data. Exact source variant:
[ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF](https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF),
**IQ1_M**, served as `qwen3.8-flash-next-coder-iq1_m`, already loaded in Strata.
No applications were closed and no engine settings were changed. One Windows
snapshot during the run reported 0.72 GiB of available physical memory.

Three sequential, identical direct local Chat Completions requests used a
128-token output cap, temperature 0 and `reasoning_effort: none`. The prompt
asked for a Python `chunked(iterable, size)` generator. Each produced 93 output
tokens from 45 input tokens. Strata reported 38 cached input tokens on repeats.

| Request | Cached input | Engine decode tokens/s | Complete request time | Output / complete time |
| --- | ---: | ---: | ---: | ---: |
| First | 0 | 17.4 | 8.58 s | 10.8 tokens/s |
| Identical repeat | 38 | 30.9 | 3.14 s | 29.6 tokens/s |
| Identical repeat | 38 | 36.7 | 2.71 s | 34.3 tokens/s |

[Raw numeric results](benchmarks/2026-10-24-throughput.json) include the limits,
timestamps, usage and memory readings. These are short coding requests, not a
long tool-using agent benchmark. Repeating a tiny prompt can benefit from cache
and is not representative of every real task. The observations do not isolate
one cause of the earlier 11.8 reading or demonstrate a general speed increase.

## Read the right measurement

- **Prompt processing / prefill** measures reading input, including large tool
  definitions and conversation context. Cache reuse changes how much is read.
- **Decode** measures generating output after prompt processing. The launcher
  labels live decode and an idle last-request sample separately.
- **Time to first token** measures how long the user waits for output to begin.
- **End-to-end time** also includes prompt processing, waiting and transport.
- **Reasoning effort and output budget** affect latency and answer quality.
  Higher effort can use thousands of tokens before the answer appears.

The creator's 64 GB / Ryzen 9 / 12 GB GPU video is a separate configuration from
our 32 GB / Ryzen 5 PC. Input rates near 900 tokens/s must not be described as
900 generated tokens/s. Model variants and quantization differ as well.

Changes to inference/cache settings should be measured on the same task with
conditions recorded. Do not substitute a better cached-repeat number for an
everyday speed guarantee. Review generated code and measure task success too.

## Different prompts on the same warm engine

Four sequential requests used different creative, coding, explanation and planning
prompts, temperature 0, reasoning none and a 192-token cap. Each produced 192
tokens and ended at the cap, so these are short throughput samples, not completed
task-quality evaluations. No apps were closed or engine settings changed.

| Task | Cached input | Decode tokens/s | Complete time | Output / total time |
| --- | ---: | ---: | ---: | ---: |
| creative | 0 | 18.5 | 12.85 s | 14.9 tokens/s |
| coding | 0 | 19.5 | 12.06 s | 15.9 tokens/s |
| explanation | 0 | 20.8 | 11.04 s | 17.4 tokens/s |
| planning | 0 | 17.8 | 12.49 s | 15.4 tokens/s |

The observed decode range was **17.8–20.8 tokens/s**. This does not consistently
meet a 20–25 target. Different hardware and workloads will differ.
If a thumbnail abbreviates the uncached observation as “~20”, that refers to
the separate 20.8 explanation sample, not the original 17.4 first request.
The 30.9 and 36.7 cached repeats are a different short-request series. Other
model logos represent catalog references, not additional benchmark subjects.
[All prompts, timestamps, usage and timings](benchmarks/2026-10-24-varied-prompts.json).
