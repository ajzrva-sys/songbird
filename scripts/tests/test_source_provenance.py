import pathlib
import runpy
import tempfile
import unittest

provenance = runpy.run_path(str(pathlib.Path(__file__).parents[1] / 'usability/source-provenance'))['provenance']

class SourceProvenanceTests(unittest.TestCase):
    def test_current_inputs_and_excluded_artifacts(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = pathlib.Path(directory)
            source = root / 'Sources'; source.mkdir()
            file = source / 'First.swift'; file.write_text('first')
            initial = provenance(root)
            self.assertIsNone(initial['head'])
            self.assertEqual(initial['tree_sha256'], provenance(root)['tree_sha256'])
            (root / '.build').mkdir(); (root / '.build/cache').write_text('private')
            self.assertEqual(initial['tree_sha256'], provenance(root)['tree_sha256'])
            file.write_text('changed')
            changed = provenance(root)
            self.assertNotEqual(initial['tree_sha256'], changed['tree_sha256'])
            file.chmod(0o755)
            self.assertNotEqual(changed['tree_sha256'], provenance(root)['tree_sha256'])
            added = source / 'Added.swift'; added.write_text('added')
            self.assertEqual(provenance(root)['file_count'], 2)
            added.unlink()
            self.assertEqual(provenance(root)['file_count'], 1)

    def test_links_and_special_files_fail_closed(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = pathlib.Path(directory); (root / 'Sources').mkdir()
            outside = root / 'secret'; outside.write_text('secret')
            link = root / 'Sources/link'; link.symlink_to(outside)
            with self.assertRaises(ValueError): provenance(root)
            link.unlink()
            (root / 'Sources/nested').symlink_to(root, target_is_directory=True)
            with self.assertRaises(ValueError): provenance(root)

if __name__ == '__main__': unittest.main()
