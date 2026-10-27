import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'app'))
import plugin_host as plugins


class MonitorPlugins(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.config = {'StateRoot': str(self.root/'state'), 'PythonExecutable': sys.executable}
        self.folder = Path(self.config['StateRoot'])/'plugins/test-monitor'
        self.folder.mkdir(parents=True)
        self.manifest = {'id': 'test-monitor', 'name': 'Test monitor', 'apiVersion': 1,
                         'runtime': 'python', 'entry': 'main.py', 'hooks': ['monitor.sample'],
                         'capabilities': ['read_system']}
        self.source = ('import json,os,sys\nfrom pathlib import Path\n'
                       'r=json.load(sys.stdin)\np=Path(os.environ["AIBRAINWORX_PLUGIN_DATA"])\n'
                       '(p/"request.json").write_text(json.dumps(r))\n'
                       'print(json.dumps({"apiVersion":1,"panel":{"metrics":[{"label":"CPU","value":None,"unit":"%"}],"note":"Sample"}}))\n')
        self.write()

    def tearDown(self):
        self.temp.cleanup()

    def write(self):
        (self.folder/'plugin.json').write_text(json.dumps(self.manifest), encoding='utf-8')
        (self.folder/'main.py').write_text(self.source, encoding='utf-8')

    @property
    def data(self):
        return Path(self.config['StateRoot'])/'plugin-data/test-monitor'

    def item(self):
        return plugins.inventory(self.config)[0]

    def approve(self, enabled=True):
        item = self.item()
        return plugins.approve(self.config, {'id': item['id'], 'fingerprint': item['fingerprint'],
                                            'enabled': enabled, 'acceptLocalCodeRisk': True})

    def test_disabled_never_executes_and_explicit_risk_consent_required(self):
        item = self.item()
        with self.assertRaises(ValueError):
            plugins.approve(self.config, {'id': item['id'], 'fingerprint': item['fingerprint'], 'enabled': True})
        self.assertNotIn('panel', plugins.panels(self.config)['items'][0])
        self.assertFalse(self.data.exists())

    def test_hot_enable_disable_and_manual_remove_restore(self):
        self.approve()
        self.assertIn('panel', plugins.panels(self.config)['items'][0])
        marker = self.data/'request.json'
        marker.unlink()
        self.approve(False)
        self.assertNotIn('panel', plugins.panels(self.config)['items'][0])
        self.assertFalse(marker.exists())
        self.approve()
        removed = self.folder.with_name('removed-source')
        self.folder.rename(removed)
        self.assertEqual(plugins.panels(self.config)['items'], [])
        removed.rename(self.folder)
        self.assertIn('panel', plugins.panels(self.config)['items'][0])

    def test_changed_source_and_incompatible_api_never_execute(self):
        self.approve()
        self.source += '\n# reviewed source changed\n'
        self.write()
        self.assertEqual(plugins.panels(self.config)['items'][0]['state'], 'review')
        self.assertFalse(self.data.exists())
        self.approve()
        self.assertIn('panel', plugins.panels(self.config)['items'][0])
        self.manifest['apiVersion'] = 2
        self.write()
        self.assertEqual(plugins.panels(self.config)['items'][0]['state'], 'incompatible')

    def test_context_contains_only_telemetry_and_explicit_flags(self):
        self.approve()
        context = {'backend': 'strata', 'chat': 'private chat', 'projectPath': 'C:\\private\\project',
                   'inspectProcesses': 1, 'includeGpuProcesses': True,
                   'modelMetrics': {'hardware': {'cpu': 0, 'ram_used': 100, 'path': '/private/model'},
                                    'live': {'tok_s': 12, 'state': 'generating', 'prompt': 'private prompt'},
                                    'requests': [{'decode_tok_s': 15, 'prompt_read': 50, 'prompt': 'private prompt', 'id': 'private-id'}]}}
        with mock.patch.dict('os.environ', {'AIBRAINWORX_PRIVATE_CONTEXT': 'secret workspace'}, clear=False):
            self.assertIn('panel', plugins.panels(self.config, context)['items'][0])
        request = json.loads((self.data/'request.json').read_text())
        self.assertEqual(set(request), {'apiVersion', 'hook', 'context'})
        self.assertEqual(request['context']['backend'], 'strata')
        self.assertFalse(request['context']['inspectProcesses'])
        self.assertFalse(request['context']['includeGpuProcesses'])
        self.assertEqual(request['context']['modelMetrics']['hardware']['cpu'], 0)
        self.assertNotIn('private', json.dumps(request))
        env = plugins._monitor_environment(self.data)
        self.assertNotIn('AIBRAINWORX_PRIVATE_CONTEXT', env)
        self.assertNotIn('WORKSPACE_ROOT', env)

    def test_invalid_context_values_cannot_break_host(self):
        self.approve()
        for value in ([], {}, float('nan'), 10**500):
            context = {'backend': value, 'modelMetrics': {'live': {'state': value}, 'hardware': {'cpu': value}}}
            self.assertIn('panel', plugins.panels(self.config, context)['items'][0])

    def test_disabling_in_flight_discards_real_subprocess_result(self):
        self.source = self.source.replace('print(json.dumps(',
            '(p/"ready").write_text("ready")\nimport time\nwhile not (p/"release").exists(): time.sleep(.01)\nprint(json.dumps(')
        self.write()
        self.approve()
        result = {}
        thread = threading.Thread(target=lambda: result.update(plugins.panels(self.config)))
        thread.start()
        try:
            deadline = time.monotonic()+3
            while not (self.data/'ready').exists() and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue((self.data/'ready').exists())
            self.approve(False)
        finally:
            self.data.mkdir(parents=True, exist_ok=True)
            (self.data/'release').write_text('release')
            thread.join(timeout=6)
        self.assertFalse(thread.is_alive())
        self.assertNotIn('panel', result['items'][0])
        self.assertEqual(result['items'][0]['state'], 'review')

    def test_source_change_during_collection_discards_output(self):
        self.approve()
        original = plugins.subprocess.run
        def changed(*args, **kwargs):
            reply = original(*args, **kwargs)
            (self.folder/'main.py').write_text(self.source+'\n# changed in flight\n')
            return reply
        with mock.patch.object(plugins.subprocess, 'run', side_effect=changed):
            row = plugins.panels(self.config)['items'][0]
        self.assertNotIn('panel', row)
        self.assertEqual(row['state'], 'review')

    def test_removal_during_collection_discards_output(self):
        self.approve()
        original = plugins.subprocess.run
        def removed(*args, **kwargs):
            reply = original(*args, **kwargs)
            item = self.item()
            plugins.remove(self.config, {'id': item['id'], 'fingerprint': item['fingerprint']})
            return reply
        with mock.patch.object(plugins.subprocess, 'run', side_effect=removed):
            row = plugins.panels(self.config)['items'][0]
        self.assertNotIn('panel', row)
        self.assertEqual(plugins.panels(self.config)['items'], [])

    def test_disable_then_reenable_during_collection_discards_old_sample(self):
        self.approve()
        original = plugins.subprocess.run
        def toggled(*args, **kwargs):
            reply = original(*args, **kwargs)
            self.approve(False)
            self.approve(True)
            return reply
        with mock.patch.object(plugins.subprocess, 'run', side_effect=toggled):
            row = plugins.panels(self.config)['items'][0]
        self.assertNotIn('panel', row)
        self.assertEqual(row['state'], 'review')
        self.assertIn('panel', plugins.panels(self.config)['items'][0])

    def test_example_runs_through_host_using_only_supplied_model_metrics(self):
        example = Path(__file__).resolve().parents[1]/'examples/plugins/resource-monitor'
        target = self.folder.with_name('resource-monitor')
        shutil.copytree(example, target, ignore=shutil.ignore_patterns('__pycache__'))
        item = next(item for item in plugins.inventory(self.config) if item['id'] == 'resource-monitor')
        plugins.approve(self.config, {'id': item['id'], 'fingerprint': item['fingerprint'],
                                     'enabled': True, 'acceptLocalCodeRisk': True})
        result = plugins.panels(self.config, {'backend': 'strata', 'modelMetrics': {
            'hardware': {'cpu': 8, 'ram_used': 1024}, 'live': {'state': 'generating', 'tok_s': 12}}})
        row = next(row for row in result['items'] if row['id'] == 'resource-monitor')
        self.assertEqual(row['state'], 'enabled')
        self.assertEqual(row['panel']['metrics'][0]['value'], 8)
        self.assertEqual(row['panel']['processes'], [])

    def test_approval_is_checked_immediately_before_subprocess(self):
        self.approve()
        discovered = plugins.inventory(self.config)
        self.approve(False)
        with mock.patch.object(plugins, 'inventory', return_value=discovered), \
             mock.patch.object(plugins.subprocess, 'run', side_effect=AssertionError('Must not execute')) as run:
            row = plugins.panels(self.config)['items'][0]
        run.assert_not_called()
        self.assertEqual(row['state'], 'review')

    def test_one_bad_plugin_does_not_break_other_panels_and_errors_are_sanitized(self):
        self.approve()
        bad = self.folder.with_name('bad-monitor')
        bad.mkdir()
        (bad/'plugin.json').write_text(json.dumps({**self.manifest, 'id': 'bad-monitor'}))
        (bad/'main.py').write_text('raise RuntimeError("C:/private/model private chat")\n')
        item = next(item for item in plugins.inventory(self.config) if item['id'] == 'bad-monitor')
        plugins.approve(self.config, {'id': item['id'], 'fingerprint': item['fingerprint'], 'enabled': True, 'acceptLocalCodeRisk': True})
        result = plugins.panels(self.config)
        self.assertEqual([item['state'] for item in result['items']], ['error', 'enabled'])
        self.assertIn('panel', result['items'][1])
        self.assertNotIn('private', json.dumps(result))

    def test_malformed_manifest_or_approval_cannot_break_other_plugins(self):
        self.approve()
        bad = self.folder.with_name('bad-monitor')
        bad.mkdir()
        (bad/'plugin.json').write_text('[]')
        self.assertIn('panel', plugins.panels(self.config)['items'][0])
        self.assertEqual(plugins.inventory(self.config)[0]['state'], 'invalid')
        (bad/'plugin.json').write_text(json.dumps({**self.manifest, 'id': 'bad-monitor'}))
        (bad/'main.py').write_text(self.source)
        path = Path(self.config['StateRoot'])/'plugin-approvals.local.json'
        saved = json.loads(path.read_text())
        saved['bad-monitor'] = []
        path.write_text(json.dumps(saved))
        result = plugins.panels(self.config)['items']
        self.assertEqual(result[0]['state'], 'review')
        self.assertIn('panel', result[1])

    def test_entry_in_unfingerprinted_dependency_folder_is_refused(self):
        folder = self.folder/'.venv'
        folder.mkdir()
        (folder/'entry.py').write_text(self.source)
        self.manifest['entry'] = '.venv/entry.py'
        self.write()
        self.assertEqual(self.item()['state'], 'invalid')

    def test_bounded_timeout_does_not_change_chat_timeout(self):
        self.approve()
        with mock.patch.object(plugins.subprocess, 'run', side_effect=TimeoutError('C:/private/file')) as run:
            row = plugins.panels(self.config)['items'][0]
        self.assertEqual(run.call_args.kwargs['timeout'], 5)
        self.assertEqual(row['state'], 'error')
        self.manifest['hooks'] = ['chat.before_send']
        self.write()
        self.approve()
        reply = mock.Mock(stdout='{"apiVersion":1,"data":{"message":"Hello"}}')
        with mock.patch.object(plugins.subprocess, 'run', return_value=reply) as run:
            self.assertEqual(plugins.run_hook(self.config, 'chat.before_send', {'message': 'Hello'}), {'message': 'Hello'})
        self.assertEqual(run.call_args.kwargs['timeout'], 3)

    def test_app_source_folder_replacement_preserves_approvals_and_data(self):
        self.approve()
        self.assertIn('panel', plugins.panels(self.config)['items'][0])
        (self.data/'keep.txt').write_text('persistent plugin data')
        source_root = self.root/'app-install'
        source_root.mkdir()
        shutil.copy2(Path(plugins.__file__), source_root/'plugin_host.py')
        source_root.rename(self.root/'previous-app-install')
        source_root.mkdir()
        shutil.copy2(Path(plugins.__file__), source_root/'plugin_host.py')
        spec = importlib.util.spec_from_file_location('replacement_plugin_host', source_root/'plugin_host.py')
        replacement = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(replacement)
        self.assertEqual(replacement.inventory(self.config)[0]['state'], 'enabled')
        self.assertIn('panel', replacement.panels(self.config)['items'][0])
        self.assertEqual((self.data/'keep.txt').read_text(), 'persistent plugin data')

    def test_remove_archives_source_preserves_data_restore_requires_enable(self):
        self.approve()
        plugins.panels(self.config)
        item = self.item()
        removed = plugins.remove(self.config, {'id': item['id'], 'fingerprint': item['fingerprint']})
        self.assertFalse(self.folder.exists())
        self.assertTrue((self.data/'request.json').exists())
        self.assertEqual(plugins.panels(self.config)['items'], [])
        archived = plugins.archives(self.config)['items'][0]
        self.assertEqual(archived['archiveId'], removed['archiveId'])
        self.assertEqual(archived['fingerprint'], item['fingerprint'])
        plugins.restore(self.config, {'archiveId': archived['archiveId']})
        self.assertEqual(plugins.archives(self.config)['items'], [])
        self.assertEqual(self.item()['state'], 'review')
        self.assertNotIn('panel', plugins.panels(self.config)['items'][0])
        self.approve()
        self.assertIn('panel', plugins.panels(self.config)['items'][0])

    def test_archive_rejects_stale_review_traversal_and_existing_restore_target(self):
        item = self.item()
        (self.folder/'main.py').write_text(self.source+'\n# changed\n')
        with self.assertRaises(ValueError):
            plugins.remove(self.config, {'id': item['id'], 'fingerprint': item['fingerprint']})
        for identity in ('../test-monitor', 'C:\\private', None):
            with self.assertRaises(ValueError):
                plugins.remove(self.config, {'id': identity})
        for archive in ('../test-monitor', '/tmp/other', None):
            with self.assertRaises(ValueError):
                plugins.restore(self.config, {'archiveId': archive})
        item = self.item()
        removed = plugins.remove(self.config, {'id': item['id'], 'fingerprint': item['fingerprint']})
        self.folder.mkdir()
        with self.assertRaises(ValueError):
            plugins.restore(self.config, {'archiveId': removed['archiveId']})
        self.assertTrue((Path(self.config['StateRoot'])/'plugin-archive'/removed['archiveId']).is_dir())

    def test_archive_rejects_links_even_inside_ignored_source_directory(self):
        external = self.root/'external'
        external.mkdir()
        link = self.folder/'.venv'
        try:
            link.symlink_to(external, target_is_directory=True)
        except OSError:
            self.skipTest('Creating local symbolic links is unavailable for this account.')
        try:
            item = self.item()
            with self.assertRaises(ValueError):
                plugins.remove(self.config, {'id': item['id'], 'fingerprint': item['fingerprint']})
            self.assertTrue(self.folder.exists())
        finally:
            link.unlink(missing_ok=True)


class PanelSchema(unittest.TestCase):
    def test_limits_and_private_or_executable_fields_are_rejected(self):
        bad = [
            {'metrics': [{'label': 'CPU', 'value': 1}]*13},
            {'services': [{'name': 'Model', 'state': 'ok'}]*9},
            {'processes': [{'pid': 1, 'name': 'python', 'cpuPercent': 1, 'memoryBytes': 1}]*21},
            {'metrics': [{'label': '<script>', 'value': 1}]},
            {'metrics': [{'label': 'CPU', 'value': float('nan')}]},
            {'metrics': [{'label': 'CPU', 'value': True}]},
            {'note': 'C:\\private\\project'}, {'note': '/private/fixture/project'},
            {'html': '<b>Markup</b>'}, {'actions': ['kill']},
            {'processes': [{'pid': 1, 'name': 'python -c secret', 'cpuPercent': 1, 'memoryBytes': 1}]},
            {'processes': [{'pid': 1, 'name': 'python', 'cpuPercent': 101, 'memoryBytes': 1}]},
            {'processes': [{'pid': 1, 'name': 'python', 'cpuPercent': 1, 'memoryBytes': -1}]},
            {'processes': [{'pid': 1, 'name': 'python', 'cpuPercent': 1, 'memoryBytes': 1, 'cmdline': 'private'}]},
        ]
        for value in bad:
            with self.subTest(value=value), self.assertRaises((ValueError, TypeError)):
                plugins.validate_panel(value)

    def test_unknown_measurements_are_null_and_real_zero_is_preserved(self):
        panel = plugins.validate_panel({'metrics': [{'label': 'GPU', 'value': None}, {'label': 'CPU', 'value': 0}],
                                       'processes': [{'pid': 1, 'name': 'python.exe', 'cpuPercent': None, 'memoryBytes': None, 'gpuMemoryBytes': None}]})
        self.assertIsNone(panel['metrics'][0]['value'])
        self.assertEqual(panel['metrics'][1]['value'], 0)
        self.assertIsNone(panel['processes'][0]['gpuMemoryBytes'])


class ResourceMonitorExample(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[1]/'examples/plugins/resource-monitor/main.py'
        spec = importlib.util.spec_from_file_location('resource_monitor_example', path)
        cls.example = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.example)

    def test_automatic_light_sample_only_reuses_supplied_telemetry(self):
        with mock.patch.object(self.example, 'windows_processes', side_effect=AssertionError('No process collection')), \
             mock.patch.object(self.example, 'linux_processes', side_effect=AssertionError('No process collection')), \
             mock.patch.object(self.example, 'gpu_memory', side_effect=AssertionError('No GPU collection')):
            panel = self.example.sample({'backend': 'strata', 'includeGpuProcesses': True, 'modelMetrics': {
                'hardware': {'cpu': 0, 'ram_used': 123, 'gpu_mem_used': None},
                'live': {'state': 'generating', 'tok_s': 12},
                'requests': [{'prompt_ms': 20, 'prompt_read': 10, 'first_engine_token_s': .3}]}})
        plugins.validate_panel(panel)
        values = {row['label']: row['value'] for row in panel['metrics']}
        self.assertEqual(values['CPU usage'], 0)
        self.assertEqual(values['RAM used'], 123)
        self.assertIsNone(values['GPU memory used'])
        self.assertEqual(values['Decode rate'], 12)
        self.assertEqual(values['Prompt processing'], 500)
        self.assertEqual(panel['processes'], [])

    def test_missing_telemetry_stays_unknown_without_any_collection(self):
        with mock.patch.object(self.example.subprocess, 'run', side_effect=AssertionError('No subprocesses')):
            panel = self.example.sample({'backend': 'compatible'})
        self.assertTrue(all(row['value'] is None for row in panel['metrics']))
        self.assertEqual(panel['services'][0]['state'], 'unknown')

    def test_explicit_process_inspection_and_gpu_are_separate_choices(self):
        rows = [{'pid': 1, 'name': 'python', 'cpuPercent': None, 'memoryBytes': 123}]
        with mock.patch.object(self.example.sys, 'platform', 'linux'), \
             mock.patch.object(self.example, 'linux_processes', return_value=(rows, {'cpu': None})) as collect, \
             mock.patch.object(self.example, 'gpu_memory', return_value={}) as gpu:
            panel = self.example.sample({'inspectProcesses': True})
            self.assertEqual(collect.call_count, 1)
            gpu.assert_not_called()
            self.assertNotIn('gpuMemoryBytes', panel['processes'][0])
            panel = self.example.sample({'inspectProcesses': True, 'includeGpuProcesses': True})
            gpu.assert_called_once()
            self.assertIsNone(panel['processes'][0]['gpuMemoryBytes'])
        plugins.validate_panel(panel)

    def test_unavailable_process_collection_keeps_supplied_model_values(self):
        with mock.patch.object(self.example.sys, 'platform', 'win32'), \
             mock.patch.object(self.example, 'windows_processes', side_effect=OSError('private-path')):
            panel = self.example.sample({'inspectProcesses': True, 'modelMetrics': {'hardware': {'cpu': 12}}})
        self.assertEqual(panel['metrics'][0]['value'], 12)
        self.assertEqual(panel['processes'], [])
        self.assertNotIn('private-path', panel['note'])

    def test_windows_collector_uses_bounded_hidden_child_and_fixed_fields(self):
        response = {'rows': [{'IDProcess': 42, 'Name': 'python', 'PercentProcessorTime': 50, 'WorkingSetPrivate': 123}],
                    'total': 1000, 'free': 500, 'cpu': 10}
        with mock.patch.object(self.example.subprocess, 'run', return_value=mock.Mock(stdout=json.dumps(response))) as run, \
             mock.patch.object(self.example.os, 'cpu_count', return_value=4):
            rows, hardware = self.example.windows_processes()
        self.assertEqual(rows[0]['cpuPercent'], 12.5)
        self.assertEqual(hardware['cpu'], 10)
        self.assertEqual(hardware['ram_used'], 500*1024)
        self.assertEqual(run.call_args.kwargs['timeout'], 3.2)
        self.assertEqual(run.call_args.kwargs['creationflags'], getattr(self.example.subprocess, 'CREATE_NO_WINDOW', 0))
        command = run.call_args.args[0]
        self.assertEqual(command[-1].splitlines()[0], "$ErrorActionPreference='Stop'")
        self.assertIn('-NoProfile', command)
        self.assertNotIn('CommandLine', command[-1])
        self.assertNotIn('ExecutablePath', command[-1])
        self.assertNotIn('Get-Process', command[-1])
        self.assertIn('-Property IDProcess,Name,PercentProcessorTime,WorkingSetPrivate', command[-1])

    def test_linux_collector_reads_only_proc_stat_and_memory_with_short_sample(self):
        calls, counts = [], {}
        def read(path, *args, **kwargs):
            location = str(path).replace('\\', '/')
            calls.append(location)
            counts[location] = counts.get(location, 0)+1
            second = counts[location] > 1
            if location == '/proc/stat':
                return 'cpu 110 0 0 110 0 0 0 0\n' if second else 'cpu 100 0 0 100 0 0 0 0\n'
            if location == '/proc/42/stat':
                fields = ['0']*22
                fields[0], fields[11], fields[12], fields[21] = 'S', '15' if second else '10', '0', '2'
                return '42 (python) '+' '.join(fields)
            if location == '/proc/meminfo':
                return 'MemTotal: 1000 kB\nMemAvailable: 500 kB\n'
            raise AssertionError('Unexpected process field requested')
        with mock.patch.object(self.example.Path, 'read_text', read), \
             mock.patch.object(self.example.Path, 'iterdir', return_value=iter([Path('/proc/42')])) as iterdir, \
             mock.patch.object(self.example.os, 'sysconf', return_value=4096, create=True), \
             mock.patch.object(self.example.time, 'sleep') as sleep:
            # Each snapshot gets a fresh enumeration, as an actual /proc does.
            iterdir.side_effect = lambda: iter([Path('/proc/42')])
            rows, hardware = self.example.linux_processes()
        self.assertEqual(rows, [{'pid': 42, 'name': 'python', 'cpuPercent': 25, 'memoryBytes': 8192}])
        self.assertEqual(hardware['cpu'], 50)
        self.assertEqual(hardware['ram_used'], 500*1024)
        sleep.assert_called_once_with(.12)
        self.assertEqual(set(calls), {'/proc/stat', '/proc/42/stat', '/proc/meminfo'})


if __name__ == '__main__':
    unittest.main()
