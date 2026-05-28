#!/usr/bin/env bash
# PostToolUse hook: when Claude edits a file inside a nested (non-root) folder
# of the client repo, score the folder against the gap-detection heuristic and
# append a "pending" candidate to .claude/state/claude-md-candidates.jsonl.
#
# This hook is PASSIVE -- it only records. Generation is gated on the user
# running /yang-toolkit:claude-md-gaps. bash 3.2 / BSD userland portable.

set -u

input="$(cat -)"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
state_dir="${project_dir}/.claude/state"
candidates="${state_dir}/claude-md-candidates.jsonl"
mkdir -p "$state_dir" 2>/dev/null || exit 0

# ----- 0. Pull the edited file path out of the hook input. -----
file_path=""
tool=""
if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
  file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)"
fi

# No file path -> nothing to score. Stay silent.
[ -z "$file_path" ] && exit 0

# Make file_path absolute (best effort) -> relative to project_dir.
case "$file_path" in
  /*) abs="$file_path" ;;
  *)  abs="${project_dir}/${file_path}" ;;
esac

# Strip project_dir prefix to get repo-relative path.
case "$abs" in
  "${project_dir}/"*) rel="${abs#${project_dir}/}" ;;
  "${project_dir}")   rel="" ;;
  *)                  exit 0 ;;  # File outside the project; ignore.
esac

# The folder is the directory portion of the relative path.
dir="${rel%/*}"
[ "$dir" = "$rel" ] && exit 0   # File is at repo root; skip (root CLAUDE.md is out of scope).
[ -z "$dir" ] && exit 0
[ "$dir" = "." ] && exit 0

# ----- 1. Negative-signal short-circuits. Drop and exit silently. -----
case "$dir" in
  .git|.git/*) exit 0 ;;
  node_modules|node_modules/*) exit 0 ;;
  vendor|vendor/*) exit 0 ;;
  dist|dist/*|build|build/*|out|out/*) exit 0 ;;
  coverage|coverage/*|.coverage|.coverage/*) exit 0 ;;
  .next|.next/*|.nuxt|.nuxt/*|.turbo|.turbo/*) exit 0 ;;
  target|target/*) exit 0 ;;        # Rust / Java build outputs.
  __pycache__|__pycache__/*|.venv|.venv/*|venv|venv/*) exit 0 ;;
  tmp|tmp/*|.tmp|.tmp/*|log|log/*|logs|logs/*) exit 0 ;;
  .claude|.claude/*) exit 0 ;;       # Don't recurse on our own state.
  docs/decisions|docs/decisions/*) exit 0 ;;  # Per-feature decision dirs.
esac

# Test fixture / snapshot directories -- skip.
case "$dir" in
  *test/fixtures|*test/fixtures/*|*tests/fixtures|*tests/fixtures/*) exit 0 ;;
  *__snapshots__|*__snapshots__/*) exit 0 ;;
  *spec/fixtures|*spec/fixtures/*) exit 0 ;;
esac

# Already has a CLAUDE.md? Then no gap. (Audit is claude-md-improver's job, not ours.)
if [ -f "${project_dir}/${dir}/CLAUDE.md" ]; then
  exit 0
fi

# ----- 2. Positive-signal scoring. -----
# Each signal contributes a weight; final score is sum / max_weight (clamped 0..1).
# Weights chosen so "high-edit-activity + size threshold" alone clears 0.5,
# and edit-activity alone (without size) clears ~0.35 -- borderline, will surface
# but not as top candidate.

W_SIZE=20            # source-file count >= threshold
W_EDIT_RECENT=25     # touched recently (within last 7 days of session logs)
W_EDIT_FREQ=20       # touched repeatedly (this hook is one such touch by definition)
W_NAMING=10          # folder name implies a bounded context (services/, modules/, contexts/, ...)
W_DEPTH=5            # folder is at least 2 levels deep (more focused == more likely to need it)
W_ANCESTOR_SCOPE=10  # ancestor CLAUDE.md doesn't already cover this folder by name (best-effort)
MAX_WEIGHT=90        # = W_SIZE + W_EDIT_RECENT + W_EDIT_FREQ + W_NAMING + W_DEPTH + W_ANCESTOR_SCOPE

SIZE_THRESHOLD=4     # source files inside the folder (excluding nested vendored dirs)

score_num=0
signals=""

add_signal() {
  # $1 = weight, $2 = signal label
  score_num=$(( score_num + $1 ))
  if [ -z "$signals" ]; then
    signals="\"$2\""
  else
    signals="${signals},\"$2\""
  fi
}

# --- size threshold ---
# Count non-binary, non-hidden files directly under $dir (NOT recursive,
# to favor "this folder is its own module" semantics).
folder_abs="${project_dir}/${dir}"
file_count=0
if [ -d "$folder_abs" ]; then
  # Count regular files at top of $folder_abs only; ignore dotfiles.
  file_count="$(find "$folder_abs" -mindepth 1 -maxdepth 1 -type f \
    ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
fi
[ -z "$file_count" ] && file_count=0
if [ "$file_count" -ge "$SIZE_THRESHOLD" ]; then
  add_signal "$W_SIZE" "size>=${SIZE_THRESHOLD}"
fi

# --- this edit itself counts as edit-frequency evidence ---
add_signal "$W_EDIT_FREQ" "edit-touch"

# --- recent edit activity from session logs (last 7 day's logs) ---
# Heuristic: if any session log within the last 7 days references a file path
# inside this folder, count it as "edited recently".
log_dir="${project_dir}/.claude/logs"
recent=0
if [ -d "$log_dir" ] && command -v jq >/dev/null 2>&1; then
  # Iterate the last 7 daily log files by name (YYYYMMDD).
  i=0
  while [ "$i" -lt 7 ]; do
    # BSD date -v is macOS; GNU date -d is Linux. Try BSD first, fall back.
    d="$(date -u -v -"$i"d +%Y%m%d 2>/dev/null)"
    if [ -z "$d" ]; then
      d="$(date -u -d "-$i days" +%Y%m%d 2>/dev/null)"
    fi
    [ -z "$d" ] && { i=$((i+1)); continue; }

    f="${log_dir}/session-${d}.jsonl"
    if [ -r "$f" ]; then
      # Cheap substring match -- avoids parsing every line; safe because
      # paths in our logs are JSON-encoded so a substring is decisive enough.
      if grep -F -q "/${dir}/" "$f" 2>/dev/null; then
        recent=1
        break
      fi
    fi
    i=$((i+1))
  done
fi
[ "$recent" = "1" ] && add_signal "$W_EDIT_RECENT" "recent-activity"

# --- naming hint ---
# Last path segment matches a "bounded context"-style word.
last_seg="${dir##*/}"
case "$last_seg" in
  services|service|modules|module|contexts|context|domains|domain|features|feature|packages|app|apps|lib|libs|engine|engines|core|api|web|workers|jobs|controllers|models)
    add_signal "$W_NAMING" "bounded-context-name"
    ;;
