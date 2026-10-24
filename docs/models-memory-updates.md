# Models, memory and updates

The v0.3 desktop sidebar separates everyday Chat, model connections, project
Memory and update checking. These features share the saved project profile.

## Connect an existing model

Strata uses an installed `strata-*.json` configuration. Ollama and LM Studio use
their local APIs. The compatible option can connect a separately configured
llama.cpp or llama-swap server. Refresh lists identifiers reported by the server;
availability is not a claim that every model is loaded or supports agent tools.

Save the exact identifier, context limit and capability declarations. The
context setting does not change the server allocation. Leave reasoning at
Server default unless the model and backend accept the explicit value. A
non-reasoning model does not gain reasoning by selecting xhigh.

The launcher controls Strata start/stop only. Switching connections does not
unload another backend. Do that in its own app. Use local weights: a loopback
endpoint can itself be configured to proxy cloud services. Ollama discovery
excludes advertised cloud entries, but that cannot audit arbitrary proxies.

API keys are optional environment-variable names, not secret values in profiles.
Set the variable before starting the settings service. External servers must
remain on loopback HTTP. HTTPS/remote hosts and the gateway's own port are
rejected. Chat Completions and Responses support depends on server versions;
Ollama requires complete stateless Responses input histories.

## Explore the library

33 source-model suggestions cover small text models, stories, learning, puzzles,
writing and reasoning. The launcher includes readable summaries offline and
links to [AiBrainWorX model profiles](https://aibrainworx.com/model-library/).
Original Hugging Face cards remain available for complete documentation/files.
Names, creators, license metadata and reviewed revision IDs are retained.

Suggestions are not certification. A quantization can differ from its parent
model in requirements and behavior. Check the exact artifact and the backend's
architecture support. No weights are bundled, automatically downloaded or
benchmarked just by browsing the library.

Our five additional research profiles include large/server or specialized
models. They are not one-click launcher downloads. DeepInfer currently targets
Linux NVIDIA SM100 or Ascend 950, not our RTX 3060. It remains a research note,
not an installed alternative to Strata on this PC.

## Tool-free chat

Use Chat for small models and creative prompts without coding-agent tool
definitions. Ctrl+Enter sends; Stop reply closes that connection, although the
backend may take a moment to stop generation. New conversation clears in-app
history. A new profile starts a new chat. Built-in chat accepts text only.

Save important decisions with Make a memory note: this creates an editable draft,
not an automatic saved fact. Check it, give it a useful title and save explicitly.
Reasoning-heavy models can consume the output allowance before answering;
adjust their supported effort/budget instead of treating an empty answer as a
completed response. The chat history has a bounded size; begin a new conversation
when prompted. Context declarations are not exact token counting.

## AiBrainWorX Memory

The original SQLite implementation groups notes by the normalized project folder.
Profiles using that folder share facts, decisions, tasks and handoffs across
models. Different folders remain separate. Moving a project changes this key in
the alpha; use an export to preserve important work for a move.

Memory is opt-in for model requests. Recall ranks pinned, matching and recent
notes, adds up to six and approximately 4,000 characters, and labels them as
reference material that may be stale. A context preview is a hypothetical view
even if inclusion is disabled; the actual request's user message affects ranking.
User verified is the author's judgment, not independent validation.

Edits and archive actions retain revisions in the local database. Archive/restore
is reversible; it is not secure deletion. The launcher does not encrypt notes.
Handoff export contains saved notes, not transcripts, and can include any private
information the user wrote. Review before sharing.

## Manual updates

Check for updates reads this repository's published GitHub releases. With alpha
versions included, it also compares the version on main, even when an older
release exists. A failed network
request is shown as unavailable, never as up to date. Checking installs nothing.
Read changes and replace the source package manually, keeping private runtime
state separate. Existing active model requests block an owned old service's
automatic restart. No release/tag is created just by changing VERSION.

## Research and ownership

[REA](https://github.com/morluto/rea) was used for a selected-source static
research exercise on OpenHuman's memory interfaces. It was not a whole-app
runtime analysis. [OpenHuman](https://github.com/tinyhumansai/openhuman) is GPL-3.0;
its source and private research copies are not part of this MIT repository.
AiBrainWorX Memory is an independent Python/SQLite implementation.

Future hands-on model reviews are deferred. The planned workflow is to select
one candidate, download explicitly, test documented workloads, publish measured
results and decide whether to retain or remove those local files. Current
source-reviewed profiles are not presented as those future hands-on tests.
