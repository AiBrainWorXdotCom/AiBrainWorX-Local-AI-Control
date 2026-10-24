---
name: awx-unreal-source
description: Investigate Unreal project or installed-engine source to explain build failures, reflection, module boundaries, configuration or API behavior. Use when exact local evidence is needed, including for UE 5.8.
---

# Unreal source investigation

Locate the intended project without assuming a personal folder or drive. Confirm
its engine association and, where available, the installed engine's Build.version.
Say whether full engine source, installed headers, or only project code is present.

Start with the failing symbol or exact diagnostic. Use `rg --files` and focused
`rg` queries rather than recursively reading Content or generated caches. Inspect
the descriptor, module rules, owning class, call sites and relevant INI keys.
Read engine declarations and implementations when available to resolve lifecycle,
threading, ownership and version-specific behavior.

Check editor/runtime dependencies, module loading phases, public/private include
boundaries, `WITH_EDITOR` guards, reflected declarations and generated includes.
Do not assume the currently open editor belongs to the project being investigated.

Ground the conclusion in exact files and symbols. If the relevant source is
missing, identify the gap and use official documentation or a bounded reproduction
instead of presenting a guess as a verified API. Preserve generated files and
binary assets unless the task specifically requires their supported regeneration.
