#!/usr/bin/env bash
# SubagentStop hook: write the agent type into .claude/state/current-agent.txt
# so statusline + dashboard can show which agent last ran.
# bash 3.2 / BSD portable. Reads JSON event from stdin.

set -u

input="$(cat -)"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
state_dir="${project_dir}/.claude/state"
mkdir -p "$state_dir" 2>/dev/null || exit 0

agent="unknown"
if command -v jq >/dev/null 2>&1; then
  agent="$(printf '%s' "$input" | jq -r '.agent_type // .agent // "unknown"' 2>/dev/null)"
  [ -z "$agent" ] && agent="unknown"
fi

printf '%s\n' "$agent" > "${state_dir}/current-agent.txt" 2>/dev/null || true

exit 0
