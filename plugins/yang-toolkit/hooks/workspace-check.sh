#!/usr/bin/env bash
# SessionStart hook: when Claude is launched in a *workspace* (a directory that
# is not a git repo but holds several projects, e.g. ~/Projects), tell the model
# the registry's state -- missing, invalid, or which projects it doesn't cover
# yet -- so `/yang-toolkit:go` refreshes it automatically before routing.
# All the logic lives in scripts/workspace/status.sh; rules: references/workspace.md.
#
# Never writes and never builds anything. Silent (exit 0, no output) inside a
# git work tree, with fewer than 2 projects, without jq, or when opted out.
# bash 3.2 / BSD portable. Opt-out: HARNESS_DISABLE_WORKSPACE=1.

set -u

[ "${HARNESS_DISABLE_WORKSPACE:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

plugin="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
rules="$plugin/references/workspace.md"
st="$("$plugin/scripts/workspace/status.sh" "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null)" || exit 0
[ "$(printf '%s' "$st" | jq -r '.workspace' 2>/dev/null)" = true ] || exit 0

# Names come from discover.sh, which already refuses markup/control/bidi names;
# strip < > ` again anyway since this lands in model context.
printf '%s' "$st" | jq -c --arg rules "$rules" '
  def names($xs): ($xs[0:5] | map(gsub("[<>`[:cntrl:]]"; "")) | join(", "))
                  + (if ($xs | length) > 5 then ", ..." else "" end);
  "yang-toolkit workspace: \(.projects) projects"
  + (if .config == "missing" then
       ", not registered yet -- /yang-toolkit:go registers them automatically on first use (same as /yang-toolkit:workspace-init)"
     elif .config == "invalid" then
       ", but .claude/workspace.json is invalid -- /yang-toolkit:go repairs it automatically (same as /yang-toolkit:workspace-init)"
     elif (.unregistered | length) == 0 and (.missing | length) == 0 then
       ", all registered in .claude/workspace.json"
     else
       (if (.unregistered | length) > 0 then ", \(.unregistered | length) unregistered: \(names(.unregistered))" else "" end)
       + (if (.missing | length) > 0 then ", \(.missing | length) registered but missing: \(names(.missing))" else "" end)
       + " -- /yang-toolkit:go refreshes the registry automatically before routing"
     end)
  + " (rules: \($rules))."
  | {hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
exit 0
