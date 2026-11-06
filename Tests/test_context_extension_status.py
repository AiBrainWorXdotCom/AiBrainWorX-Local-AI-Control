"""The optional DSH extension stays scoped to the selected launcher profile."""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == 'nt' and shutil.which('powershell.exe'), 'Windows PowerShell required')
class ContextExtensionStatus(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        workspace = root / 'project'
        workspace.mkdir()
        self.runtime = root / 'runtime'
        # Never mistake the owner's running Harness for this isolated fixture.
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            harness_port = listener.getsockname()[1]
        model = root / 'model.json'
        model.write_text('{"model_name":"test-model"}', encoding='utf-8')
        config = {'NodeExecutable': shutil.which('node.exe') or sys.executable,
                  'PythonExecutable': sys.executable, 'HarnessEntry': str(Path(__file__).resolve()),
                  'WorkspaceRoot': str(workspace), 'StateRoot': str(self.runtime), 'StrataConfig': str(model),
                  'HarnessPort': harness_port}
        self.config = root / 'config.json'
        self.config.write_text(json.dumps(config), encoding='utf-8')

    def tearDown(self):
        self.temp.cleanup()

    def status(self):
        result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                 str(ROOT / 'app/Context-Extension.ps1'), '-Action', 'Status',
                                 '-ConfigPath', str(self.config)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def change(self, input_text):
        result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                 str(ROOT / 'app/Context-Extension.ps1'), '-ConfigPath', str(self.config)],
                                input=input_text, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        if 'GetActiveTcpListeners' in result.stdout and 'Access is denied' in result.stdout:
            self.skipTest('Sandbox forbids inspecting listeners required by the stopped-Harness guard')
        self.assertNotIn('Could not complete the action', result.stdout)
        return result.stdout

    def test_status_reports_install_and_disabled_without_changing_manifest(self):
        self.assertIn('Not installed', self.status())
        target = self.runtime / 'managed-clients/default/harness/profiles/web/package.json'
        target.parent.mkdir(parents=True)
        manifest = {'dependencies': {'billion-context': '0.1.212', 'another': '1.0.0'},
                    'dsh': {'profile': {'bundles': ['@deepseek-ai/dsh-base', 'billion-context']}}}
        original = json.dumps(manifest)
        target.write_text(original, encoding='utf-8')
        self.assertIn('package files are missing', self.status())
        node_manifest = target.parent / 'node_modules/billion-context/package.json'
        node_manifest.parent.mkdir(parents=True)
        node_manifest.write_text('{"name":"billion-context","version":"0.1.212"}', encoding='utf-8')
        self.assertIn('Registered', self.status())
        self.assertEqual(target.read_text(encoding='utf-8'), original)
        manifest['dsh']['profile']['bundles'].remove('billion-context')
        original = json.dumps(manifest)
        target.write_text(original, encoding='utf-8')
        self.assertIn('Disabled', self.status())
        self.assertEqual(target.read_text(encoding='utf-8'), original)

    def test_disable_and_reenable_keep_other_plugins_and_session_files(self):
        self.status()  # initialize the private launcher profile
        target = self.runtime / 'managed-clients/default/harness/profiles/web/package.json'
        target.parent.mkdir(parents=True)
        node_manifest = target.parent / 'node_modules/billion-context/package.json'
        node_manifest.parent.mkdir(parents=True)
        node_manifest.write_text('{"name":"billion-context","version":"0.1.212"}', encoding='utf-8')
        manifest = {'name': 'test', 'dependencies': {'billion-context': '0.1.212', 'another': '1.0.0'},
                    'dsh': {'profile': {'bundles': ['@deepseek-ai/dsh-base', 'billion-context', 'another']}}}
        target.write_text(json.dumps(manifest), encoding='utf-8')
        session = self.runtime / 'managed-clients/default/billion-context/sessions/sentinel.txt'
        session.parent.mkdir(parents=True)
        session.write_text('keep', encoding='utf-8')
        self.change('2\nDISABLE\n\n')
        disabled = json.loads(target.read_text(encoding='utf-8'))
        self.assertEqual(disabled['dependencies'], manifest['dependencies'])
        self.assertEqual(disabled['dsh']['profile']['bundles'], ['@deepseek-ai/dsh-base', 'another'])
        self.assertEqual(session.read_text(encoding='utf-8'), 'keep')
        self.change('1\nINSTALL\n\n')
        enabled = json.loads(target.read_text(encoding='utf-8'))
        self.assertEqual(enabled['dependencies'], manifest['dependencies'])
        self.assertEqual(enabled['dsh']['profile']['bundles'], ['@deepseek-ai/dsh-base', 'another', 'billion-context'])
        self.assertEqual(session.read_text(encoding='utf-8'), 'keep')


if __name__ == '__main__':
    unittest.main()
