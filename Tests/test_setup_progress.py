"""Offline display/exit/privacy tests. Fixture transfers never download files."""
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "app" / "setup_progress.py"
spec = importlib.util.spec_from_file_location("setup_progress", WRAPPER)
progress = importlib.util.module_from_spec(spec)
spec.loader.exec_module(progress)


class ProgressTests(unittest.TestCase):
    def test_exact_upstream_percent_not_rounded_byte_ratio(self):
        renderer = progress.ProgressRenderer(width=20)
        rendered = renderer.render("  model:  0.01 / 58.40 GB (0.02%)   ")
        self.assertEqual(rendered, "  model: [--------------------] 0.01 / 58.40 GB (0.02%)   ")
        self.assertIn("[##########----------]", renderer.render("engine: 1 / 2 GB (50%)"))
        self.assertIn("[####################]", renderer.render("engine: 2 / 2 GB (100%)"))
        # Upstream displays GB rounded to two places even for a small file. Its
        # explicit percentage stays authoritative when the size rounds to zero.
        self.assertIn("[####################] 0.00 / 0.00 GB (100%)",
                      renderer.render("engine metadata: 0.00 / 0.00 GB (100%)"))

    def test_nonprogress_text_is_byte_for_byte_unchanged(self):
        output = io.StringIO()
        filtered = progress.OutputFilter(output, progress.ProgressRenderer())
        text = "License: review before continuing\r\nChecking certificate...\nRAM: 32 GB\nWarning: server error (50%)\n"
        for character in text:
            filtered.emit(character)
        filtered.emit("", final=True)
        self.assertEqual(output.getvalue(), text)

    def test_unknown_total_never_invents_a_percent(self):
        renderer = progress.ProgressRenderer()
        first = renderer.render("  engine: 25.3 MB   ", carriage_return=True)
        second = renderer.render("  engine: 26.1 MB   ", carriage_return=True)
        self.assertEqual(first, "  engine: [|] 25.3 MB (total unknown)   ")
        self.assertIn("[/]", second)
        self.assertNotIn("%", first + second)
        output = io.StringIO()
        filtered = progress.OutputFilter(output, progress.ProgressRenderer())
        filtered.emit("\r  engine: 25.3 MB\r  engine: 26.1 MB\n", final=True)
        self.assertEqual(output.getvalue(), "\r  engine: [|] 25.3 MB (total unknown)\r  engine: [/] 26.1 MB (total unknown)\n")

    def test_public_paths_names_and_slash_variants(self):
        redact = progress.PublicRedactor({
            r"C:\Fixture\Private Owner": "<home>",
            r"D:\Private Runtime": "<runtime>",
            r"E:\Source Check": "<source>",
            r"F:\Secret Project": "<workspace>",
            "Secret Project": "<project>",
        })
        text = (r'At C:/Fixture/Private Owner/AppData/config and "D:\Private Runtime\engine.exe"; '
                r'E:\Source Check\app.py F:\Secret Project\sample.uproject Secret Project '
                r'G:\Unexpected\file.json https://example.com/model')
        rendered = redact(text)
        for private in ("Private Owner", "Private Runtime", "Source Check", "Secret Project", "Unexpected"):
            self.assertNotIn(private, rendered)
        self.assertIn("https://example.com/model", rendered)

    def test_split_private_path_and_prompt_marker_are_not_leaked(self):
        output = io.StringIO()
        filtered = progress.OutputFilter(output, progress.ProgressRenderer(progress.PublicRedactor({r"C:\Private Name": "<home>"})))
        filtered.emit("Path C:\\Private")
        self.assertEqual(output.getvalue(), "")
        filtered.emit(" Name\\file? " + progress.INPUT_MARKER)
        self.assertEqual(output.getvalue(), "Path <home>\\file? ")


class WrapperTests(unittest.TestCase):
    def run_fixture(self, source, *arguments, public=False, input_text=None):
        # Keep temporary fixture writes inside this checkout, including when a
        # Windows sandbox redirects TEMP to an inaccessible per-app directory.
        with tempfile.TemporaryDirectory(prefix="awx-progress-test-", dir=ROOT / "tests") as temporary:
            fixture = Path(temporary) / "setup fixture.py"
            fixture.write_text(source, encoding="utf-8")
            command = [sys.executable, "-u", str(WRAPPER)]
            if public:
                command.append("--public-output")
            command.extend(["--script", str(fixture), "--", *arguments])
            environment = os.environ.copy()
            environment["AWX_SETUP_REDACTIONS_JSON"] = json.dumps({temporary: "<fixture>"})
            return subprocess.run(command, input=input_text, text=True, capture_output=True,
                                  encoding="utf-8", timeout=15, env=environment)

    def test_runpy_real_argv_and_interactive_stdin(self):
        result = self.run_fixture(
            "import sys\nassert __name__ == '__main__'\n"
            "assert sys.argv[1:] == ['--family', 'coder']\n"
            "answer=input('Choose [1]: ')\nprint('answer='+answer)\n",
            "--family", "coder", input_text="2\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Choose [1]: answer=2", result.stdout)
        self.assertNotIn(progress.INPUT_MARKER, result.stdout)

    def test_nonzero_upstream_exit_is_preserved(self):
        result = self.run_fixture("import sys\nprint('real failure')\nsys.exit(7)\n")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout, "real failure\n")

    def test_public_descendant_output_and_exception_are_redacted(self):
        result = self.run_fixture(
            "import subprocess,sys\n"
            "subprocess.run([sys.executable,'-c',\"import sys; print(sys.argv[1]); print(sys.argv[1],file=sys.stderr)\",__file__])\n"
            "raise RuntimeError('fixture error at '+__file__)\n", public=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("fixture error", result.stdout)
        self.assertIn("<fixture>", result.stdout)
        self.assertNotIn("awx-progress-test-", result.stdout + result.stderr)

    def test_failed_command_start_is_failure(self):
        result = subprocess.run([sys.executable, str(WRAPPER), "--", "awx-command-that-does-not-exist"],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn("could not start", result.stdout)


if __name__ == "__main__":
    unittest.main()
