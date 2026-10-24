import importlib.util
from pathlib import Path
import unittest
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('unreal_mcp', Path(__file__).with_name('unreal_mcp.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Contracts(unittest.TestCase):
    def test_initialize(self):
        result = module.handle({'method': 'initialize', 'params': {'protocolVersion': '2025-06-18'}})
        self.assertEqual(result['protocolVersion'], '2025-06-18')
        self.assertIn('tools', result['capabilities'])

    def test_tools_are_read_only(self):
        for tool in module.TOOLS:
            self.assertTrue(tool['annotations']['readOnlyHint'])
            self.assertFalse(tool['inputSchema']['additionalProperties'])

    def test_unknown_tool(self):
        with self.assertRaises(ValueError):
            module.validate('execute_python', {'code': 'bad'})

    def test_unknown_argument(self):
        with self.assertRaises(ValueError):
            module.validate('unreal_list_actors', {'code': 'bad'})

    def test_invalid_limit(self):
        for value in [True, 0, 201, '50']:
            with self.assertRaises(ValueError):
                module.validate('unreal_list_actors', {'limit': value})

    def test_folder_validation(self):
        for value in ['C:/Windows', '/Game/../Engine', '/Game\\test', '/Game/test:bad']:
            with self.assertRaises(ValueError):
                module.validate('unreal_find_assets', {'folder': value})

    def test_label_required(self):
        with self.assertRaises(ValueError):
            module.validate('unreal_inspect_actor', {})

    def test_valid_arguments(self):
        module.validate('unreal_list_actors', {'query': 'lamp', 'limit': 10})
        module.validate('unreal_find_assets', {'folder': '/Game/DroneKilla', 'query': 'Murdock'})

    def editor_node(self, **overrides):
        return {'machine': module.os.environ.get('COMPUTERNAME', module.socket.gethostname()),
                'project_name': module.PROJECT_NAME, 'project_root': str(module.PROJECT), 'node_id': 'test', **overrides}

    def test_discover_exact_project_only(self):
        expected = self.editor_node()
        nodes = [self.editor_node(project_name='Other'), self.editor_node(machine='OtherPC'),
                 self.editor_node(project_root='C:/Other/DroneKillaV2'), expected]
        self.assertEqual(module.discover(SimpleNamespace(remote_nodes=nodes), wait_seconds=0), expected)

    def test_discover_duplicate_editors_refused(self):
        nodes = [self.editor_node(node_id='first'), self.editor_node(node_id='second')]
        with self.assertRaises(RuntimeError):
            module.discover(SimpleNamespace(remote_nodes=nodes), wait_seconds=0)


if __name__ == '__main__':
    unittest.main()
