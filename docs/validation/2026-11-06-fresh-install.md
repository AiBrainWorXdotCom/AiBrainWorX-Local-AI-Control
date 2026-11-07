# Fresh Windows install and model reuse — November 6, 2026

This record describes a real isolated install of launcher commit `829bae2` cloned
from GitHub on an existing Windows PC. The test used separate source, runtime,
workspace and client-service ports. It reused the PC's existing Python, Node and
model files; it was not a clean-PC or full model-download test.

## What was installed and tested

- Cloned the launcher from GitHub and Strata's pinned source into the test area.
- Downloaded the official Windows CUDA engine through Strata's signed feed. The
  transfer was resumed, its size and SHA-256 checked, and Strata's updater verified
  and installed engine 0.1.57. The updater's own initial smoke test was binary-only.
- Manually prepared a separate Strata model configuration pointing to the existing
  model shards and prepared pack, and to the new test engine. Model weights were
  not copied or downloaded. This is not an automated model-import test.
- Ran setup from the fresh launcher clone. It created a private Strata Python
  environment, installed the official runtime requirements, installed the pinned
  coding clients into the test runtime, and reported setup complete. An isolated
  npm cache from an earlier test was reused.
- Started the test model and gateway. A direct test through the gateway returned
  `PONG`. The newly installed DeepSeek Harness completed a separate headless test
  conversation with the expected `HARNESS_OK` response. The Harness web service
  also responded with its expected authentication requirement; an interactive
  browser conversation was not tested in this run.

The original launcher and Strata model configuration files matched their pre-test
checksums. The normal model and Harness were restarted after the test.

## Findings and limits

The first fresh-environment attempt failed at model startup because its Strata
virtual environment lacked `jinja2`. Commit `829bae2` adds installation and
verification of Strata's runtime requirements for newly managed environments;
the successful retest above used that fix.

The test model's stop command reported an incomplete shutdown. The model listener
and GPU load later cleared, but the cause was not established. This warning
should not be treated as a verified clean shutdown or a fixed issue.

The run did not verify a new Windows account, automatic discovery/import of
existing weights, a fresh model-weight download, visual UI acceptance, or a long
8,192-token output. Separate context-extension checks are documented elsewhere.
