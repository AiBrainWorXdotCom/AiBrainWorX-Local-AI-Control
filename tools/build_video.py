"""Rebuild the 90-second captioned walkthrough using FFmpeg, without narration.

Screenshots/graphics come from media/. Optionally supply --frames to a private
60-frame, 5fps launcher capture. Without frames the real launcher screenshot is
used. The output and intermediate video files are intentionally ignored by Git.
"""
import argparse
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CAPTIONS = [
    (0, 7, "AiBrainWorX: local coding AI on an RTX 3060 12 GB GPU and Ryzen 5 5500."),
    (7, 19, "Our actual launcher controls Strata, DeepSeek Harness, and optional Unreal inspection tools."),
    (19, 37, "Codex CLI and DeepSeek Harness are clients. Strata serves local Qwen. MCP connects inspection tools to Unreal."),
    (37, 50, "Start the model, wait until it is ready, then start Harness and open chat. Closing the panel leaves the model running."),
    (50, 65, "The full model is not stored in 12 GB of VRAM. This build also uses 32 GB system RAM and SSD-backed data."),
    (65, 80, "We observed about 20 to 25 tokens per second on short probes, and around 13 under heavy memory pressure. Results vary."),
    (80, 90, "Made by AiBrainWorX. Our integration source is MIT licensed. Upstream tools and models keep their own terms."),
]


def timestamp(seconds):
    return f"00:{seconds // 60:02d}:{seconds % 60:02d},000"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    parser.add_argument("--media", type=Path, default=ROOT / "media")
    parser.add_argument("--frames", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "media/aibrainworx-launcher-walkthrough.mp4")
    args = parser.parse_args()
    if not args.ffmpeg:
        parser.error("Install FFmpeg from its official source and add it to PATH, or supply --ffmpeg.")
    media = args.media.resolve()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    work = output.parent / ".video-build"
    work.mkdir(exist_ok=True)
    bold = Path("C:/Windows/Fonts/segoeuib.ttf")
    font = str(bold).replace("\\", "/").replace(":", r"\:")
    if not bold.is_file():
        parser.error("This Windows build script expects the Segoe UI font installed with Windows.")

    def run(arguments):
        subprocess.run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y", *arguments], cwd=work, check=True)

    def text(value, x, y, size=30, color="0xF0F5FC"):
        # Draw individual lines: some Windows FFmpeg/font builds display newline
        # control characters as missing-glyph boxes in multiline text files.
        if "\n" in value:
            return ",".join(text(line, x, y + i * (size + 14), size, color)
                            for i, line in enumerate(value.splitlines()) if line)
        name = f"caption-{len(list(work.glob('caption-*.txt'))):03d}.txt"
        (work / name).write_text(value, encoding="utf-8", newline="\n")
        return f"drawtext=fontfile='{font}':textfile={name}:x={x}:y={y}:fontsize={size}:fontcolor={color}:line_spacing=14"

    clips = []
    def encode(name, duration, inputs, graph):
        target = work / (name + ".mp4")
        graph += f",fade=t=in:st=0:d=0.3,fade=t=out:st={duration - .3}:d=0.3,format=yuv420p[out]"
        run([*inputs, "-filter_complex", graph, "-map", "[out]", "-t", str(duration), "-r", "30", "-an", "-c:v", "libx264", "-threads", "2", "-preset", "veryfast", "-crf", "22", "-movflags", "+faststart", str(target)])
        clips.append(target)

    def image_clip(name, seconds, filename):
        encode(name, seconds, ["-loop", "1", "-framerate", "30", "-i", str(media / filename)], "[0:v]scale=1920:1080,setsar=1")

    image_clip("01-intro", 7, "aibrainworx-video-intro.png")
    live = args.frames and (args.frames / "frame-0000.png").is_file()
    # CaptureFrame numbering begins at 0000. Require the entire 12-second sequence.
    if live and not (args.frames / "frame-0059.png").is_file():
        parser.error("The launcher capture needs all 60 frames, numbered 0000 through 0059.")
    capture_input = ["-framerate", "5", "-i", str(args.frames.resolve() / "frame-%04d.png")] if live else ["-loop", "1", "-framerate", "30", "-i", str(media / "aibrainworx-local-ai-control.png")]
    title = text("THE LAUNCHER / REAL APP CONTROLS", 65, 60, 46)
    notes = text("01  START THE MODEL\nWait for Ready.\n\n02  START HARNESS\nOpen your local chat.\n\n03  CHECK UNREAL\nOptional inspection tools.\n\nSeparate Start / Stop controls.\nNo terminal juggling.", 1180, 225, 29)
    footer = text("Made by AiBrainWorX  |  Application-rendered capture with live status; explanatory overlays added.", 65, 1010, 23, "0x6DE7D6")
    encode("02-launcher", 12, ["-f", "lavfi", "-i", "color=c=0x0C111B:s=1920x1080:r=30", *capture_input], f"[1:v]scale=1080:-2,setsar=1[app];[0:v][app]overlay=50:180,{title},{notes},{footer}")
    image_clip("03-architecture", 18, "aibrainworx-stack-infographic.png")
    steps = text("START. WAIT. CREATE.", 80, 85, 58)
    steps2 = text("1. Start Coder.\n2. Wait for the model to report Ready.\n3. Start Harness and open chat.\n\nClosing a panel keeps the service running.\nUse Stop to release model resources.", 1030, 300, 31)
    mark = text("Made by AiBrainWorX", 80, 1000, 27, "0x6DE7D6")
    encode("04-model-controls", 13, ["-f", "lavfi", "-i", "color=c=0x0C111B:s=1920x1080:r=30", "-loop", "1", "-framerate", "30", "-i", str(media / "aibrainworx-qwen-control.png")], f"[1:v]scale=860:-2,setsar=1[panel];[0:v][panel]overlay=80:330,{steps},{steps2},{mark}")
    image_clip("05-hardware", 15, "aibrainworx-hardware-infographic.png")
    image_clip("06-results", 15, "aibrainworx-results.png")
    image_clip("07-end", 10, "aibrainworx-video-end.png")
    (work / "concat.txt").write_text("".join(f"file '{clip.name}'\n" for clip in clips), encoding="utf-8")
    run(["-f", "concat", "-safe", "0", "-i", "concat.txt", "-c", "copy", "-movflags", "+faststart", str(output)])
    subtitles = "\n".join(f"{i}\n{timestamp(start)} --> {timestamp(end)}\n{caption}\n" for i, (start, end, caption) in enumerate(CAPTIONS, 1))
    output.with_suffix(".srt").write_text(subtitles, encoding="utf-8")
    print(f"Created {output.name}: 90 seconds, 1920x1080, 30 fps, captioned, no narration.")


if __name__ == "__main__":
    main()