esac

# --- depth ---
# Count slashes in $dir; depth 0 = top-level folder, depth 1 = nested-once, etc.
depth=$(printf '%s' "$dir" | tr -cd '/' | wc -c | tr -d ' ')
if [ "$depth" -ge 1 ]; then
  add_signal "$W_DEPTH" "depth>=2"
fi

# --- ancestor scope ---
# If no ancestor CLAUDE.md mentions this folder name, treat that as "not covered".
# (Best-effort. False positives are fine; the command-side review filters them.)
covered=0
walk="$dir"
while [ -n "$walk" ] && [ "$walk" != "." ]; do
  parent="${walk%/*}"
  [ "$parent" = "$walk" ] && parent=""    # No more slashes -> walked out.
  candidate="${project_dir}/${parent}/CLAUDE.md"
  [ -z "$parent" ] && candidate="${project_dir}/CLAUDE.md"
  if [ -r "$candidate" ]; then
    if grep -F -q "$last_seg" "$candidate" 2>/dev/null; then
      covered=1
      break
    fi
  fi
  [ -z "$parent" ] && break
  walk="$parent"
done
[ "$covered" = "0" ] && add_signal "$W_ANCESTOR_SCOPE" "not-in-ancestor"

# ----- 3. Compute score (0..1, 3 decimals) and append. -----
# Use awk for portable fixed-point division (no bc dependency).
score="$(awk -v n="$score_num" -v m="$MAX_WEIGHT" 'BEGIN { printf "%.3f", (m==0?0:n/m) }')"

# Below 0.30 -> too weak to surface. Drop silently.
weak="$(awk -v s="$score" 'BEGIN { print (s+0 < 0.30) ? "1" : "0" }')"
[ "$weak" = "1" ] && exit 0

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ----- 4. Dedupe: if there's already a pending entry for this dir, replace it. -----
# Rewrite the file with the old entry removed, then append the fresh one.
tmp="${candidates}.tmp.$$"
if [ -r "$candidates" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -c --arg dir "$dir" 'select(.dir != $dir or .status != "pending")' \
      "$candidates" > "$tmp" 2>/dev/null || cp "$candidates" "$tmp"
    mv "$tmp" "$candidates" 2>/dev/null || rm -f "$tmp"
  fi
fi

# Build the fresh entry.
if command -v jq >/dev/null 2>&1; then
  jq -n -c \
    --arg ts "$ts" \
    --arg dir "$dir" \
    --argjson signals "[${signals}]" \
    --argjson score "$score" \
    '{ts:$ts, dir:$dir, signals:$signals, score:$score, status:"pending"}' \
    >> "$candidates" 2>/dev/null || true
else
  # jq missing -> best-effort raw line.
  printf '{"ts":"%s","dir":"%s","signals":[%s],"score":%s,"status":"pending"}\n' \
    "$ts" "$dir" "$signals" "$score" >> "$candidates" 2>/dev/null || true
fi

exit 0
