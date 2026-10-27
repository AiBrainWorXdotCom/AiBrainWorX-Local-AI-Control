"""Display real setup progress and optionally remove local paths from child output.

HELP: This is a presentation wrapper, never a downloader. Strata still owns its
downloads, hashes, range resumes, certificates, licenses and interactive choices.
The private venv interpreter executes the selected setup.py via runpy. stdout and
stderr from it and its subprocesses are captured; stdin remains the real console.
"""
from __future__ import annotations

import argparse
import builtins
import codecs
import getpass
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import traceback

INPUT_MARKER = "\x1eAWX_INPUT\x1e"
PERCENT = re.compile(
    r"^(?P<indent>\s*)(?P<label>[^\r\n]+?):\s*"
    r"(?P<done>\d+(?:\.\d+)?)\s*/\s*(?P<total>\d+(?:\.\d+)?)\s*"
    r"(?P<unit>[KMGT]?i?B)\s*\((?P<percent>\d+(?:\.\d+)?)%\)(?P<tail>\s*)$"
)
UNKNOWN = re.compile(
    r"^(?P<indent>\s*)(?P<label>[^\r\n]+?):\s*"
    r"(?P<size>\d+(?:\.\d+)?\s*[KMGT]?i?B)(?P<tail>\s*)$"
)


class PublicRedactor:
    """Redact configured roots/names and unexpected absolute filesystem paths."""

    def __init__(self, replacements: dict[str, str] | None = None):
        self.replacements = dict(replacements or {})
        for value in (os.environ.get("USERPROFILE"), os.environ.get("HOME")):
            if value:
                self.replacements.setdefault(value, "<home>")
        self.rules = []
        for value, label in sorted(self.replacements.items(), key=lambda item: len(item[0]), reverse=True):
            if value:
                # Windows tools differ in slash direction and case. Match both.
                pattern = r"[\\/]".join(re.escape(part) for part in re.split(r"[\\/]", value))
                if not re.search(r"[\\/]", value):
                    pattern = r"(?<!\w)" + pattern + r"(?!\w)"
                self.rules.append((re.compile(pattern, re.IGNORECASE), label))

    def __call__(self, text: str) -> str:
        for pattern, label in self.rules:
            text = pattern.sub(lambda _match: label, text)
        # Quoted paths may contain spaces. Bare fallback paths stop at whitespace
        # so an upstream error message remains useful. Known roots above include
        # spaces and are replaced before this fallback is considered.
        text = re.sub(r'''(["'])(?:[A-Za-z]:[\\/]|\\\\)[^\r\n"']+\1''', "<path>", text)
        text = re.sub(r"(?<![\w:])[A-Za-z]:[\\/][^\s\"<>|]+", "<path>", text)
        text = re.sub(r"\\\\[^\s\"<>|]+", "<path>", text)
        text = re.sub(r"(?<![\w:/])/(?:home|Users|tmp|private|var|opt)/[^\s\"<>|]+", "<path>", text)
        return text


class ProgressRenderer:
    def __init__(self, redact=None, width: int = 28):
        self.redact = redact or (lambda value: value)
        self.width = width
        self.activity = 0

    def render(self, line: str, carriage_return: bool = False) -> str:
        match = PERCENT.fullmatch(line)
        if match and 0 <= float(match["percent"]) <= 100:
            # HELP: The percentage is upstream's reported value, not a timer or
            # an estimate derived from its rounded GB display. Keep it exact.
            filled = int(float(match["percent"]) * self.width / 100)
            bar = "#" * filled + "-" * (self.width - filled)
            line = (f'{match["indent"]}{match["label"]}: [{bar}] '
                    f'{match["done"]} / {match["total"]} {match["unit"]} '
                    f'({match["percent"]}%){match["tail"]}')
        else:
            match = UNKNOWN.fullmatch(line)
            if match and carriage_return:
                activity = "|/-\\"[self.activity % 4]
                self.activity += 1
                line = (f'{match["indent"]}{match["label"]}: [{activity}] '
                        f'{match["size"]} (total unknown){match["tail"]}')
        return self.redact(line)


