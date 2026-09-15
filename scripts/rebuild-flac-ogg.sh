#!/bin/sh
# Controlled FLAC + ogg outputs only; never adopt as part of a build.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec python3 "$SCRIPT_DIR/vendor_rebuild.py" flac-ogg "$@"
