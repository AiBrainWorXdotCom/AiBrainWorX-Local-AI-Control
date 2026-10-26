import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
import plugin_host as plugins


class Plugins(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.config = {'StateRoot': self.temp.name, 'PythonExecutable': sys.executable}
        self.folder = Path(self.temp.name)/'plugins/test-plugin'
        self.folder.mkdir(parents=True)
        self.manifest = {'id': 'test-plugin', 'name': 'Test plugin', 'version': '0.1.0',
                         'apiVersion': 1, 'runtime': 'python', 'entry': 'main.py',
                         'hooks': ['chat.before_send'], 'capabilities': ['read_chat', 'modify_chat']}
        self.write()
        (self.folder/'main.py').write_text('import json,sys\nr=json.load(sys.stdin)\nr["data"]["message"] += " [custom]"\nprint(json.dumps(r))\n')

    def write(self):
        (self.folder/'plugin.json').write_text(json.dumps(self.manifest))

    def tearDown(self):
        self.temp.cleanup()

    def approve(self):
        item = plugins.inventory(self.config)[0]
        plugins.approve(self.config, {'id': item['id'], 'fingerprint': item['fingerprint'],
                                     'enabled': True, 'acceptLocalCodeRisk': True})

    def test_unapproved_plugin_is_never_executed(self):
        self.assertEqual(plugins.run_hook(self.config, 'chat.before_send', {'message': 'Hello'}), {'message': 'Hello'})

    def test_explicitly_approved_hook_runs(self):
        self.approve()
        self.assertEqual(plugins.run_hook(self.config, 'chat.before_send', {'message': 'Hello'})['message'], 'Hello [custom]')

    def test_edited_source_requires_fresh_approval(self):
        self.approve()
        (self.folder/'main.py').write_text('raise RuntimeError("changed")')
        self.assertEqual(plugins.inventory(self.config)[0]['state'], 'review')
        self.assertEqual(plugins.run_hook(self.config, 'chat.before_send', {'message': 'Hello'}), {'message': 'Hello'})

    def test_incompatible_update_preserves_and_disables_plugin(self):
        self.approve()
        self.manifest['apiVersion'] = 2
        self.write()
        self.assertEqual(plugins.inventory(self.config)[0]['state'], 'incompatible')
        self.assertTrue((self.folder/'main.py').is_file())

    def test_plugin_outside_folder_is_refused(self):
        self.manifest['entry'] = '../outside.py'
        self.write()
        self.assertEqual(plugins.inventory(self.config)[0]['state'], 'invalid')

    def test_disabling_preserves_files(self):
        self.approve()
        item = plugins.inventory(self.config)[0]
        plugins.approve(self.config, {'id': item['id'], 'fingerprint': item['fingerprint'], 'enabled': False})
        self.assertTrue((self.folder/'main.py').exists())
        self.assertEqual(plugins.inventory(self.config)[0]['state'], 'review')


if __name__ == '__main__':
    unittest.main()
