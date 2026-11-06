"""HTTP-level output-budget checks for tool-bearing Harness requests."""
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import queue
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
import control_core as core
import control_runtime as runtime


class ToolOutputGateway(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.config = {'StateRoot': self.temp.name, 'WorkspaceRoot': self.temp.name,
                       'ModelBackend': 'compatible', 'ModelId': 'test',
                       'ModelBaseUrl': 'http://127.0.0.1:9099/v1'}
        self.received = queue.Queue()
        self.count = 100
        owner = self

        class Counter:
            def __init__(self, *args):
                pass
            def preflight(self, payload):
                return 16384, owner.count

        class Upstream(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_POST(self):
                payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                owner.received.put(payload)
                self.send_response(200)
                self.send_header('Content-Type', 'text/event-stream')
                self.end_headers()
                # An interrupted tool call must remain untouched, not retried or
                # silently joined to a newly generated call.
                event = {'id': 'test', 'choices': [{'index': 0, 'delta': {
                    'tool_calls': [{'index': 0, 'id': 'call_1', 'type': 'function',
                                    'function': {'name': 'inspect', 'arguments': '{"path":"'}}]},
                    'finish_reason': 'length'}]}
                self.wfile.write(('data: ' + json.dumps(event) + '\n\ndata: [DONE]\n\n').encode())

        self.upstream = ThreadingHTTPServer(('127.0.0.1', 0), Upstream)
        self.upstream.daemon_threads = True
        self.counter = patch.object(runtime.backend_budget, 'Backend', Counter)
        self.counter.start()
        self.gateway = runtime.make_server(self.config, 0, self.upstream.server_port)
        self.threads = []
        for server in (self.gateway, self.upstream):
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.threads.append(thread)
        state = core.ensure_state(self.config)
        profile = core.get_profile(state)
        profile['maxOutputTokens'] = 8192
        core.save_profile(self.config, {'profile': profile, 'revision': state['revision']})

    def tearDown(self):
        for server in (self.gateway, self.upstream):
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(3)
        self.counter.stop()
        self.temp.cleanup()

    def send(self, requested):
        connection = HTTPConnection('127.0.0.1', self.gateway.server_port, timeout=5)
        body = {'model': 'test', 'messages': [{'role': 'user', 'content': 'Inspect a file'}],
                'stream': True, 'max_tokens': requested,
                'tools': [{'type': 'function', 'function': {'name': 'inspect',
                           'parameters': {'type': 'object', 'properties': {}}}}]}
        try:
            connection.request('POST', '/profiles/default/v1/chat/completions',
                               json.dumps(body), {'Content-Type': 'application/json'})
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_large_tool_stream_keeps_client_limit_and_finish_reason(self):
        status, stream = self.send(8192)
        self.assertEqual(status, 200)
        self.assertEqual(self.received.get(timeout=1)['max_tokens'], 8192)
        self.assertTrue(self.received.empty())
        self.assertIn(b'"tool_calls"', stream)
        self.assertIn(b'"finish_reason": "length"', stream)
        self.assertEqual(stream.count(b'data: [DONE]'), 1)

    def test_tool_stream_reserves_space_using_actual_prompt_count(self):
        self.count = 9000
        status, stream = self.send(8192)
        self.assertEqual(status, 200)
        self.assertEqual(self.received.get(timeout=1)['max_tokens'], 16384 - 9000 - 256)
        self.assertTrue(self.received.empty())
        self.assertIn(b'"finish_reason": "length"', stream)

    def test_smaller_client_limit_is_never_increased(self):
        status, _ = self.send(1024)
        self.assertEqual(status, 200)
        self.assertEqual(self.received.get(timeout=1)['max_tokens'], 1024)


if __name__ == '__main__':
    unittest.main()
