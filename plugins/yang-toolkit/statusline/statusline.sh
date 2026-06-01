#!/usr/bin/env bash
# yang-toolkit statusline.
# Reads JSON session data from stdin (Claude Code statusline contract).
# Emits a single line: [harness] {agent} . {phase} . {files}f . {tokens}t
# bash 3.2 / BSD userland portable. jq optional.
# Graceful degrade: missing files -> placeholder values, never errors.

set -u

# Consume stdin so the caller doesn't block; we don't use its contents here.
# (The session JSON contains cwd, model, etc.; we rely on CLAUDE_PROJECT_DIR.)
cat - >/dev/null 2>&1 || true

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"

# harness_root = MAIN git worktree, so durable state survives worktree deletion
# and is shared across worktrees. Falls back to project_dir when git is absent
# or this is not a repo. Inlined (not sourced) to keep hooks dependency-free.
harness_root="$project_dir"
if command -v git >/dev/null 2>&1; then
  _main="$(git -C "$project_dir" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
  [ -n "$_main" ] && harness_root="$_main"
fi

state_dir="${project_dir}/.claude/state"
log_dir="${project_dir}/.claude/logs"
ledger="${harness_root}/.claude/ledger.jsonl"

today="$(date -u +%Y%m%d)"
log_file="${log_dir}/session-${today}.jsonl"

agent="-"
if [ -r "${state_dir}/current-agent.txt" ]; then
  a="$(head -n 1 "${state_dir}/current-agent.txt" 2>/dev/null)"
  [ -n "$a" ] && agent="$a"
fi

phase="-"
files="0"
tokens="0"

if command -v jq >/dev/null 2>&1 && [ -r "$ledger" ]; then
  # Last ledger entry gives us the most recent phase/files/tokens.
  last="$(tail -n 1 "$ledger" 2>/dev/null)"
  if [ -n "$last" ]; then
    p="$(printf '%s' "$last" | jq -r '.phase // "-"' 2>/dev/null)"
    f="$(printf '%s' "$last" | jq -r '.files // 0' 2>/dev/null)"
    t="$(printf '%s' "$last" | jq -r '.tokens // 0' 2>/dev/null)"
    [ -n "$p" ] && phase="$p"
    [ -n "$f" ] && files="$f"
    [ -n "$t" ] && tokens="$t"
  fi
fi

# If no ledger yet, fall back to a rough file count from today's tool log.
if [ "$files" = "0" ] && [ -r "$log_file" ] && command -v jq >/dev/null 2>&1; then
  f="$(jq -s '
    [ .[] | select(.tool=="Write" or .tool=="Edit" or .tool=="Read")
          | .params.file_path // empty ] | unique | length
  ' "$log_file" 2>/dev/null)"
  [ -n "$f" ] && files="$f"
fi

# tokens=0 (or empty/unknown) means UNKNOWN, not zero. Render "-" instead of "0".
# files stays numeric ("0f" is fine).
if [ -z "$tokens" ] || [ "$tokens" = "0" ]; then
  tokens="-"
fi

printf '[harness] %s . %s . %sf . %st\n' "$agent" "$phase" "$files" "$tokens"
