#!/usr/bin/env bash
# Propose a workspace.json for a workspace directory, from structure only.
#
# Every field comes from something a script can check: the dir name, the
# manifest name, the README/CLAUDE.md H1 split into short tokens, and a small
# rule table for risk. Prose below the H1 is never read, so a README body can't
# end up in the proposal. /yang-toolkit:workspace-init writes the result (plus
# agent-chosen aliases, under the same alias.jq rules) without asking.
#
# Output: proposed workspace.json on stdout. Writes nothing. Needs jq.
# bash 3.2 / BSD portable.
#
# Usage: propose.sh [ROOT]      ROOT defaults to ${CLAUDE_PROJECT_DIR:-$PWD}

set -u

root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
root="${root%/}"
here="$(cd "$(dirname "$0")" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "propose.sh: jq is required" >&2; exit 1; }
[ -d "$root" ] || { echo "propose.sh: not a directory: $root" >&2; exit 1; }

bom="$(printf '\357\273\277')"

# First H1 of README/CLAUDE/AGENTS that is not just the file's own name.
# Tolerates a UTF-8 BOM and CRLF line endings.
first_h1() {
  for f in README.md readme.md README CLAUDE.md AGENTS.md; do
    [ -f "$1/$f" ] || continue
    h="$(LC_ALL=C sed -n "1s/^$bom//; /^# /{s/^# *//;p;q;}" "$1/$f" 2>/dev/null | tr -d '\r')"
    case "$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')" in
      ''|claude.md|readme|readme.md|agents.md) continue ;;
    esac
    printf '%s' "$h"
    return 0
  done
}

manifest_name() {
  if [ -f "$1/package.json" ]; then
    n="$(jq -r '.name | strings' "$1/package.json" 2>/dev/null)"
    [ -n "$n" ] && { printf '%s' "$n"; return 0; }
  fi
  if [ -f "$1/pyproject.toml" ]; then
    grep -m1 -E '^name *= *"' "$1/pyproject.toml" 2>/dev/null | sed -E 's/^name *= *"([^"]*)".*/\1/'
  fi
}

manifests() {
  find "$1" -maxdepth 2 \( -name node_modules -o -name .git -o -name .venv \) -prune -o \
    -type f \( -name package.json -o -name pyproject.toml -o -name 'requirements*.txt' \) -print0 2>/dev/null
}

# True only when grep actually names a matching file. (`xargs grep -q` is not
# enough: BSD xargs runs nothing on empty input and still exits 0.)
any_match() {
  xargs -0 grep -liE "$1" 2>/dev/null | grep -q .
}

risk_tags() {
  p="$1"
  if manifests "$p" | any_match '(shioaji|ccxt|ib[_-]insync|alpaca|fubon|yuanta)'; then
    echo live-money
  fi
  if find "$p" -maxdepth 4 \( -name node_modules -o -name .git -o -name .venv \) -prune -o \
       -type f -iname '*schema*' -print0 2>/dev/null \
     | any_match '(student|guardian|patient|national_id|身分證)'; then
    echo pii
  fi
  deploy=""
  for f in vercel.json fly.toml netlify.toml render.yaml Procfile; do
    [ -f "$p/$f" ] && deploy=1
  done
  [ -d "$p/.vercel" ] && deploy=1
  for f in "$p"/.github/workflows/*deploy*; do
    [ -f "$f" ] && deploy=1
  done
  [ -n "$deploy" ] && echo prod-deploy
  return 0
}

local_files() {
  for f in "$1"/.env "$1"/.env.*; do
    [ -f "$f" ] || continue
    b="${f##*/}"
    case "$b" in *.example|*.sample|*.template|*.dist|*.bak|*.old|*.orig) continue ;; esac
    printf '%s' "$b" | LC_ALL=C grep -q '[[:cntrl:]<>`]' && continue
    echo "$b"
  done
}

