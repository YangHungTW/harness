---
name: today
description: Aggregate today's work surface across sources -- GitHub PRs/notifications, Jira/Linear issues, Slack mentions, local markdown notes, and each tracked client repo's `.claude/ledger.jsonl`. TRIGGER on /today, "today", "今日", "morning brief", "每日簡報", or a standalone greeting when no other task is present.
---

# today

## Purpose
Produce one daily digest combining: external task surfaces (GitHub / Jira / Slack)
plus every harness-tracked client repo's recent ledger activity, so I can see in
one place what to work on next.

<!-- TODO: implement the actual gathering logic. Sketch:
  1. Read ~/.config/harness/repos.json -> list of client repos
  2. For each repo: read last N entries of .claude/ledger.jsonl
  3. Pull GitHub: gh search prs --author @me --state open
  4. Pull Jira/Linear: TBD which one(s) I'm using right now
  5. Pull Slack mentions: TBD (cli? api?)
  6. Pull local notes: ~/notes/today.md if it exists
  7. Merge + dedupe + present grouped by client
-->

## Inputs
- `~/.config/harness/repos.json` (tracked repo list -- shared with /week skill)
- Per-repo `.claude/ledger.jsonl` (last ~24h of entries)
- `gh` CLI for GitHub
<!-- TODO: confirm Jira vs Linear vs both, and which Slack workspace(s) to scan -->

## Output format
<!-- TODO: design the digest format. Suggested grouping:
  ## Today's surface
  ### Per client
    - {client}: open PRs, blocked items, last touch
  ### Cross-cutting
    - GitHub mentions
    - Slack DMs not yet answered
-->

## Notes
- This skill is OK with stale data -- it's a starting point, not authoritative.
- If a source is unreachable (e.g., no internet), emit a partial digest and flag
  which sources were skipped.
