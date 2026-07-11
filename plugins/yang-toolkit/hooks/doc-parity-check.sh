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
# It ALSO checks version-badge parity: the `yang-toolkit v<X.Y.Z>` badge in the
# usage manuals must match the version in plugin.json (that badge is hand-edited
# and silently lags release bumps).
#
# Two modes:
#   1. --report  -> scan ALL commands + skills against ALL surfaces, print a
#                   coverage matrix, exit 1 if any gap/orphan/version mismatch.
#                   Run it by hand or from a pre-commit check.
#   2. (default) -> PostToolUse hook. Reads the hook JSON on stdin; nudge Claude
#                   when an edited command/skill definition is missing from any
#                   surface, or when an edit to plugin.json / a usage manual
#                   leaves the version badge out of sync. Mirrors test-parity.
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

# --- version-badge parity helpers ------------------------------------------
# The usage manuals carry a hand-written `yang-toolkit v<X.Y.Z>` badge that
# drifts behind plugin.json on every release bump. Catch that drift too.

# The plugin's declared version (no jq dependency -- report mode has no jq).
plugin_version() {
  pj="${plugin_root}/.claude-plugin/plugin.json"
  [ -f "$pj" ] || return 0
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pj" | head -1
}

# Print "<surface>|<badge-version>" for each HTML manual carrying a badge.
badge_versions() {
  _repo="$1"
  for s in docs/usage.html docs/usage.zh.html; do
    f="${_repo}/${s}"
    [ -f "$f" ] || continue
    bv="$(sed -n 's/.*yang-toolkit v\([0-9][0-9.]*\).*/\1/p' "$f" | head -1)"
    [ -n "$bv" ] && printf '%s|%s\n' "$s" "$bv"
  done
}

# Print one line per surface whose badge disagrees with plugin.json.
# Empty output = in sync (or nothing to compare). Line form:
#   "<surface> badge v<badge> != plugin.json v<plugin>"
version_mismatches() {
  _repo="$1"
  _pv="$(plugin_version)"
  [ -z "$_pv" ] && return 0
  while IFS='|' read -r _s _bv; do
    [ -z "$_s" ] && continue
    [ "$_bv" != "$_pv" ] && printf '%s badge v%s != plugin.json v%s\n' "$_s" "$_bv" "$_pv"
  done <<EOF
$(badge_versions "$_repo")
EOF
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

  # Version-badge parity: usage-manual badge must match plugin.json version.
  vmiss=0
  vlines="$(version_mismatches "$repo")"
  if [ -n "$vlines" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo "  VERSION: ${line}"
      vmiss=$((vmiss+1))
    done <<EOF
$vlines
EOF
  fi

  echo
  if [ "$gaps" = "0" ] && [ "$orphans" = "0" ] && [ "$vmiss" = "0" ]; then
    echo "doc-parity: OK -- every command/skill is listed in every surface, no orphans, badge in sync."
    exit 0
  fi
  echo "doc-parity: ${gaps} missing coverage cell(s), ${orphans} orphan(s), ${vmiss} version mismatch(es)."
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

# Version-badge parity: fire when plugin.json or a usage manual is edited, so a
# release bump (or a manual badge edit) that leaves the two out of step nudges.
case "$rel" in
  plugins/yang-toolkit/.claude-plugin/plugin.json|docs/usage.html|docs/usage.zh.html)
    vlines="$(version_mismatches "$project_dir")"
    if [ -n "$vlines" ]; then
      today="$(date -u +%Y%m%d)"
      vwarned="${state_dir}/doc-parity-version-warned-${today}.txt"
      if ! { [ -r "$vwarned" ] && grep -Fxq "VERSION" "$vwarned" 2>/dev/null; }; then
        printf 'VERSION\n' >> "$vwarned" 2>/dev/null || true
        joined="$(printf '%s' "$vlines" | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
        vmsg="doc-parity nudge (version): the usage-manual badge and plugin.json disagree -- ${joined}. Bump the badge(s) to match plugin.json before declaring this task complete."
        jq -n -c --arg msg "$vmsg" \
          '{ suppressOutput: false, systemMessage: $msg,
             hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $msg } }'
      fi
    fi
    exit 0 ;;
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
