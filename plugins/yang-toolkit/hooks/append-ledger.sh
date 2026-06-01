#!/usr/bin/env bash
# Stop hook: append a session-summary record to .claude/ledger.jsonl
# with outcome="in-progress" (controlled vocabulary). User may correct it later
# via /ledger-append. bash 3.2 / BSD portable. Reads JSON event from stdin.

set -u

input="$(cat -)"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
state_dir="${project_dir}/.claude/state"
log_dir="${project_dir}/.claude/logs"
ledger="${project_dir}/.claude/ledger.jsonl"
mkdir -p "$(dirname "$ledger")" "$state_dir" "$log_dir" 2>/dev/null || exit 0

# Only the Stop hook records when a feature is actively being tracked. If no
# current-feature.txt exists (or it is empty), do NOT append -- this avoids
# polluting the ledger with repo-name noise entries that dashboard/week read.
current_feature=""
if [ -r "${state_dir}/current-feature.txt" ]; then
  current_feature="$(head -n 1 "${state_dir}/current-feature.txt" 2>/dev/null)"
  # Trim leading/trailing whitespace (bash 3.2 / BSD portable).
  current_feature="$(printf '%s' "$current_feature" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
fi
[ -z "$current_feature" ] && exit 0

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
today="$(date -u +%Y%m%d)"
log_file="${log_dir}/session-${today}.jsonl"

# Pull last-known agent from state file (set by SubagentStop hook).
agent="unknown"
if [ -r "${state_dir}/current-agent.txt" ]; then
  agent="$(head -n 1 "${state_dir}/current-agent.txt" 2>/dev/null)"
  [ -z "$agent" ] && agent="unknown"
fi

# Compute lightweight stats from today's tool-call log if it exists.
files=0
tools_json="{}"
if [ -r "$log_file" ] && command -v jq >/dev/null 2>&1; then
  # Count distinct files touched (Read/Write/Edit tools).
  files="$(jq -s '
    [ .[] | select(.tool=="Write" or .tool=="Edit" or .tool=="Read")
          | .params.file_path // empty ] | unique | length
  ' "$log_file" 2>/dev/null)"
  [ -z "$files" ] && files=0

  # Build a histogram of tool names.
  tools_json="$(jq -s -c '
    map(.tool) | group_by(.) | map({key: .[0], value: length}) | from_entries
  ' "$log_file" 2>/dev/null)"
  [ -z "$tools_json" ] && tools_json="{}"
fi

# Feature slug comes from the active feature tracked in state (never repo name).
feature="$current_feature"

# Compose the ledger record. tokens defaults to 0 (unknown) -- Stop hook input
# does not yet expose token counts portably; user can amend via /ledger-append.
if command -v jq >/dev/null 2>&1; then
  jq -n -c \
    --arg ts "$ts" \
    --arg feature "$feature" \
    --arg phase "summary" \
    --arg agent "$agent" \
    --arg outcome "in-progress" \
    --arg source "stop-hook" \
    --argjson files "$files" \
    --argjson tokens 0 \
    --argjson tools "$tools_json" \
    '{ts:$ts, feature:$feature, phase:$phase, agent:$agent, outcome:$outcome, files:$files, tokens:$tokens, tools:$tools, pr:null, commit:null, source:$source}' \
    >> "$ledger" 2>/dev/null || true
else
  printf '{"ts":"%s","feature":"%s","phase":"summary","agent":"%s","outcome":"in-progress","files":%s,"tokens":0,"tools":%s,"pr":null,"commit":null,"source":"stop-hook"}\n' \
    "$ts" "$feature" "$agent" "$files" "$tools_json" >> "$ledger" 2>/dev/null || true
fi

exit 0
