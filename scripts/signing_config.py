"""Resolve local packaging identity without publishing keys or relaxing app identity."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def signing_options(environment, run=subprocess.run):
    explicit = environment.get("SONGBIRD_SIGNING_CONFIG")
    override = environment.get("SONGBIRD_SIGNING_IDENTITY")
    config = {}
    if override is not None:
        config["identity"] = override
    else:
        root = Path(environment.get("XDG_CONFIG_HOME", str(Path(environment.get("HOME", "~")) / ".config")))
        path = Path(explicit) if explicit else root / "songbird/code-signing.json"
        if not path.exists() and not explicit:
            return ["--sign", "-", "--timestamp=none"]
        try:
            config = json.loads(path.read_text())
        except (OSError, ValueError):
            raise ValueError("Could not read local code-signing configuration.") from None
    if not isinstance(config, dict):
        raise ValueError("Code-signing configuration must be an object.")
    identity = config.get("identity", "")
    if not isinstance(identity, str) or not (identity == "-" or re.fullmatch(r"[0-9a-fA-F]{40}", identity)):
        raise ValueError("Code-signing identity must be a certificate SHA-1 fingerprint or '-'.")
    options = ["--sign", identity, "--timestamp=none"]
    keychain = config.get("keychain")
    password_file = config.get("password_file")
    if password_file and not keychain:
        raise ValueError("A signing password file requires an explicit build keychain.")
    if keychain:
        if identity == "-" or not isinstance(keychain, str) or "\n" in keychain or not Path(keychain).is_absolute() or not Path(keychain).is_file():
            raise ValueError("The configured signing keychain is unavailable or invalid.")
        options += ["--keychain", keychain]
    if password_file:
        try:
            path = Path(password_file)
            if not path.is_absolute() or path.stat().st_mode & 0o077:
                raise ValueError("The build-keychain password file must be private (mode 0600).")
            password = path.read_text().strip()
            if not password:
                raise ValueError("The build-keychain password file is empty.")
        except (OSError, TypeError):
            raise ValueError("Could not read the build-keychain password file.") from None
        result = run(["/usr/bin/security", "unlock-keychain", "-p", password, keychain], capture_output=True)
        if result.returncode:
            # Never include command arguments or Security output containing private data.
            raise ValueError("Could not unlock the configured build keychain; signing stopped.")
    return options


if __name__ == "__main__":
    try:
        print("\n".join(signing_options(os.environ)))
    except ValueError as error:
        raise SystemExit(str(error))
