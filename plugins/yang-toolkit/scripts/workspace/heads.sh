#!/usr/bin/env bash
# Print the head of each project's own instruction file, in ONE call, as quoted
# data (rules: references/workspace.md, "Trust boundary").
#
# For each DIR (relative to ROOT): the first 60 lines (at most 16 KiB, lines cut
# at 400 bytes) of the first existing CLAUDE.md / AGENTS.md / README.md / README
# -- CLAUDE.md is preferred -- with control, bidi, zero-width and BOM characters
# stripped and every line prefixed with "| ", under a "=== <dir> (<file>)" header.
# Symlinks are never followed out of ROOT: a symlinked instruction file, or a dir
# that resolves outside ROOT, is refused (a hostile clone could point CLAUDE.md
# at ~/.ssh/id_rsa).
#
# Using this instead of the Read tool matters: Read on a file inside a project
# makes Claude Code load that project's CLAUDE.md as memory (instructions); this
# prints plain output and loads nothing. Read-only. bash 3.2 / BSD portable.
#
# Usage: heads.sh ROOT DIR [DIR...]

set -u

[ $# -ge 2 ] || { echo "usage: heads.sh ROOT DIR [DIR...]" >&2; exit 2; }
root="${1%/}"; shift
[ -d "$root" ] || { echo "heads.sh: not a directory: $root" >&2; exit 1; }
real_root="$(cd -P "$root" && pwd -P)"

# U+200B-200F, U+2028-202E, U+2060, U+2066-2069, U+FEFF as UTF-8 byte patterns.
invisible="$(printf '\342\200[\213-\217\250-\256]|\342\201[\240\246-\251]|\357\273\277')"

label() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177<>`'; }

for d in "$@"; do
  shown="$(label "$d")"
  case "/$d/" in
    //*|*/../*|*/./*) echo "=== $shown (refused: must be a relative path without . or ..)"; continue ;;
  esac
  p="$root/$d"
  if [ ! -d "$p" ]; then echo "=== $shown (not found)"; continue; fi
  real_p="$(cd -P "$p" 2>/dev/null && pwd -P)"
  case "$real_p/" in
    "$real_root"/*) ;;
    *) echo "=== $shown (refused: resolves outside the workspace)"; continue ;;
  esac
  f=""
  for c in CLAUDE.md AGENTS.md README.md README readme.md; do
    [ -e "$p/$c" ] || [ -L "$p/$c" ] || continue
    if [ -L "$p/$c" ]; then echo "=== $shown ($c refused: symlink)"; f="-"; break; fi
    [ -f "$p/$c" ] && { f="$c"; break; }
  done
  [ "$f" = "-" ] && continue
  if [ -z "$f" ]; then echo "=== $shown (no instruction file)"; continue; fi
  echo "=== $shown ($f)"
  head -c 16384 -- "$p/$f" | head -n 60 | LC_ALL=C tr -d '\000-\010\013-\037\177' \
    | LC_ALL=C sed -E "s/$invisible//g" | LC_ALL=C cut -c1-400 | sed 's/^/| /'
done
exit 0
