import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('lastfm_build_config', Path(__file__).parents[1] / 'lastfm_build_config.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class LastFMBuildConfigTests(unittest.TestCase):
    def test_local_configuration_survives_repeated_packaging(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            private = home / '.config/songbird/lastfm-build.plist'
            private.parent.mkdir(parents=True)
            private.write_bytes(plistlib.dumps({'SongbirdLastFMAPIKey': 'c' * 32, 'SongbirdLastFMAPISecret': 'd' * 32}))
            path = home / 'Info.plist'
            for _ in range(2):
                path.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'fixture.app'}))
                self.assertTrue(config.configure(path, {'HOME': temporary}))
                self.assertEqual(plistlib.loads(path.read_bytes())['SongbirdLastFMAPIKey'], 'c' * 32)

    def test_explicit_missing_configuration_fails_without_silently_disabling_sign_in(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'Info.plist'
            before = plistlib.dumps({'CFBundleIdentifier': 'fixture.app'})
            path.write_bytes(before)
            with self.assertRaises(ValueError):
                config.configure(path, {'SONGBIRD_LASTFM_CONFIG': str(Path(temporary) / 'missing.plist')})
            self.assertEqual(path.read_bytes(), before)

    def test_configuration_is_written_before_signing_without_changing_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'Info.plist'
            path.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'fixture.app'}))
            environment = {'SONGBIRD_LASTFM_API_KEY': 'a' * 32, 'SONGBIRD_LASTFM_API_SECRET': 'b' * 32}
            self.assertTrue(config.configure(path, environment))
            info = plistlib.loads(path.read_bytes())
            self.assertEqual(info['CFBundleIdentifier'], 'fixture.app')
            self.assertEqual(info['SongbirdLastFMAPIKey'], 'a' * 32)
            self.assertEqual(info['SongbirdLastFMAPISecret'], 'b' * 32)

    def test_incomplete_configuration_does_not_change_package(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'Info.plist'
            before = plistlib.dumps({'CFBundleIdentifier': 'fixture.app'})
            path.write_bytes(before)
            with self.assertRaises(ValueError):
                config.configure(path, {'SONGBIRD_LASTFM_API_KEY': 'a' * 32})
            self.assertEqual(path.read_bytes(), before)
            self.assertFalse(config.configure(path, {}))
            self.assertEqual(path.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
