import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'app'))
import update_center as center


class UpdateProgress(unittest.TestCase):
    def test_progress_reports_completed_jobs_including_unavailable_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            config = {'StateRoot': temporary}
            report = []
            row = center.row('Test', 'Test', state='unavailable')
            with patch.object(center.core, 'ensure_state', return_value={}), \
                 patch.object(center, 'model_sources', return_value=[]), \
                 patch.object(center, 'launcher', return_value=row), \
                 patch.object(center, 'strata', return_value=[row]), \
                 patch.object(center, 'harness', return_value=row), \
                 patch.object(center, 'skills', return_value=[row]), \
                 patch.object(center, 'user_plugins', side_effect=OSError('offline')):
                result = center.check(config, '0.4.0-alpha.6', progress=report.append)
            self.assertEqual([r['completed'] for r in report], list(range(6)))
            self.assertTrue(all(r['total'] == 5 for r in report))
            self.assertEqual(report[0]['state'], 'checking')
            self.assertEqual(report[-1]['state'], 'complete')
            self.assertEqual(result['summary']['unavailable'], 5)

    def test_progress_identity_cannot_choose_a_file_path(self):
        for identity in ('../outside', '', 'a'*33, 'Z'*32, 5):
            with self.assertRaises(ValueError):
                center.progress_path({'StateRoot': '.'}, identity)

    def test_writer_keeps_progress_under_private_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            config = {'StateRoot': temporary}
            write = center.progress_writer(config, 'a'*32)
            write({'completed': 2, 'total': 5, 'state': 'checking', 'unit': 'checks'})
            saved = json.loads(center.progress_path(config, 'a'*32).read_text())
            self.assertEqual(saved['completed'], 2)
            self.assertEqual(list(Path(temporary).iterdir())[0].name, 'update-checks')

    def test_progress_storage_failure_does_not_misreport_source_results(self):
        with tempfile.TemporaryDirectory() as temporary:
            row = center.row('Test', 'Test', state='current')
            with patch.object(center.core, 'ensure_state', return_value={}), \
                 patch.object(center, 'model_sources', return_value=[]), \
                 patch.object(center, 'launcher', return_value=row), \
                 patch.object(center, 'strata', return_value=[]), \
                 patch.object(center, 'harness', return_value=row), \
                 patch.object(center, 'skills', return_value=[]), \
                 patch.object(center, 'user_plugins', return_value=[]):
                result = center.check({'StateRoot': temporary}, '0.4.0-alpha.6', progress=lambda _: (_ for _ in ()).throw(OSError()))
            self.assertEqual(result['summary']['current'], 2)


if __name__ == '__main__':
    unittest.main()
