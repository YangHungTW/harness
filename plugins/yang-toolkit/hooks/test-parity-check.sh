#!/usr/bin/env bash
# PostToolUse hook: nudge Claude when production-code is edited without
# touching the corresponding test file in the same session.
#
# Operates by:
#   1. parsing the edited file path from the tool input
#   2. mapping it to one or more "mirror" test file candidates per language
#   3. scanning today's PreToolUse log to see if any mirror was modified
#      in this session by Edit / Write / MultiEdit
#   4. if not, emitting a JSON `additionalContext` + `systemMessage` so the
#      next turn of conversation prompts Claude to update the test
#
# Conservative by design: false positives (extra nudges) are preferable to
# false negatives (silent test rot). bash 3.2 / BSD userland portable.
#
# Opt-out: set HARNESS_DISABLE_TEST_PARITY=1 in your env (repo or global).
# Per-session dedupe: once we warn about a file, we don't warn about it again
# until the next day (state file under .claude/state/).

set -u

# Global opt-out.
[ "${HARNESS_DISABLE_TEST_PARITY:-0}" = "1" ] && exit 0

input="$(cat -)"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
state_dir="${project_dir}/.claude/state"
log_dir="${project_dir}/.claude/logs"
mkdir -p "$state_dir" 2>/dev/null || exit 0

# Need jq for input parsing. If missing, degrade silently -- the reminder
# is a nice-to-have, not a correctness requirement.
command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

# Defensive: matcher should already filter, but double-check.
case "$tool" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

[ -z "$file_path" ] && exit 0

# Make the path repo-relative for both matching and log scanning.
case "$file_path" in
  /*) abs="$file_path" ;;
  *)  abs="${project_dir}/${file_path}" ;;
esac
case "$abs" in
  "${project_dir}/"*) rel="${abs#${project_dir}/}" ;;
  *) exit 0 ;;  # outside project; not our business
esac

# ----- 1. Negative filter: paths where a test mirror doesn't apply. -----
case "$rel" in
  # Tests themselves: don't recurse.
  *_test.go|*.test.ts|*.test.tsx|*.test.js|*.test.jsx) exit 0 ;;
  *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx) exit 0 ;;
  *_spec.rb|*Spec.scala|*Test.java) exit 0 ;;
  spec/*|test/*|tests/*|__tests__/*|spec/**|tests/**) exit 0 ;;
  */spec/*|*/test/*|*/tests/*|*/__tests__/*) exit 0 ;;
  # Things that don't have unit tests by convention.
  db/migrate/*|db/seeds.rb|db/schema.rb) exit 0 ;;
  config/*|.config/*) exit 0 ;;
  app/views/*|app/assets/*|app/javascript/templates/*) exit 0 ;;
  public/*|vendor/*|node_modules/*|dist/*|build/*) exit 0 ;;
  bin/*|script/*) exit 0 ;;
  *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock) exit 0 ;;
  Gemfile|Gemfile.lock|package.json|package-lock.json|yarn.lock|go.mod|go.sum|requirements.txt|Cargo.toml|Cargo.lock) exit 0 ;;
  .env|.env.*|*.env) exit 0 ;;
  *.css|*.scss|*.sass|*.svg|*.png|*.jpg|*.jpeg|*.gif|*.ico) exit 0 ;;
  Dockerfile|docker-compose*.yml|docker-compose*.yaml) exit 0 ;;
esac

# Also skip our own harness state files.
case "$rel" in
  .claude/*|docs/decisions/*) exit 0 ;;
esac

# ----- 2. Build mirror candidates by file extension / path shape. -----
mirrors=""

add_mirror() {
  if [ -z "$mirrors" ]; then mirrors="$1"; else mirrors="${mirrors}|$1"; fi
}

dir_of="${rel%/*}"
base_of="${rel##*/}"
ext="${base_of##*.}"
stem="${base_of%.*}"

# Special-case empty dir_of (top-level file).
[ "$dir_of" = "$base_of" ] && dir_of=""

