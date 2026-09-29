#!/usr/bin/env bash
# Validate a workspace.json -- the one read handler every workspace reader uses
# (mirrors straw-boss's apps-config read handler exit codes).
#
# Exit 0: valid; the JSON is printed on stdout.
# Exit 1: invalid (or unreadable, or the validator itself failed); one
#         "workspace.json: <reason>" per line on stderr. Fails closed.
# Exit 3: no config at that path.
#
# Usage: validate.sh [FILE]   FILE defaults to ${CLAUDE_PROJECT_DIR:-$PWD}/.claude/workspace.json
#        validate.sh -        validate a candidate from stdin before writing it

set -u

file="${1:-${CLAUDE_PROJECT_DIR:-$PWD}/.claude/workspace.json}"
here="$(cd "$(dirname "$0")" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "workspace.json: jq is required" >&2; exit 1; }
if [ "$file" = "-" ]; then
  file="$(mktemp "${TMPDIR:-/tmp}/workspace-candidate.XXXXXX")" || exit 1
  trap 'rm -f "$file"' EXIT
  cat > "$file"
fi
[ -e "$file" ] || { echo "workspace.json: no config at $file" >&2; exit 3; }

# Exactly one JSON document (a stream of several would be merged by readers).
docs="$(jq -s 'length' "$file" 2>/dev/null)"
if [ -z "$docs" ]; then
  echo "workspace.json: not valid JSON ($file)" >&2
  exit 1
elif [ "$docs" != 1 ]; then
  echo "workspace.json: must hold exactly one JSON document, found $docs ($file)" >&2
  exit 1
fi

# Every check is exact-match (never jq's substring-matching `inside`/`contains`),
# and every string that ends up in the managed CLAUDE.md block is kept free of
# control characters, markup brackets and backticks.
errors="$(jq -L "$here" -r '
  include "alias";
  def isstr: type == "string";
  def safe: isstr and (test("[[:cntrl:]<>`\\p{Cf}\u2028\u2029]") | not);
  def relpath: isstr and safe and length > 0 and (startswith("/") | not)
               and . != "~" and (startswith("~/") | not)
               and (endswith("/") | not) and . != "."
               and ((split("/") | map(select(. == ".." or . == "." or . == "")) | length) == 0);
  def strs: type == "array" and all(.[]; isstr);
  def member($xs): . as $x | any($xs[]; . == $x);
  if type != "object" then ["top level must be an object"] else
  . as $root
  | ((.projects // []) | if type == "array" then . else [] end | map(objects)) as $ps
  | ($ps | map(.name)) as $names
  | ($ps | map(select(.redirectTo | isstr)) | map(.name)) as $redirecting
  | [
      (keys - ["version", "projects", "ignored"] | .[] | "unknown top-level key: \(.)"),
      (if .version != 1 then "version must be 1" else empty end),
      (if (.projects | type) != "array" then "projects must be an array" else empty end),
      (if has("ignored") then
         (if (.ignored | strs) | not then "ignored must be an array of strings"
          else (.ignored[] | select(relpath | not) | "ignored entry must be a relative path: \(.)"),
               (.ignored | group_by(.) | map(select(length > 1) | .[0]) | .[] | "duplicate ignored entry: \(.)"),
               (.ignored[] | select(member($ps | map(.dir))) | "dir is both a project and ignored: \(.)")
          end)
       else empty end),
      ($names | map(select(isstr)) | group_by(.) | map(select(length > 1) | .[0]) | .[] | "duplicate name: \(.)"),
      ($ps | map(.dir) | map(select(isstr)) | group_by(.) | map(select(length > 1) | .[0]) | .[] | "duplicate dir: \(.)"),
      (if (.projects | type) == "array" then
        (.projects | to_entries[] | .key as $i | .value as $p | "projects[\($i)]" as $at
         | if ($p | type) != "object" then "\($at): must be an object" else
           ( ($p | keys - ["name","dir","match","note","redirectTo","risk","forbidDirectCommit","localFiles"]
               | .[] | "\($at): unknown key: \(.)"),
             (if ($p.name | isstr | not) or ($p.name | test("^[a-z0-9][a-z0-9-]*$") | not)
                then "\($at): name must match ^[a-z0-9][a-z0-9-]*$" else empty end),
             (if ($p.dir | relpath) | not
                then "\($at): dir must be a relative path (no .., ., ~, leading or trailing /)" else empty end),
             (if ($p.match | strs) | not then "\($at): match must be an array of strings"
              elif ($p.match | length) < 1 or ($p.match | length) > 12 then "\($at): match must have 1-12 entries"
              else
                ([$p.dir, ($p.dir | tostring | split("/") | last), ($p.dir | tostring | split("/") | last | alias_clean), $p.name]
                 | map(select(type == "string"))) as $exempt
                | ($p.match[] | select(alias_ok($exempt) | not)
                   | "\($at): match entry is not a plain name (letters/digits, . _ @ & -, ≤3 words, no instruction or command words): \(.)")
              end),
             (if $p | has("risk") then
                (if ($p.risk | strs) | not then "\($at): risk must be an array of strings"
                 else ($p.risk - ["live-money","pii","prod-deploy"] | .[] | "\($at): unknown risk tag: \(.)"),
                      (if ($p.risk | length) != ($p.risk | unique | length) then "\($at): duplicate risk tag" else empty end) end)
              else empty end),
             (if ($p | has("forbidDirectCommit")) and (($p.forbidDirectCommit | type) != "boolean")
                then "\($at): forbidDirectCommit must be boolean" else empty end),
             (if ($p | has("note")) and $p.note != null and ((($p.note | safe) | not) or ($p.note | length) > 200)
                then "\($at): note must be null or at most 200 chars without control characters, <, > or backticks" else empty end),
             (if ($p | has("redirectTo") | not) or $p.redirectTo == null then empty
              elif ($p.redirectTo | isstr | not) then "\($at): redirectTo must be a project name or null"
              elif $p.redirectTo == $p.name then "\($at): redirectTo points at itself"
              elif ($p.redirectTo | member($names) | not) then "\($at): redirectTo names a missing project: \($p.redirectTo)"
              elif ($p.redirectTo | member($redirecting)) then "\($at): redirectTo target \($p.redirectTo) itself redirects (no chains or cycles)"
              else empty end),
             (if $p | has("localFiles") then
                (if ($p.localFiles | type) != "array" then "\($at): localFiles must be an array"
                 else ($p.localFiles[]
                       | if type != "object" then "\($at): each localFiles entry must be an object"
                         else ((keys - ["path","sensitive","optional","note"] | .[] | "\($at): localFiles unknown key: \(.)"),
                               (if (.path | relpath) | not then "\($at): localFiles path must be relative without .. or unsafe characters" else empty end),
                               (if has("note") and .note != null and (((.note | safe) | not) or (.note | length) > 200)
                                  then "\($at): localFiles note must be at most 200 safe chars" else empty end),
                               (if (has("sensitive") and (.sensitive | type) != "boolean") or (has("optional") and (.optional | type) != "boolean")
                                  then "\($at): localFiles sensitive/optional must be boolean" else empty end))
                         end)
                 end)
              else empty end)
           ) end)
       else empty end)
    ] end
  | .[]' "$file")" || { echo "workspace.json: validator error (jq failed on $file)" >&2; exit 1; }

if [ -n "$errors" ]; then
  printf '%s\n' "$errors" | sed 's/^/workspace.json: /' >&2
  exit 1
fi

jq . "$file"
