#!/usr/bin/env bash
# PreToolUse hook: append one JSONL line per tool call to the client repo's session log.
# bash 3.2 / BSD userland portable. Reads JSON event from stdin.
# Graceful: never blocks the tool call (always exits 0, never writes to stderr loudly).

set -u

input="$(cat -)"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
log_dir="${project_dir}/.claude/logs"
state_dir="${project_dir}/.claude/state"
mkdir -p "$log_dir" "$state_dir" 2>/dev/null || exit 0

today="$(date -u +%Y%m%d)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log_file="${log_dir}/session-${today}.jsonl"

# Best-effort extract tool name + a compact param summary using jq if present.
tool="unknown"
params_summary="{}"
if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // "unknown"' 2>/dev/null)"
  # Keep params summary small; full params can be huge.
  params_summary="$(printf '%s' "$input" | jq -c '
    .tool_input
    | if type == "object" then
        with_entries(.value |= (if type == "string" then (.[0:120]) else . end))
      else . end
  ' 2>/dev/null)"
  [ -z "$params_summary" ] && params_summary="{}"
fi

# Build the log line without jq dependency for the wrapper itself.
printf '{"ts":"%s","tool":"%s","params":%s}\n' \
  "$ts" "$tool" "$params_summary" >> "$log_file" 2>/dev/null || true

exit 0
