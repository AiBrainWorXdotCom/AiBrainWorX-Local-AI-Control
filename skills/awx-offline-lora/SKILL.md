---
name: awx-offline-lora
description: Prepare, validate and manage an explicit tiny-text LoRA job through AiBrainWorX training tools, using local checkpoints and local JSONL data.
---

Establish the task, allowed data and held-out evaluation before training. Inspect
the selected model architecture, weight format and applicable rights. A dataset
card's task label alone does not establish schema, licensing or model compatibility.

`training_preflight` checks the profile-selected paths and optional dependencies.
The initial worker supports small dense text HF checkpoints with floating-point
safetensors, about 1B parameters, and text or messages JSONL. It is LoRA with
full-sequence loss, not QLoRA or an audio/vision trainer. It does not train GGUF.

Start only for the user's requested training task, after preflight succeeds and
the user enables training starts in the launcher profile. `training_start` uses
those saved settings; do not alter private settings to grant yourself permission.
Monitor `training_job_status`; `training_stop` requests cooperative cancellation.
Do not kill unrelated inference or editor processes to make room.

The worker keeps network downloads disabled and saves a separate adapter. Report
the actual job state, evaluation and base/adapter provenance. A successful
preflight is not a successful training run, and a lower training loss is not
proof of improved task quality.

Primary references:
- https://huggingface.co/docs/peft/main/en/developer_guides/lora
- https://huggingface.co/docs/transformers/trainer
