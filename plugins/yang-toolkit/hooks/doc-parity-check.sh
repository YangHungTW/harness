#!/usr/bin/env bash
# doc-parity: keep the command/skill inventory in sync across every doc surface.
#
# The one-line summary of each yang-toolkit command/skill is hand-copied into
# several surfaces (README command list + cheat-sheet, and the en/zh usage
# manuals). Those surfaces are curated and TRANSLATED, so we do NOT auto-rewrite
# them (that would clobber the zh manual). Instead we CHECK coverage by name:
# every `/yang-toolkit:<name>` that has a definition file must appear in each
# surface, and every surface entry must map to a real definition (no orphans).
#
# Two modes:
#   1. --report  -> scan ALL commands + skills against ALL surfaces, print a
#                   coverage matrix, exit 1 if any gap/orphan. Run it by hand or
#                   from a pre-commit check.
#   2. (default) -> PostToolUse hook. Reads the hook JSON on stdin; if the edited
#                   file is a command/skill definition, nudge Claude when that
#                   command is missing from any surface. Mirrors test-parity.
#
# Conservative by design, exactly like test-parity-check.sh: a false nudge is
# cheaper than silent doc drift. bash 3.2 / BSD userland portable.
#
# Opt-out (hook mode): HARNESS_DISABLE_DOC_PARITY=1.

set -u

# --- resolve plugin root (this script is <plugin>/hooks/doc-parity-check.sh) ---
script_dir="$(cd "$(dirname "$0")" && pwd)"
plugin_root="$(cd "${script_dir}/.." && pwd)"

# Definition sources.
cmd_dir="${plugin_root}/commands"
skill_dir="${plugin_root}/skills"

# Enumerate every command/skill name that ships.
list_names() {
  for f in "${cmd_dir}"/*.md; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"; printf '%s\n' "${b%.md}"
  done
  for d in "${skill_dir}"/*/; do
    [ -e "${d}SKILL.md" ] || continue
    printf '%s\n' "$(basename "$d")"
  done
}

# ============================ REPORT MODE =====================================
if [ "${1:-}" = "--report" ]; then
  # Repo root holding the doc surfaces: prefer CLAUDE_PROJECT_DIR, else the
  # dev-repo layout (plugin_root/../..), else give up gracefully.
  repo="${CLAUDE_PROJECT_DIR:-$(cd "${plugin_root}/../.." 2>/dev/null && pwd)}"
  surfaces="README.md docs/usage.html docs/usage.zh.html"

  # Confirm at least one surface exists (only meaningful in the marketplace repo).
  have=0
  for s in $surfaces; do [ -f "${repo}/${s}" ] && have=1; done
  if [ "$have" = "0" ]; then
    echo "doc-parity: no doc surfaces found under ${repo} (nothing to check)."
    exit 0
  fi

  names="$(list_names | sort -u)"
  gaps=0

  printf '%-24s' "command / skill"
  for s in $surfaces; do printf '%-14s' "$(basename "$s" | sed 's/usage\.//;s/\.html//;s/README\.md/README/')"; done
  printf '\n'
  printf '%s\n' "-------------------------------------------------------------------------"

  while IFS= read -r n; do
    [ -z "$n" ] && continue
    printf '%-24s' "$n"
    for s in $surfaces; do
      if grep -Eq "/yang-toolkit:${n}([^a-z-]|$)" "${repo}/${s}" 2>/dev/null; then
        printf '%-14s' "ok"
      else
        printf '%-14s' "MISSING"
        gaps=$((gaps+1))
      fi
    done
    printf '\n'
  done <<EOF
$names
EOF

  # Orphan check: a surface entry with no matching definition file.
  echo
  defined=" $(printf '%s ' $names) "
  orphans=0
  for s in $surfaces; do
    refs="$(grep -rhoE '/yang-toolkit:[a-z-]+' "${repo}/${s}" 2>/dev/null | sed 's#/yang-toolkit:##' | sort -u)"
    for r in $refs; do
      case "$defined" in
        *" $r "*) : ;;
        *) echo "  ORPHAN: /yang-toolkit:${r} appears in ${s} but has no definition file"; orphans=$((orphans+1)) ;;
      esac
    done
  done

  echo
  if [ "$gaps" = "0" ] && [ "$orphans" = "0" ]; then
    echo "doc-parity: OK -- every command/skill is listed in every surface, no orphans."
    exit 0
  fi
  echo "doc-parity: ${gaps} missing coverage cell(s), ${orphans} orphan(s)."
  exit 1
fi

# ============================ HOOK MODE =======================================
[ "${HARNESS_DISABLE_DOC_PARITY:-0}" = "1" ] && exit 0

input="$(cat -)"
command -v jq >/dev/null 2>&1 || exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
state_dir="${project_dir}/.claude/state"
mkdir -p "$state_dir" 2>/dev/null || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

case "$tool" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac
[ -z "$file_path" ] && exit 0

# Make repo-relative.
case "$file_path" in
  /*) abs="$file_path" ;;
  *)  abs="${project_dir}/${file_path}" ;;
esac
case "$abs" in
  "${project_dir}/"*) rel="${abs#${project_dir}/}" ;;
  *) exit 0 ;;
esac

# Only act on a yang-toolkit command/skill DEFINITION file, and derive its name.
name=""
case "$rel" in
  plugins/yang-toolkit/commands/*.md)
    b="${rel##*/}"; name="${b%.md}" ;;
  plugins/yang-toolkit/skills/*/SKILL.md)
    rest="${rel#plugins/yang-toolkit/skills/}"; name="${rest%%/*}" ;;
  *) exit 0 ;;
esac
[ -z "$name" ] && exit 0

# Doc surfaces to keep in sync. If none exist here, we're not in the dev repo.
surfaces="README.md docs/usage.html docs/usage.zh.html"
missing=""
any_surface=0
for s in $surfaces; do
  [ -f "${project_dir}/${s}" ] || continue
  any_surface=1
  if ! grep -Eq "/yang-toolkit:${name}([^a-z-]|$)" "${project_dir}/${s}" 2>/dev/null; then
    missing="${missing}${missing:+, }${s}"
  fi
done
[ "$any_surface" = "0" ] && exit 0
[ -z "$missing" ] && exit 0

# Per-day dedupe per command name.
today="$(date -u +%Y%m%d)"
warned_file="${state_dir}/doc-parity-warned-${today}.txt"
if [ -r "$warned_file" ] && grep -F -x -q "$name" "$warned_file" 2>/dev/null; then
  exit 0
fi
printf '%s\n' "$name" >> "$warned_file" 2>/dev/null || true

message="doc-parity nudge: \`/yang-toolkit:${name}\` was edited but is not listed in: ${missing}. Add its one-line summary to each missing surface (the README command inventory + cheat-sheet, and the en/zh usage manuals -- translate for docs/usage.zh.html) before declaring this task complete, or run \`hooks/doc-parity-check.sh --report\` to see the full coverage matrix."

jq -n -c --arg msg "$message" \
  '{ suppressOutput: false, systemMessage: $msg,
     hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $msg } }'

exit 0
