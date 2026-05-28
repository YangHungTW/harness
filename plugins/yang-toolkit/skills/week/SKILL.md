---
name: week
description: Cross-repo weekly report. Scans every harness-tracked client repo's `.claude/ledger.jsonl`, produces a markdown weekly recap grouped by client AND by feature. TRIGGER on /week, "週報", "weekly report".
---

# week

## Purpose
Roll up cross-project activity from the last 7 days. Uses the controlled-vocabulary
ledger schema so outcomes are aggregatable (`merged` count vs `abandoned`, etc.).

## Configuration

This skill reads its tracked-repo list from:

```
~/.config/harness/repos.json
```

Expected shape (TODO: confirm and lock):

```json
{
  "repos": [
    {
      "client":  "string -- billing entity / engagement name",
      "name":    "string -- short slug, used in headings",
      "path":    "absolute path to the repo on disk",
      "active":  true
    }
  ]
}
```

A missing config file is treated as an empty list -- the skill should walk the
user through creating it the first time.

## Behavior
1. Load `~/.config/harness/repos.json`. If absent, emit a starter template and exit.
2. For each `active=true` repo, read `<repo>/.claude/ledger.jsonl`.
3. Filter to the last 7 days (UTC, by `ts`).
4. Build two views:
   - **By client**: each client section lists features, hours-proxy (token sum),
     PR links, and an outcome breakdown.
   - **By feature**: every distinct `feature` slug across all clients, with its
     latest phase and outcome.
5. Emit a single markdown document. Default destination is stdout; with
   `--write`, save to `~/notes/weekly/<YYYY-WW>.md`.

## Notes
- Be resilient: a malformed JSONL line should be skipped with a warning, not abort.
- If a repo has no ledger, list it under "no activity captured".

<!-- TODO: implement the actual aggregation + markdown rendering. -->
