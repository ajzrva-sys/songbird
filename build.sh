#!/bin/zsh
# Build Songbird (release) and package Songbird.app.
#
# Usage:
#   ./build.sh                         # package ./Songbird.app and reveal in Finder
#   ./build.sh /Applications/Songbird.app
#   ./build.sh --open                  # package then launch
#   ./build.sh --open /Applications/Songbird.app
#   ./build.sh --sandbox                 # sandboxed parity candidate
#   ./build.sh --no-reveal              # package without opening Finder
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OPEN=0
REVEAL=1
APP=""
SANDBOX=0

for arg in "$@"; do
  case "$arg" in
    --open) OPEN=1 ;;
    --no-reveal) REVEAL=0 ;;
    --sandbox) SANDBOX=1 ;;
    -h|--help)
      sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d'
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
swift_build_arguments=(-c release)
if [[ -n "${CLANG_MODULE_CACHE_PATH:-}" ]]; then
  swift_build_arguments+=(-Xcc "-fmodules-cache-path=$CLANG_MODULE_CACHE_PATH")
fi
swift build "${swift_build_arguments[@]}"

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
if [[ "$REVEAL" -eq 1 ]]; then
  echo "→ Showing the finished app in Finder…"
  if ! open -R "$APP"; then
    echo "Finder could not reveal the app. It is ready at: $APP" >&2
  fi
fi
