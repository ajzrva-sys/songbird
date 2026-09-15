"""Apply the maintainer's Last.fm application identity before signing a package."""
import os
from pathlib import Path
import plistlib
import re
import sys


def configure(plist_path, environment):
    key = environment.get("SONGBIRD_LASTFM_API_KEY", "").strip()
    secret = environment.get("SONGBIRD_LASTFM_API_SECRET", "").strip()
    if not key and not secret:
        explicit = environment.get("SONGBIRD_LASTFM_CONFIG")
        config_path = Path(explicit) if explicit else None
        if config_path is None and environment.get("HOME"):
            config_root = Path(environment.get("XDG_CONFIG_HOME", str(Path(environment["HOME"]) / ".config")))
            config_path = config_root / "songbird/lastfm-build.plist"
        if config_path is None or (not explicit and not config_path.exists()):
            return False
        try:
            saved = plistlib.loads(config_path.read_bytes())
            key = saved["SongbirdLastFMAPIKey"].strip()
            secret = saved["SongbirdLastFMAPISecret"].strip()
        except (OSError, ValueError, KeyError, AttributeError, TypeError):
            raise ValueError("Could not read the local Last.fm build configuration.") from None
    if not all(re.fullmatch(r"[0-9a-fA-F]{32}", value) for value in (key, secret)):
        raise ValueError("Last.fm packaging requires both valid application credentials.")
    path = Path(plist_path)
    data = plistlib.loads(path.read_bytes())
    data["SongbirdLastFMAPIKey"] = key
    data["SongbirdLastFMAPISecret"] = secret
    path.write_bytes(plistlib.dumps(data, sort_keys=False))
    return True


if __name__ == "__main__":
    try:
        configured = configure(sys.argv[1], os.environ)
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
    print("Last.fm application configured." if configured else
          "Last.fm: no packaged application identity; existing saved credentials remain usable.")
