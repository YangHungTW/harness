#!/usr/bin/env bash
# One-call workspace status, shared by hooks/workspace-check.sh and the `go`
# workspace pre-step (rules: references/workspace.md).
#
# Output (one JSON object):
#   {"workspace": bool, "config": "missing"|"invalid"|"ok", "projects": N,
#    "unregistered": [dir...], "missing": [dir...]}
# "workspace" is false inside a git work tree or with fewer than 2 projects; the
# other fields are then empty. "unregistered" = discovered dirs in neither
# projects[].dir nor ignored[]; "missing" = registered/ignored dirs discover no
# longer finds. Read-only. Needs jq. bash 3.2 / BSD portable.
#
# Usage: status.sh [ROOT]      ROOT defaults to ${CLAUDE_PROJECT_DIR:-$PWD}

set -u

root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
root="${root%/}"
here="$(cd "$(dirname "$0")" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "status.sh: jq is required" >&2; exit 1; }

not_ws() {
  jq -cn '{workspace: false, config: "missing", projects: 0, unregistered: [], missing: []}'
  exit 0
}

[ -d "$root" ] || not_ws
if command -v git >/dev/null 2>&1 && git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  not_ws
fi

found="$("$here/discover.sh" "$root" 2>/dev/null | cut -f1)"
n="$(printf '%s\n' "$found" | grep -c . )"
[ "$n" -ge 2 ] || not_ws

valid="$("$here/validate.sh" "$root/.claude/workspace.json" 2>/dev/null)"
case $? in
  0) config=ok ;;
  3) config=missing; valid='{}' ;;
  *) config=invalid; valid='{}' ;;
esac

printf '%s\n' "$found" | grep . | jq -R . | jq -s \
  --arg config "$config" --argjson cfg "$valid" '
  . as $found
  | ([($cfg.projects // [])[] | .dir] + ($cfg.ignored // [])) as $known
  | { workspace: true, config: $config, projects: ($found | length),
      unregistered: (if $config == "ok" then [$found[] | select(. as $d | any($known[]; . == $d) | not)] else [] end),
      missing:      (if $config == "ok" then [$known[] | select(. as $d | any($found[]; . == $d) | not)] else [] end) }'
