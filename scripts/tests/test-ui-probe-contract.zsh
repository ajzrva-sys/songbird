#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$ROOT/.build/release/SongbirdUIProbe"

[[ -x "$PROBE" ]] || {
  echo "Build SongbirdUIProbe in release mode before running this test." >&2
  exit 2
}

task_probe_dir="$(mktemp -d /private/tmp/songbird-probe-contract.XXXXXX)"
task_probe_pid=""
cleanup() {
  if [[ -n "$task_probe_pid" ]]; then
    kill "$task_probe_pid" 2>/dev/null || true
    wait "$task_probe_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

"$PROBE" serve --safe --directory "$task_probe_dir" \
  --bundle-id com.songbird.player.usability.nonexistent \
  >"$task_probe_dir/server.log" 2>&1 &
task_probe_pid=$!
for _ in {1..50}; do
  [[ -s "$task_probe_dir/server-state.json" ]] && break
  sleep 0.05
done

"$PROBE" client --json --directory "$task_probe_dir" --trace-id 123 \
  observation-diagnostic /tmp/nope >"$task_probe_dir/response.json"

/usr/bin/python3 - "$task_probe_dir" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
state = json.loads((root / "server-state.json").read_text())
response = json.loads((root / "response.json").read_text())
assert state["phase"] == "idle", state
assert response["traceID"] == 123, response
assert response["serverEpoch"] == state["serverEpoch"], (response, state)
assert response["ok"] is True, response
diagnostic = json.loads(response["output"])
assert diagnostic["matchingApplicationCount"] == 0, diagnostic
assert diagnostic["accessibilityTrusted"] is True, diagnostic
PY

test_root="$ROOT/.build/usability/runs/contract/profile"
common_environment=(
  SONGBIRD_USABILITY_PREPARED=1
  SONGBIRD_USABILITY_SESSION=/tmp/songbird-unused-session
  SONGBIRD_USABILITY_ARTIFACTS=/tmp/songbird-unused-artifacts
  SONGBIRD_UI_TEST_ROOT="$test_root"
)
env "${common_environment[@]}" "$ROOT/scripts/usability/ui" \
  validate-selector id=usability.folder.addAndScan | grep -qx allowed
env "${common_environment[@]}" "$ROOT/scripts/usability/ui" \
  validate-selector id=usability.folder.initialImport | grep -qx allowed
if env "${common_environment[@]}" "$ROOT/scripts/usability/ui" \
  validate-selector "Add Folder…" >/dev/null 2>&1; then
  echo "Visible filesystem selectors must remain blocked." >&2
  exit 1
fi
if SONGBIRD_USABILITY_PREPARED=1 SONGBIRD_UI_TEST_ROOT=/tmp/not-songbird \
  "$ROOT/scripts/usability/ui" validate-selector id=usability.folder.addAndScan \
  >/dev/null 2>&1; then
  echo "Disposable folder identifiers require a validated run root." >&2
  exit 1
fi

echo "UI probe envelope, diagnostic, and selector policy passed"
