#!/usr/bin/env bash
# UserPromptSubmit hook: reset .claude/state/current-agent.txt to "main" at the
# start of each user turn, so statusline + dashboard + Stop hook don't show a
# stale subagent name after a SubagentStop. A SubagentStop within this turn can
# still overwrite it via update-current-agent.sh.
# bash 3.2 / BSD portable. Reads JSON event from stdin (not used).

set -u

cat - >/dev/null 2>&1 || true

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
state_dir="${project_dir}/.claude/state"
mkdir -p "$state_dir" 2>/dev/null || exit 0

printf '%s\n' "main" > "${state_dir}/current-agent.txt" 2>/dev/null || true

exit 0
