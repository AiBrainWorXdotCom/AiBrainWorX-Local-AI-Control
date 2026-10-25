# October 25 speed-check media

- `aibrainworx-coding-speed-20261025.png`: reproducible measurement summary.
- `aibrainworx-coding-latency-20261025.png`: reproducible latency comparison.
- `aibrainworx-youtube-v06.jpg`: 1280 x 720 conceptual YouTube artwork with
  measured labels. Created with the built-in image generator, then resized and
  encoded as JPEG. It is not a screenshot or documentary photo of the test PC.

The two charts are generated from
`docs/benchmarks/2026-10-25-coding-speed.json` by
`tools/Build-SpeedCheckGraphics.ps1` (PowerShell 7, System.Drawing on Windows).
The earlier October 25 review graphic remains a historical asset.

The thumbnail identifies Strata as the inference engine and DeepSeek Harness as
the coding client. Those product names and identifying marks remain their
owners' trademarks; their appearance is not an endorsement or a claim of
ownership by AiBrainWorX. The repository's MIT license does not relicense those
third-party marks or model weights.

All throughput labels refer to separate short requests on an already-loaded,
warm engine with reasoning off. Cached repeat results are labeled separately.
