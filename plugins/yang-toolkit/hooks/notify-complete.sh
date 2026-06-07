#!/usr/bin/env bash
# Stop hook: play a short completion sound (and an optional desktop notification)
# so that, with several parallel sessions running, you can tell which one just
# finished. Best-effort and silent on any failure; never blocks the session.
# bash 3.2 / BSD portable. Reads (and discards) the Stop event JSON from stdin.
#
# Env knobs:
#   HARNESS_DISABLE_NOTIFY=1   -- turn this hook off entirely.
#   HARNESS_NOTIFY_SOUND=/path -- override the sound file (default macOS Blow.aiff).
#   HARNESS_NOTIFY_DESKTOP=1   -- also post a desktop notification (off by default).

set -u

# Drain stdin (the Stop event JSON) -- we do not use it.
cat - >/dev/null 2>&1 || true

# Opt-out.
case "${HARNESS_DISABLE_NOTIFY:-0}" in
  1|true|TRUE|yes) exit 0 ;;
esac

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
state_dir="${project_dir}/.claude/state"

# Nicer label when a feature is actively tracked (set by the flow commands).
label="session"
if [ -r "${state_dir}/current-feature.txt" ]; then
  _f="$(head -n 1 "${state_dir}/current-feature.txt" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$_f" ] && label="$_f"
fi
repo="$(basename "$project_dir" 2>/dev/null)"
msg="${repo}: ${label} done"

# ---- Sound (synchronous; system sounds are < ~1s, well within the hook timeout)
sound="${HARNESS_NOTIFY_SOUND:-}"
if command -v afplay >/dev/null 2>&1; then            # macOS
  [ -z "$sound" ] && sound="/System/Library/Sounds/Blow.aiff"
  [ -r "$sound" ] && afplay "$sound" >/dev/null 2>&1
elif command -v paplay >/dev/null 2>&1; then          # Linux / PulseAudio
  [ -n "$sound" ] && [ -r "$sound" ] && paplay "$sound" >/dev/null 2>&1
elif command -v aplay >/dev/null 2>&1; then           # Linux / ALSA
  [ -n "$sound" ] && [ -r "$sound" ] && aplay -q "$sound" >/dev/null 2>&1
fi

# ---- Desktop notification (opt-in; the sound is the primary signal) ----
case "${HARNESS_NOTIFY_DESKTOP:-0}" in
  1|true|TRUE|yes)
    if command -v terminal-notifier >/dev/null 2>&1; then
      terminal-notifier -title "Claude Code" -message "$msg" >/dev/null 2>&1 &
    elif command -v osascript >/dev/null 2>&1; then    # macOS built-in
      osascript -e "display notification \"${msg}\" with title \"Claude Code\"" >/dev/null 2>&1 &
    elif command -v notify-send >/dev/null 2>&1; then  # Linux
      notify-send "Claude Code" "$msg" >/dev/null 2>&1 &
    fi
  ;;
esac

exit 0
