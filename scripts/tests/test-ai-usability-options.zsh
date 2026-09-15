#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/scripts/ai-usability"

expect_success() {
  local expected="$1"
  shift
  local output
  output="$($RUNNER "$@" --validate-options)"
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected '$expected' in: $output" >&2
    exit 1
  }
}

expect_failure() {
  if "$RUNNER" "$@" --validate-options >/dev/null 2>&1; then
    echo "Expected option validation to fail: $*" >&2
    exit 1
  fi
}

expect_success '"fixture":"standard","track_count":10000,"count_was_set":false' \
  --fixture standard
expect_success '"fixture":"empty","track_count":10000,"count_was_set":false' \
  --fixture empty
expect_success '"fixture":"health","track_count":10000,"count_was_set":false' \
  --fixture health
expect_success '"fixture":"large","track_count":10000,"count_was_set":false' \
  --fixture large
expect_success '"fixture":"large","track_count":1234,"count_was_set":true' \
  --fixture large --count 1234
expect_failure --fixture standard --count 2500
expect_success '"fixture":"standard","track_count":10000,"count_was_set":false' \
  --fixture standard --first-run
expect_failure --fixture health --first-run
expect_failure --fixture large --count 0
expect_failure --fixture large --count 50001

echo "ai-usability option validation passed"
