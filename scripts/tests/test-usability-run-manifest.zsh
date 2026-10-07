#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
task_manifest_dir="$(mktemp -d /private/tmp/songbird-run-manifest.XXXXXX)"
task_manifest="$task_manifest_dir/run.json"

write_phase() {
  local phase="$1"
  local error="${2:-}"
  RUN_MANIFEST_PATH="$task_manifest" \
  RUN_ID_VALUE=contract-run RUN_MODE_VALUE=audit RUN_FIXTURE_VALUE=large \
  RUN_FIRST_RUN_VALUE=0 \
  RUN_TRACK_COUNT_VALUE=10000 RUN_PHASE_VALUE="$phase" RUN_ERROR_VALUE="$error" \
  RUN_BUNDLE_ID_VALUE=com.songbird.contract RUN_APP_PID_VALUE=123 \
  RUN_BROKER_PID_VALUE=456 RUN_SESSION_VALUE=/tmp/session \
  RUN_ARTIFACTS_VALUE="$task_manifest_dir" RUN_PARITY_VALUE=1 RUN_SCREEN_VALUE=1 \
  RUN_SOURCE_HEAD_VALUE=abc RUN_SOURCE_STATUS_SHA_VALUE=def \
  RUN_SOURCE_DIFF_SHA_VALUE=ghi RUN_APP_SHA_VALUE=jkl RUN_FIXTURE_SHA_VALUE=mno \
  "$ROOT/scripts/usability/update-run-manifest"
}

write_phase initialized
write_phase failed "AX window unavailable"

/usr/bin/python3 - "$task_manifest" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
assert data["schema_version"] == 3, data
assert data["phase"] == "failed", data
assert data["error"] == "AX window unavailable", data
assert data["requested_large_track_count"] == 10000, data
assert data["package_parity"] is True, data
assert data["source"]["tracked_diff_sha256"] == "ghi", data
assert not path.with_suffix(".json.tmp").exists()
PY

RUN_MANIFEST_PATH="$task_manifest" \
RUN_ID_VALUE=contract-run RUN_MODE_VALUE=audit RUN_FIXTURE_VALUE=standard \
RUN_FIRST_RUN_VALUE=0 RUN_TRACK_COUNT_VALUE=10000 RUN_PHASE_VALUE=prepared RUN_ERROR_VALUE= \
RUN_BUNDLE_ID_VALUE=com.songbird.contract RUN_APP_PID_VALUE=123 RUN_BROKER_PID_VALUE=456 \
RUN_SESSION_VALUE=/tmp/session RUN_ARTIFACTS_VALUE="$task_manifest_dir" \
RUN_PARITY_VALUE=1 RUN_SCREEN_VALUE=1 RUN_APP_SHA_VALUE=jkl RUN_FIXTURE_SHA_VALUE=mno \
RUN_SOURCE_PROVENANCE_VALUE='{"method":"source-tree","tree_sha256":"fixture","file_count":2,"head":null,"status_sha256":null,"tracked_diff_sha256":null}' \
"$ROOT/scripts/usability/update-run-manifest"

/usr/bin/python3 - "$task_manifest" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data['source']['method'] == 'source-tree'
assert data['source']['head'] is None
assert data['source']['tree_sha256'] == 'fixture'
assert data['phase'] == 'prepared'
PY

echo "usability run manifest transitions passed"
