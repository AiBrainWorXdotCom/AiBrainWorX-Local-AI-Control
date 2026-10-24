# Measured performance, with the conditions attached

There is no single guaranteed tokens-per-second rate for this setup. Earlier
20–25 decode-token/s probes, a screenshot showing 11.8, and the audit below are
different observations. We have removed the fixed-rate marketing headline.

## October 24, 2026 audit

Hardware: RTX 3060 12 GB, Ryzen 5 5500, approximately 32 GB RAM and SSD-backed
model data. Model: `qwen3.8-flash-next-coder-iq1_m`, already loaded in Strata.
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
[All prompts, timestamps, usage and timings](benchmarks/2026-10-24-varied-prompts.json).
