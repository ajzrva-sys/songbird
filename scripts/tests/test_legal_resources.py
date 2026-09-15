import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from legal_resources import LEGAL, check, stage


class LegalResourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / 'Sources/Resources/Legal'
        self.source.mkdir(parents=True)
        for name, original in LEGAL.items():
            data = ('synthetic fixture: ' + name).encode()
            (self.root / original).write_bytes(data)
            (self.source / name).write_bytes(data)

    def test_stage_delivers_exact_texts(self):
        destination = self.root / 'staged/Legal'
        stage(self.root, destination)
        self.assertTrue(destination.is_dir(), 'Legal resources were not staged')
        self.assertEqual({p.name for p in destination.iterdir()}, set(LEGAL))
        for name, original in LEGAL.items():
            self.assertEqual((destination / name).read_bytes(), (self.root / original).read_bytes())
        check(self.root, destination)


    def test_stale_swiftpm_copy_blocks_packaging_before_destination_creation(self):
        (self.source / 'GPL-3.0.txt').write_text('stale')
        destination = self.root / 'staged/Legal'
        with self.assertRaises(ValueError):
            stage(self.root, destination)
        self.assertFalse(destination.exists())
        with self.assertRaises(ValueError):
            check(self.root, self.source)


    def test_extra_resource_is_rejected(self):
        (self.source / 'unexpected.txt').write_text('extra')
        with self.assertRaises(ValueError):
            check(self.root, self.source)


    def test_missing_resource_is_rejected(self):
        (self.source / 'GPL-3.0.txt').unlink()
        with self.assertRaises(ValueError):
            check(self.root, self.source)

    def test_symlinked_resource_is_rejected(self):
        resource = self.source / 'GPL-3.0.txt'
        resource.unlink()
        resource.symlink_to(self.root / 'LICENSE')
        with self.assertRaises(ValueError):
            check(self.root, self.source)


    def test_empty_or_non_utf8_canonical_text_cannot_be_staged(self):
        for data in (b'', b' \n\t', b'\xff'):
            with self.subTest(data=data):
                (self.root / 'LICENSE').write_bytes(data)
                (self.source / 'GPL-3.0.txt').write_bytes(data)
                destination = self.root / ('staged-' + data.hex()) / 'Legal'
                with self.assertRaises(ValueError):
                    stage(self.root, destination)
                self.assertFalse(destination.exists())


    def test_existing_destination_is_rejected_without_changing_it(self):
        destination = self.root / 'staged/Legal'
        destination.mkdir(parents=True)
        sentinel = destination / 'sentinel'
        sentinel.write_text('keep')
        with self.assertRaises((ValueError, OSError)) as caught:
            stage(self.root, destination)
        self.assertIsInstance(caught.exception, ValueError)
        self.assertEqual(sentinel.read_text(), 'keep')
        self.assertEqual({p.name for p in destination.iterdir()}, {'sentinel'})


    def test_symlink_destination_parent_is_rejected_before_copy(self):
        outside = self.root / 'outside'
        outside.mkdir()
        alias = self.root / 'alias'
        alias.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            stage(self.root, alias / 'Legal')
        self.assertFalse((outside / 'Legal').exists())


    def test_cli_stages_and_rejects_stale_text(self):
        helper = Path(__file__).resolve().parents[1] / 'legal_resources.py'
        destination = self.root / 'cli/Legal'
        result = subprocess.run([sys.executable, str(helper), 'stage', str(self.root), str(destination)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(destination.is_dir(), 'CLI returned success without staging legal texts')
        result = subprocess.run([sys.executable, str(helper), 'check', str(self.root), str(destination)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        (destination / 'GPL-3.0.txt').write_text('stale')
        result = subprocess.run([sys.executable, str(helper), 'check', str(self.root), str(destination)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Legal text mismatch', result.stderr)


if __name__ == '__main__':
    unittest.main()