case "$rel" in
  # Ruby on Rails / Ruby
  app/*.rb)
    rest="${rel#app/}"
    base_no_ext="${rest%.rb}"
    add_mirror "spec/${base_no_ext}_spec.rb"
    add_mirror "test/${base_no_ext}_test.rb"
    ;;
  lib/*.rb)
    rest="${rel#lib/}"
    base_no_ext="${rest%.rb}"
    add_mirror "spec/lib/${base_no_ext}_spec.rb"
    add_mirror "spec/${base_no_ext}_spec.rb"
    add_mirror "test/lib/${base_no_ext}_test.rb"
    ;;
  *.rb)
    # Misc .rb -- guess a same-dir spec sibling.
    [ -n "$dir_of" ] && add_mirror "${dir_of}/${stem}_spec.rb"
    add_mirror "spec/${stem}_spec.rb"
    ;;

  # Go
  *.go)
    base_no_ext="${rel%.go}"
    add_mirror "${base_no_ext}_test.go"
    ;;

  # TypeScript / JavaScript (Jest-style)
  *.ts|*.tsx|*.js|*.jsx)
    base_no_ext="${rel%.${ext}}"
    add_mirror "${base_no_ext}.test.${ext}"
    add_mirror "${base_no_ext}.spec.${ext}"
    # __tests__/ sibling
    if [ -n "$dir_of" ]; then
      add_mirror "${dir_of}/__tests__/${stem}.test.${ext}"
      add_mirror "${dir_of}/__tests__/${stem}.spec.${ext}"
    fi
    ;;

  # Python (pytest layout)
  *.py)
    # Quick filter: already a test? Skip.
    case "$base_of" in
      test_*.py|*_test.py|conftest.py) exit 0 ;;
    esac
    add_mirror "tests/test_${stem}.py"
    [ -n "$dir_of" ] && add_mirror "${dir_of}/test_${stem}.py"
    [ -n "$dir_of" ] && add_mirror "tests/${dir_of}/test_${stem}.py"
    ;;

  # Solidity (Foundry layout)
  *.sol)
    case "$rel" in test/*|src/test/*) exit 0 ;; esac
    add_mirror "test/${stem}.t.sol"
    add_mirror "test/${stem}.test.sol"
    ;;

  # No rule -> exit silently. We deliberately do NOT warn on unknown
  # extensions; users with exotic stacks can extend the rules later.
  *) exit 0 ;;
esac

[ -z "$mirrors" ] && exit 0

# ----- 3. Per-session dedupe: have we already warned about this file today? -----
today="$(date -u +%Y%m%d)"
warned_file="${state_dir}/test-parity-warned-${today}.txt"

if [ -r "$warned_file" ] && grep -F -x -q "$rel" "$warned_file" 2>/dev/null; then
  exit 0
fi

# ----- 4. Scan today's tool-call log for any mirror modification in this session. -----
log_file="${log_dir}/session-${today}.jsonl"
mirror_touched=0

if [ -r "$log_file" ]; then
  # Build a regex of mirror paths (escaped). The PreToolUse log stores
  # tool_input verbatim (possibly absolute path), so check both relative
  # and absolute against the log.
  IFS='|' read -ra mirror_arr <<< "$mirrors"
  for m in "${mirror_arr[@]}"; do
    abs_m="${project_dir}/${m}"
    # Use jq to filter Edit/Write/MultiEdit entries with matching file_path.
    hit="$(jq -r --arg rel "$m" --arg abs "$abs_m" '
      select(.tool == "Edit" or .tool == "Write" or .tool == "MultiEdit")
      | .params.file_path // empty
      | select(. == $rel or . == $abs or endswith("/" + $rel))
    ' "$log_file" 2>/dev/null | head -1)"
    if [ -n "$hit" ]; then
      mirror_touched=1
      break
    fi
  done
fi

[ "$mirror_touched" = "1" ] && exit 0

# ----- 5. Build the reminder and emit JSON. -----
# Show up to 3 mirror candidates so Claude knows what we expected.
preview="$(printf '%s' "$mirrors" | tr '|' '\n' | head -3 | sed 's/^/  - /')"

message="test-parity nudge: \`${rel}\` was modified in this session, but none of its expected test mirrors have been touched. Either edit the relevant test (or add a new test case), or explicitly state why no test change is needed before declaring this task complete.

Expected mirror candidates (in order of likelihood):
${preview}"

# Record that we've now warned about this file.
printf '%s\n' "$rel" >> "$warned_file" 2>/dev/null || true

# Output structured JSON for Claude Code to interpret. Use BOTH
# systemMessage (always shown) and additionalContext (preferred -- injected
# into Claude's next-turn context if the version supports it on PostToolUse).
jq -n -c \
  --arg msg "$message" \
  '{
    suppressOutput: false,
    systemMessage: $msg,
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $msg
    }
  }'

exit 0
