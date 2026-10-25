---
name: awx-model-dataset-review
description: Review local model, dataset and runtime compatibility before downloads, training, benchmarking or edge deployment.
---

Keep original model/dataset IDs, creator credit, exact revision and license.
Distinguish source-model terms, conversion terms, voice/image assets and dataset
rights. A code repository's MIT license does not automatically cover its weights.

Match the actual task and schema: text/messages for text SFT; image/conversation
processing for VLM SFT; audio/transcripts for ASR; reference-speaker formatting
for the supported TTS trainer. Validate a small local sample before allocating
large downloads or training resources. Do not execute dataset loading scripts
or remote model code just to inspect metadata.

Record hardware, quantization, context, cache state, effort, output cap and task
success when benchmarking. Attribute publisher benchmarks separately. Mark edge
models as candidates until the specific converted artifact runs on the device.
Skills provide workflow instructions; they do not modify model weights or
create new runtime capabilities.
