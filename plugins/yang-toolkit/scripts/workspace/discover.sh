#!/usr/bin/env bash
# List the projects inside a workspace directory (e.g. ~/Projects).
#
# A project is a directory carrying a marker: .git (dir or file), .claude/,
# CLAUDE.md, or AGENTS.md. Depth-1 dirs are checked first; a depth-1 dir with no
# marker is descended exactly once (depth 2), so nested layouts such as
# SDESString/SDESString or "ProgramTrading/Program Trading" are found. The scan
# stops at the first marker -- a project's own subdirs are never listed.
#
# Output: one line per project, "<reldir>\t<git|dir>", LC_ALL=C sorted.
# Read-only: never writes, never calls git. bash 3.2 / BSD portable; paths with
# spaces or non-ASCII are safe (glob iteration, no word splitting).
#
# Usage: discover.sh [ROOT]      ROOT defaults to ${CLAUDE_PROJECT_DIR:-$PWD}

set -u

root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
root="${root%/}"
[ -d "$root" ] || { echo "discover.sh: not a directory: $root" >&2; exit 1; }

skip_name() {
  case "$1" in
    .*|node_modules|vendor|.venv|venv|__pycache__) return 0 ;;
  esac
  # Names that can't travel safely: the output is TAB/newline-delimited, and dir
  # names end up in the managed CLAUDE.md block and in hook context, so markup
  # (< > `), control chars, and Unicode line/paragraph separators or bidi
  # overrides are refused here -- validate.sh applies the same rule.
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]<>`]' \
     || printf '%s' "$1" | LC_ALL=C grep -qE "$(printf '\342\200[\250-\256]|\342\201[\246-\251]')"; then
    echo "discover.sh: skipping a dir whose name has control, markup or bidi characters: $(printf '%s' "$1" | LC_ALL=C tr -c '[:alnum:] ._-' '?')" >&2
    return 0
  fi
  return 1
}

# Prints the kind when $1 carries a marker; returns 1 otherwise.
marker_kind() {
  if [ -e "$1/.git" ]; then echo git; return 0; fi
  if [ -d "$1/.claude" ] || [ -f "$1/CLAUDE.md" ] || [ -f "$1/AGENTS.md" ]; then
    echo dir; return 0
  fi
  return 1
}

{
  for d1 in "$root"/*/; do
    [ -d "$d1" ] || continue
    d1="${d1%/}"
    n1="${d1##*/}"
    [ -L "$d1" ] && continue   # never follow a symlinked dir out of the workspace
    skip_name "$n1" && continue
    if kind="$(marker_kind "$d1")"; then
      printf '%s\t%s\n' "$n1" "$kind"
      continue
    fi
    for d2 in "$d1"/*/; do
      [ -d "$d2" ] || continue
      d2="${d2%/}"
      n2="${d2##*/}"
      [ -L "$d2" ] && continue
      skip_name "$n2" && continue
      if kind="$(marker_kind "$d2")"; then
        printf '%s\t%s\n' "$n1/$n2" "$kind"
      fi
    done
  done
} | LC_ALL=C sort

exit 0