class OutputFilter:
    """Retain carriage-return updates and plain text, even across byte chunks."""

    def __init__(self, output, renderer: ProgressRenderer):
        self.output = output
        self.renderer = renderer
        self.pending = ""
        self.carriage_return = False

    def emit(self, text: str, final: bool = False):
        self.pending += text
        while self.pending:
            # A runpy input hook inserts this marker immediately before reading
            # real stdin. It makes prompts visible without waiting for a newline.
            marker = self.pending.find(INPUT_MARKER)
            delimiters = [i for i in (self.pending.find("\r"), self.pending.find("\n")) if i >= 0]
            end = min(delimiters) if delimiters else -1
            if marker >= 0 and (end < 0 or marker < end):
                self.output.write(self.renderer.render(self.pending[:marker], self.carriage_return))
                self.pending = self.pending[marker + len(INPUT_MARKER):]
            elif end >= 0:
                self.output.write(self.renderer.render(self.pending[:end], self.carriage_return) + self.pending[end])
                self.carriage_return = self.pending[end] == "\r"
                self.pending = self.pending[end + 1:]
            else:
                break
            self.output.flush()
        if final and self.pending:
            self.output.write(self.renderer.render(self.pending, self.carriage_return))
            self.pending = ""
            self.output.flush()


def run_script(script: str, arguments: list[str], public: bool = False):
    """Run the actual trusted installer without modifying its source or logic."""
    script_path = Path(script).resolve(strict=True)
    original_input = builtins.input

    def console_input(prompt=""):
        sys.stdout.write(str(prompt) + INPUT_MARKER)
        sys.stdout.flush()
        # Hide terminal echo when recording private path answers. Redirected test
        # input behaves exactly like input(); it has no terminal echo to suppress.
        if public and sys.stdin.isatty():
            return getpass.getpass("", stream=sys.stdout)
        return original_input()

    builtins.input = console_input
    sys.argv = [str(script_path), *arguments]
    sys.path.insert(0, str(script_path.parent))
    try:
        runpy.run_path(str(script_path), run_name="__main__")
    finally:
        builtins.input = original_input


def relay(command: list[str], renderer: ProgressRenderer) -> int:
    """Capture child and descendant output; retain the console stdin handle."""
    environment = os.environ.copy()
    environment["PYTHONUNBUFFERED"] = "1"
    environment["PYTHONUTF8"] = "1"
    # HELP: A setup display wrapper must not activate a Python manager fallback.
    environment["PYTHON_MANAGER_AUTOMATIC_INSTALL"] = "false"
    environment.pop("PYLAUNCHER_ALLOW_INSTALL", None)
    environment.pop("PYLAUNCHER_ALWAYS_INSTALL", None)
    output = OutputFilter(sys.stdout, renderer)
    decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
    try:
        with subprocess.Popen(command, stdin=None, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=environment) as child:
            assert child.stdout is not None
            while chunk := child.stdout.read1(4096):
                output.emit(decoder.decode(chunk))
            output.emit(decoder.decode(b"", final=True), final=True)
            return child.wait()
    except OSError as error:
        output.emit(f"Setup command could not start: {error}\n", final=True)
        return 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-output", action="store_true")
    parser.add_argument("--run-script", help=argparse.SUPPRESS)
    parser.add_argument("--script", help="Trusted setup.py to execute with this interpreter using runpy")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    options = parser.parse_args(argv)
    arguments = options.arguments
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    if options.run_script:
        run_script(options.run_script, arguments, options.public_output)
        return 0
    # The child already supplied its line endings. Windows text translation here
    # would turn CRLF into CRCRLF and add blank lines to ordinary output.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="")
    replacements = json.loads(os.environ.get("AWX_SETUP_REDACTIONS_JSON", "{}"))
    renderer = ProgressRenderer(PublicRedactor(replacements) if options.public_output else None)
    if options.script:
        script = Path(options.script)
        if not script.is_file():
            print(renderer.redact("The selected Strata setup.py is missing."), file=sys.stderr)
            return 1
        command = [sys.executable, "-u", str(Path(__file__).resolve())]
        if options.public_output:
            command.append("--public-output")
        command.extend(["--run-script", str(script.resolve()), "--", *arguments])
    else:
        command = arguments
        if not command:
            parser.error("Choose --script or provide a command after --")
    return relay(command, renderer)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception:
        # Parent relay redacts child exceptions; top-level failures also redact
        # the traceback instead of leaking installer locations in public mode.
        detail = traceback.format_exc()
        if "--public-output" in sys.argv:
            detail = PublicRedactor(json.loads(os.environ.get("AWX_SETUP_REDACTIONS_JSON", "{}")))(detail)
        print(detail, file=sys.stderr, end="")
        raise SystemExit(1)
