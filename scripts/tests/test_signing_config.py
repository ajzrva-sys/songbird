import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location('signing_config', Path(__file__).parents[1] / 'signing_config.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningConfigTests(unittest.TestCase):
    def test_unconfigured_builds_remain_adhoc(self):
        with tempfile.TemporaryDirectory() as home:
            self.assertEqual(signing.signing_options({'HOME': home}), ['--sign', '-', '--timestamp=none'])

    def test_explicit_broken_config_never_falls_back(self):
        with tempfile.TemporaryDirectory() as home:
            with self.assertRaises(ValueError):
                signing.signing_options({'SONGBIRD_SIGNING_CONFIG': str(Path(home) / 'absent.json')})

    def test_stable_identity_and_private_keychain_used_on_every_build(self):
        with tempfile.TemporaryDirectory() as home:
            root = Path(home)
            config = root / '.config/songbird/code-signing.json'
            config.parent.mkdir(parents=True)
            keychain = root / 'build.keychain-db'
            keychain.touch()
            password = root / 'password'
            password.write_text('synthetic-password')
            password.chmod(0o600)
            config.write_text(json.dumps(dict(identity='a' * 40, keychain=str(keychain), password_file=str(password))))
            calls = []
            def run(args, **kwargs):
                calls.append(args)
                return SimpleNamespace(returncode=0)
            for _ in range(2):
                options = signing.signing_options({'HOME': home}, run)
                self.assertEqual(options, ['--sign', 'a' * 40, '--timestamp=none', '--keychain', str(keychain)])
                self.assertNotIn('synthetic-password', options)
            self.assertEqual(len(calls), 2)
            password.chmod(0o644)
            with self.assertRaises(ValueError):
                signing.signing_options({'HOME': home}, run)

    def test_unlock_failure_is_sanitized_and_fatal(self):
        with tempfile.TemporaryDirectory() as home:
            root = Path(home)
            keychain = root / 'build.keychain-db'
            keychain.touch()
            password = root / 'password'
            password.write_text('synthetic-password')
            password.chmod(0o600)
            config = root / 'sign.json'
            config.write_text(json.dumps(dict(identity='a' * 40, keychain=str(keychain), password_file=str(password))))
            with self.assertRaisesRegex(ValueError, 'Could not unlock') as caught:
                signing.signing_options({'SONGBIRD_SIGNING_CONFIG': str(config)}, lambda *args, **kwargs: SimpleNamespace(returncode=1, stderr=b'synthetic-password'))
            self.assertNotIn('synthetic-password', str(caught.exception))

    def test_override_and_invalid_identity(self):
        self.assertEqual(signing.signing_options({'SONGBIRD_SIGNING_IDENTITY': '-'}), ['--sign', '-', '--timestamp=none'])
        for identity in ('', 'unstable-name', 'a' * 40 + '\n--anything'):
            with self.assertRaises(ValueError):
                signing.signing_options({'SONGBIRD_SIGNING_IDENTITY': identity})


if __name__ == '__main__':
    unittest.main()
