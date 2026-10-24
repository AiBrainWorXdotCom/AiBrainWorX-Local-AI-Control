import copy
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import queue
import sys
import tempfile
import shutil
import threading
import tomllib
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
import control_core as core
import control_runtime as runtime


class Profiles(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.workspace = self.root / 'project & tools'
        self.workspace.mkdir()
        self.model = self.root / 'strata.json'
        self.model.write_text('{"model_name":"test-model","aliases":["test-model"]}')
        self.config = dict(StateRoot=str(self.root / 'runtime'), WorkspaceRoot=str(self.workspace),
                           StrataConfig=str(self.model), PythonExecutable=sys.executable, HarnessEntry=__file__)
        self.port_patch = patch.object(core, 'port_open', return_value=False)
        self.port_patch.start()
        core.ensure_state(self.config)

    def tearDown(self):
        self.port_patch.stop()
        self.temp.cleanup()

    def save(self, profile, new=False):
        return core.save_profile(self.config, dict(profile=profile, saveAsNew=new,
                                                  revision=core.ensure_state(self.config)['revision']))

    def test_profiles_persist_and_preserve_workspace_files(self):
        sentinel = self.workspace / 'AGENTS.md'
        sentinel.write_text('Existing project instructions.')
        state = core.view_state(self.config)
        profile = copy.deepcopy(state['active'])
        profile.update(name='Review', useInstructions=True, instructions='Keep literal {{braces}} and "quotes".\nSecond line.')
        result = self.save(profile, new=True)
        self.assertEqual(len(result['profiles']), 2)
        self.assertEqual(core.view_state(self.config)['active']['instructions'], profile['instructions'])
        self.assertEqual(sentinel.read_text(), 'Existing project instructions.')
        self.assertTrue(core.state_path(self.config).is_relative_to(self.root / 'runtime'))

    def test_invalid_sampler_and_prompt_rejected(self):
        for field, value in [('temperature', float('nan')), ('temperature', 3), ('topP', 0),
                             ('maxOutputTokens', True), ('maxOutputTokens', 100000), ('instructions', 'x' * 8193)]:
            profile = core.default_profile(self.config)
            profile[field] = value
            with self.assertRaises(ValueError):
                self.save(profile)

    def test_concurrent_edit_is_not_overwritten(self):
        profile = core.default_profile(self.config)
        self.save(profile)
        with self.assertRaises(ValueError):
            core.save_profile(self.config, dict(profile=profile, revision=0, saveAsNew=False))

    def test_project_switch_does_not_interrupt_running_harness(self):
        profile = core.default_profile(self.config)
        profile['name'] = 'Second'
        second = self.save(profile, new=True)['activeId']
        core.select_profile(self.config, {'id': 'default'})
        with patch.object(core, 'port_open', return_value=True):
            with self.assertRaises(ValueError):
                core.select_profile(self.config, {'id': second})
            changed = core.default_profile(self.config)
            another = self.root / 'other'
            another.mkdir()
            changed['workspaceRoot'] = str(another)
            with self.assertRaises(ValueError):
                self.save(changed)

    def test_managed_clients_are_literal_and_separate(self):
        prepared = core.prepare_clients(self.config)
        home = Path(prepared['HarnessHome'])
        rows = core.read_json(home / 'profiles/web/cordis.patch.yml')
        self.assertIn('/profiles/default/v1', rows[0]['config']['providers']['local_strata']['baseURL'])
        self.assertTrue(Path(prepared['CodexHome']).is_relative_to(self.root / 'runtime'))
        text = (Path(prepared['CodexHome']) / 'aibrainworx-local.config.toml').read_text()
        self.assertIn('requires_openai_auth = false', text)
        self.assertIn('/profiles/default/v1', text)
        self.assertNotIn('[mcp_servers.unreal_local]', text)
        self.assertEqual(tomllib.loads(text)['model_provider'], 'local_strata')

    def test_relocation_regenerates_unreal_bridge_path(self):
        moved = self.root / 'moved launcher'
        shutil.copytree(core.ROOT / 'examples', moved / 'examples')
        engine = self.root / 'engine python'
        engine.mkdir()
        (engine / 'remote_execution.py').touch()
        (self.workspace / 'Sample.uproject').write_text('{}')
        profile = core.default_profile(self.config)
        profile['enginePython'] = str(engine)
        self.save(profile)
        with patch.object(core, 'ROOT', moved):
            prepared = core.prepare_clients(self.config)
        text = (Path(prepared['CodexHome']) / 'aibrainworx-local.config.toml').read_text()
        config = tomllib.loads(text)
        self.assertEqual(config['mcp_servers']['unreal_local']['args'][0], (moved / 'bridge/unreal_mcp.py').as_posix())
        self.assertEqual(config['mcp_servers']['unreal_local']['env']['UE_PROJECT_NAME'], 'Sample')

    def test_chat_and_responses_preserve_client_instructions_and_tools(self):
        profile = core.default_profile(self.config)
        profile.update(useInstructions=True, instructions='Literal {{value}}', overrideSampling=True, temperature=.2, topP=.8)
        original = {'messages': [{'role': 'system', 'content': 'Client instructions'}, {'role': 'user', 'content': 'hello'}],
                    'tools': [{'type': 'function', 'function': {'name': 'inspect'}}], 'max_tokens': 32}
        result = core.transform_request(original, profile, '/v1/chat/completions')
        self.assertEqual(result['max_tokens'], 32)
        self.assertEqual(result['temperature'], .2)
        self.assertEqual(result['top_p'], .8)
        self.assertIn('Client instructions', result['messages'][0]['content'])
        self.assertIn('Literal {{value}}', result['messages'][0]['content'])
        self.assertEqual(result['tools'], original['tools'])
        self.assertEqual(original['messages'][0]['content'], 'Client instructions')
        response = core.transform_request({'instructions': 'Base', 'input': 'hello', 'previous_response_id': 'previous'}, profile, '/v1/responses')
        self.assertTrue(response['instructions'].startswith('Base'))
        self.assertEqual(response['previous_response_id'], 'previous')
        self.assertEqual(response['max_output_tokens'], 4096)

    def test_default_sampling_keeps_client_values(self):
        original = {'messages': [], 'temperature': .3, 'top_p': .6, 'max_completion_tokens': 8}
        result = core.transform_request(original, core.default_profile(self.config), '/v1/chat/completions')
        self.assertEqual(result, original)


class Gateway(Profiles):
    def setUp(self):
        super().setUp()
        self.received = queue.Queue()
        self.release_stream = threading.Event()
        owner = self

        class Upstream(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                owner.received.put((self.path, request))
                self.send_response(200)
                if request.get('stream'):
                    self.send_header('Content-Type', 'text/event-stream')
                    self.end_headers()
                    self.wfile.write(b'data: first\n\n')
                    self.wfile.flush()
                    owner.release_stream.wait(3)
                    self.wfile.write(b'data: [DONE]\n\n')
                    self.wfile.flush()
                else:
                    data = json.dumps({'ok': True}).encode()
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)

        self.upstream = ThreadingHTTPServer(('127.0.0.1', 0), Upstream)
        self.upstream.daemon_threads = True
        self.gateway = runtime.make_server(self.config, 0, self.upstream.server_port)
        self.threads = []
        for server in (self.upstream, self.gateway):
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.threads.append(thread)

    def tearDown(self):
        self.release_stream.set()
        for server in (self.gateway, self.upstream):
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(3)
        super().tearDown()

    def request(self, body, route='/profiles/default/v1/chat/completions', headers=None):
        connection = HTTPConnection('127.0.0.1', self.gateway.server_port, timeout=2)
        merged = {'Content-Type': 'application/json', **(headers or {})}
        connection.request('POST', route, json.dumps(body).encode(), merged)
        return connection, connection.getresponse()

    def test_stream_is_forwarded_before_generation_finishes(self):
        profile = core.default_profile(self.config)
        profile.update(useInstructions=True, instructions='Live profile instruction')
        self.save(profile)
        connection, response = self.request({'messages': [{'role': 'user', 'content': 'hi'}], 'stream': True})
        try:
            self.assertEqual(response.status, 200)
            self.assertIn(b'data: first', response.read1(100))
            self.assertFalse(self.release_stream.is_set())
            route, request = self.received.get(timeout=1)
            self.assertEqual(route, '/v1/chat/completions')
            self.assertIn('Live profile instruction', request['messages'][0]['content'])
            self.release_stream.set()
            self.assertIn(b'[DONE]', response.read())
        finally:
            self.release_stream.set()
            connection.close()

    def test_cross_origin_and_unknown_routes_are_rejected(self):
        for route, headers, expected in [('/profiles/default/v1/chat/completions', {'Origin': 'https://example.com'}, 403),
                                         ('/shutdown', {}, 404), ('/profiles/../../v1/responses', {}, 404)]:
            connection, response = self.request({'messages': []}, route, headers)
            self.assertEqual(response.status, expected)
            response.read()
            connection.close()
        self.assertTrue(self.received.empty())

    def test_later_requests_read_updated_profile_without_changing_other_profile(self):
        profile = core.default_profile(self.config)
        profile.update(name='Other profile', useInstructions=True, instructions='Other instructions')
        identity = self.save(profile, new=True)['activeId']
        for route in ('/profiles/default/v1/chat/completions', f'/profiles/{identity}/v1/chat/completions'):
            connection, response = self.request({'messages': []}, route)
            self.assertEqual(response.status, 200)
            response.read()
            connection.close()
        first = self.received.get(timeout=1)[1]
        second = self.received.get(timeout=1)[1]
        self.assertEqual(first['messages'], [])
        self.assertIn('Other instructions', second['messages'][0]['content'])


if __name__ == '__main__':
    unittest.main()
