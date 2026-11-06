"""The persistent tokenizer protocol must round-trip non-ASCII text on Windows."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'app'))
import token_counter_process


class CounterEncoding(unittest.TestCase):
    def test_utf8_persistent_ipc_even_with_legacy_python_io_encoding(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            # Exercise the real parent IPC and child stream configuration,
            # without needing a large model or downloading a tokenizer.
            worker = root / 'strata_counter.py'
            worker.write_text(
                'import json, sys\n'
                f'sys.path.insert(0, {str(ROOT / "app")!r})\n'
                'from strata_counter import configure_ipc_streams\n'
                'configure_ipc_streams()\n'
                'for line in sys.stdin:\n'
                '    content = json.loads(line)["payload"]["messages"][0]["content"]\n'
                '    print(json.dumps({"count": len(content.encode("utf-8"))}), flush=True)\n', encoding='utf-8')
            config = {'StrataRoot':str(root), 'StrataPython':sys.executable, 'PythonExecutable':sys.executable}
            selected = {'configPath':str(root / 'unused.json')}
            counter = token_counter_process.Counter(config, selected)
            try:
                with patch.object(token_counter_process, '__file__', str(root / 'placeholder.py')), \
                     patch.dict(os.environ, {'PYTHONIOENCODING':'cp1252:surrogateescape'}):
                    for content in ('smart quote: ”', '日本語 and café', 'emoji: 🌴'):
                        payload = {'messages':[{'role':'user','content':content}]}
                        self.assertEqual(counter.count(payload, 'digest', '/v1/chat/completions'), len(content.encode('utf-8')))
            finally:
                counter.close()


if __name__ == '__main__':
    unittest.main()
