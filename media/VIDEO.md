# Walkthrough source

The graphics and application-only captures in this folder are used to build our
90-second captioned walkthrough. The rendered MP4 stays outside Git so a launcher
update can replace the video without accumulating large binary files in history.
This first video has no narration.

With official FFmpeg installed and on PATH, run from the repository folder:

```powershell
python tools/build_video.py
```

The default uses the included launcher screenshot. For live status frames, close
unneeded windows, run the real launcher in capture mode, then supply the private
frame folder to the builder:

```powershell
powershell -NoProfile -STA -File app/Launcher.ps1 -CaptureFrames recordings-private/launcher
python tools/build_video.py --frames recordings-private/launcher
```

Capture renders only the application's own controls. It does not record the
desktop, click buttons, or prove that editor changes occurred. Review every frame
before publishing, particularly after changing labels or status messages. Never
record configuration files, terminal output, or Harness authentication URLs.
