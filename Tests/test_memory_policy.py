import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'app'))
import plugin_host as plugins
import project_memory as memory

ROOT = Path(__file__).resolve().parents[1]

class MemoryPolicy(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.config = {'StateRoot': str(self.root/'state'), 'PythonExecutable': sys.executable}
        self.folder = Path(self.config['StateRoot'])/'plugins/memory-policy'
        self.folder.mkdir(parents=True)
        shutil.copy(ROOT/'examples/plugins/memory-policy/plugin.json', self.folder/'plugin.json')
        self.profile = {'workspaceRoot': str(self.root/'project'), 'useMemory':True}
        memory.save(self.config, self.profile, {'title':'User reviewed', 'body':'alpha marker', 'verified':True})
        memory.save(self.config, self.profile, {'title':'Pending', 'body':'beta marker'})
    def tearDown(self):
        self.temp.cleanup()
    def enable(self):
        item=plugins.inventory(self.config)[0]
        plugins.approve(self.config, {'id':item['id'],'fingerprint':item['fingerprint'], 'enabled':True,'acceptLocalCodeRisk':True})
    def test_default_and_disable_are_fail_closed_and_preserve_notes(self):
        self.assertEqual(plugins.memory_policy(self.config),'off')
        self.enable()
        self.assertEqual(plugins.memory_policy(self.config),'off')
        plugins.set_memory_policy(self.config, {'level':'all'})
        item=plugins.inventory(self.config)[0]
        plugins.approve(self.config, {'id':item['id'],'fingerprint':item['fingerprint'],'enabled':False})
        self.assertEqual(plugins.memory_policy(self.config),'off')
        self.assertEqual(len(memory.items(self.config,self.profile)),2)
    def test_verified_scope_and_project_isolation(self):
        self.enable();plugins.set_memory_policy(self.config, {'level':'verified'})
        output=memory.recall(self.config,self.profile,policy=plugins.memory_policy(self.config))['text']
        self.assertIn('alpha marker',output);self.assertNotIn('beta marker',output)
        self.assertFalse(memory.recall(self.config,{'workspaceRoot':str(self.root/'other'),'useMemory':True},policy='all')['text'])
        self.assertFalse(memory.recall(self.config,{**self.profile,'useMemory':False},policy='all')['text'])
    def test_changed_or_invalid_source_fails_closed(self):
        self.enable();plugins.set_memory_policy(self.config, {'level':'all'})
        (self.folder/'extra.py').write_text('raise RuntimeError("must never execute")')
        self.assertEqual(plugins.inventory(self.config)[0]['state'],'invalid')
        self.assertEqual(plugins.memory_policy(self.config),'off')
    def test_unknown_builtin_and_policy_rejected(self):
        self.enable()
        with self.assertRaises(ValueError):plugins.set_memory_policy(self.config, {'level':'filesystem-admin'})
        data=json.loads((self.folder/'plugin.json').read_text());data['entry']='arbitrary';(self.folder/'plugin.json').write_text(json.dumps(data))
        self.assertEqual(plugins.memory_policy(self.config),'off')
    def test_plugin_removal_keeps_memory_disclosure_blocked(self):
        self.enable();plugins.set_memory_policy(self.config, {'level':'verified'})
        item=plugins.inventory(self.config)[0]
        plugins.remove(self.config, {'id':item['id'],'fingerprint':item['fingerprint']})
        self.assertEqual(plugins.memory_policy(self.config),'off')
        self.assertEqual(len(memory.items(self.config,self.profile)),2)

if __name__=='__main__': unittest.main()
