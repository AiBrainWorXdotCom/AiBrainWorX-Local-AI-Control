from copy import deepcopy
from http.client import HTTPConnection
import json
from pathlib import Path
import sys
import tempfile
import threading
import uuid
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
import control_core as core
import control_runtime as runtime
from context_policy import BudgetError


def chunk(text, finish):
    return {'choices': [{'index': 0, 'delta': {'content': text}, 'finish_reason': finish}]}


class Gateway(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.config = {'StateRoot': self.temp.name, 'WorkspaceRoot': self.temp.name,
                       'ModelBackend': 'compatible', 'ModelId': 'test', 'ModelBaseUrl': 'http://127.0.0.1:9099/v1'}
        self.prompts, self.generated = [], []
        owner = self
        class Backend:
            def __init__(self, *args):
                pass
            def preflight(self, payload):
                owner.prompts.append(deepcopy(payload))
                return owner.context, owner.count
            def stream(self, payload):
                owner.generated.append(payload)
                yield chunk('A bounded reply.', 'stop')
        self.context, self.count = 4096, 3700
        self.backend = patch.object(runtime.backend_budget, 'Backend', Backend)
        self.backend.start()
        self.server = runtime.make_server(self.config, 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(3)
        self.backend.stop()
        self.temp.cleanup()

    def send(self, payload):
        connection = HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        try:
            connection.request('POST', '/profiles/default/v1/chat/completions', json.dumps(payload),
                               {'Content-Type': 'application/json'})
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_real_http_route_clamps_before_sending_generation(self):
        status, wire = self.send({'model': 'test', 'messages': [{'role': 'user', 'content': 'hello'}],
                                  'stream': True, 'max_tokens': 4096})
        self.assertEqual(status, 200)
        self.assertEqual(self.generated[0]['max_tokens'], 140)
        self.assertEqual(wire.count(b'data: [DONE]'), 1)

    def test_no_room_is_actionable_422_without_generation(self):
        self.count = 3900
        status, data = self.send({'messages': [{'role': 'user', 'content': 'hello'}], 'stream': True})
        self.assertEqual(status, 422)
        self.assertEqual(json.loads(data)['error']['code'], 'context_full')
        self.assertEqual(self.generated, [])

    def test_counting_sees_instructions_and_enabled_memory(self):
        profile = core.get_profile(core.ensure_state(self.config))
        profile.update(useInstructions=True, instructions='Owner policy', useMemory=True)
        runtime.memory.save(self.config, profile, {'title': 'Rule', 'body': 'Verified project fact.', 'pinned': True})
        core.save_profile(self.config, {'profile': profile, 'revision': 0})
        self.send({'messages': [{'role': 'user', 'content': 'hello'}], 'stream': True})
        rendered = json.dumps(self.prompts[0])
        self.assertIn('Owner policy', rendered)
        self.assertIn('Verified project fact', rendered)

    def test_missing_counter_fails_closed_and_no_request_sent(self):
        with patch.object(runtime.backend_budget, 'Backend', side_effect=BudgetError('No token counter', 'preflight_unavailable')):
            status, data = self.send({'messages': [{'role': 'user', 'content': 'hello'}], 'stream': True})
        self.assertEqual(status, 422)
        self.assertIn(b'preflight_unavailable', data)
        self.assertEqual(self.generated, [])

    def test_disabling_continuation_keeps_saved_assistant_history(self):
        from conversation_sessions import Sessions
        import project_memory
        self.count = 24
        profile = core.get_profile(core.ensure_state(self.config))
        profile['autoContinue'] = False
        core.save_profile(self.config, {'profile': profile, 'revision': 0})
        identity = uuid.uuid4().hex
        status, wire = self.send({'model': 'test', 'messages': [{'role': 'user', 'content': 'First question'}],
            'stream': True, 'aibrainworx_session': {'id': identity, 'requestId': uuid.uuid4().hex}})
        self.assertEqual(status, 200)
        self.assertEqual(wire.count(b'data: [DONE]'), 1)
        rows = Sessions(self.config['StateRoot']).transcript(identity, project_memory.project_key(profile))
        self.assertEqual([r['role'] for r in rows], ['user', 'assistant'])
        self.assertEqual(rows[-1]['content'], 'A bounded reply.')
        self.send({'model': 'test', 'messages': [{'role': 'user', 'content': 'Second question'}],
            'stream': True, 'aibrainworx_session': {'id': identity, 'requestId': uuid.uuid4().hex}})
        self.assertIn('A bounded reply.', json.dumps(self.generated[-1]))


if __name__ == '__main__':
    unittest.main()
