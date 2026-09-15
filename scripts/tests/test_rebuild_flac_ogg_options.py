"""Shared boundary plus exact approved Xiph source imports."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest
import test_rebuild_aubio_options as aubio

SOURCE = aubio.SOURCE

class FlacOptionsTests(aubio.AubioOptionsTests):
    script = 'rebuild-flac-ogg.sh'

    def setUp(self):
        super().setUp()
        shutil.copytree(SOURCE/'Vendor/FLAC/source', self.root/'Vendor/FLAC/source')
        (self.root/'publication').mkdir()
        shutil.copy2(SOURCE/'publication/vendor-source-imports.json', self.root/'publication/vendor-source-imports.json')
        self.vendor = self.root/'Vendor/FLAC/libFLAC.14.dylib'
        self.vendor.write_bytes(b'original sentinel, not a library')

    def options(self):
        return super().options()+['--source-dir', str(self.root/'Vendor/FLAC/source')]

    def test_source_is_explicit_and_exact_before_any_build_tool(self):
        r = self.run_script('--validate-options', *super().options())
        self.assertNotEqual(r.returncode, 0, 'implicit source accepted')
        source = self.root/'Vendor/FLAC/source/flac/src/libFLAC/stream_decoder.c'
        source.write_bytes(source.read_bytes()+b'\n/* changed input */\n')
        r = self.run_script('--validate-options', *self.options())
        self.assertNotEqual(r.returncode, 0, 'altered authenticated source accepted')
        self.assertIn('source inventory mismatch', r.stdout)
        self.assertFalse(self.calls.exists())

class FlacSourceTests(unittest.TestCase):
    def test_complete_archive_import_retains_all_notices_and_bytes(self):
        ledger = json.loads((SOURCE/'publication/vendor-source-imports.json').read_text())
        for item in ledger['imports']:
            root = SOURCE/item['root']
            files = {p.relative_to(root).as_posix():p for p in root.rglob('*') if p.is_file()}
            self.assertEqual(set(files), {r['path'] for r in item['files']})
            self.assertEqual(item['omissions'], [])
            self.assertEqual(item['modifications'], [])
            for row in item['files']:
                p = files[row['path']]
                self.assertFalse(p.is_symlink())
                self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(), row['sha256'], row['path'])
            notices = ['COPYING.Xiph','COPYING.GPL','COPYING.LGPL','COPYING.FDL'] if item['component']=='flac' else ['COPYING']
            for name in notices:
                self.assertIn(name, files)

class ActualFlacBuildTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('SONGBIRD_REBUILD_RUN'), 'explicit external integration evidence root required')
    def test_actual_pair_uses_only_controlled_ogg_with_retained_receipts(self):
        run = Path(os.environ['SONGBIRD_REBUILD_RUN'])
        before = {n:hashlib.sha256((SOURCE/'Vendor/FLAC'/n).read_bytes()).hexdigest() for n in ['libFLAC.14.dylib','libogg.0.dylib']}
        env = dict(os.environ, CFLAGS='-I/host-leak-should-not-be-used', CPATH='/host-leak-should-not-be-used',
                   PKG_CONFIG_PATH='/host-leak-should-not-be-used', CMAKE_PREFIX_PATH='/host-leak-should-not-be-used')
        r = subprocess.run([str(SOURCE/'scripts/rebuild-flac-ogg.sh'), '--source-dir', str(SOURCE/'Vendor/FLAC/source'),
                            '--output-dir', str(run/'flac-ogg-output'), '--evidence-dir', str(run/'flac-ogg-evidence')],
                           env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(r.returncode, 0, r.stdout)
        ev = run/'flac-ogg-evidence'
        receipt = json.loads((ev/'receipt.json').read_text())
        self.assertEqual(receipt['status'], 'built-not-adopted')
        self.assertEqual(len(receipt['outputs']), 2)
        self.assertIn('install_stages', receipt, 'CMake install-name transformations lack pre/post receipts')
        self.assertEqual(len(receipt['install_stages']), 2)
        for stage in receipt['install_stages']:
            self.assertEqual(hashlib.sha256(Path(stage['pre']['path']).read_bytes()).hexdigest(), stage['pre']['sha256'])
            self.assertEqual(hashlib.sha256(Path(stage['post']['path']).read_bytes()).hexdigest(), stage['post']['sha256'])
            self.assertIn('load_commands', stage['pre'])
            self.assertIn('load_commands', stage['post'])
        for output in receipt['outputs']:
            p = Path(output['post']['path'])
            self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(), output['post']['sha256'])
            self.assertEqual(output['post']['archs'].strip(), 'arm64')
            self.assertIn('minos 14.0', output['post']['build_version'])
            self.assertEqual(hashlib.sha256((SOURCE/'Vendor/FLAC'/p.name).read_bytes()).hexdigest(), before[p.name])
        cache = (ev/'flac-build/CMakeCache.txt').read_text()
        self.assertIn('OGG_INCLUDE_DIR:PATH='+str(ev/'ogg-stage/include'), cache)
        self.assertIn('OGG_LIBRARY:FILEPATH='+str(ev/'ogg-stage/lib/libogg.dylib'), cache)
        compile_commands = (ev/'flac-build/compile_commands.json').read_text()
        self.assertIn(str(ev/'ogg-stage/include'), compile_commands)
        self.assertNotIn('host-leak', compile_commands)
        self.assertNotIn('host-leak', (ev/'environment.json').read_text())
        self.assertEqual(receipt['ogg_linkage']['staged_sha256'], receipt['outputs'][0]['post']['sha256'])
        self.assertTrue((ev/'ogg-build/include/ogg/config_types.h').is_file())
        self.assertTrue((ev/'flac-build/config.h').is_file())

if __name__ == '__main__':
    unittest.main()
