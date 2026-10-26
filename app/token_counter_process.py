"""Persistent, serialized tokenizer helper. No model process control."""
import atexit
import json
from pathlib import Path
import queue
import subprocess
import threading

from context_policy import BudgetError

_workers = {}
_lock = threading.Lock()


class Counter:
    def __init__(self, config, selected):
        self.config, self.selected = config, selected
        self.lock, self.process, self.replies = threading.Lock(), None, None
        atexit.register(self.close)

    def close(self):
        if self.process:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=3)
            for handle in (self.process.stdin, self.process.stdout):
                if handle:
                    handle.close()
            self.process = None

    def start(self):
        self.close()
        replies = queue.Queue(maxsize=4)
        command = [self.config.get('StrataPython') or self.config['PythonExecutable'], '-u',
                   str(Path(__file__).with_name('strata_counter.py')), '--root', self.config['StrataRoot'],
                   '--config', self.selected['configPath']]
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, encoding='utf-8',
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        self.replies = replies
        process = self.process
        def read():
            try:
                for line in process.stdout:
                    try:
                        result = json.loads(line)
                    except ValueError:
                        continue
                    replies.put(result, timeout=1)
            except (OSError, ValueError, queue.Full):
                pass
            finally:
                try:
                    replies.put({'error': 'Token counter stopped.'}, timeout=1)
                except queue.Full:
                    pass
        threading.Thread(target=read, daemon=True).start()

    def count(self, payload, digest, route):
        with self.lock:
            if self.process is None or self.process.poll() is not None:
                self.start()
            try:
                self.process.stdin.write(json.dumps({'payload': payload, 'template_sha256': digest, 'route': route}, ensure_ascii=False)+'\n')
                self.process.stdin.flush()
                result = self.replies.get(timeout=30)
                if result.get('error') or type(result.get('count')) is not int:
                    raise BudgetError('Cannot verify this Strata request. Check the installed frontend and tokenizer.', 'unsupported_token_count')
                return result['count']
            except (OSError, queue.Empty):
                self.close()
                raise BudgetError('The tokenizer helper is unavailable. No generation was submitted.', 'preflight_unavailable') from None


def count(config, selected, payload, digest, route='/v1/chat/completions'):
    key = (config['StrataRoot'], selected['configPath'])
    with _lock:
        if key not in _workers:
            _workers[key] = Counter(config, selected)
        worker = _workers[key]
    return worker.count(payload, digest, route)
