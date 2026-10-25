# Local video and personal avatars

Use **Models → Browse model library → Video / Avatar** for source-reviewed video
references. In **Profiles + prompts**, load the Video / personal avatar studio
template for a coding assistant planning the workflow. It does not install a
renderer. Blender is a separate asset workflow, not part of this avatar setup.

The intended pipeline is a reference photo or video, the user's own voice audio,
local voice synthesis, video generation/lip sync and final effects/compositing.
One text model cannot do all of these tasks. Built-in Chat currently generates
text; audio/video inference needs a dedicated separately installed runtime.

## Candidates and actual limits

- [Wan 2.1 T2V 1.3B](https://huggingface.co/Wan-AI/Wan2.1-T2V-1.3B): Apache-2.0,
  short text-to-video scenes. Its publisher lists 8.19 GB VRAM and recommends
  480p. That is a starting candidate for testing, not a measured RTX 3060 render
  time. Text-to-video alone does not preserve a person's identity or lip sync.
- [Qwen3 TTS 0.6B Base](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base):
  Apache-2.0, reference-audio voice cloning. It needs its dedicated audio runtime;
  CustomVoice is a different interface using supported preset speakers.
- [MuseTalk](https://github.com/TMElyralab/MuseTalk): lip synchronization of a
  supplied portrait video, rather than full scene generation. Its README permits
  commercial use of the main model and lists dependency-specific terms. Review
  every required checkpoint; supplied internet test media are research-only.
  Identity details and jitter remain documented limitations.
- [Wan 2.2 S2V 14B](https://huggingface.co/Wan-AI/Wan2.2-S2V-14B): Apache-2.0,
  reference image plus audio for speech-driven video. The official example lists
  at least 80 GB VRAM. It is not a validated 12 GB solution.

LTX has broader audiovisual controls but a separate community license; it is
not being bundled or described as MIT/Apache. No avatar runtime, voice clone or
video model has been installed or benchmarked by this launcher update.

Start with short low-resolution previews and measure identity, motion, lip sync,
peak memory and render time. Release other GPU workloads in their owning apps
before rendering. Models, auxiliary assets and user media retain their own terms.

## Watch completed output inside Chat

Choose **Chat → Open video**, then a completed local MP4, M4V, WMV or AVI. The
transcript and video appear side by side in the Chat panel. Play/pause, seek,
volume and fullscreen are supplied by the installed Windows Media Player
component. **Hide** stops playback and restores the full-width transcript.
Changing pages pauses playback.

The optional Windows Media Player legacy component and a compatible codec must
be present. The launcher reports an unavailable player instead of downloading
one. H.264/AAC MP4 is a useful interchange format; codec availability varies.
Media is selected explicitly, kept local and never uploaded to the text model.
Arbitrary media URLs in model replies are not automatically opened. There is
currently no automatic render submission or render-completion attachment.
