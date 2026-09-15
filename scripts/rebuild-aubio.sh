#!/bin/sh
# Non-destructive vendor build; adoption is a separate reviewed operation.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec python3 "$SCRIPT_DIR/vendor_rebuild.py" aubio "$@"
