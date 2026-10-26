# Update Center

Choose **Updates → Check everything**. The operation runs outside the interface
thread and reads public metadata. It never installs a package, downloads model
weights, rewrites a skill, accepts a license or stops/restarts a running service.

The report includes:

- Launcher releases and optionally public-main/prerelease source packages.
- Strata app/CLI and the exact matching Qwen engine platform/backend variant.
  App and engine versions are separate. DeepSeek engine releases are separate too.
- The official DeepSeek Harness npm package compared with its installed package.json.
- Models saved in launcher profiles and other discovered Strata configurations.
- Bundled skill content compared with public Git blobs, preserving local edits.
- Upstream skill references compared with their recorded review commits. A reference
  is not an installed/audited skill; an upstream change requires a fresh review.

Each row reports **Update available**, **Up to date**, **Development**, **Needs
review** or **Could not check**. A failed request, unknown installed version or
unrecorded model revision never becomes an up-to-date claim. Rate limiting and
offline failures remain visible. Reviews link to official sources.

## Model provenance

Select a model row and choose **Connect model card**. Enter the original
Hugging Face `owner/repository`; optionally enter the full installed commit SHA
only if known. These records stay in the ignored local state folder. A runtime
alias, quant filename, model card timestamp or current upstream SHA does not prove
which revision is installed. The app never fills an unknown installed revision
with today's remote SHA. A changed repository may include documentation changes,
not new weights; inspect the actual file/quant changes before downloading.

Checks disclose public repository names and ordinary connection metadata to GitHub,
Hugging Face and npm. No prompt, transcript, project memory, credential or personal
installation path is sent. Strata feed metadata is advisory here: artifact signature,
hash and compatibility verification remain the installer/upstream updater's job.

Model catalog entries are suggestions, not installed models. Ollama/LM Studio
installation updates, every system package and arbitrary third-party tools are not
silently certified by this report. Their dedicated version adapters can be added
without changing this read-only contract.
