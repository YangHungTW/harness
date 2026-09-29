# Alias rules for workspace.json `match` entries -- the single definition, used
# by validate.sh (to enforce) and propose.sh (to never emit what validate would
# refuse). Aliases render into the managed CLAUDE.md block that loads at every
# launch, so they must read as names, never as instructions.
#
# Load with: jq -L "<scripts/workspace>" 'include "alias"; ...'

# Allowed shape: starts with a letter/digit; then letters, digits, single spaces
# and . _ @ & - ; at most 3 words; no "--" (the managed block's field separator).
# \p{L}/\p{N} exclude format/invisible characters (bidi, zero-width, BOM).
def alias_shape_ok:
  type == "string"
  and length >= 1 and length <= 24
  and test("^[\\p{L}\\p{N}][\\p{L}\\p{N} ._@&-]*$")
  and (test("--|  | $") | not)
  and ((split(" ") | length) <= 3);

# Fold fullwidth ASCII (U+FF01-FF5E) to ASCII, then lowercase.
def alias_fold:
  explode | map(if . >= 65281 and . <= 65374 then . - 65248 else . end) | implode | ascii_downcase;

# Instruction- or command-shaped words (prefix-matched on word starts), plus
# CJK instruction terms anywhere.
def alias_denied:
  alias_fold
  | test("(^|[ ._@&-])(ignor|disregard|instruct|prompt|overrid|approv|must|sudo|curl|wget|exec|bash|system|skip|bypass|always|never)")
    or test("(^|[ ._@&-])(rm|sh|run|eval)($|[ ._@&-])")
    or test("忽略|無視|忽視|指示|指令|提示|執行|系統|務必|一律|无视|忽视|执行|系统");

# $exempt: strings that come straight from disk (the dir, its last segment, the
# name). Those skip the deny list -- a folder may really be called "Override" --
# but never the shape check.
def alias_ok($exempt):
  alias_shape_ok and ((. as $a | any($exempt[]; . == $a)) or (alias_denied | not));

# Make a disk-derived string (a dir basename) alias-shaped: disallowed chars to
# spaces, "--" and space runs collapsed, trimmed, at most 3 words and 24 chars.
def alias_clean:
  gsub("[^\\p{L}\\p{N} ._@&-]"; " ") | gsub("-{2,}"; "-") | gsub(" +"; " ")
  | gsub("^[ ._@&-]+|[ ]+$"; "")
  | (split(" ") | .[0:3] | join(" ")) | .[0:24] | gsub(" +$"; "");
