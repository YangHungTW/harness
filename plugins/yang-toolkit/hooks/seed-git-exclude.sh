#!/usr/bin/env bash
# SessionStart hook: teach the *consuming* repo to ignore yang-toolkit's
# transient state, WITHOUT touching its committed .gitignore.
#
# The plugin's hooks write ephemeral files into <project>/.claude/ (state/,
# logs/, sessions/, dashboards, locks). A client repo has no rule for these, so
# they perpetually show up as untracked. This hook appends a marker-delimited
# block to .git/info/exclude -- a LOCAL, per-clone, never-committed ignore list
# -- so `git status` stays clean here without editing files other collaborators
# would see.
#
# Deliberately does NOT ignore .claude/ledger.jsonl or .claude/plans/*.md: those
# are the durable, trackable artifacts.
#
# Idempotent (keyed on a marker line), safe outside a git repo, no jq/stdin
# dependency. bash 3.2 / BSD userland portable. Opt-out: HARNESS_DISABLE_GIT_EXCLUDE=1.

set -u

[ "${HARNESS_DISABLE_GIT_EXCLUDE:-0}" = "1" ] && exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$project_dir" 2>/dev/null || exit 0

# Only act inside a real work tree.
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# info/exclude lives in the common dir (shared across worktrees). Resolve to abs.
gcd="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
[ -z "$gcd" ] && exit 0
case "$gcd" in /*) ;; *) gcd="${project_dir}/${gcd}" ;; esac
exclude="${gcd}/info/exclude"

marker_begin="# >>> yang-toolkit transient state (managed by seed-git-exclude.sh) >>>"
marker_end="# <<< yang-toolkit <<<"

# Already seeded? Nothing to do.
if [ -f "$exclude" ] && grep -Fq "$marker_begin" "$exclude" 2>/dev/null; then
  exit 0
fi

mkdir -p "${gcd}/info" 2>/dev/null || exit 0

# Append our block. Patterns are repo-root-anchored, same syntax as .gitignore.
{
  printf '%s\n' "$marker_begin"
  printf '%s\n' "# Local-only (per clone); safe to delete. Keeps ledger.jsonl + plans/*.md trackable."
  printf '%s\n' "/.claude/sessions/"
  printf '%s\n' "/.claude/logs/"
  printf '%s\n' "/.claude/state/"
  printf '%s\n' "/.claude/dashboard.html"
  printf '%s\n' "/.claude/dashboard-*.html"
  printf '%s\n' "/.claude/dashboard-*.md"
  printf '%s\n' "/.claude/plans/*.html"
  printf '%s\n' "/.claude/scheduled_tasks.lock"
  printf '%s\n' "/.claude/*.lock"
  printf '%s\n' "$marker_end"
} >> "$exclude" 2>/dev/null || exit 0

exit 0
