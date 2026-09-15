"""Exercise real entry points only in disposable script-root fixtures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2]

class AubioOptionsTests(unittest.TestCase):
    script = 'rebuild-aubio.sh'
    source_args = []

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='songbird-rebuild-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / 'project'
        shutil.copytree(SOURCE / 'scripts', self.root / 'scripts')
        shutil.copytree(SOURCE / 'Vendor/aubio/src', self.root / 'Vendor/aubio/src')
        self.vendor = self.root / 'Vendor/aubio/libaubio.5.dylib'
        self.vendor.write_bytes(b'original sentinel, not a library')
        self.bin = self.base / 'bin'; self.bin.mkdir()
        self.calls = self.base / 'compiler-called'
        for name in ['cmake', 'clang', 'clang++', 'install_name_tool', 'otool', 'vtool', 'file']:
            p = self.bin / name
            p.write_text('#!/bin/sh\nprintf "%s\\n" "$0 $*" >> "$CALLS"\n')
            p.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin)+':/usr/bin:/bin', CALLS=str(self.calls), PYTHONDONTWRITEBYTECODE='1')

    def run_script(self, *args):
        return subprocess.run(['/bin/zsh', str(self.root/'scripts'/self.script), *args], env=self.env,
                              cwd=self.base, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def options(self):
        return ['--output-dir', str(self.base/'outputs'), '--evidence-dir', str(self.base/'evidence')]

    def test_validate_options_is_non_mutating_without_tool_discovery(self):
        result = self.run_script('--validate-options', *self.options())
        self.assertFalse(self.calls.exists(), 'option validation invoked a build or inspection tool: '+result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.vendor.read_bytes(), b'original sentinel, not a library')
        self.assertFalse((self.base/'outputs').exists())
        self.assertFalse((self.base/'evidence').exists())

    def test_unsafe_destinations_fail_before_tools_or_writes(self):
        existing = self.base/'existing'; existing.mkdir()
        link = self.base/'alias'; link.symlink_to(existing, target_is_directory=True)
        invalid = [
            [], ['--output-dir', str(self.base/'out')],
            ['--output-dir', 'relative', '--evidence-dir', str(self.base/'ev')],
            ['--output-dir', str(existing), '--evidence-dir', str(self.base/'ev')],
            ['--output-dir', str(self.root/'new'), '--evidence-dir', str(self.base/'ev')],
            ['--output-dir', str(self.base/'out'), '--evidence-dir', str(self.base/'out')],
            ['--output-dir', str(self.base/'out'), '--evidence-dir', str(self.base/'out/ev')],
            ['--output-dir', str(link/'out'), '--evidence-dir', str(self.base/'ev')],
            ['--output-dir', str(self.base/'missing/out'), '--evidence-dir', str(self.base/'ev')],
            ['--output-dir', str(self.base)+'/existing/../out', '--evidence-dir', str(self.base/'ev')],
            self.options()+['--source-dir', str(self.base/'missing')],
            self.options()+['--source-dir', 'relative'],
        ]
        for args in invalid:
            with self.subTest(args=args):
                for prefix in [[], ['--validate-options']]:
                    r = self.run_script(*prefix, *args)
                    self.assertNotEqual(r.returncode, 0, 'unsafe arguments accepted: '+str(args))
                    self.assertFalse(self.calls.exists())
        self.assertEqual(self.vendor.read_bytes(), b'original sentinel, not a library')

    def test_reviewed_adoption_requires_exact_hash_and_new_external_backup(self):
        reviewed = self.base/self.vendor.name; reviewed.write_bytes(b'explicit reviewed sentinel')
        expected = hashlib.sha256(reviewed.read_bytes()).hexdigest()
        backup = self.base/'backup'
        valid = ['--install-reviewed-output', str(reviewed), '--expected-sha256', expected, '--backup-dir', str(backup)]
        bad = [valid[:2], valid[:3]+['0'*64]+valid[4:], valid[:-1]+[str(self.root/'backup')],
               valid+['--output-dir', str(self.base/'out')]]
        for args in bad:
            r = self.run_script(*args)
            self.assertNotEqual(r.returncode, 0, r.stdout)
            self.assertEqual(self.vendor.read_bytes(), b'original sentinel, not a library')
            self.assertFalse(backup.exists())
        result = self.run_script(*valid)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.vendor.read_bytes(), reviewed.read_bytes())
        self.assertEqual((backup/self.vendor.name).read_bytes(), b'original sentinel, not a library')
        receipt = json.loads((backup/'adoption.json').read_text())
        self.assertEqual(receipt['after_sha256'], expected)
        self.assertNotEqual(self.run_script(*valid).returncode, 0, 'reused backup accepted')
        self.assertFalse(self.calls.exists())

class ActualAubioBuildTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('SONGBIRD_REBUILD_RUN'), 'explicit external integration evidence root required')
    def test_actual_build_preserves_vendor_and_records_complete_inputs(self):
        run = Path(os.environ['SONGBIRD_REBUILD_RUN'])
        vendor = SOURCE/'Vendor/aubio/libaubio.5.dylib'
        before = hashlib.sha256(vendor.read_bytes()).hexdigest()
        r = subprocess.run([str(SOURCE/'scripts/rebuild-aubio.sh'), '--output-dir', str(run/'aubio-output'),
                            '--evidence-dir', str(run/'aubio-evidence')], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertEqual(hashlib.sha256(vendor.read_bytes()).hexdigest(), before)
        evidence = run/'aubio-evidence'
        receipt = json.loads((evidence/'receipt.json').read_text())
        self.assertEqual(receipt['status'], 'built-not-adopted')
        output = run/'aubio-output/libaubio.5.dylib'
        self.assertEqual(hashlib.sha256(output.read_bytes()).hexdigest(), receipt['outputs'][0]['post']['sha256'])
        self.assertTrue((evidence/'aubio-build/compile_commands.json').is_file())
        self.assertTrue((evidence/'aubio-build/config.h').is_file())
        self.assertTrue((evidence/'commands.jsonl').is_file())
        self.assertTrue((evidence/'source-inputs.json').is_file())
        self.assertTrue((evidence/'environment.json').is_file())
        self.assertEqual(receipt['outputs'][0]['post']['archs'].strip(), 'arm64')
        self.assertIn('minos 14.0', receipt['outputs'][0]['post']['build_version'])

import hashlib
import json

if __name__ == '__main__':
    unittest.main()
