#!/usr/bin/env bash
# Stop hook: don't let a turn end with a plan stranded in `executing`.
#
# Ported from straw-boss's `dispatched-agent-stop-guard.py`, which blocks an
# in-progress dispatched session from ending a turn without a durable
# checkpoint or a terminal report. Same failure it prevents here: /execute-plan
# sets `status: executing` + current-feature.txt in Step 4, and if the turn ends
# before Step 7 runs, the plan is left claiming to be running, the Execution Log
# never gets written, and the next session inherits a lie that only
# `/status --abandon` clears by hand.
#
# A plan is FINE to leave behind in any terminal state (done/failed) or in
# either PARKED state (awaiting-input/awaiting-auth) -- parking is the
# documented way to stop cleanly on a question. Only bare `executing` is stranded.
#
# Default: nudge (inject context so the next turn closes it out).
# HARNESS_STRICT_CHECKPOINT=1: block the stop, so an unattended /goal or /loop
# run is forced back in to finish Step 7 instead of dying silently.
#
# Opt-out: HARNESS_DISABLE_CHECKPOINT_GUARD=1.
# bash 3.2 / BSD userland portable. Reads the hook JSON event on stdin.

set -u

input="$(cat -)"
[ "${HARNESS_DISABLE_CHECKPOINT_GUARD:-0}" = "1" ] && exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"

# Never fire twice for the same stop: Claude Code re-runs Stop hooks after a
# block, so a second pass with stop_hook_active must fall through or the turn
# can never end.
if command -v jq >/dev/null 2>&1; then
  active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
  [ "$active" = "true" ] && exit 0
fi

# harness_root = MAIN git worktree (plans are durable state). Inlined rather
# than sourced, matching the other hooks -- see references/conventions.md.
harness_root="$project_dir"
if command -v git >/dev/null 2>&1; then
  _main="$(git -C "$project_dir" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
  [ -n "$_main" ] && harness_root="$_main"
fi

state_dir="${project_dir}/.claude/state"
plans_dir="${harness_root}/.claude/plans"
[ -d "$plans_dir" ] || exit 0

# Only a tracked feature can strand a plan. No pointer -> nothing to guard.
current_feature=""
if [ -r "${state_dir}/current-feature.txt" ]; then
  current_feature="$(head -n 1 "${state_dir}/current-feature.txt" 2>/dev/null \
    | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
fi
[ -z "$current_feature" ] && exit 0

plan="${plans_dir}/${current_feature}.md"
[ -r "$plan" ] || exit 0

# Read `status:` from the frontmatter only -- the first one, before the body's
# closing `---`, so a status word inside the plan prose can never match.
status="$(awk '
  NR==1 && $0 ~ /^---[[:space:]]*$/ { infm=1; next }
  infm && $0 ~ /^---[[:space:]]*$/  { exit }
  infm && $0 ~ /^status:[[:space:]]*/ {
    sub(/^status:[[:space:]]*/, "");
    sub(/[[:space:]]*(#.*)?$/, "");
    print; exit
  }
' "$plan" 2>/dev/null)"

[ "$status" = "executing" ] || exit 0

# An Execution Log entry for THIS run is the checkpoint. Its absence is what
# makes the plan stranded rather than merely mid-flight.
log_hint="no '## Execution Log' section has been written"
grep -q '^## Execution Log' "$plan" 2>/dev/null \
  && log_hint="the '## Execution Log' section may be missing this run's entry"

msg="checkpoint guard: plan '${current_feature}' is still \`status: executing\` and ${log_hint}. Before this turn ends, run /yang-toolkit:execute-plan's Step 7 close-out for it: set a terminal status (\`done\`/\`failed\`), or park it (\`awaiting-input\`/\`awaiting-auth\` with a \`waiting:\` block) if it stopped on a question, then append the Execution Log entry and the ledger record, and clear current-feature.txt. Leaving it as \`executing\` strands the plan for the next session."

if [ "${HARNESS_STRICT_CHECKPOINT:-0}" = "1" ]; then
  # Block: Claude Code feeds `reason` back to the model and continues the turn.
  if command -v jq >/dev/null 2>&1; then
    jq -n -c --arg r "$msg" '{decision:"block", reason:$r}'
  else
    printf '{"decision":"block","reason":"checkpoint guard: plan is still executing; run execute-plan Step 7 close-out before ending the turn."}\n'
  fi
  exit 0
fi

# Default: nudge only. Never blocks an interactive turn the user wants to end.
if command -v jq >/dev/null 2>&1; then
  jq -n -c --arg msg "$msg" \
    '{ suppressOutput: false, systemMessage: $msg,
       hookSpecificOutput: { hookEventName: "Stop", additionalContext: $msg } }'
else
  printf '{"suppressOutput":false,"systemMessage":"checkpoint guard: plan %s is still executing; run execute-plan Step 7 close-out."}\n' "$current_feature"
fi

exit 0
