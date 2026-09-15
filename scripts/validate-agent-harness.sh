#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

required_files=(
  "AGENTS.md"
  "docs/.INDEX.md"
  "CONTINUITY.md"
  "ARCHITECTURE.md"
  "TESTING.md"
  "TOOLS.md"
  "NEXT_STEPS.md"
  ".agent/PLANS.md"
  "PARITY.md"
  "REVIEW_CHECKLIST.md"
  "CODE_AUDIT.md"
  "AUDIO_ENGINE.md"
  "docs/QUALITY.md"
  "docs/GOLDEN_PRINCIPLES.md"
  "docs/exec-plans/README.md"
  "docs/UI_PERFORMANCE_ACCEPTANCE.md"
  "docs/CD_HARDWARE_MATRIX.md"
  "Tests/HardwareAudioMatrix.md"
  "Usability/PRODUCT_REQUIREMENTS.md"
  "Usability/AI_TESTER.md"
  "Usability/report.schema.json"
  ".agents/skills/songbird-usability/SKILL.md"
)

required_directories=(
  ".agent"
  ".agents/skills/songbird-usability"
  "docs/exec-plans/active"
  "docs/exec-plans/completed"
  "Usability"
)

markdown_files=(
  "AGENTS.md"
  "docs/.INDEX.md"
  "CONTINUITY.md"
  "ARCHITECTURE.md"
  "TESTING.md"
  "TOOLS.md"
  "NEXT_STEPS.md"
  ".agent/PLANS.md"
  "PARITY.md"
  "REVIEW_CHECKLIST.md"
  "CODE_AUDIT.md"
  "AUDIO_ENGINE.md"
  "docs/QUALITY.md"
  "docs/GOLDEN_PRINCIPLES.md"
  "docs/exec-plans/README.md"
  "docs/UI_PERFORMANCE_ACCEPTANCE.md"
  "docs/CD_HARDWARE_MATRIX.md"
  "Tests/HardwareAudioMatrix.md"
  "Usability/PRODUCT_REQUIREMENTS.md"
  "Usability/AI_TESTER.md"
  ".agents/skills/songbird-usability/SKILL.md"
)

failures=0

fail() {
  print -u2 -- "Agent harness invalid: $1"
  failures=$((failures + 1))
}

for relative_path in "${required_files[@]}"; do
  if [[ ! -f "$ROOT/$relative_path" ]]; then
    fail "missing required file $relative_path."
  fi
done

for relative_path in "${required_directories[@]}"; do
  if [[ ! -d "$ROOT/$relative_path" ]]; then
    fail "missing required directory $relative_path."
  fi
done

if [[ -f "$ROOT/AGENTS.md" ]]; then
  agents_lines="$(wc -l < "$ROOT/AGENTS.md" | tr -d '[:space:]')"
  if (( agents_lines >= 200 )); then
    fail "AGENTS.md has $agents_lines lines; it must stay below 200."
  fi
fi

if (( $# > 0 )); then
  for supplied_path in "$@"; do
    if [[ "$supplied_path" == /* ]]; then
      resolved_supplied_path="$supplied_path"
    else
      resolved_supplied_path="$ROOT/$supplied_path"
    fi
    if [[ ! -f "$resolved_supplied_path" ]]; then
      fail "missing supplied Markdown source $supplied_path."
    else
      markdown_files+=("$resolved_supplied_path")
    fi
  done
fi

extract_markdown_targets() {
  perl -ne '
    if (/^[[:space:]]*(```|~~~)/) {
      $fenced = !$fenced;
      next;
    }
    next if $fenced;
    s/`[^`]*`//g;
    while (/\]\((<[^>]+>|[^)[:space:]]+)(?:[[:space:]]+["'"'"'][^"'"'"']*["'"'"'])?\)/g) {
      print "$1\n";
    }
    if (/^[[:space:]]*\[[^]]+\]:[[:space:]]*(<[^>]+>|[^[:space:]]+)/) {
      print "$1\n";
    }
  ' "$1"
}

for configured_path in "${markdown_files[@]}"; do
  if [[ "$configured_path" == /* ]]; then
    source_path="$configured_path"
    source_label="$configured_path"
  else
    source_path="$ROOT/$configured_path"
    source_label="$configured_path"
  fi

  [[ -f "$source_path" ]] || continue

  while IFS= read -r raw_target; do
    target="${raw_target#<}"
    target="${target%>}"

    case "$target" in
      ""|\#*|http://*|https://*|mailto:*|app://*)
        continue
        ;;
    esac

    target="${target%%\#*}"
    target="${target%%\?*}"
    [[ -n "$target" ]] || continue

    if [[ "$target" == /* ]]; then
      resolved_target="$target"
    else
      resolved_target="${source_path:h}/$target"
    fi

    if [[ ! -e "$resolved_target" ]]; then
      fail "$source_label references missing $target."
    fi
  done < <(extract_markdown_targets "$source_path")
done

if (( failures > 0 )); then
  print -u2 -- "Agent harness validation failed with $failures issue(s)."
  exit 1
fi

print -- "Agent harness valid: ${#required_files[@]} required files, ${#required_directories[@]} required directories, and local Markdown links checked."
