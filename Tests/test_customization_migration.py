import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
import customization_migration as migration


class Migration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.old, self.new = Path(self.temp.name)/'old', Path(self.temp.name)/'new'
        self.old.mkdir(); self.new.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def file(self, root, relative, content):
        path = root/relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_preview_does_not_write(self):
        self.file(self.old, 'plugins/voice.js', 'custom voice')
        report = migration.plan(self.old, self.new)
        self.assertTrue(report['canApply'])
        self.assertEqual(list(self.new.iterdir()), [])

    def test_user_plugin_transfers_without_modifying_original(self):
        source = self.file(self.old, 'plugins/voice.js', 'custom voice')
        report = migration.plan(self.old, self.new)
        result = migration.apply(report)
        self.assertEqual((self.new/'plugins/voice.js').read_text(), 'custom voice')
        self.assertEqual(source.read_text(), 'custom voice')
        self.assertFalse(result['servicesRestarted'])

    def test_both_changed_is_conflict_and_no_overwrite(self):
        self.file(self.old, 'app.js', 'local voice integration')
        target = self.file(self.new, 'app.js', 'upstream changed')
        report = migration.plan(self.old, self.new, {'app.js': hashlib.sha256(b'original').hexdigest()})
        self.assertFalse(report['canApply'])
        with self.assertRaises(ValueError):
            migration.apply(report)
        self.assertEqual(target.read_text(), 'upstream changed')

    def test_unchanged_upstream_accepts_local_patch_and_backs_up(self):
        self.file(self.old, 'app.js', 'local change')
        target = self.file(self.new, 'app.js', 'original')
        report = migration.plan(self.old, self.new, {'app.js': hashlib.sha256(b'original').hexdigest()})
        result = migration.apply(report)
        self.assertEqual(target.read_text(), 'local change')
        self.assertEqual((Path(result['backup'])/'app.js').read_text(), 'original')

    def test_changed_after_preview_is_refused(self):
        source = self.file(self.old, 'plugins/voice.js', 'first')
        report = migration.plan(self.old, self.new)
        source.write_text('edited later')
        with self.assertRaises(ValueError):
            migration.apply(report)
        self.assertFalse((self.new/'plugins/voice.js').exists())

    def test_overlapping_folders_are_refused(self):
        child = self.old/'nested'
        child.mkdir()
        with self.assertRaises(ValueError):
            migration.plan(self.old, child)

    def test_credential_files_are_not_transferred(self):
        self.file(self.old, 'plugins/.env', 'SECRET=private')
        report = migration.plan(self.old, self.new)
        self.assertEqual(report['actions'], [])
        self.assertEqual(len(report['skipped']), 1)


if __name__ == '__main__':
    unittest.main()
