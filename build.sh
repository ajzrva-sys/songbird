#!/bin/zsh
# Build Songbird (release) and package Songbird.app.
#
# Usage:
#   ./build.sh                         # → ./Songbird.app
#   ./build.sh /Applications/Songbird.app
#   ./build.sh --open                  # package then launch
#   ./build.sh --open /Applications/Songbird.app
#   ./build.sh --sandbox                 # sandboxed parity candidate
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OPEN=0
APP=""
SANDBOX=0

for arg in "$@"; do
  case "$arg" in
    --open) OPEN=1 ;;
    --sandbox) SANDBOX=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    -*)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
    *)
      APP="$arg"
      ;;
  esac
done

APP="${APP:-$ROOT/Songbird.app}"

cd "$ROOT"

echo "→ Building release…"
swift build -c release

echo "→ Packaging $APP…"
if [[ "$SANDBOX" -eq 1 ]]; then
  "$ROOT/scripts/package-songbird.sh" --sandbox "$APP"
else
  "$ROOT/scripts/package-songbird.sh" "$APP"
fi

if [[ "$OPEN" -eq 1 ]]; then
  killall Songbird 2>/dev/null || true
  echo "→ Opening $APP…"
  open "$APP"
fi

echo "Done: $APP"