has_code() {
  [ -n "$(find "$1" -maxdepth 3 \( -name node_modules -o -name .git -o -name .venv \) -prune -o -type f \
    \( -name package.json -o -name pyproject.toml -o -name 'requirements*.txt' -o -name Gemfile \
       -o -name go.mod -o -name Cargo.toml -o -name composer.json \
       -o -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.rb' \
       -o -name '*.go' -o -name '*.rs' -o -name '*.php' -o -name '*.swift' -o -name '*.kt' \) \
    -print 2>/dev/null | head -1)" ]
}

"$here/discover.sh" "$root" | while IFS="$(printf '\t')" read -r rel kind; do
  [ -n "$rel" ] || continue
  p="$root/$rel"
  if [ "$kind" = "dir" ] && ! has_code "$p"; then
    jq -cn --arg dir "$rel" '{ignored: $dir}'
    continue
  fi
  jq -L "$here" -cn \
    --arg dir "$rel" \
    --arg base "${rel##*/}" \
    --arg mname "$(manifest_name "$p")" \
    --arg h1 "$(first_h1 "$p")" \
    --arg risk "$(risk_tags "$p")" \
    --arg envs "$(local_files "$p")" '
    include "alias";
    def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | ltrimstr("-") | rtrimstr("-");
    def lines: split("\n") | map(select(length > 0));
    # Filenames, stopwords and single chars say nothing about a project.
    def informative: ascii_downcase
      | (test("^(claude\\.md|readme(\\.md)?|agents\\.md)$")
         or test("^(a|an|and|or|the|of|for|to|in|on|with|app|project|english)$")
         or test("^[a-z0-9]$"))
      | not;
    # Seeds, all shaped by alias.jq so validate.sh never refuses them: the
    # cleaned basename (exempt from the deny list -- it is the folder name), the
    # manifest name and H1 tokens (both must pass the full alias rules). If all
    # of them clean away (e.g. an all-space dir name), fall back to the slug,
    # then "project" -- match is never empty.
    ($base | alias_clean) as $seed
    | ([$seed] | map(select(length > 0)))
      + ([$mname | alias_clean] | map(select(length >= 2 and informative and alias_ok([]))))
      + ($h1 | [splits("[\\s—–:：,，、;；()（）\\[\\]|/+＋]+")]
             | map(alias_clean | select(length > 0 and informative and alias_ok([]))) | .[0:6])
    | reduce .[] as $t ([]; if any(.[]; ascii_downcase == ($t | ascii_downcase)) then . else . + [$t] end)
    | .[0:8]
    | (if length > 0 then .
       else [([($base | slug), ($dir | slug), "project"] | map(select(length > 0)) | .[0][0:24])] end) as $match
    | ($risk | lines) as $r
    | {project: {
        name: ($base | slug), fullname: ($dir | slug), dir: $dir, match: $match,
        note: null, redirectTo: null, risk: $r,
        forbidDirectCommit: ($r | length > 0),
        localFiles: ($envs | lines | map({path: ., sensitive: true, optional: false}))
      }}'
done | jq -s '
  . as $all
  | [ $all[] | select(.project) | .project ] as $ps
  | ($ps | group_by(.name) | map(select(length > 1) | .[0].name)) as $dups
  # 1) basename slug; the full-path slug when basenames collide or the slug is
  #    empty (e.g. a CJK-only dir name); "project" as the last resort.
  | [ $ps[]
      | .name as $n
      | .name = (if ($n == "" or any($dups[]; . == $n)) then
                   (if .fullname == "" then "project" else .fullname end)
                 else $n end)
      | del(.fullname) ]
  # 2) force uniqueness with -2, -3, ... so the proposal always passes validate.sh.
  | reduce .[] as $p ([];
      . as $acc
      | ($acc | map(.name)) as $taken
      | ([range(1; 1000)]
         | map(if . == 1 then $p.name else "\($p.name)-\(.)" end)
         | map(select(. as $c | any($taken[]; . == $c) | not))
         | .[0]) as $unique
      | $acc + [$p | .name = $unique])
  | { version: 1, projects: ., ignored: [ $all[] | select(.ignored) | .ignored ] }'
