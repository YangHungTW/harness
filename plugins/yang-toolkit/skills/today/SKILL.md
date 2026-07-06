---
name: today
description: Aggregate today's work surface across sources -- GitHub PRs/notifications, each tracked client repo's `.claude/ledger.jsonl`, and any optional config-gated issue/Slack sources. TRIGGER on /today, "today", "今日", "morning brief", "每日簡報", or a standalone greeting when no other task is present.
model: haiku
---

# today

## Purpose
Produce one daily digest combining external task surfaces (GitHub, plus any
optional configured trackers) and every harness-tracked client repo's recent
ledger activity, so I can see in one place what to work on next.

This skill is OK with stale or partial data -- it is a starting point, not an
authoritative report. Always emit whatever you could gather; never abort just
because one source is missing.

## Inputs
- `~/.config/harness/repos.json` (tracked repo list -- shared with /week skill).
- Per-repo `<repo>/.claude/ledger.jsonl` (last ~24h of entries).
- `gh` CLI for GitHub.
- OPTIONAL external sources, only if configured (see step 4).

### repos.json shape (shared with /week)
```json
{
  "repos": [
    { "client": "...", "name": "...", "path": "/abs/path", "active": true }
  ],
  "sources": [
    { "name": "acme-tracker", "kind": "issue|slack|other", "...": "free-form" }
  ]
}
```
The `sources` block is OPTIONAL. It may also live in `~/.config/harness/today.json`.

## Procedure

Run these steps in order. For each shell step, prefer `jq` when available, but
ALWAYS have a `jq`-less fallback (grep/sed or a plain read). Treat any single
failure as "source skipped", record it, and continue.

### 1. Load the repo list
- Read `~/.config/harness/repos.json`.
- If the file is ABSENT or unreadable: note "repos.json not found -- per-repo
  ledger section skipped (run /week to create it)" and continue to GitHub
  (step 3). Do NOT ask the user to configure it now.
- Otherwise parse `repos[]`. Keep only entries where `active` is `true`
  (treat a missing `active` as true). Capture `client`, `name`, `path`.

### 2. Per-repo recent ledger (last ~24h)
For each active repo, read `<path>/.claude/ledger.jsonl` (skip + note any repo
whose ledger is missing).

Apply the SHARED CONTRACT source-dedupe rule:
- Each ledger line is a JSON object that MAY carry a `"source"` field:
  `"stop-hook"` (low-trust, automatic) or `"command"` (authoritative). A line
  with NO `"source"` key counts as `"command"` (back-compat).
- For STATS (outcome counts, token sums, feature/kanban state): use ONLY
  `command`/no-source entries. EXCLUDE `stop-hook` entries from every count.
- Use `stop-hook` entries ONLY as a recency / "last touched" signal -- never
  add their tokens or outcomes to any total.

Filter to entries whose `ts` is within the last 24h. For each repo compute:
- `last touched`: most recent `ts` across ALL entries (including stop-hook).
- active features: distinct `feature` slugs from `command` entries, with their
  latest phase/outcome.
- token proxy: sum of `tokens` from `command` entries only.

Token display rule: render a token value of `0` as `-` (unknown), not `0`.
A `files` value of `0` stays the numeric `0f`.

### 3. GitHub (via `gh`)
- If `gh` is not on `PATH`, or `gh auth status` fails: SKIP this section and add
  "GitHub" to the skipped-sources line. Do not error.
- Otherwise gather:
  - Open PRs authored by me:
    `gh search prs --author @me --state open --json title,repository,url,updatedAt`
    (fallback without `--json` if needed and summarize the table).
  - PRs awaiting my review:
    `gh search prs --review-requested @me --state open --json title,repository,url`
  - Unread notifications:
    `gh api notifications --jq '.[] | {repo: .repository.full_name, reason, title: .subject.title}'`
    (fallback: `gh api notifications` and summarize). If `jq`/`--jq` is
    unavailable, read the raw JSON and summarize counts.
- If a single `gh` call fails but others succeed, include what worked and note
  the partial failure.

### 4. Optional external trackers / Slack (config-gated)
- Look for a `sources` array in `repos.json`, or in `~/.config/harness/today.json`.
- If NO sources are configured: emit one line "External trackers / Slack: not
  configured" and move on. Do NOT ask which tracker to use; do NOT assume Jira
  vs Linear vs anything.
- If sources ARE configured: treat each generically by its `kind`/`name`. For
  each source, attempt only what its config describes (e.g. a CLI command or an
  endpoint named in the config). If the tool/credential is missing or the call
  fails, SKIP that source and add it to the skipped-sources line. Never block.

### 5. Render the digest
Output ONE markdown digest:

```
# Today -- <local date>
_Generated: <now UTC, ISO 8601>._

## Per client
### <client> (<repo name>)
- last touched: <relative time>   (or "no activity in last 24h")
- features: <slug> — <phase>/<outcome>, ...
- tokens (proxy): <sum or ->   files: <count>f
(repeat per active repo, grouped by client)

## Cross-cutting
- GitHub — open PRs: <n>, review-requested: <n>, unread notifications: <n>
  (list the most relevant 3-5 with links)
- External trackers / Slack: <summary, or "not configured">

## Skipped sources
- <source>: <reason>   (omit this whole section only if nothing was skipped)
```

Always end with the **Skipped sources** line/section whenever ANY source was
unconfigured, missing, unreachable, or unauthenticated, so it's clear the digest
is partial.

### 6. Optional write
By default the digest is printed to the chat only -- no file is written. If
invoked with `--write`, ALSO save the exact same markdown to
`~/notes/daily/today-<YYYY-MM-DD>-<TS>.md` (create `~/notes/daily/` if needed),
where `<TS>` is a compact UTC timestamp (`date -u +%Y%m%dT%H%M%SZ` -> e.g.
`20260605T031421Z`). The date groups files by day; the `<TS>` suffix keeps
multiple briefs on the same day distinct and lexically sortable instead of
overwriting. Print the saved path. Use the **Write** tool (it creates parent
directories); never `>`/`tee`/`mkdir`.

## Notes
- Stale or partial data is acceptable and expected; flag it, don't fail on it.
- Never double-count `stop-hook` ledger entries into any stat (see step 2).
- Never prompt the user to configure optional sources -- silently skip them.
