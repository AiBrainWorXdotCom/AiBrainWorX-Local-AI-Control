# Local training and platform workspaces (experimental)

Version 0.4 adds profile templates, a dataset catalog, two optional inspection
bridges and an explicit tiny-text LoRA job workflow. No extra model download,
package installation or live training run was performed as part of this update.

## Offline tiny-text training

In **Training**, select a separate training Python, a complete local Hugging Face
checkpoint folder, a local JSONL dataset and an existing output parent folder.
The optional environment needs PyTorch, Transformers, PEFT, Accelerate and
safetensors. Use the official PyTorch installer for your platform; install the
other packages into that separate environment. The launcher does not install
them or assume the inference environment can train.

The initial worker supports ordinary floating-point safetensors for small dense
Qwen2/Qwen3, Llama/SmolLM2 and Gemma3-text architectures, with a 1.2B stored-tensor
cap. It is **LoRA**, not QLoRA. It does not train our large Strata GGUF, MoE,
audio, embedding or vision checkpoints. Those require their own trainers.

JSONL rows contain nonempty `text` or a `messages` list of text-only
system/user/assistant messages. Prepare a small relevant subset and a separate
evaluation set first. Dataset references describe schema/workflow compatibility,
not proof that training has run or that all source rights are cleared.

Save settings and run **Preflight**. It checks local files, tensor-header size,
dataset shape and installed package metadata. Then explicitly enable training
starts for that profile and save. This allows Start in the launcher and in its
coding-client tools. The worker disables Hub downloads and remote model code,
uses batch 1 / gradient accumulation 4 / learning rate 2e-4, and applies
full-sequence language-model loss. Default limits are 256 tokens, 1,000 examples,
rank 8 and 50 steps; the UI exposes bounded alternatives.

Each run saves a separate adapter under a new unique output subfolder. Original
weights are not overwritten or automatically merged. GPU mode requires CUDA
and at least 3 GB free VRAM before loading; that minimum is not a fit guarantee.
Stop competing GPU workloads yourself. CPU mode is explicit and can be slow.
Actual memory use depends on model, sequence length and runtime.

Stop requests are cooperative at the next training callback. Closing the
launcher does not kill an already-started worker. Reopen Training to inspect its
latest job. An interrupted/stale starting job can block another run; inspect its
private status/log before maintenance rather than launching overlapping jobs.
Logs, datasets, paths and adapters stay in private runtime/output folders.

The worker and guards have contract tests, not a completed real-model training
acceptance run. Check a small authorized job and held-out quality before relying
on the trainer for important work. Preflight does not establish improvements.

## Coding clients can manage the job

Managed client configurations expose `training_preflight`, `training_start`,
`training_job_status` and `training_stop`. They use only the saved profile's
settings; the tools cannot enable their own permission or supply arbitrary
commands/paths. Starts default to disabled. Reopen managed clients after an
upgrade to discover new tools. Existing active clients are not interrupted.

## Android and tiny edge devices

Choose an Android Gradle project folder, load **Android / tiny edge AI** in
Profiles + prompts and save. The optional bridge exposes project status, module
list, source-manifest inspection, local model-asset names/sizes and device states.
The device query talks only to an existing ADB server at 127.0.0.1:5037; it does
not start ADB, pair, connect, install apps or execute shell commands. Device
serials are replaced by hashes. Gradle scripts are not evaluated.

Start with very small candidates: Gemma 270M/1B, small Qwen/SmolLM, compact
embeddings and tiny vision/audio models. A catalog entry is not a certified
Android artifact. Check architecture, format, ABI, preprocessing, context and
RAM on the actual device. New Google Android LLM work should use the documented
[LiteRT-LM workflow](https://developers.google.com/edge/litert-lm/android);
the old MediaPipe LLM API is maintenance-only. The Windows launcher is not itself
an Android app.

## Blender

Install `bridge/blender_addon.py` manually through Blender's add-on preferences,
enable it and click **Start inspection bridge** in 3D View → Sidebar →
AiBrainWorX. It binds only to 127.0.0.1:9877. Load the Blender profile template in
the launcher, save and reopen a managed coding client.

The add-on moves scene reads onto Blender's main thread. Four tools inspect
project/scene identity, objects, transforms/mesh counts and render settings.
There is no arbitrary Python, scene mutation, render or save tool. Code editing
and other separately authorized tools remain the coding client's responsibility.
This Blender bridge is unrelated to the owner's requested avatar-video pipeline.

These loopback bridges are not authentication boundaries against other software
on the same PC. Keep their ports private and their project metadata out of public
screenshots. No live on-device inference or real Blender add-on acceptance run
has been claimed from the mocked contract tests.

## Skills and templates

The bundled eight skills are original MIT workflows. Coding clients can use workflow_list and workflow_read to retrieve them through the managed training/workflow MCP server. The 13 instruction/profile
presets include Android, Blender, tiny LoRA, voice, vision/edge and video/avatar work. Loading a
template does not enable training starts, accept a model license, download a
checkpoint or create project files.

The Skills browser includes source/license-reviewed links to
[Android skills](https://github.com/android/skills),
[Hugging Face skills](https://github.com/huggingface/skills),
[community Blender skills](https://github.com/arjun988/blender-skills) and
[community Unreal skills](https://github.com/quodsoler/unreal-engine-skills).
Review the particular skill, its scripts, tools and license before installing;
the launcher does not run upstream installers or cloud training jobs.
