#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
COMMAND="${1:-quick}"
shift || true

case "$COMMAND" in
  quick)
    cd "$ROOT"
    swift test "$@"
    ;;
  usability)
    MODE="audit"
    if [[ "${1:-}" == "--repair" ]]; then MODE="repair"; shift; fi
    for fixture in empty standard large; do
      "$ROOT/scripts/ai-usability" "$MODE" --fixture "$fixture" "$@"
    done
    ;;
  usability-smoke)
    "$ROOT/scripts/ai-usability" audit --fixture standard --prepare-only "$@"
    ;;
  *)
    echo "Usage: ./check.sh quick | usability [--repair] | usability-smoke" >&2
    exit 2
    ;;
esac

