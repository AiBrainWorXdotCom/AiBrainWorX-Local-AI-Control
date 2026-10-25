---
name: awx-android-edge
description: Inspect or develop an Android project using the AiBrainWorX Android bridge, especially tiny on-device models, manifests and local model assets.
---

Confirm the selected Gradle project and Android target. Use `android_project_status`
and `android_list_modules` before assuming an editor, SDK or device connection.
`android_inspect_manifest` reports source XML, not the merged manifest or resolved
Gradle values. `android_devices` reads an existing ADB server and hashes serials.

For edge AI, start with a very small model and an artifact supported by the actual
runtime/device. Google recommends LiteRT-LM for new Android LLM work; the older
MediaPipe LLM API is maintenance-only. GGUF, ONNX and .litertlm files are not
interchangeable. Check RAM, context, ABI and supported CPU/GPU/NPU backends.

These inspection tools cannot build, install, pair, control a device or execute
shell commands. Source edits and builds use separately authorized client tools.
Do not infer successful compilation or on-device inference from a file inventory.
Report the exact validation performed and any missing physical-device test.

Primary references:
- https://developer.android.com/tools/adb
- https://developers.google.com/edge/litert-lm/android
