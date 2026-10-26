import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
import update_center as center


class Updates(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.config = {'StateRoot': self.temp.name, 'WorkspaceRoot': self.temp.name,
                       'ModelBackend': 'compatible', 'ModelId': 'local-alias',
                       'ModelBaseUrl': 'http://127.0.0.1:9099/v1'}

    def tearDown(self):
        self.temp.cleanup()

    def test_unknown_model_provenance_never_claims_current(self):
        with patch.object(center.app_updates, 'request_json') as network:
            result = center.model({'key': 'compatible:alias', 'name': 'alias', 'repo': '', 'revision': ''})
        self.assertEqual(result['state'], 'review')
        network.assert_not_called()

    def test_latest_sha_without_installed_sha_is_review(self):
        with patch.object(center.app_updates, 'request_json', return_value={'sha': 'a'*40}):
            result = center.model({'key': 'x', 'name': 'Qwen/model', 'repo': 'Qwen/model', 'revision': ''})
        self.assertEqual(result['state'], 'review')

    def test_recorded_model_revision_comparison(self):
        with patch.object(center.app_updates, 'request_json', return_value={'sha': 'a'*40}):
            for installed, state in [('a'*40, 'current'), ('b'*40, 'available')]:
                result = center.model({'key': 'x', 'name': 'model', 'repo': 'Qwen/model', 'revision': installed})
                self.assertEqual(result['state'], state)

    def test_failed_model_check_is_not_up_to_date(self):
        with patch.object(center.app_updates, 'request_json', side_effect=OSError):
            result = center.model({'key': 'x', 'name': 'model', 'repo': 'Qwen/model', 'revision': 'a'*40})
        self.assertEqual(result['state'], 'unavailable')

    def test_engine_comparison_uses_matching_qwen_component(self):
        root = self.root / 'strata'
        (root/'engine').mkdir(parents=True)
        (root/'strata_cli').mkdir()
        (root/'strata_cli/__init__.py').write_text('PRODUCT_VERSION = "0.2.4"')
        (root/'engine/engine-component.json').write_text(json.dumps({'version': '0.1.48', 'platform': 'windows-x86_64', 'backend': 'cuda', 'build_id': 'abc+cuda13.0'}))
        feed = {'app': {'version': '0.2.6'}, 'engine': {'packages': [
            {'version': '0.1.50', 'platform': 'windows-x86_64', 'backend': 'cuda', 'variant': 'cuda13'},
            {'version': '0.1.60', 'platform': 'linux-x86_64', 'backend': 'cuda', 'variant': 'cuda13'}]},
            'dsv41': {'version': '0.1.99'}}
        with patch.object(center.app_updates, 'request_json', return_value=feed):
            rows = center.strata({'StrataRoot': str(root)})
        self.assertEqual(rows[0]['latest'], '0.2.6')
        self.assertEqual(rows[1]['latest'], '0.1.50')
        self.assertEqual(rows[1]['state'], 'available')

    def test_harness_reads_package_without_starting_it(self):
        package = self.root/'package'
        (package/'lib').mkdir(parents=True)
        (package/'package.json').write_text(json.dumps({'name': '@deepseek-ai/dsh', 'version': '0.2.1-rc.2'}))
        with patch.object(center.app_updates, 'request_json', return_value={'version': '0.2.1-rc.2'}):
            result = center.harness({'HarnessEntry': str(package/'lib/bin.js')}, True)
        self.assertEqual(result['state'], 'current')

    def test_source_tracking_validates_repo_and_revision(self):
        for repo in ('https://example.com/model', '../model', 'owner/model?token=secret'):
            with self.assertRaises(ValueError):
                center.save_model_source(self.config, {'key': 'compatible:local-alias', 'repo': repo})
        result = center.save_model_source(self.config, {'key': 'compatible:local-alias', 'repo': 'Qwen/model'})
        self.assertIn('unverified', result['note'])
        saved = json.loads((self.root/'model-sources.local.json').read_text())
        self.assertEqual(saved['compatible:local-alias']['revision'], '')

    def test_skill_comparison_normalizes_git_line_endings(self):
        folder = self.root/'skills/guide'
        folder.mkdir(parents=True)
        (folder/'SKILL.md').write_bytes(b'# Guide\r\nRead the source.\r\n')
        (self.root/'skills/catalog.json').write_text(json.dumps([{'name': 'guide', 'path': 'guide/SKILL.md'}]))
        data = b'# Guide\nRead the source.\n'
        digest = hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        with patch.object(center.app_updates, 'request_json', return_value={'tree': [{'path': 'skills/guide/SKILL.md', 'sha': digest, 'type': 'blob'}]}):
            result = center.skills(self.root)
        self.assertEqual(result[0]['state'], 'current')

    def test_skill_reference_change_requires_review_not_install(self):
        (self.root/'skills').mkdir()
        (self.root/'skills/catalog.json').write_text(json.dumps([{'name': 'skills', 'url': 'https://github.com/owner/skills', 'revision': 'a'*40}]))
        with patch.object(center.app_updates, 'request_json', side_effect=[{'tree': []}, [{'sha': 'b'*40}]]):
            result = center.skills(self.root)
        self.assertEqual(result[-1]['state'], 'review')
        self.assertIn('Not installed', result[-1]['detail'])


if __name__ == '__main__':
    unittest.main()
